from typer.testing import CliRunner

from invest import __version__
from invest.cli import app

runner = CliRunner()


def test_version_command_prints_version() -> None:
    result = runner.invoke(app, ["version"])
    assert result.exit_code == 0
    assert result.stdout.strip() == __version__


def test_signals_commands_are_registered() -> None:
    result = runner.invoke(app, ["signals", "--help"])
    assert result.exit_code == 0
    for command in ("scan", "record", "evaluate", "backfill", "ledger", "lab"):
        assert command in result.stdout


def test_signals_reject_a_malformed_date_before_touching_the_database() -> None:
    result = runner.invoke(app, ["signals", "scan", "--as-of", "yesterday"])
    assert result.exit_code == 1
    assert "ISO date" in result.output
