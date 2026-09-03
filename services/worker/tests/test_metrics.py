"""Metrics service tests.

These run without a database. The integration counterpart in
test_schema.py exercises the real Postgres sink.
"""

from __future__ import annotations

import json
from uuid import uuid4

import pytest

from recruiting_intel.metrics import (
    EVENT_NAMES,
    Metrics,
    NullMetrics,
    RecordingMetrics,
)


@pytest.fixture
def sink() -> RecordingMetrics:
    return RecordingMetrics()


@pytest.fixture
def metrics(sink: RecordingMetrics) -> Metrics:
    return Metrics(sink)


# ---------------------------------------------------------------------------
# Vocabulary
# ---------------------------------------------------------------------------
def test_rejects_unregistered_event_name(metrics: Metrics) -> None:
    """A typo must fail loudly, not quietly create a new metric name."""
    with pytest.raises(ValueError, match="unregistered metric event"):
        metrics._emit("scan_startd")


def test_every_semantic_method_emits_a_registered_name(
    metrics: Metrics, sink: RecordingMetrics
) -> None:
    job_id, company_id, source_id = uuid4(), uuid4(), uuid4()

    metrics.scan_started(scan_run_id=uuid4(), source_config_id=source_id)
    metrics.scan_completed(
        scan_run_id=uuid4(),
        source_config_id=source_id,
        duration_ms=120,
        items_seen=10,
        discoveries_created=3,
        http_requests=2,
    )
    metrics.scan_failed(
        scan_run_id=uuid4(),
        source_config_id=source_id,
        error_type="timeout",
        retryable=True,
    )
    metrics.discovery_created(
        discovery_id=uuid4(), source_config_id=source_id, source_type="GREENHOUSE"
    )
    metrics.classification_completed(
        classification_id=uuid4(),
        method="DETERMINISTIC_RULES",
        role_family="SOFTWARE_ENGINEERING",
        confidence=0.9,
        accepted=True,
    )
    metrics.duplicate_collapsed(
        job_id=job_id,
        discovery_id=uuid4(),
        match_level="ats_id",
        source_type="GITHUB_TRACKER",
    )
    metrics.canonical_job_created(
        job_id=job_id, company_id=company_id, source_type="GREENHOUSE"
    )
    metrics.research_enqueued(job_id=job_id, company_id=company_id)
    metrics.research_completed(
        job_id=job_id, duration_ms=4200, recruiters_found=2, evidence_sources=5
    )

    assert len(sink.events) == 9
    for name in sink.names():
        assert name in EVENT_NAMES


# ---------------------------------------------------------------------------
# Event content
# ---------------------------------------------------------------------------
def test_scan_completed_records_observed_counts(
    metrics: Metrics, sink: RecordingMetrics
) -> None:
    scan_id = uuid4()

    metrics.scan_completed(
        scan_run_id=scan_id,
        source_config_id=uuid4(),
        duration_ms=250,
        items_seen=42,
        discoveries_created=7,
        http_requests=3,
    )

    event = sink.events[0]
    assert event.entity_type == "scan_run"
    assert event.entity_id == scan_id
    assert event.numeric_value == 250
    assert event.metadata["items_seen"] == 42
    assert event.metadata["discoveries_created"] == 7
    assert event.metadata["http_requests"] == 3


def test_classification_records_method_for_llm_avoidance_metric(
    metrics: Metrics, sink: RecordingMetrics
) -> None:
    """`method` is what makes "classified without an LLM" computable."""
    metrics.classification_completed(
        classification_id=uuid4(),
        method="COMPANY_ALIAS",
        role_family="SOFTWARE_ENGINEERING",
        confidence=0.95,
        accepted=True,
    )

    event = sink.events[0]
    assert event.metadata["method"] == "COMPANY_ALIAS"
    # Absent, not zero: a non-LLM classification did not cost zero tokens, it
    # cost no tokens at all, and the two are different measurements.
    assert event.metadata["llm_tokens"] is None
    assert event.metadata["llm_cost"] is None


def test_llm_classification_records_usage(
    metrics: Metrics, sink: RecordingMetrics
) -> None:
    metrics.classification_completed(
        classification_id=uuid4(),
        method="LLM_FALLBACK",
        role_family="SOFTWARE_ENGINEERING",
        confidence=0.7,
        accepted=True,
        llm_tokens=480,
        llm_cost=0.0012,
    )

    event = sink.events[0]
    assert event.metadata["llm_tokens"] == 480
    assert event.metadata["llm_cost"] == 0.0012


def test_duplicate_collapsed_records_match_level(
    metrics: Metrics, sink: RecordingMetrics
) -> None:
    """The per-level dedupe breakdown must be measured, not assumed."""
    metrics.duplicate_collapsed(
        job_id=uuid4(),
        discovery_id=uuid4(),
        match_level="canonical_url",
        source_type="REDDIT",
    )

    assert sink.events[0].metadata["match_level"] == "canonical_url"


def test_research_completing_with_zero_recruiters_is_recorded(
    metrics: Metrics, sink: RecordingMetrics
) -> None:
    """Zero recruiters is a valid result, not a failure to be hidden."""
    metrics.research_completed(
        job_id=uuid4(), duration_ms=900, recruiters_found=0, evidence_sources=0
    )

    event = sink.events[0]
    assert event.event_name == "research_completed"
    assert event.metadata["recruiters_found"] == 0


def test_linkedin_blocked_is_recorded_not_hidden(
    metrics: Metrics, sink: RecordingMetrics
) -> None:
    metrics.research_completed(
        job_id=uuid4(),
        duration_ms=1500,
        recruiters_found=1,
        evidence_sources=2,
        linkedin_blocked=True,
    )

    assert sink.events[0].metadata["linkedin_blocked"] is True


# ---------------------------------------------------------------------------
# Failure isolation
# ---------------------------------------------------------------------------
class _ExplodingSink:
    def emit(self, event: object) -> None:
        raise RuntimeError("database is on fire")


def test_sink_failure_does_not_propagate(capsys: pytest.CaptureFixture[str]) -> None:
    """Losing a measurement must never lose the work it measured."""
    from recruiting_intel.logging_config import configure_logging

    configure_logging(level="debug", json_output=True)
    metrics = Metrics(_ExplodingSink())

    # Must not raise.
    metrics.canonical_job_created(
        job_id=uuid4(), company_id=uuid4(), source_type="GREENHOUSE"
    )

    record = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert record["event"] == "metric_emit_failed"
    assert record["level"] == "error"
    assert record["metric_event"] == "canonical_job_created"
    assert record["error_class"] == "RuntimeError"


def test_unregistered_name_still_raises_despite_failure_isolation(
    metrics: Metrics,
) -> None:
    """Swallowing sink errors must not also swallow programming errors."""
    with pytest.raises(ValueError):
        metrics._emit("not_a_real_event")


# ---------------------------------------------------------------------------
# Null sink
# ---------------------------------------------------------------------------
def test_null_metrics_discards_without_error() -> None:
    metrics = Metrics(NullMetrics())
    metrics.research_enqueued(job_id=uuid4(), company_id=uuid4())
