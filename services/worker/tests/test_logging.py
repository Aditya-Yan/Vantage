"""Structured logging tests.

Two properties matter enough to pin with tests:

* correlation identifiers survive across await boundaries (MASTER_PLAN 26);
* secrets never reach the output, even when passed directly to a log call.
"""

from __future__ import annotations

import json
from collections.abc import Iterator

import pytest
from pydantic import SecretStr

from recruiting_intel.logging_config import (
    REDACTED,
    bind_context,
    clear_context,
    configure_logging,
    get_logger,
)


@pytest.fixture(autouse=True)
def fresh_logging() -> Iterator[None]:
    configure_logging(level="debug", json_output=True)
    clear_context()
    yield
    clear_context()


def _emit(capsys: pytest.CaptureFixture[str], **kwargs: object) -> dict:
    """Log one event and return it parsed."""
    get_logger("test").info("test_event", **kwargs)
    captured = capsys.readouterr().out.strip()
    assert captured, "expected a log line on stdout"
    return json.loads(captured.splitlines()[-1])


def test_emits_parseable_json(capsys: pytest.CaptureFixture[str]) -> None:
    record = _emit(capsys)

    assert record["event"] == "test_event"
    assert record["level"] == "info"
    assert "timestamp" in record


def test_event_fields_are_included(capsys: pytest.CaptureFixture[str]) -> None:
    record = _emit(capsys, source_type="greenhouse", items_seen=42)

    assert record["source_type"] == "greenhouse"
    assert record["items_seen"] == 42


def test_bound_correlation_ids_appear(capsys: pytest.CaptureFixture[str]) -> None:
    bind_context(scan_run_id="scan-1", company_id="company-9", job_id="job-3")

    record = _emit(capsys)

    assert record["scan_run_id"] == "scan-1"
    assert record["company_id"] == "company-9"
    assert record["job_id"] == "job-3"


def test_none_correlation_ids_are_dropped(capsys: pytest.CaptureFixture[str]) -> None:
    bind_context(scan_run_id="scan-1", job_id=None)

    record = _emit(capsys)

    assert record["scan_run_id"] == "scan-1"
    # Unknown stays absent rather than being logged as null.
    assert "job_id" not in record


def test_clear_context_removes_ids(capsys: pytest.CaptureFixture[str]) -> None:
    bind_context(scan_run_id="scan-1")
    clear_context()

    record = _emit(capsys)

    assert "scan_run_id" not in record


async def test_context_survives_await(capsys: pytest.CaptureFixture[str]) -> None:
    """Correlation IDs must follow an operation across await boundaries.

    This is the whole reason for contextvar binding rather than passing a
    logger through every signature.
    """
    import asyncio

    bind_context(research_task_id="task-7")

    async def inner() -> None:
        await asyncio.sleep(0)
        get_logger("test").info("inner_event")

    await inner()

    record = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert record["research_task_id"] == "task-7"


def test_secretstr_value_is_redacted(capsys: pytest.CaptureFixture[str]) -> None:
    record = _emit(capsys, llm_api_key=SecretStr("sk-super-secret"))

    assert record["llm_api_key"] == REDACTED
    assert "sk-super-secret" not in json.dumps(record)


def test_sensitive_key_is_redacted_even_as_plain_string(
    capsys: pytest.CaptureFixture[str],
) -> None:
    """A secret already unwrapped to `str` is the case most likely to leak."""
    record = _emit(capsys, api_key="raw-value", access_token="another-raw-value")

    assert record["api_key"] == REDACTED
    assert record["access_token"] == REDACTED
    assert "raw-value" not in json.dumps(record)


def test_nonsensitive_fields_are_not_redacted(capsys: pytest.CaptureFixture[str]) -> None:
    record = _emit(capsys, company_id="meta", raw_title="Production Engineer Intern")

    # Raw titles must survive the pipeline exactly (MASTER_PLAN 0.15).
    assert record["raw_title"] == "Production Engineer Intern"
    assert record["company_id"] == "meta"
