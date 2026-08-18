"""Price ingestion: provider -> validation gate -> insert.

The orchestration knows about providers only through the `PriceProvider`
protocol, so this file is identical whether the bars came from Stooq, yfinance,
or a paid vendor added in a later version.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import date

from sqlalchemy.orm import Session

from invest.db.enums import JobStatus, ValueType
from invest.db.models import PriceObservation, WorkflowJob
from invest.providers.base import PriceBar, PriceProvider, ProviderError
from invest.security_master import ResolvedSecurity, resolve
from invest.validation.gate import GateReport, Outcome, ValidationGate, build_price_context

logger = logging.getLogger(__name__)

DEFAULT_STALENESS_DAYS = 7


@dataclass
class IngestResult:
    ticker: str
    source: str
    report: GateReport
    written: int
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None


def _symbol_for(provider: PriceProvider, security: ResolvedSecurity) -> str:
    """Map our canonical ticker onto the vendor's symbol convention.

    Kept here rather than inside the provider so a provider stays a pure
    transport/parse component with no knowledge of our security master.
    """
    if provider.source_name == "stooq" and security.stooq_symbol:
        return security.stooq_symbol
    return security.ticker


def ingest_prices_for_security(
    session: Session,
    provider: PriceProvider,
    security: ResolvedSecurity,
    *,
    start: date | None = None,
    end: date | None = None,
    today: date | None = None,
    staleness_days: int | None = DEFAULT_STALENESS_DAYS,
) -> IngestResult:
    today = today or date.today()
    gate = ValidationGate(session)
    report = GateReport()
    written = 0

    job = WorkflowJob(
        job_type="ingest_prices",
        target_ref=f"{security.ticker}:{provider.source_name}",
        status=JobStatus.RUNNING,
    )
    session.add(job)
    session.flush()

    try:
        bars: list[PriceBar] = provider.fetch_daily_bars(
            _symbol_for(provider, security), start=start, end=end
        )
    except ProviderError as exc:
        # A failed fetch writes nothing. It never falls back to an estimate.
        job.status = JobStatus.FAILED
        job.error = str(exc)
        session.flush()
        logger.warning("price ingest failed for %s: %s", security.ticker, exc)
        return IngestResult(security.ticker, provider.source_name, report, 0, error=str(exc))

    ctx = build_price_context(
        session,
        security_id=security.security_id,
        source=provider.source_name,
        today=today,
        expected_currency=security.currency,
        staleness_days=staleness_days,
    )

    # Series-level findings are recorded once for the batch, not per row.
    series_findings = gate.check_price_series(bars, ctx)
    gate.persist_series_findings(
        series_findings, table_name="price_observations", security_id=security.security_id
    )
    report.findings.extend(series_findings)

    for bar in bars:
        result = gate.check_price_bar(bar, ctx, security_id=security.security_id)
        report.record(result)

        if result.outcome == Outcome.SKIPPED:
            continue

        session.add(
            PriceObservation(
                security_id=security.security_id,
                obs_date=bar.obs_date,
                open=bar.open,
                high=bar.high,
                low=bar.low,
                close=bar.close,
                adj_close=bar.adj_close,
                volume=bar.volume,
                currency=bar.currency,
                is_split_adjusted=bar.is_split_adjusted,
                is_dividend_adjusted=bar.is_dividend_adjusted,
                source=bar.source,
                value_type=ValueType.OBSERVED,
                data_quality_flag=result.data_quality_flag,
            )
        )
        written += 1
        # Keep the context current so duplicates inside one batch are caught.
        ctx.known_dates.add(bar.obs_date)

    job.status = JobStatus.SUCCEEDED
    job.rows_written = written
    job.rows_quarantined = report.quarantined
    job.stats_json = report.as_dict()
    session.flush()

    return IngestResult(security.ticker, provider.source_name, report, written)


def ingest_prices(
    session: Session,
    provider: PriceProvider,
    tickers: list[str],
    *,
    start: date | None = None,
    end: date | None = None,
    today: date | None = None,
) -> list[IngestResult]:
    results: list[IngestResult] = []
    for ticker in tickers:
        security = resolve(session, ticker)
        results.append(
            ingest_prices_for_security(
                session, provider, security, start=start, end=end, today=today
            )
        )
    return results
