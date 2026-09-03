"""Database access.

Plain psycopg 3 with hand-written SQL (ADR-012). No ORM: the schema is the
interface, and deduplication correctness depends on specific constraint
behavior that a mapping layer would obscure.
"""

from recruiting_intel.db.connection import (
    DEFAULT_LOCAL_DB_URL,
    DatabaseUnavailable,
    connect,
    database_url,
    is_reachable,
)

__all__ = [
    "DEFAULT_LOCAL_DB_URL",
    "DatabaseUnavailable",
    "connect",
    "database_url",
    "is_reachable",
]
