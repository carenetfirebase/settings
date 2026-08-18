"""CLI entry point. `invest --help` after `pip install -e .`."""

from __future__ import annotations

import typer
from sqlalchemy import func, select, text
from sqlalchemy.exc import SQLAlchemyError

from invest import __version__
from invest.db.models import Entity, Security
from invest.db.session import get_engine, session_scope
from invest.security_master import resolve, seed_universe

app = typer.Typer(help="Zero-cost, institutional-style investment research platform.")
db_app = typer.Typer(help="Database utilities.")
universe_app = typer.Typer(help="Security master / research universe.")
ingest_app = typer.Typer(help="Data ingestion (provider -> validation gate -> database).")
app.add_typer(db_app, name="db")
app.add_typer(universe_app, name="universe")
app.add_typer(ingest_app, name="ingest")


@app.command()
def version() -> None:
    """Print the installed invest version."""
    typer.echo(__version__)


@db_app.command("check")
def db_check() -> None:
    """Verify the configured database is reachable."""
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        typer.echo(f"DATABASE UNREACHABLE: {exc}", err=True)
        raise typer.Exit(code=1) from exc
    typer.echo("Database connection OK.")


@universe_app.command("seed")
def universe_seed() -> None:
    """Load the bootstrap universe into the security master.

    CIKs are written flagged 'unverified_bootstrap'. Run `universe verify`
    against EDGAR to confirm them before trusting any fundamentals.
    """
    with session_scope() as session:
        seeded = seed_universe(session)
    typer.echo(f"Seeded {len(seeded)} securities (CIKs flagged unverified_bootstrap).")
    typer.echo("Next: `invest universe verify` to confirm CIKs against SEC EDGAR.")


@universe_app.command("list")
def universe_list() -> None:
    """Show the current research universe."""
    with session_scope() as session:
        rows = session.execute(
            select(Security.ticker, Entity.name, Entity.cik, Entity.sector, Entity.data_quality_flag)
            .join(Entity, Security.entity_id == Entity.id)
            .order_by(Security.ticker)
        ).all()

    if not rows:
        typer.echo("Universe is empty. Run `invest universe seed`.")
        raise typer.Exit(code=1)

    typer.echo(f"{'TICKER':<8} {'CIK':<12} {'FLAG':<22} {'SECTOR':<24} NAME")
    for ticker, name, cik, sector, flag in rows:
        typer.echo(f"{ticker:<8} {cik or '-':<12} {flag:<22} {(sector or '-'):<24} {name}")
    typer.echo(f"\n{len(rows)} securities.")


@universe_app.command("resolve")
def universe_resolve(ticker: str) -> None:
    """Resolve a ticker to its entity_id / CIK."""
    with session_scope() as session:
        try:
            r = resolve(session, ticker)
        except LookupError as exc:
            typer.echo(str(exc), err=True)
            raise typer.Exit(code=1) from exc
        typer.echo(f"ticker       {r.ticker}")
        typer.echo(f"entity_id    {r.entity_id}")
        typer.echo(f"security_id  {r.security_id}")
        typer.echo(f"cik          {r.cik}")
        typer.echo(f"name         {r.name}")
        typer.echo(f"stooq_symbol {r.stooq_symbol}")
        typer.echo(f"is_financial {r.is_financial}")


@ingest_app.command("prices")
def ingest_prices_cmd(
    tickers: list[str] = typer.Argument(None, help="Tickers; omit for the whole universe."),
    start: str | None = typer.Option(None, help="ISO start date, e.g. 2020-01-01."),
    end: str | None = typer.Option(None, help="ISO end date."),
) -> None:
    """Fetch daily OHLCV from Stooq through the validation gate."""
    from datetime import date as _date

    from invest.ingest.prices import ingest_prices_for_security
    from invest.providers.stooq import StooqProvider

    start_date = _date.fromisoformat(start) if start else None
    end_date = _date.fromisoformat(end) if end else None

    provider = StooqProvider()
    try:
        with session_scope() as session:
            if not tickers:
                targets = list(session.scalars(select(Security.ticker).order_by(Security.ticker)))
                if not targets:
                    typer.echo("Universe is empty. Run `invest universe seed`.", err=True)
                    raise typer.Exit(code=1)
            else:
                targets = tickers

            failures = 0
            for ticker in targets:
                try:
                    security = resolve(session, ticker)
                except LookupError as exc:
                    typer.echo(f"{ticker:<8} SKIPPED  {exc}", err=True)
                    failures += 1
                    continue

                result = ingest_prices_for_security(
                    session, provider, security, start=start_date, end=end_date
                )
                if not result.ok:
                    typer.echo(f"{ticker:<8} FAILED   {result.error}", err=True)
                    failures += 1
                    continue

                r = result.report
                typer.echo(
                    f"{ticker:<8} wrote {result.written:<6} "
                    f"accepted={r.accepted} flagged={r.flagged} "
                    f"quarantined={r.quarantined} skipped={r.skipped} "
                    f"conflicts={r.conflict_count}"
                )
    finally:
        provider.close()

    if failures:
        typer.echo(f"\n{failures} ticker(s) failed.", err=True)
        raise typer.Exit(code=1)


@app.command("conflicts")
def show_conflicts(limit: int = typer.Option(20, help="Rows to show.")) -> None:
    """Recent validation-gate findings — nothing is dropped silently."""
    from invest.db.models import DataConflict

    with session_scope() as session:
        rows = session.scalars(
            select(DataConflict).order_by(DataConflict.detected_at.desc()).limit(limit)
        ).all()
        if not rows:
            typer.echo("No conflicts recorded.")
            return
        typer.echo(f"{'SEVERITY':<10} {'TYPE':<30} {'DATE':<12} DETAIL")
        for c in rows:
            typer.echo(
                f"{c.severity:<10} {c.conflict_type:<30} "
                f"{c.obs_date or '-'!s:<12} {(c.detail or '')[:80]}"
            )


@db_app.command("stats")
def db_stats() -> None:
    """Row counts per table — a quick 'what do I actually have?' check."""
    from invest.db.models import Base

    with session_scope() as session:
        typer.echo(f"{'TABLE':<32} ROWS")
        for table in sorted(Base.metadata.tables):
            count = session.scalar(select(func.count()).select_from(text(table)))
            typer.echo(f"{table:<32} {count}")


if __name__ == "__main__":
    app()
