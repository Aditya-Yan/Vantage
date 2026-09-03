"""CLI tests."""

from __future__ import annotations

import json

import pytest

from recruiting_intel import __version__
from recruiting_intel.cli import build_parser, main


@pytest.fixture(autouse=True)
def clean_env(monkeypatch: pytest.MonkeyPatch) -> None:
    for var in ("APP_ENV", "LOG_LEVEL", "LLM_API_KEY", "SUPABASE_URL", "GITHUB_TOKEN"):
        monkeypatch.delenv(var, raising=False)


def test_health_exits_zero(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["health"]) == 0
    assert capsys.readouterr().out.strip()


def test_health_emits_expected_fields(capsys: pytest.CaptureFixture[str]) -> None:
    main(["health"])

    record = json.loads(capsys.readouterr().out.strip().splitlines()[-1])

    assert record["event"] == "health_check"
    assert record["status"] == "ok"
    assert record["version"] == __version__
    assert record["config_loaded"] is True
    assert "python" in record


def test_health_reports_unconfigured_integrations(capsys: pytest.CaptureFixture[str]) -> None:
    """With no credentials, health must say so rather than claiming readiness."""
    main(["health"])

    record = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    integrations = record["integrations_configured"]

    assert integrations["supabase"] is False
    assert integrations["llm"] is False


def test_health_reflects_configured_integration(
    capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("GITHUB_TOKEN", "a-token")

    main(["health"])

    record = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert record["integrations_configured"]["github"] is True
    # The token itself must never appear in the output.
    assert "a-token" not in json.dumps(record)


def test_no_command_prints_help_and_exits_nonzero(capsys: pytest.CaptureFixture[str]) -> None:
    assert main([]) == 2
    assert "usage:" in capsys.readouterr().out


def test_unknown_command_exits_nonzero() -> None:
    # argparse raises SystemExit(2) for an unrecognized subcommand.
    with pytest.raises(SystemExit) as excinfo:
        main(["definitely-not-a-command"])

    assert excinfo.value.code != 0


def test_text_output_is_not_json(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["--text", "health"]) == 0

    out = capsys.readouterr().out.strip()
    assert "health_check" in out
    with pytest.raises(json.JSONDecodeError):
        json.loads(out.splitlines()[-1])


def test_parser_exposes_health_subcommand() -> None:
    args = build_parser().parse_args(["health"])
    assert args.command == "health"
