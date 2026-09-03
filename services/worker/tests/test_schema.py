"""Schema integration tests.

Covers the Phase 2 acceptance criteria that need a real database: foreign keys,
enum rejection, the uniqueness rules that make ingestion idempotent, and the
metric-event write path.

The uniqueness tests matter most. Phase 6's "3 discoveries -> 1 canonical job
-> 1 research task" guarantee rests on database constraints rather than
application checks, because concurrent multi-source ingestion is the normal
case. If these constraints are wrong, the dedupe logic built on them cannot be
correct no matter how it is written.
"""

from __future__ import annotations

from uuid import uuid4

import psycopg
import pytest
from tests.conftest import requires_db

from recruiting_intel.metrics import Metrics, PostgresMetricSink

pytestmark = [pytest.mark.integration, requires_db]

EXPECTED_TABLES = {
    "companies",
    "company_aliases",
    "company_role_aliases",
    "source_configs",
    "scan_runs",
    "discoveries",
    "jobs",
    "job_sources",
    "classifications",
    "applications",
    "recruiters",
    "recruiter_evidence",
    "email_patterns",
    "email_drafts",
    "metric_events",
    "daily_metric_snapshots",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _company(db, name: str | None = None) -> str:
    row = db.execute(
        "insert into companies (canonical_name) values (%s) returning id",
        (name or f"Test Co {uuid4().hex[:8]}",),
    ).fetchone()
    return row[0]


def _source_config(db, company_id: str | None = None) -> str:
    row = db.execute(
        """
        insert into source_configs (company_id, source_type, source_identifier)
        values (%s, 'GREENHOUSE', %s) returning id
        """,
        (company_id, f"board-{uuid4().hex[:8]}"),
    ).fetchone()
    return row[0]


def _job(db, company_id: str, **overrides) -> str:
    fields = {
        "raw_title": "Software Engineer, Infrastructure",
        "ats_type": "GREENHOUSE",
        "ats_job_id": uuid4().hex[:10],
        **overrides,
    }
    row = db.execute(
        """
        insert into jobs (company_id, raw_title, ats_type, ats_job_id)
        values (%s, %s, %s, %s) returning id
        """,
        (company_id, fields["raw_title"], fields["ats_type"], fields["ats_job_id"]),
    ).fetchone()
    return row[0]


def _discovery(db, source_config_id: str, **overrides) -> str:
    fields = {
        "external_source_id": uuid4().hex[:10],
        "raw_title": "Software Engineer, Infrastructure",
        "canonicalized_url": None,
        **overrides,
    }
    row = db.execute(
        """
        insert into discoveries
            (source_config_id, external_source_id, raw_title, canonicalized_url)
        values (%s, %s, %s, %s) returning id
        """,
        (
            source_config_id,
            fields["external_source_id"],
            fields["raw_title"],
            fields["canonicalized_url"],
        ),
    ).fetchone()
    return row[0]


# ---------------------------------------------------------------------------
# Structure
# ---------------------------------------------------------------------------
def test_all_expected_tables_exist(db) -> None:
    rows = db.execute(
        """
        select table_name from information_schema.tables
        where table_schema = 'public' and table_type = 'BASE TABLE'
        """
    ).fetchall()

    assert {row[0] for row in rows} >= EXPECTED_TABLES


def test_pgmq_extension_installed(db) -> None:
    """Phase 6 depends on this; discovering its absence now is the point."""
    row = db.execute("select 1 from pg_extension where extname = 'pgmq'").fetchone()
    assert row is not None


def test_research_queue_round_trips(db) -> None:
    """Send, read, archive. No consumer logic -- just proof the queue works."""
    msg_id = db.execute(
        "select pgmq.send('research_tasks', %s)",
        ('{"job_id": "test", "attempt": 1}',),
    ).fetchone()[0]
    assert msg_id is not None

    read = db.execute("select msg_id, message from pgmq.read('research_tasks', 5, 1)").fetchall()
    assert any(row[0] == msg_id for row in read)

    archived = db.execute(
        "select pgmq.archive('research_tasks', %s::bigint)", (msg_id,)
    ).fetchone()[0]
    assert archived is True


def test_row_level_security_enabled_on_all_tables(db) -> None:
    rows = db.execute(
        """
        select c.relname
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
        """
    ).fetchall()

    unprotected = {row[0] for row in rows} & EXPECTED_TABLES
    assert unprotected == set(), f"RLS disabled on: {sorted(unprotected)}"


# ---------------------------------------------------------------------------
# Foreign keys
# ---------------------------------------------------------------------------
def test_orphan_discovery_rejected(db, failing) -> None:
    with failing(psycopg.errors.ForeignKeyViolation):
        db.execute(
            """
            insert into discoveries (source_config_id, external_source_id, raw_title)
            values (%s, 'x', 'Engineer')
            """,
            (str(uuid4()),),
        )


def test_orphan_job_rejected(db, failing) -> None:
    with failing(psycopg.errors.ForeignKeyViolation):
        db.execute(
            "insert into jobs (company_id, raw_title) values (%s, 'Engineer')",
            (str(uuid4()),),
        )


def test_company_delete_is_restricted_while_jobs_exist(db, failing) -> None:
    """Deleting a company must not silently destroy job history."""
    company_id = _company(db)
    _job(db, company_id)

    with failing(psycopg.errors.ForeignKeyViolation):
        db.execute("delete from companies where id = %s", (company_id,))


# ---------------------------------------------------------------------------
# Enum rejection
# ---------------------------------------------------------------------------
@pytest.mark.parametrize(
    ("table", "column", "value", "setup"),
    [
        ("jobs", "role_family", "NOT_A_FAMILY", True),
        ("jobs", "research_status", "MAYBE", True),
        ("recruiters", "email_status", "GUARANTEED", False),
        ("recruiters", "candidate_scope", "{SOPHOMORE}", False),
        ("applications", "status", "SORT_OF_APPLIED", False),
        ("discoveries", "verification_status", "PROBABLY", False),
    ],
)
def test_invalid_enum_values_rejected(
    db, failing, table: str, column: str, value: str, setup: bool
) -> None:
    """Invalid states must be impossible to write, not merely discouraged."""
    company_id = _company(db)

    if table == "jobs":
        with failing(psycopg.errors.InvalidTextRepresentation):
            db.execute(
                f"insert into jobs (company_id, raw_title, {column}) "
                "values (%s, 'Engineer', %s)",
                (company_id, value),
            )
    elif table == "recruiters":
        with failing(psycopg.errors.InvalidTextRepresentation):
            db.execute(
                f"insert into recruiters (company_id, name, {column}) "
                "values (%s, 'A Person', %s)",
                (company_id, value),
            )
    elif table == "applications":
        job_id = _job(db, company_id)
        with failing(psycopg.errors.InvalidTextRepresentation):
            db.execute(
                f"insert into applications (job_id, {column}) values (%s, %s)",
                (job_id, value),
            )
    else:
        source_id = _source_config(db, company_id)
        with failing(psycopg.errors.InvalidTextRepresentation):
            db.execute(
                f"insert into discoveries "
                f"(source_config_id, external_source_id, raw_title, {column}) "
                "values (%s, 'x', 'Engineer', %s)",
                (source_id, value),
            )


# ---------------------------------------------------------------------------
# Idempotent ingestion -- the constraints Phase 6 depends on
# ---------------------------------------------------------------------------
def test_same_posting_from_same_source_cannot_duplicate(db, failing) -> None:
    """Re-scanning must not create a second discovery."""
    source_id = _source_config(db, _company(db))
    external_id = "gh-12345"

    _discovery(db, source_id, external_source_id=external_id)

    with failing(psycopg.errors.UniqueViolation):
        _discovery(db, source_id, external_source_id=external_id)


def test_url_fallback_uniqueness_when_no_external_id(db, failing) -> None:
    source_id = _source_config(db, _company(db))
    url = "https://example.test/jobs/42"

    _discovery(db, source_id, external_source_id=None, canonicalized_url=url)

    with failing(psycopg.errors.UniqueViolation):
        _discovery(db, source_id, external_source_id=None, canonicalized_url=url)


def test_discovery_must_be_identifiable(db, failing) -> None:
    """Without an ID or URL, re-scanning could never be idempotent."""
    source_id = _source_config(db, _company(db))

    with failing(psycopg.errors.CheckViolation):
        db.execute(
            "insert into discoveries (source_config_id, raw_title) values (%s, 'Engineer')",
            (source_id,),
        )


def test_two_jobs_cannot_share_an_ats_identity(db, failing) -> None:
    """Dedupe Level 1. This is the constraint that makes 3 -> 1 possible."""
    company_id = _company(db)
    _job(db, company_id, ats_job_id="shared-id")

    with failing(psycopg.errors.UniqueViolation):
        _job(db, company_id, ats_job_id="shared-id")


def test_two_jobs_cannot_share_an_application_url(db, failing) -> None:
    """Dedupe Level 2."""
    company_id = _company(db)
    url = "https://boards.example.test/jobs/777"

    db.execute(
        "insert into jobs (company_id, raw_title, application_url) values (%s, 'E', %s)",
        (company_id, url),
    )

    with failing(psycopg.errors.UniqueViolation):
        db.execute(
            "insert into jobs (company_id, raw_title, application_url) "
            "values (%s, 'E2', %s)",
            (company_id, url),
        )


def test_jobs_without_ats_identity_do_not_collide(db) -> None:
    """The partial index must not treat two NULL identities as duplicates."""
    company_id = _company(db)

    for title in ("Engineer A", "Engineer B"):
        db.execute(
            "insert into jobs (company_id, raw_title) values (%s, %s)",
            (company_id, title),
        )

    count = db.execute(
        "select count(*) from jobs where company_id = %s", (company_id,)
    ).fetchone()[0]
    assert count == 2


def test_discovery_attaches_to_a_job_only_once(db, failing) -> None:
    """Re-running ingestion must not inflate source-overlap metrics."""
    company_id = _company(db)
    source_id = _source_config(db, company_id)
    job_id = _job(db, company_id)
    discovery_id = _discovery(db, source_id)

    db.execute(
        "insert into job_sources (job_id, discovery_id, source_type) "
        "values (%s, %s, 'GREENHOUSE')",
        (job_id, discovery_id),
    )

    with failing(psycopg.errors.UniqueViolation):
        db.execute(
            "insert into job_sources (job_id, discovery_id, source_type) "
            "values (%s, %s, 'GREENHOUSE')",
            (job_id, discovery_id),
        )


def test_one_discovery_cannot_support_two_jobs(db, failing) -> None:
    company_id = _company(db)
    source_id = _source_config(db, company_id)
    discovery_id = _discovery(db, source_id)
    job_a = _job(db, company_id)
    job_b = _job(db, company_id)

    db.execute(
        "insert into job_sources (job_id, discovery_id, source_type) "
        "values (%s, %s, 'GREENHOUSE')",
        (job_a, discovery_id),
    )

    with failing(psycopg.errors.UniqueViolation):
        db.execute(
            "insert into job_sources (job_id, discovery_id, source_type) "
            "values (%s, %s, 'LEVER')",
            (job_b, discovery_id),
        )


def test_alias_resolves_to_exactly_one_company(db, failing) -> None:
    company_a = _company(db)
    company_b = _company(db)

    db.execute(
        "insert into company_aliases (company_id, alias) values (%s, 'Shared Alias')",
        (company_a,),
    )

    with failing(psycopg.errors.UniqueViolation):
        db.execute(
            "insert into company_aliases (company_id, alias) values (%s, 'shared alias')",
            (company_b,),
        )


def test_one_application_record_per_job(db, failing) -> None:
    job_id = _job(db, _company(db))
    db.execute("insert into applications (job_id) values (%s)", (job_id,))

    with failing(psycopg.errors.UniqueViolation):
        db.execute("insert into applications (job_id) values (%s)", (job_id,))


# ---------------------------------------------------------------------------
# Domain invariants
# ---------------------------------------------------------------------------
def test_raw_title_cannot_be_blank(db, failing) -> None:
    """The published title is evidence; an empty one is a bug upstream."""
    company_id = _company(db)
    with failing(psycopg.errors.CheckViolation):
        db.execute(
            "insert into jobs (company_id, raw_title) values (%s, '   ')",
            (company_id,),
        )


def test_unknown_email_status_forbids_an_address(db, failing) -> None:
    """UNKNOWN must mean unknown -- not an address we are coy about."""
    company_id = _company(db)
    with failing(psycopg.errors.CheckViolation):
        db.execute(
            """
            insert into recruiters (company_id, name, email, email_status)
            values (%s, 'A Person', 'someone@example.test', 'UNKNOWN')
            """,
            (company_id,),
        )


def test_known_email_status_requires_an_address(db, failing) -> None:
    company_id = _company(db)
    with failing(psycopg.errors.CheckViolation):
        db.execute(
            """
            insert into recruiters (company_id, name, email_status)
            values (%s, 'A Person', 'PUBLISHED')
            """,
            (company_id,),
        )


def test_application_state_and_timestamps_must_agree(db, failing) -> None:
    """Status transitions are deterministic and must never need an LLM."""
    job_id = _job(db, _company(db))

    with failing(psycopg.errors.CheckViolation):
        db.execute(
            "insert into applications (job_id, status) values (%s, 'APPLIED_EMAILED')",
            (job_id,),
        )


def test_valid_application_transition_accepted(db) -> None:
    job_id = _job(db, _company(db))

    db.execute(
        """
        insert into applications (job_id, status, applied_at, emailed_at)
        values (%s, 'APPLIED_EMAILED', now(), now())
        """,
        (job_id,),
    )

    status = db.execute(
        "select status from applications where job_id = %s", (job_id,)
    ).fetchone()[0]
    assert status == "APPLIED_EMAILED"


def test_non_llm_classification_cannot_claim_llm_cost(db, failing) -> None:
    """Cost accounting must stay attributable to actual model calls."""
    job_id = _job(db, _company(db))

    with failing(psycopg.errors.CheckViolation):
        db.execute(
            """
            insert into classifications
                (job_id, role_family, confidence, method, llm_tokens, llm_cost)
            values (%s, 'SOFTWARE_ENGINEERING', 0.9, 'DETERMINISTIC_RULES', 100, 0.01)
            """,
            (job_id,),
        )


def test_email_pattern_sources_cannot_exceed_examples(db, failing) -> None:
    company_id = _company(db)

    with failing(psycopg.errors.CheckViolation):
        db.execute(
            """
            insert into email_patterns
                (company_id, pattern, example_count, independent_source_count)
            values (%s, 'first.last@x.com', 2, 5)
            """,
            (company_id,),
        )


def test_running_scan_cannot_have_a_finish_time(db, failing) -> None:
    source_id = _source_config(db, _company(db))

    with failing(psycopg.errors.CheckViolation):
        db.execute(
            "insert into scan_runs (source_config_id, status, finished_at) "
            "values (%s, 'RUNNING', now())",
            (source_id,),
        )


# ---------------------------------------------------------------------------
# Metric events
# ---------------------------------------------------------------------------
def test_metric_event_insert_through_service(db) -> None:
    metrics = Metrics(PostgresMetricSink(db))
    job_id = uuid4()

    metrics.canonical_job_created(
        job_id=job_id, company_id=uuid4(), source_type="GREENHOUSE"
    )

    row = db.execute(
        "select event_name, entity_type, entity_id, metadata_json "
        "from metric_events where entity_id = %s",
        (job_id,),
    ).fetchone()

    assert row is not None
    assert row[0] == "canonical_job_created"
    assert row[1] == "job"
    assert row[3]["source_type"] == "GREENHOUSE"


def test_metric_events_are_append_only(db, failing) -> None:
    """A measurement that can be edited after the fact is not a measurement."""
    db.execute(
        "insert into metric_events (event_name, numeric_value) values ('scan_started', 1)"
    )

    with failing(psycopg.errors.RaiseException):
        db.execute("update metric_events set numeric_value = 999")

    with failing(psycopg.errors.RaiseException):
        db.execute("delete from metric_events")


def test_metric_event_requires_a_name(db, failing) -> None:
    with failing(psycopg.errors.CheckViolation):
        db.execute("insert into metric_events (event_name) values ('  ')")
