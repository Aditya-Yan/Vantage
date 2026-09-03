"""Worker command-line interface.

Uses `argparse` from the standard library rather than a CLI framework: the
command surface is small and adding a dependency would buy nothing here.

Subcommands are registered through `_add_*_parser` helpers so later phases can
add their own (`worker ingest --source <id>` in Phase 4A) without restructuring
this module.
"""

from __future__ import annotations

import argparse
import platform
import sys
from collections.abc import Sequence

from recruiting_intel import __version__
from recruiting_intel.config import Settings
from recruiting_intel.db import DatabaseUnavailable, connect, database_url
from recruiting_intel.logging_config import configure_logging, get_logger

# Printed whenever the database is unreachable. The local stack needs Docker
# running, which is the usual cause.
_DB_HELP = (
    "Database unreachable. Start it with: docker info && supabase start "
    "(then: supabase db reset)"
)


def _add_health_parser(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser(
        "health",
        help="Report worker status and which integrations are configured.",
    )
    parser.set_defaults(func=_cmd_health)


def _cmd_health(_args: argparse.Namespace, settings: Settings) -> int:
    """Report worker health.

    Reports what is actually true: the package loads, configuration parses, and
    these integrations are or are not configured. It does not check that any
    integration *works* — nothing is wired up until Phase 2.
    """
    log = get_logger(__name__)
    log.info(
        "health_check",
        status="ok",
        version=__version__,
        python=platform.python_version(),
        app_env=settings.app_env,
        config_loaded=True,
        integrations_configured=settings.configured_integrations(),
    )
    return 0


def _add_db_parser(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser(
        "db",
        help="Inspect the database.",
    )
    db_sub = parser.add_subparsers(dest="db_command", metavar="<subcommand>")

    check = db_sub.add_parser(
        "check", help="Report connectivity, applied migrations, and table counts."
    )
    check.set_defaults(func=_cmd_db_check)


def _cmd_db_check(args: argparse.Namespace, settings: Settings) -> int:
    """Report what is actually true about the database.

    Distinguishes "not running" (exit 1, actionable message) from "running but
    unmigrated" (exit 1, different message) from healthy. Reporting a schema as
    present when it is not would make every later phase debug the wrong thing.
    """
    log = get_logger(__name__)

    if getattr(args, "db_command", None) is None:
        log.error("db_check_failed", reason="no subcommand given")
        return 2

    try:
        with connect(settings) as conn:
            version = conn.execute("select version()").fetchone()
            tables = conn.execute(
                """
                select table_name
                from information_schema.tables
                where table_schema = 'public' and table_type = 'BASE TABLE'
                order by table_name
                """
            ).fetchall()
            table_names = [row[0] for row in tables]

            migrations: list[str] = []
            try:
                rows = conn.execute(
                    "select version from supabase_migrations.schema_migrations "
                    "order by version"
                ).fetchall()
                migrations = [row[0] for row in rows]
            except Exception:
                # The migration table only exists once the CLI has applied
                # migrations at least once. Absence is information, not error.
                conn.rollback()

            has_queue = bool(
                conn.execute(
                    "select 1 from pg_extension where extname = 'pgmq'"
                ).fetchone()
            )
    except DatabaseUnavailable as exc:
        log.error(
            "db_check_failed",
            status="unreachable",
            url=_redact_db_url(database_url(settings)),
            hint=_DB_HELP,
            error=str(exc).strip().splitlines()[0] if str(exc).strip() else "",
        )
        return 1

    healthy = bool(table_names) and bool(migrations)
    log.info(
        "db_check",
        status="ok" if healthy else "unmigrated",
        url=_redact_db_url(database_url(settings)),
        server_version=version[0].split(" on ")[0] if version else None,
        migrations_applied=len(migrations),
        latest_migration=migrations[-1] if migrations else None,
        tables=len(table_names),
        table_names=table_names,
        pgmq_installed=has_queue,
        hint=None if healthy else "Run: supabase db reset",
    )
    return 0 if healthy else 1


def _redact_db_url(url: str) -> str:
    """Strip credentials from a connection URL before it reaches a log."""
    if "@" not in url:
        return url
    scheme, _, rest = url.partition("://")
    _, _, host_part = rest.partition("@")
    return f"{scheme}://***@{host_part}"


def _add_metrics_parser(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser(
        "metrics",
        help="Inspect collected metrics.",
    )
    metrics_sub = parser.add_subparsers(dest="metrics_command", metavar="<subcommand>")

    show = metrics_sub.add_parser("show", help="Print the resume_metrics view.")
    show.set_defaults(func=_cmd_metrics_show)


def _cmd_metrics_show(args: argparse.Namespace, settings: Settings) -> int:
    """Print the resume_metrics view as it actually stands.

    On an empty system every count is 0 and every rate is null. Both are
    reported verbatim: a null rate means "no data yet", which is a different
    claim from 0%, and collapsing the two would be exactly the kind of
    fabricated metric docs/METRICS.md prohibits.
    """
    log = get_logger(__name__)

    if getattr(args, "metrics_command", None) is None:
        log.error("metrics_show_failed", reason="no subcommand given")
        return 2

    try:
        with connect(settings) as conn:
            cursor = conn.execute("select * from resume_metrics")
            columns = [desc[0] for desc in cursor.description or []]
            row = cursor.fetchone()

            event_total = conn.execute("select count(*) from metric_events").fetchone()
    except DatabaseUnavailable as exc:
        log.error(
            "metrics_show_failed",
            status="unreachable",
            hint=_DB_HELP,
            error=str(exc).strip().splitlines()[0] if str(exc).strip() else "",
        )
        return 1

    if row is None:
        log.error("metrics_show_failed", reason="resume_metrics returned no row")
        return 1

    values = {
        name: (float(value) if hasattr(value, "as_integer_ratio") else value)
        for name, value in zip(columns, row, strict=True)
    }

    log.info(
        "resume_metrics",
        metric_events_recorded=event_total[0] if event_total else 0,
        **values,
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="worker",
        description="Recruiting intelligence platform worker.",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    parser.add_argument(
        "--log-level",
        choices=["debug", "info", "warning", "error", "critical"],
        help="Override the configured log level.",
    )
    parser.add_argument(
        "--text",
        action="store_true",
        help="Human-readable log output instead of JSON.",
    )

    subparsers = parser.add_subparsers(dest="command", metavar="<command>")
    _add_health_parser(subparsers)
    _add_db_parser(subparsers)
    _add_metrics_parser(subparsers)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Entry point. Returns a process exit code."""
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        return 2

    # A command group invoked without a subcommand ("worker db") sets no
    # handler. Show usage rather than failing on a missing attribute.
    if not hasattr(args, "func"):
        parser.parse_args([args.command, "--help"])
        return 2

    settings = Settings()
    configure_logging(
        level=args.log_level or settings.log_level,
        json_output=not args.text,
    )

    return int(args.func(args, settings))


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
