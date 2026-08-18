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


@ingest_app.command("fundamentals")
def ingest_fundamentals_cmd(
    tickers: list[str] = typer.Argument(None, help="Tickers; omit for the whole universe."),
) -> None:
    """Fetch XBRL companyfacts from SEC EDGAR through the validation gate."""
    from invest.ingest.fundamentals import ingest_fundamentals_for_security
    from invest.providers.edgar import EdgarProvider

    try:
        provider = EdgarProvider()
    except ValueError as exc:
        typer.echo(str(exc), err=True)
        raise typer.Exit(code=1) from exc

    try:
        with session_scope() as session:
            targets = tickers or list(
                session.scalars(select(Security.ticker).order_by(Security.ticker))
            )
            if not targets:
                typer.echo("Universe is empty. Run `invest universe seed`.", err=True)
                raise typer.Exit(code=1)

            failures = 0
            for ticker in targets:
                try:
                    security = resolve(session, ticker)
                except LookupError as exc:
                    typer.echo(f"{ticker:<8} SKIPPED  {exc}", err=True)
                    failures += 1
                    continue

                result = ingest_fundamentals_for_security(session, provider, security)
                if not result.ok:
                    typer.echo(f"{ticker:<8} FAILED   {result.error}", err=True)
                    failures += 1
                    continue
                typer.echo(
                    f"{ticker:<8} wrote {result.written:<6} "
                    f"accepted={result.accepted} flagged={result.flagged} "
                    f"quarantined={result.quarantined} skipped={result.skipped}"
                )
    finally:
        provider.close()

    if failures:
        typer.echo(f"\n{failures} ticker(s) failed.", err=True)
        raise typer.Exit(code=1)


@ingest_app.command("filings")
def ingest_filings_cmd(
    tickers: list[str] = typer.Argument(None, help="Tickers; omit for the whole universe."),
    insider: bool = typer.Option(True, help="Also fetch and parse Form 4 filings."),
    limit: int = typer.Option(50, help="Max Form 4 documents per company."),
) -> None:
    """Index SEC filings and parse insider (Form 4) transactions."""
    from invest.ingest.filings import ingest_filings_for_security, ingest_insider_for_security
    from invest.providers.edgar import EdgarProvider

    try:
        provider = EdgarProvider()
    except ValueError as exc:
        typer.echo(str(exc), err=True)
        raise typer.Exit(code=1) from exc

    failures = 0
    try:
        with session_scope() as session:
            targets = tickers or list(
                session.scalars(select(Security.ticker).order_by(Security.ticker))
            )
            if not targets:
                typer.echo("Universe is empty. Run `invest universe seed`.", err=True)
                raise typer.Exit(code=1)

            for ticker in targets:
                try:
                    security = resolve(session, ticker)
                except LookupError as exc:
                    typer.echo(f"{ticker:<8} SKIPPED  {exc}", err=True)
                    failures += 1
                    continue

                filings_result = ingest_filings_for_security(session, provider, security)
                if not filings_result.ok:
                    typer.echo(f"{ticker:<8} FAILED   {filings_result.error}", err=True)
                    failures += 1
                    continue

                line = (
                    f"{ticker:<8} filings +{filings_result.filings_written} "
                    f"(skipped {filings_result.filings_skipped})"
                )

                if insider:
                    insider_result = ingest_insider_for_security(
                        session, provider, security, limit=limit
                    )
                    if not insider_result.ok:
                        typer.echo(f"{line}  form4 FAILED {insider_result.error}", err=True)
                        failures += 1
                        continue
                    line += (
                        f"  form4 +{insider_result.insider_written} "
                        f"(skipped {insider_result.insider_skipped})"
                    )
                typer.echo(line)
    finally:
        provider.close()

    if failures:
        typer.echo(f"\n{failures} ticker(s) failed.", err=True)
        raise typer.Exit(code=1)


@ingest_app.command("political")
def ingest_political_cmd(
    file: str = typer.Option(..., "--file", help="CSV export of disclosures."),
    source: str = typer.Option("house_clerk", help="house_clerk or senate_efd."),
    chamber: str | None = typer.Option(None, help="Default chamber if absent from the file."),
    universe_only: bool = typer.Option(False, help="Keep only tickers in the universe."),
) -> None:
    """Ingest congressional disclosures — FIREWALLED, never a score input.

    Requires a structured CSV: the official sources publish PDFs and a search
    UI, and parsing transaction tables out of PDFs would risk writing a
    plausible-looking wrong number into the database.
    """
    from pathlib import Path

    from invest.ingest.political import ingest_political_trades
    from invest.providers.congress import parse_disclosure_csv

    path = Path(file)
    if not path.exists():
        typer.echo(f"No such file: {file}", err=True)
        raise typer.Exit(code=1)

    try:
        records = parse_disclosure_csv(
            path.read_text(), source=source, default_chamber=chamber
        )
    except Exception as exc:
        typer.echo(f"Could not parse {file}: {exc}", err=True)
        raise typer.Exit(code=1) from exc

    if not records:
        typer.echo("No usable rows found.")
        return

    with session_scope() as session:
        result = ingest_political_trades(session, records, universe_only=universe_only)

    typer.echo(
        f"Parsed {len(records)} rows -> wrote {result.written}, skipped {result.skipped}"
    )
    if result.out_of_universe:
        typer.echo(f"  {result.out_of_universe} referenced tickers outside the universe")
    if result.unresolved_tickers:
        typer.echo(f"  {result.unresolved_tickers} rows had no usable ticker")
        for example in result.unresolved_examples:
            typer.echo(f"    e.g. {example}")
    typer.echo(
        "\nAll rows stored with firewall_status='investigate_only'. "
        "This data contributes nothing to any score."
    )


@app.command("disclosures")
def disclosures_cmd(
    ticker: str,
    as_of: str | None = typer.Option(None, help="Point-in-time cutoff (ISO date)."),
    lookback: int = typer.Option(365, help="Days of history."),
) -> None:
    """Show congressional disclosures for a security — research context only."""
    from datetime import date as _date

    from invest.ingest.political import get_disclosure_context

    cutoff = _date.fromisoformat(as_of) if as_of else _date.today()

    with session_scope() as session:
        try:
            security = resolve(session, ticker)
        except LookupError as exc:
            typer.echo(str(exc), err=True)
            raise typer.Exit(code=1) from exc

        context = get_disclosure_context(
            session, security.security_id, as_of=cutoff, lookback_days=lookback
        )

        if not context.count:
            typer.echo(f"No disclosures on file for {security.ticker} through {cutoff}.")
            return

        typer.echo(
            f"{security.ticker} congressional disclosures through {cutoff}  "
            f"[FIREWALLED — not a score input]\n"
        )
        typer.echo(
            f"{'DISCLOSED':<12} {'TRADED':<12} {'LAG':>5} {'TYPE':<10} "
            f"{'AMOUNT RANGE':<28} WHO"
        )
        for trade in context.trades:
            lag = (trade.disclosure_date - trade.transaction_date).days
            low = trade.amount_range_low
            high = trade.amount_range_high
            if low is None:
                amount = "INSUFFICIENT DATA"
            elif high is None:
                amount = f"over ${float(low):,.0f}"
            else:
                amount = f"${float(low):,.0f} - ${float(high):,.0f}"
            typer.echo(
                f"{trade.disclosure_date.isoformat():<12} "
                f"{trade.transaction_date.isoformat():<12} {lag:>5} "
                f"{(trade.transaction_type or '?'):<10} {amount:<28} "
                f"{trade.politician_name}"
            )

        median = context.median_disclosure_lag_days
        typer.echo(f"\n{context.count} disclosures. Median lag: {median:.0f} days.")
        typer.echo(
            "Amounts are the brackets as filed. No midpoint is computed — that "
            "would be a number nobody reported."
        )


@app.command("insider")
def insider_cmd(
    ticker: str,
    as_of: str | None = typer.Option(None, help="Point-in-time cutoff (ISO date)."),
    lookback: int = typer.Option(180, help="Days of history to summarise."),
) -> None:
    """Show insider activity, separating conviction trades from compensation."""
    from datetime import date as _date

    from invest.providers.form4 import InsiderSummary, describe_code, is_discretionary
    from invest.repository import get_insider_transactions

    cutoff = _date.fromisoformat(as_of) if as_of else _date.today()

    with session_scope() as session:
        try:
            security = resolve(session, ticker)
        except LookupError as exc:
            typer.echo(str(exc), err=True)
            raise typer.Exit(code=1) from exc

        records = get_insider_transactions(
            session, security.entity_id, as_of=cutoff, lookback_days=lookback
        )

    if not records:
        typer.echo(
            f"No insider transactions on file for {security.ticker} "
            f"in the {lookback} days to {cutoff}."
        )
        typer.echo("INSUFFICIENT DATA — run `invest ingest filings` first.")
        return

    summary = InsiderSummary(records)
    typer.echo(f"{security.ticker} insider activity through {cutoff} ({lookback}-day window)\n")
    typer.echo(
        f"{'FILED':<12} {'TRADED':<12} {'LAG':>4} {'CODE':<5} {'DIR':<4} "
        f"{'SHARES':>12} {'PRICE':>10}  INSIDER / MEANING"
    )
    for r in sorted(records, key=lambda r: r.filed_date, reverse=True):
        lag = (r.filed_date - r.transaction_date).days
        marker = "*" if is_discretionary(r.transaction_code) else " "
        shares = "-" if r.shares is None else f"{float(r.shares):,.0f}"
        price = "-" if r.price_per_share is None else f"{float(r.price_per_share):,.2f}"
        typer.echo(
            f"{r.filed_date.isoformat():<12} {r.transaction_date.isoformat():<12} "
            f"{lag:>4} {marker}{(r.transaction_code or '?'):<4} "
            f"{(r.acquired_disposed or '-'):<4} {shares:>12} {price:>10}  "
            f"{r.insider_name} — {describe_code(r.transaction_code)}"
        )

    typer.echo(
        f"\n* = discretionary open-market trade. "
        f"{summary.transaction_count} of {len(records)} filings qualify."
    )
    ratio = summary.net_buy_ratio
    typer.echo(
        "Net conviction: "
        + ("INSUFFICIENT DATA (no discretionary trades)" if ratio is None else f"{ratio:+.2f}")
    )
    typer.echo(
        f"Bought ${summary.buy_value:,.0f} / sold ${summary.sell_value:,.0f} "
        f"(priced trades only)"
    )
    typer.echo(
        "\nLAG is days between the trade and its disclosure. Only the filing "
        "date is used for point-in-time scoring."
    )


@universe_app.command("verify")
def universe_verify() -> None:
    """Reconcile seeded CIKs against SEC EDGAR's company_tickers.json.

    Until this has run, seeded CIKs carry data_quality_flag
    'unverified_bootstrap' — they are claims, not confirmed identifiers.
    """
    from invest.providers.edgar import EdgarProvider
    from invest.security_master import verify_ciks

    try:
        provider = EdgarProvider()
    except ValueError as exc:
        typer.echo(str(exc), err=True)
        raise typer.Exit(code=1) from exc

    try:
        authority = provider.fetch_ticker_cik_map()
    except Exception as exc:
        typer.echo(f"Could not reach EDGAR: {exc}", err=True)
        raise typer.Exit(code=1) from exc
    finally:
        provider.close()

    with session_scope() as session:
        results = verify_ciks(session, authority)

    by_status: dict[str, int] = {}
    for r in results:
        by_status[r.status] = by_status.get(r.status, 0) + 1
        if r.status == "corrected":
            typer.echo(f"CORRECTED {r.ticker}: {r.seeded_cik} -> {r.authoritative_cik}")
        elif r.status == "missing_from_authority":
            typer.echo(f"UNCONFIRMED {r.ticker}: EDGAR does not list this ticker")

    typer.echo("\n" + ", ".join(f"{k}={v}" for k, v in sorted(by_status.items())))


@app.command("analyze")
def analyze_cmd(
    ticker: str,
    as_of: str | None = typer.Option(None, help="Point-in-time cutoff (ISO date)."),
    save: bool = typer.Option(True, help="Write an immutable research snapshot."),
    output: str | None = typer.Option(None, help="Also write the report to this file."),
) -> None:
    """Score a security and render its research report."""
    from datetime import date as _date

    from invest.analysis import analyze, save_snapshot

    cutoff = _date.fromisoformat(as_of) if as_of else None

    with session_scope() as session:
        try:
            result = analyze(session, ticker, as_of=cutoff)
        except LookupError as exc:
            typer.echo(str(exc), err=True)
            raise typer.Exit(code=1) from exc

        typer.echo(result.report_text)

        if save:
            snapshot = save_snapshot(session, result)
            session.flush()
            typer.echo(f"Snapshot {snapshot.id} saved (immutable).")

        if output:
            from pathlib import Path

            Path(output).write_text(result.report_text)
            typer.echo(f"Report written to {output}")


@app.command("snapshots")
def snapshots_cmd(
    ticker: str | None = typer.Argument(None, help="Filter to one ticker."),
    limit: int = typer.Option(20, help="Rows to show."),
) -> None:
    """List stored research snapshots."""
    from invest.db.models import ResearchSnapshot

    with session_scope() as session:
        stmt = (
            select(ResearchSnapshot, Security.ticker)
            .join(Security, ResearchSnapshot.security_id == Security.id)
            .order_by(ResearchSnapshot.created_at.desc())
            .limit(limit)
        )
        if ticker:
            stmt = stmt.where(Security.ticker == ticker.upper())
        rows = session.execute(stmt).all()

        if not rows:
            typer.echo("No snapshots stored.")
            return

        typer.echo(
            f"{'ID':<6} {'TICKER':<8} {'AS OF':<12} {'MODEL':<14} "
            f"{'QUALITY':>8} {'SETUP':>8} {'CONF':>8}"
        )
        for snapshot, snapshot_ticker in rows:

            def fmt(value):
                return "  n/a" if value is None else f"{float(value):.1f}"

            typer.echo(
                f"{snapshot.id:<6} {snapshot_ticker:<8} "
                f"{snapshot.as_of_date.isoformat():<12} {snapshot.model_version:<14} "
                f"{fmt(snapshot.investment_quality_score):>8} "
                f"{fmt(snapshot.trade_setup_score):>8} "
                f"{fmt(snapshot.confidence_score):>8}"
            )


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
