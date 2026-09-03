"""Metrics service.

Business logic calls semantic methods here rather than writing SQL. Internally
every call appends one row to `metric_events`.

Three design rules, each with a reason:

1. **Instrumentation never breaks the pipeline.** A failed metric write is
   logged and swallowed. Losing a measurement is bad; losing an ingested job
   because its metric write failed is worse.

2. **Nothing is estimated.** Every method records values its caller actually
   observed. There is no method that derives, interpolates, or defaults a
   measurement, because `docs/METRICS.md` forbids reporting numbers that do not
   trace to stored data.

3. **Event names are a closed vocabulary.** `EVENT_NAMES` is the registry;
   emitting an unregistered name is a programming error, caught in tests rather
   than discovered as a gap in a dashboard months later.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol
from uuid import UUID

from recruiting_intel.logging_config import get_logger

# The closed vocabulary. The six methods named in MASTER_PLAN 2D, plus the
# events those stages need to make their metrics computable. Later phases add
# names here as they add stages.
EVENT_NAMES: frozenset[str] = frozenset(
    {
        "scan_started",
        "scan_completed",
        "scan_failed",
        "discovery_created",
        "classification_completed",
        "duplicate_collapsed",
        "canonical_job_created",
        "research_enqueued",
        "research_completed",
    }
)


@dataclass(frozen=True)
class MetricEvent:
    """One measurement."""

    event_name: str
    entity_type: str | None = None
    entity_id: UUID | None = None
    numeric_value: float | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


class MetricSink(Protocol):
    """Where measurements go.

    Kept minimal so tests can record events without a database, and so the
    storage decision stays behind one method.
    """

    def emit(self, event: MetricEvent) -> None: ...


class Metrics:
    """Semantic instrumentation API.

    Args:
        sink: Destination for events. `PostgresMetricSink` in production,
            `RecordingMetrics` or `NullMetrics` in tests.
    """

    def __init__(self, sink: MetricSink) -> None:
        self._sink = sink
        self._log = get_logger(__name__)

    # -- Emission ---------------------------------------------------------
    def _emit(
        self,
        event_name: str,
        *,
        entity_type: str | None = None,
        entity_id: UUID | None = None,
        numeric_value: float | None = None,
        **metadata: Any,
    ) -> None:
        if event_name not in EVENT_NAMES:
            # A programming error, not a runtime condition. Raising keeps
            # typos out of the metric vocabulary.
            raise ValueError(
                f"unregistered metric event {event_name!r}; add it to EVENT_NAMES"
            )

        event = MetricEvent(
            event_name=event_name,
            entity_type=entity_type,
            entity_id=entity_id,
            numeric_value=numeric_value,
            metadata=metadata,
        )

        try:
            self._sink.emit(event)
        except Exception as exc:
            # Instrumentation must never take down the pipeline. Log loudly so
            # the gap is visible rather than silent.
            self._log.error(
                "metric_emit_failed",
                metric_event=event_name,
                entity_type=entity_type,
                entity_id=str(entity_id) if entity_id else None,
                error_class=type(exc).__name__,
                error=str(exc),
            )

    # -- Ingestion --------------------------------------------------------
    def scan_started(self, *, scan_run_id: UUID, source_config_id: UUID) -> None:
        self._emit(
            "scan_started",
            entity_type="scan_run",
            entity_id=scan_run_id,
            source_config_id=str(source_config_id),
        )

    def scan_completed(
        self,
        *,
        scan_run_id: UUID,
        source_config_id: UUID,
        duration_ms: int,
        items_seen: int,
        discoveries_created: int,
        http_requests: int,
    ) -> None:
        """Record a successful scan.

        `duration_ms` is the headline value; the counts travel as metadata so
        per-source comparisons stay computable.
        """
        self._emit(
            "scan_completed",
            entity_type="scan_run",
            entity_id=scan_run_id,
            numeric_value=duration_ms,
            source_config_id=str(source_config_id),
            items_seen=items_seen,
            discoveries_created=discoveries_created,
            http_requests=http_requests,
        )

    def scan_failed(
        self,
        *,
        scan_run_id: UUID,
        source_config_id: UUID,
        error_type: str,
        retryable: bool,
    ) -> None:
        self._emit(
            "scan_failed",
            entity_type="scan_run",
            entity_id=scan_run_id,
            source_config_id=str(source_config_id),
            error_type=error_type,
            retryable=retryable,
        )

    def discovery_created(
        self, *, discovery_id: UUID, source_config_id: UUID, source_type: str
    ) -> None:
        self._emit(
            "discovery_created",
            entity_type="discovery",
            entity_id=discovery_id,
            source_config_id=str(source_config_id),
            source_type=source_type,
        )

    # -- Classification ---------------------------------------------------
    def classification_completed(
        self,
        *,
        classification_id: UUID,
        method: str,
        role_family: str,
        confidence: float,
        accepted: bool,
        llm_tokens: int | None = None,
        llm_cost: float | None = None,
    ) -> None:
        """Record one classification decision.

        `method` is what makes the "classified without an LLM" metric
        computable, so it is always recorded. Token and cost fields stay None
        for non-LLM methods rather than defaulting to zero: absent and zero are
        different measurements.
        """
        self._emit(
            "classification_completed",
            entity_type="classification",
            entity_id=classification_id,
            numeric_value=confidence,
            method=method,
            role_family=role_family,
            accepted=accepted,
            llm_tokens=llm_tokens,
            llm_cost=llm_cost,
        )

    # -- Deduplication ----------------------------------------------------
    def duplicate_collapsed(
        self,
        *,
        job_id: UUID,
        discovery_id: UUID,
        match_level: str,
        source_type: str,
    ) -> None:
        """Record a discovery collapsing into an existing canonical job.

        `match_level` records which rung of the dedupe hierarchy matched, so
        the per-level breakdown in docs/METRICS.md is real rather than assumed.
        """
        self._emit(
            "duplicate_collapsed",
            entity_type="job",
            entity_id=job_id,
            discovery_id=str(discovery_id),
            match_level=match_level,
            source_type=source_type,
        )

    def canonical_job_created(
        self, *, job_id: UUID, company_id: UUID, source_type: str
    ) -> None:
        self._emit(
            "canonical_job_created",
            entity_type="job",
            entity_id=job_id,
            company_id=str(company_id),
            source_type=source_type,
        )

    # -- Research ---------------------------------------------------------
    def research_enqueued(self, *, job_id: UUID, company_id: UUID) -> None:
        self._emit(
            "research_enqueued",
            entity_type="job",
            entity_id=job_id,
            company_id=str(company_id),
        )

    def research_completed(
        self,
        *,
        job_id: UUID,
        duration_ms: int,
        recruiters_found: int,
        evidence_sources: int,
        linkedin_blocked: bool = False,
    ) -> None:
        """Record a finished research task.

        Zero recruiters is a valid, correct result (MASTER_PLAN 19), so this
        method records it as readily as any other outcome. `linkedin_blocked`
        is recorded rather than hidden: the blocked-attempt rate is an honesty
        metric.
        """
        self._emit(
            "research_completed",
            entity_type="job",
            entity_id=job_id,
            numeric_value=duration_ms,
            recruiters_found=recruiters_found,
            evidence_sources=evidence_sources,
            linkedin_blocked=linkedin_blocked,
        )


# ---------------------------------------------------------------------------
# Sinks
# ---------------------------------------------------------------------------
class PostgresMetricSink:
    """Appends events to `metric_events`.

    Takes a live connection rather than opening one, so the caller controls
    transaction scope: a metric emitted inside a pipeline transaction is
    committed or rolled back with the work it describes.
    """

    def __init__(self, connection: Any) -> None:
        self._conn = connection

    def emit(self, event: MetricEvent) -> None:
        from psycopg.types.json import Jsonb

        self._conn.execute(
            """
            insert into metric_events
                (event_name, entity_type, entity_id, numeric_value, metadata_json)
            values (%s, %s, %s, %s, %s)
            """,
            (
                event.event_name,
                event.entity_type,
                event.entity_id,
                event.numeric_value,
                Jsonb(event.metadata),
            ),
        )


class RecordingMetrics:
    """In-memory sink for tests."""

    def __init__(self) -> None:
        self.events: list[MetricEvent] = []

    def emit(self, event: MetricEvent) -> None:
        self.events.append(event)

    def names(self) -> list[str]:
        return [event.event_name for event in self.events]


class NullMetrics:
    """Discards everything.

    For contexts where instrumentation is genuinely not wanted, such as a
    one-off CLI inspection command.
    """

    def emit(self, event: MetricEvent) -> None:
        return None
