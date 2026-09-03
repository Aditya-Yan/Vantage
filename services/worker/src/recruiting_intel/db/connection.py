"""Database connections.

Deliberately small. This module resolves a connection URL and hands out
connections; it does not wrap SQL, manage schema, or model rows. Migrations are
owned by the Supabase CLI and live in `supabase/migrations/`.
"""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

import psycopg

from recruiting_intel.config import Settings

# The local Supabase stack's Postgres, per supabase/config.toml (db.port).
# Used only when SUPABASE_DB_URL is unset, so local development needs no
# environment setup at all.
DEFAULT_LOCAL_DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"


class DatabaseUnavailable(RuntimeError):
    """Raised when the database cannot be reached.

    Distinct from a query error: this means the server is not there, which is
    the expected state when the local Supabase stack is not running. Callers
    use it to report an actionable message rather than a stack trace.
    """


def database_url(settings: Settings | None = None) -> str:
    """Resolve the connection URL.

    Prefers the configured `SUPABASE_DB_URL`, falling back to the local stack.
    """
    settings = settings or Settings()
    configured = settings.supabase_db_url
    if configured is not None:
        return configured.get_secret_value()
    return DEFAULT_LOCAL_DB_URL


@contextmanager
def connect(
    settings: Settings | None = None,
    *,
    url: str | None = None,
    autocommit: bool = False,
) -> Iterator[psycopg.Connection]:
    """Open a connection, closing it on exit.

    Raises `DatabaseUnavailable` when the server cannot be reached, so callers
    can distinguish "not running" from "query failed".
    """
    target = url or database_url(settings)
    try:
        conn = psycopg.connect(target, autocommit=autocommit)
    except psycopg.OperationalError as exc:
        raise DatabaseUnavailable(str(exc)) from exc

    try:
        yield conn
    finally:
        conn.close()


def is_reachable(settings: Settings | None = None, *, url: str | None = None) -> bool:
    """Return whether the database answers.

    Used to decide whether integration tests can run, and by `worker db check`.
    """
    try:
        with connect(settings, url=url) as conn:
            conn.execute("select 1")
    except DatabaseUnavailable:
        return False
    return True
