"""Political trade ingestion — FIREWALLED.

Every row written here carries `firewall_status='investigate_only'`. The
scoring engine cannot read this table (enforced by a static AST check, a
runtime SQL guard, and an end-to-end test), so ingesting more of it can never
move a score. It exists to answer "who else has been trading this?" when a
human is reading about a company.

Ticker resolution is best-effort and explicitly nullable: a disclosure naming
"Apple Inc Common Stock" with no symbol stays unresolved rather than being
matched by fuzzy name comparison, which would occasionally attribute one
company's disclosures to another.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from invest.db.enums import FirewallStatus, JobStatus, ValueType
from invest.db.models import PoliticalTrade, Security, WorkflowJob
from invest.providers.base import PoliticalTradeRecord
from invest.security_master import normalize_ticker

logger = logging.getLogger(__name__)


@dataclass
class PoliticalIngestResult:
    written: int = 0
    skipped: int = 0
    unresolved_tickers: int = 0
    out_of_universe: int = 0
    error: str | None = None
    unresolved_examples: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return self.error is None

    def as_dict(self) -> dict:
        return {
            "written": self.written,
            "skipped": self.skipped,
            "unresolved_tickers": self.unresolved_tickers,
            "out_of_universe": self.out_of_universe,
        }


def _ticker_index(session: Session) -> dict[str, int]:
    rows = session.execute(select(Security.ticker, Security.id)).all()
    return {ticker: security_id for ticker, security_id in rows}


def ingest_political_trades(
    session: Session,
    records: list[PoliticalTradeRecord],
    *,
    today: date | None = None,
    universe_only: bool = False,
) -> PoliticalIngestResult:
    """Store disclosures, firewalled.

    `universe_only=True` keeps only disclosures that resolve to a security we
    actually follow — useful for keeping the table small, at the cost of
    losing the wider picture.
    """
    today = today or date.today()
    result = PoliticalIngestResult()

    job = WorkflowJob(
        job_type="ingest_political", target_ref="disclosures", status=JobStatus.RUNNING
    )
    session.add(job)
    session.flush()

    tickers = _ticker_index(session)

    # The natural key: the same person, asset, date and type reported twice is
    # the same disclosure. There is no accession number to lean on.
    existing = {
        tuple(row)
        for row in session.execute(
            select(
                PoliticalTrade.politician_name,
                PoliticalTrade.ticker_raw,
                PoliticalTrade.transaction_date,
                PoliticalTrade.disclosure_date,
                PoliticalTrade.transaction_type,
                PoliticalTrade.amount_range_low,
            )
        ).all()
    }

    for record in records:
        if record.disclosure_date > today:
            result.skipped += 1
            continue

        security_id = None
        if record.ticker_raw:
            security_id = tickers.get(normalize_ticker(record.ticker_raw))
            if security_id is None:
                result.out_of_universe += 1
        else:
            result.unresolved_tickers += 1
            if len(result.unresolved_examples) < 5 and record.asset_description:
                result.unresolved_examples.append(record.asset_description[:60])

        if universe_only and security_id is None:
            result.skipped += 1
            continue

        key = (
            record.politician_name,
            record.ticker_raw,
            record.transaction_date,
            record.disclosure_date,
            record.transaction_type,
            record.amount_range_low,
        )
        if key in existing:
            result.skipped += 1
            continue

        session.add(
            PoliticalTrade(
                politician_name=record.politician_name,
                chamber=record.chamber,
                state=record.state,
                security_id=security_id,
                ticker_raw=record.ticker_raw,
                asset_description=record.asset_description,
                transaction_type=record.transaction_type,
                transaction_date=record.transaction_date,
                disclosure_date=record.disclosure_date,
                amount_range_low=record.amount_range_low,
                amount_range_high=record.amount_range_high,
                # Never anything else. The default is also set at the DB level.
                firewall_status=FirewallStatus.INVESTIGATE_ONLY,
                source=record.source,
                source_url=record.source_url,
                value_type=ValueType.OBSERVED,
            )
        )
        existing.add(key)
        result.written += 1

    job.status = JobStatus.SUCCEEDED
    job.rows_written = result.written
    job.stats_json = result.as_dict()
    session.flush()
    return result


@dataclass
class DisclosureContext:
    """Read-only research context for a security. Never a score input."""

    security_id: int
    trades: list[PoliticalTrade]

    @property
    def count(self) -> int:
        return len(self.trades)

    @property
    def median_disclosure_lag_days(self) -> float | None:
        """How long the public waited. Usually the most informative number
        here, and an argument against using this data for anything timely.
        """
        if not self.trades:
            return None
        lags = sorted((t.disclosure_date - t.transaction_date).days for t in self.trades)
        middle = len(lags) // 2
        if len(lags) % 2 == 1:
            return float(lags[middle])
        return (lags[middle - 1] + lags[middle]) / 2

    def as_dict(self) -> dict:
        return {
            "count": self.count,
            "median_disclosure_lag_days": self.median_disclosure_lag_days,
            "firewall_status": FirewallStatus.INVESTIGATE_ONLY.value,
            "note": "Research context only. Contributes nothing to any score.",
        }


def get_disclosure_context(
    session: Session,
    security_id: int,
    *,
    as_of: date | None = None,
    lookback_days: int = 365,
) -> DisclosureContext:
    """Fetch disclosures for human reading.

    Deliberately NOT in `repository.py`: the engines import from there, and
    keeping this function out of that module means no engine can reach it by
    accident.
    """
    from datetime import timedelta

    stmt = select(PoliticalTrade).where(PoliticalTrade.security_id == security_id)
    if as_of is not None:
        stmt = stmt.where(PoliticalTrade.disclosure_date <= as_of)
        stmt = stmt.where(PoliticalTrade.disclosure_date >= as_of - timedelta(days=lookback_days))
    stmt = stmt.order_by(PoliticalTrade.disclosure_date.desc())

    return DisclosureContext(security_id, list(session.scalars(stmt).all()))
