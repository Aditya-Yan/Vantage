"""Structured logging.

Named ``logging_config`` rather than ``logging`` so it can never shadow the
standard library module for anything importing from inside this package.

MASTER_PLAN 26 requires that every important operation carry correlation
identifiers, and that secrets never reach the log. Both are enforced here
rather than left to each call site:

* ``bind_context()`` attaches correlation IDs to a contextvar, so they follow
  the operation across ``await`` boundaries without being threaded through
  every function signature.
* ``_redact_secrets`` runs as a processor on every event, so a secret cannot be
  logged even by accident.
"""

from __future__ import annotations

import logging
import sys
from typing import Any

import structlog
from pydantic import SecretStr

# Correlation identifiers from MASTER_PLAN 26. Bound once per operation.
CORRELATION_KEYS = (
    "scan_run_id",
    "discovery_id",
    "job_id",
    "research_task_id",
    "company_id",
)

# Substrings that mark a key as sensitive regardless of its value's type.
# MASTER_PLAN 26 forbids logging API keys, tokens, cookies, and credentials.
_SENSITIVE_KEY_PARTS = (
    "api_key",
    "secret",
    "token",
    "password",
    "cookie",
    "authorization",
    "service_role",
    "db_url",
)

REDACTED = "***"


def _is_sensitive_key(key: str) -> bool:
    lowered = key.lower()
    return any(part in lowered for part in _SENSITIVE_KEY_PARTS)


def _redact_secrets(
    _logger: Any, _method_name: str, event_dict: structlog.types.EventDict
) -> structlog.types.EventDict:
    """Replace secret values before they are rendered.

    Catches both `SecretStr` instances and values whose key names them as
    sensitive, since a secret that has already been unwrapped to `str` is
    exactly the case that would otherwise leak.
    """
    for key, value in list(event_dict.items()):
        if value is None:
            # An absent value leaks nothing, and keeping it None preserves the
            # distinction between "not configured" and "configured but hidden".
            continue
        if isinstance(value, SecretStr) or _is_sensitive_key(key):
            event_dict[key] = REDACTED
    return event_dict


def configure_logging(level: str = "info", *, json_output: bool = True) -> None:
    """Configure structlog process-wide.

    Args:
        level: Minimum level to emit.
        json_output: JSON when True. Set False for human-readable local output;
            production always uses JSON.
    """
    numeric_level = getattr(logging, level.upper(), logging.INFO)

    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=numeric_level,
    )

    renderer: Any = (
        structlog.processors.JSONRenderer()
        if json_output
        else structlog.dev.ConsoleRenderer(colors=False)
    )

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            _redact_secrets,
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(numeric_level),
        logger_factory=structlog.PrintLoggerFactory(file=sys.stdout),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str | None = None) -> structlog.stdlib.BoundLogger:
    """Return a bound logger."""
    return structlog.get_logger(name)


def bind_context(**kwargs: Any) -> None:
    """Bind correlation identifiers for the current context.

    Values of ``None`` are dropped, so an unknown identifier stays absent
    rather than being logged as null.
    """
    present = {k: v for k, v in kwargs.items() if v is not None}
    if present:
        structlog.contextvars.bind_contextvars(**present)


def clear_context() -> None:
    """Clear all bound correlation identifiers.

    Call at the end of an operation so identifiers never leak into unrelated
    work on a reused worker thread or task.
    """
    structlog.contextvars.clear_contextvars()
