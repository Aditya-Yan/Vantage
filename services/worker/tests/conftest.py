"""Shared test fixtures.

Integration tests need a real Postgres: foreign keys, check constraints, and
partial unique indexes cannot be verified against a mock without testing the
mock instead of the schema.

They are marked `@pytest.mark.integration` and skipped when the database is
unreachable. The skip is deliberately visible -- `scripts/verify.sh` reports it
prominently -- because a suite that silently skips is indistinguishable from
one that passes, and that is the more dangerous failure.
"""

from __future__ import annotations

import os
from collections.abc import Iterator

import pytest

from recruiting_intel.db import DEFAULT_LOCAL_DB_URL, DatabaseUnavailable, connect

TEST_DB_URL = os.environ.get("SUPABASE_DB_URL", DEFAULT_LOCAL_DB_URL)

SKIP_REASON = (
    "Postgres unreachable at "
    f"{TEST_DB_URL.rsplit('@', 1)[-1]} -- schema is UNVERIFIED. "
    "Start it with: supabase start && supabase db reset"
)


def _database_available() -> bool:
    try:
        with connect(url=TEST_DB_URL) as conn:
            conn.execute("select 1")
    except DatabaseUnavailable:
        return False
    return True


DATABASE_AVAILABLE = _database_available()

requires_db = pytest.mark.skipif(not DATABASE_AVAILABLE, reason=SKIP_REASON)


@pytest.fixture
def db() -> Iterator[object]:
    """A connection whose work is always rolled back.

    Every integration test runs inside a transaction that is discarded, so the
    suite is order-independent and leaves the developer's database exactly as
    it found it. Tests that need to observe constraint violations use
    savepoints (see `failing`).
    """
    with connect(url=TEST_DB_URL) as conn:
        try:
            yield conn
        finally:
            conn.rollback()


@pytest.fixture
def failing(db):
    """Run a statement expected to raise, without poisoning the transaction.

    A failed statement aborts the surrounding Postgres transaction, so asserting
    on several rejections in one test needs a savepoint around each.
    """
    import contextlib

    @contextlib.contextmanager
    def _expect(exception: type[Exception]):
        with pytest.raises(exception), db.transaction():
            yield

    return _expect
