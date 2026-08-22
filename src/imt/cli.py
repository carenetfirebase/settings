"""``imt`` command line. Every job is independently runnable.

Windows Task Scheduler calls ``scripts/run_job.ps1``, which calls into here.
Jobs are separate processes so a stalled EDGAR fetch cannot wedge the scorer,
and so a failure is visible in the scheduler's own history.
"""

from __future__ import annotations

import typer

from imt.core.config import get_settings, load_sources
from imt.core.logging import configure_logging, get_logger

app = typer.Typer(
    name="imt",
    help="Informed Money Terminal — research priority, not recommendations.",
    no_args_is_help=True,
)
ingest_app = typer.Typer(help="Ingestion jobs. Each fetches, persists raw, then normalizes.")
score_app = typer.Typer(help="Scoring. Deterministic; as-of date is always explicit.")
entities_app = typer.Typer(help="Entity resolution and its review queue.")
db_app = typer.Typer(help="Database inspection.")

app.add_typer(ingest_app, name="ingest")
app.add_typer(score_app, name="score")
app.add_typer(entities_app, name="entities")
app.add_typer(db_app, name="db")

log = get_logger(__name__)


@app.callback()
def main(log_level: str = typer.Option("INFO", help="DEBUG, INFO, WARNING, ERROR")) -> None:
    configure_logging(log_level)


@db_app.command("check")
def db_check() -> None:
    """Verify the database is reachable and migrated."""
    from sqlalchemy import text

    from imt.db.session import get_engine

    with get_engine().connect() as conn:
        version = conn.execute(text("SELECT version()")).scalar_one()
        tables = conn.execute(
            text("SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'")
        ).scalar_one()
        revision = conn.execute(text("SELECT version_num FROM alembic_version")).scalar_one()
    typer.echo(f"database : {str(version).split(',')[0]}")
    typer.echo(f"tables   : {tables}")
    typer.echo(f"revision : {revision}")


@app.command("sources")
def list_sources() -> None:
    """Show every declared source and whether it is enabled.

    The count the UI displays is computed from this file, never hardcoded
    (UI_SPEC §2).
    """
    sources = load_sources()["sources"]
    enabled = sum(1 for cfg in sources.values() if cfg.get("enabled"))
    for source_id, cfg in sorted(sources.items()):
        state = "enabled" if cfg.get("enabled") else f"disabled ({cfg.get('blocked_reason', '-')})"
        typer.echo(f"  tier {cfg['tier']}  {source_id:<22} {state}")
    typer.echo(f"\n{enabled} of {len(sources)} sources enabled")


@app.command("weights")
def show_weights() -> None:
    """Print the loaded scoring weights and their calibration."""
    import math

    from imt.scoring import load_weights

    weights = load_weights()
    typer.echo(f"weights_version : {weights.version}")
    typer.echo(f"file hash       : {weights.file_hash[:16]}")
    typer.echo(f"tau / lambda    : {weights.tau} / {weights.lambda_}")
    total = sum(weights.category_weights.values())
    typer.echo(f"category sum    : {total:.2f}  (deliberately not 1.0 — see SPEC §6.4)")
    average = total / len(weights.category_weights)
    typer.echo("\nconvergence at full category strength:")
    for n in (1, 3, 5):
        value = 100 * (1 - math.exp(-weights.lambda_ * n * average))
        note = "  <- must stay under 45" if n == 1 else ""
        typer.echo(f"  {n} categories : {value:5.1f}{note}")


@entities_app.command("normalize")
def entities_normalize(name: str) -> None:
    """Show how a company name normalizes. Useful when a join is not happening."""
    from imt.entities import normalize_name

    typer.echo(normalize_name(name))


@score_app.command("run")
def score_run(
    date_: str = typer.Option(..., "--date", help="As-of date (YYYY-MM-DD) or 'today'"),
) -> None:
    """Score the universe as of a date. Reruns produce byte-identical output."""
    typer.echo(f"score run --date {date_}: not implemented until Phase 3")
    raise typer.Exit(code=1)


@ingest_app.command("form4")
def ingest_form4(since: str = typer.Option("2d", "--since")) -> None:
    """Ingest Form 4 insider transactions."""
    settings = get_settings()
    settings.user_agent()  # fail fast if IMT_SEC_CONTACT is unset
    typer.echo(f"ingest form4 --since {since}: not implemented until Phase 2")
    raise typer.Exit(code=1)


if __name__ == "__main__":
    app()
