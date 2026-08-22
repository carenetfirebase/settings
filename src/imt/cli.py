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


@app.command("load-fixtures")
def load_fixtures(
    confirm: bool = typer.Option(False, "--yes", help="Required. This writes non-production data."),
) -> None:
    """Ingest the committed test fixtures, for developing the UI against.

    These are hand-built Form 4 documents (tests/fixtures/form4/README.md),
    not recordings from EDGAR, and they are ingested through the real pipeline
    rather than inserted directly -- so what lands in the database is whatever
    the parser actually produces.

    Every company written here is named with a DEMO prefix and every row is
    marked `estimated`, so nothing from this command can be mistaken for a
    real filing. It is refused without --yes.
    """
    if not confirm:
        typer.echo("Refused. This writes non-production data; pass --yes.")
        raise typer.Exit(code=1)

    from datetime import UTC, date, datetime
    from pathlib import Path

    from imt.adapters.records import FilingRef
    from imt.db.enums import CompanyStatus
    from imt.db.models import Company, TickerMapRow
    from imt.db.session import session_scope
    from imt.ingest.base import IngestResult, sync_data_sources
    from imt.ingest.form4 import ingest_filing

    fixtures = sorted((Path(__file__).resolve().parents[2] / "tests/fixtures/form4").glob("*.xml"))
    result = IngestResult(job="load-fixtures", source_id="sec_edgar")

    with session_scope() as session:
        sync_data_sources(session)
        if session.get(Company, "0000320193") is None:
            session.add(
                Company(
                    cik="0000320193",
                    name="DEMO ALPHA BUILDERS INC",
                    sic="1531",
                    sector_code="industrials",
                    status=CompanyStatus.ACTIVE,
                    first_seen=date(2024, 1, 1),
                    last_seen=date(2026, 8, 22),
                    inclusion_reason="fixture data — not a real filer",
                )
            )
            session.add(
                TickerMapRow(
                    cik="0000320193",
                    ticker="DEMO",
                    exchange="Nasdaq",
                    valid_from=date(2024, 1, 1),
                )
            )
            session.flush()

        for i, path in enumerate(fixtures):
            ref = FilingRef(
                accession=f"0001234567-26-{i:06d}",
                cik="0000320193",
                form_type="4",
                filed_date=date(2026, 8, 16),
                primary_doc_url=f"https://www.sec.gov/Archives/{path.name}",
                acceptance_datetime=datetime(2026, 8, 16, 18, 31, tzinfo=UTC),
            )
            ingest_filing(session, payload=path.read_bytes(), ref=ref, result=result)

    typer.echo(result.summary())
    typer.echo("Loaded fixture data. Companies are DEMO-prefixed; not real filings.")
