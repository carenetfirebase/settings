"""Intraday ingestion: provider -> validation gate -> `intraday_observations`.

The one rule this module exists to hold: a price arrives with its staleness or
it does not arrive. `delay_seconds` comes from the provider — which states it
once, per feed — and is written to a NOT NULL column. There is no path here
that stores an unlabelled quote.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from invest.db.enums import DataQualityFlag, JobStatus, ValueType
from invest.db.models import IntradayObservation, WorkflowJob
from invest.providers.base import IntradayBar, ProviderError
from invest.security_master import ResolvedSecurity

logger = logging.getLogger(__name__)

#: A print older than this is not "intraday" in any useful sense; it is
#: yesterday's news wearing a timestamp.
MAX_USEFUL_AGE = timedelta(days=5)


@dataclass
class IntradayIngestResult:
    ticker: str
    source: str
    written: int = 0
    skipped: int = 0
    quarantined: int = 0
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None


def _symbol_for(provider, security: ResolvedSecurity) -> str:
    """Vendor symbol conventions stay out of the providers themselves."""
    if getattr(provider, "source_name", "") == "stooq" and security.stooq_symbol:
        return security.stooq_symbol
    return security.ticker


def ingest_intraday_for_security(
    session: Session,
    provider,
    security: ResolvedSecurity,
    *,
    interval_seconds: int = 300,
    limit: int = 100,
    now: datetime | None = None,
) -> IntradayIngestResult:
    now = now or datetime.now(UTC)
    result = IntradayIngestResult(security.ticker, getattr(provider, "source_name", "?"))

    job = WorkflowJob(
        job_type="ingest_intraday",
        target_ref=f"{security.ticker}:{result.source}",
        status=JobStatus.RUNNING,
    )
    session.add(job)
    session.flush()

    try:
        bars: list[IntradayBar] = provider.fetch_intraday(
            _symbol_for(provider, security),
            interval_seconds=interval_seconds,
            limit=limit,
        )
    except ProviderError as exc:
        job.status = JobStatus.FAILED
        job.error = str(exc)
        session.flush()
        result.error = str(exc)
        return result

    existing = {
        (observed_at, interval, source)
        for observed_at, interval, source in session.execute(
            select(
                IntradayObservation.observed_at,
                IntradayObservation.interval_seconds,
                IntradayObservation.source,
            ).where(IntradayObservation.security_id == security.security_id)
        ).all()
    }

    for bar in bars:
        key = (bar.observed_at, bar.interval_seconds, bar.source)
        if key in existing:
            result.skipped += 1
            continue

        flag = DataQualityFlag.OK
        # A timestamp ahead of now is impossible for a *delayed* feed and
        # signals a timezone error at the source or in parsing — quarantine
        # rather than let it poison a freshness calculation.
        if bar.observed_at > now + timedelta(minutes=5):
            logger.warning(
                "%s: %s print stamped %s is in the future; quarantining",
                result.source,
                security.ticker,
                bar.observed_at,
            )
            flag = DataQualityFlag.QUARANTINED
            result.quarantined += 1
        elif now - bar.observed_at > MAX_USEFUL_AGE:
            flag = DataQualityFlag.STALE

        session.add(
            IntradayObservation(
                security_id=security.security_id,
                observed_at=bar.observed_at,
                interval_seconds=bar.interval_seconds,
                open=bar.open,
                high=bar.high,
                low=bar.low,
                close=bar.close,
                volume=bar.volume,
                currency=bar.currency,
                delay_seconds=bar.delay_seconds,
                is_delayed=bar.is_delayed,
                source=bar.source,
                value_type=ValueType.OBSERVED,
                data_quality_flag=flag,
            )
        )
        existing.add(key)
        result.written += 1

    job.status = JobStatus.SUCCEEDED
    job.rows_written = result.written
    job.rows_quarantined = result.quarantined
    job.stats_json = {
        "written": result.written,
        "skipped": result.skipped,
        "quarantined": result.quarantined,
        "interval_seconds": interval_seconds,
    }
    session.flush()
    return result


def ingest_latest_quote(
    session: Session,
    provider,
    security: ResolvedSecurity,
    *,
    now: datetime | None = None,
) -> IntradayIngestResult:
    """Fetch and store the single most recent print available."""
    now = now or datetime.now(UTC)
    result = IntradayIngestResult(security.ticker, getattr(provider, "source_name", "?"))

    try:
        bar = provider.fetch_latest_quote(_symbol_for(provider, security))
    except ProviderError as exc:
        result.error = str(exc)
        return result

    if bar is None:
        result.error = f"no quote available for {security.ticker}"
        return result

    duplicate = session.scalar(
        select(IntradayObservation.id).where(
            IntradayObservation.security_id == security.security_id,
            IntradayObservation.observed_at == bar.observed_at,
            # NULL-safe: a point quote has no interval, and `= NULL` would
            # never match, so every fetch would look like a new row.
            IntradayObservation.interval_seconds.is_not_distinct_from(bar.interval_seconds),
            IntradayObservation.source == bar.source,
        )
    )
    if duplicate:
        result.skipped = 1
        return result

    session.add(
        IntradayObservation(
            security_id=security.security_id,
            observed_at=bar.observed_at,
            interval_seconds=bar.interval_seconds,
            open=bar.open,
            high=bar.high,
            low=bar.low,
            close=bar.close,
            volume=bar.volume,
            currency=bar.currency,
            delay_seconds=bar.delay_seconds,
            is_delayed=bar.is_delayed,
            source=bar.source,
            value_type=ValueType.OBSERVED,
            data_quality_flag=(
                DataQualityFlag.STALE
                if now - bar.observed_at > MAX_USEFUL_AGE
                else DataQualityFlag.OK
            ),
        )
    )
    result.written = 1
    session.flush()
    return result


# --------------------------------------------------------------------------
# Reading back, with staleness attached
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Quote:
    """A price and everything needed to judge whether to trust it."""

    price: float
    observed_at: datetime
    delay_seconds: int
    source: str
    retrieved_at: datetime

    @property
    def age(self) -> timedelta:
        """How old the print is *now* — publisher delay plus shelf time."""
        return self.retrieved_at - self.observed_at

    @property
    def age_seconds(self) -> int:
        return int(self.age.total_seconds())

    @property
    def is_realtime(self) -> bool:
        """Always False on free data, and stated rather than implied."""
        return self.delay_seconds == 0

    def describe(self) -> str:
        minutes = self.age_seconds / 60
        if minutes < 90:
            age = f"{minutes:.0f} min old"
        elif minutes < 60 * 48:
            age = f"{minutes / 60:.1f} hours old"
        else:
            age = f"{minutes / 1440:.1f} days old"
        basis = (
            "real-time"
            if self.is_realtime
            else f"{self.delay_seconds // 60}-min delayed feed"
        )
        return f"{self.price:,.2f} from {self.source} ({basis}, {age})"

    def as_dict(self) -> dict:
        return {
            "price": self.price,
            "observed_at": self.observed_at.isoformat(),
            "retrieved_at": self.retrieved_at.isoformat(),
            "delay_seconds": self.delay_seconds,
            "age_seconds": self.age_seconds,
            "is_realtime": self.is_realtime,
            "source": self.source,
            "description": self.describe(),
        }


def latest_quote(
    session: Session,
    security_id: int,
    *,
    now: datetime | None = None,
    max_age: timedelta | None = None,
) -> Quote | None:
    """The most recent usable intraday print, with its age.

    Returns None rather than a stale number when nothing is fresh enough.
    Quarantined rows are excluded, as everywhere else.
    """
    now = now or datetime.now(UTC)

    stmt = (
        select(IntradayObservation)
        .where(
            IntradayObservation.security_id == security_id,
            IntradayObservation.close.is_not(None),
            IntradayObservation.data_quality_flag != DataQualityFlag.QUARANTINED,
            IntradayObservation.observed_at <= now,
        )
        .order_by(IntradayObservation.observed_at.desc())
        .limit(1)
    )
    row = session.scalars(stmt).first()
    if row is None:
        return None

    quote = Quote(
        price=float(row.close),
        observed_at=row.observed_at,
        delay_seconds=row.delay_seconds,
        source=row.source,
        retrieved_at=now,
    )
    if max_age is not None and quote.age > max_age:
        return None
    return quote
