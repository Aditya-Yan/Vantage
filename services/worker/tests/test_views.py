"""Metric view integration tests.

The important property is honesty on an empty system: counts read zero because
nothing has been ingested, and rates read NULL because there is nothing to
divide by. Reporting a rate of 0% with no denominator would be a fabricated
metric, which docs/METRICS.md prohibits.
"""

from __future__ import annotations

import pytest
from tests.conftest import requires_db

pytestmark = [pytest.mark.integration, requires_db]

COUNT_COLUMNS = (
    "total_companies",
    "target_companies",
    "active_source_configs",
    "total_scans",
    "successful_scans",
    "total_discoveries",
    "total_canonical_jobs",
    "active_jobs",
    "total_job_sources",
    "duplicates_collapsed",
    "total_classifications",
    "non_llm_classifications",
    "llm_classifications",
    "total_recruiters",
    "recruiters_published_email",
    "recruiters_inferred_email",
    "completed_research_tasks",
    "total_email_drafts",
)

RATE_COLUMNS = (
    "scan_success_pct",
    "non_llm_classification_pct",
    "duplicate_suppression_pct",
    "published_email_coverage_pct",
    "inferred_email_coverage_pct",
)


def _metrics(db) -> dict:
    cursor = db.execute("select * from resume_metrics")
    columns = [desc[0] for desc in cursor.description]
    row = cursor.fetchone()
    return dict(zip(columns, row, strict=True))


def test_view_exists_and_returns_exactly_one_row(db) -> None:
    count = db.execute("select count(*) from resume_metrics").fetchone()[0]
    assert count == 1


def test_all_expected_columns_present(db) -> None:
    metrics = _metrics(db)
    for column in COUNT_COLUMNS + RATE_COLUMNS:
        assert column in metrics, f"resume_metrics is missing {column}"


def test_counts_are_non_negative_integers(db) -> None:
    metrics = _metrics(db)
    for column in COUNT_COLUMNS:
        value = metrics[column]
        assert value is not None, f"{column} should be a count, not NULL"
        assert value >= 0, f"{column} is negative"


def test_pipeline_counts_are_zero_before_ingestion(db) -> None:
    """Nothing has run yet, so these are true zeros -- not placeholders.

    Companies are excluded: the seed intentionally loads a few.
    """
    metrics = _metrics(db)

    assert metrics["total_scans"] == 0
    assert metrics["total_discoveries"] == 0
    assert metrics["total_canonical_jobs"] == 0
    assert metrics["total_job_sources"] == 0
    assert metrics["duplicates_collapsed"] == 0
    assert metrics["total_classifications"] == 0
    assert metrics["total_recruiters"] == 0
    assert metrics["total_email_drafts"] == 0


def test_rates_are_null_when_denominator_is_zero(db) -> None:
    """"No data yet" and "0%" are different claims."""
    metrics = _metrics(db)

    for column in RATE_COLUMNS:
        assert metrics[column] is None, (
            f"{column} reported {metrics[column]} with an empty denominator; "
            "it must be NULL until there is something to measure"
        )


def test_rate_becomes_real_once_data_exists(db) -> None:
    """And the rate must appear as soon as the denominator is non-zero."""
    company_id = db.execute(
        "insert into companies (canonical_name) values ('Rate Test Co') returning id"
    ).fetchone()[0]
    source_id = db.execute(
        """
        insert into source_configs (company_id, source_type, source_identifier)
        values (%s, 'GREENHOUSE', 'rate-test') returning id
        """,
        (company_id,),
    ).fetchone()[0]

    db.execute(
        "insert into scan_runs (source_config_id, status, finished_at) "
        "values (%s, 'SUCCESS', now())",
        (source_id,),
    )
    db.execute(
        "insert into scan_runs (source_config_id, status, finished_at) "
        "values (%s, 'FAILED', now())",
        (source_id,),
    )

    metrics = _metrics(db)
    assert metrics["total_scans"] == 2
    assert metrics["successful_scans"] == 1
    assert float(metrics["scan_success_pct"]) == 50.00


def test_seed_loaded_companies(db) -> None:
    """Acceptance criterion: seed works."""
    metrics = _metrics(db)
    assert metrics["total_companies"] > 0
    assert metrics["target_companies"] > 0


def test_seed_marks_low_scoring_company_as_non_target(db) -> None:
    """The whitelist filter needs something to exclude."""
    row = db.execute(
        "select target_company from companies where canonical_name = 'Example Staffing Co'"
    ).fetchone()

    assert row is not None
    assert row[0] is False


def test_seed_aliases_resolve(db) -> None:
    row = db.execute(
        """
        select c.canonical_name
        from company_aliases a
        join companies c on c.id = a.company_id
        where lower(a.alias) = 'facebook'
        """
    ).fetchone()

    assert row is not None
    assert row[0] == "Meta"


def test_seed_leaves_pipeline_tables_empty(db) -> None:
    """Seeded discoveries would make every pipeline metric a fiction."""
    for table in ("discoveries", "jobs", "recruiters", "metric_events"):
        count = db.execute(f"select count(*) from {table}").fetchone()[0]
        assert count == 0, f"{table} should be empty after seeding, found {count}"


# ---------------------------------------------------------------------------
# Snapshots
# ---------------------------------------------------------------------------
def test_snapshot_captures_counts(db) -> None:
    written = db.execute("select capture_daily_metric_snapshot()").fetchone()[0]
    assert written > 0

    row = db.execute(
        """
        select metric_value from daily_metric_snapshots
        where snapshot_date = current_date and metric_name = 'total_companies'
        """
    ).fetchone()
    assert row is not None


def test_snapshot_skips_null_rates(db) -> None:
    """An absent measurement must not be snapshotted as zero."""
    db.execute("select capture_daily_metric_snapshot()")

    row = db.execute(
        """
        select count(*) from daily_metric_snapshots
        where snapshot_date = current_date and metric_name = 'scan_success_pct'
        """
    ).fetchone()

    assert row[0] == 0


def test_snapshot_is_idempotent_within_a_day(db) -> None:
    db.execute("select capture_daily_metric_snapshot()")
    db.execute("select capture_daily_metric_snapshot()")

    row = db.execute(
        """
        select count(*) from daily_metric_snapshots
        where snapshot_date = current_date and metric_name = 'total_companies'
        """
    ).fetchone()

    assert row[0] == 1
