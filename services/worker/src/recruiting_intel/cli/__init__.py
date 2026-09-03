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
from recruiting_intel.logging_config import configure_logging, get_logger


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
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Entry point. Returns a process exit code."""
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        return 2

    settings = Settings()
    configure_logging(
        level=args.log_level or settings.log_level,
        json_output=not args.text,
    )

    return int(args.func(args, settings))


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
