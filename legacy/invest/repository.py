"""The read layer. Engines use this and nothing else to reach the database.

Two invariants are enforced here, once, so no engine has to remember them:

1. **Point-in-time.** Every fundamental query takes an `as_of` date and filters
   `filed_date <= as_of`. Where a period has been restated, the row visible is
   the latest one filed *on or before* the cutoff — which is exactly what a
   reader would have seen on that date. Passing `as_of=None` means "today" and
   is only appropriate for live research, never for a backtest.

2. **Quarantined rows are invisible.** Anything the validation gate marked
   `quarantined` is excluded from every read. It stays in the table for audit
   but can never reach a calculation.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from decimal import Decimal

import pandas as pd
from sqlalchemy import Select, and_, func, select
from sqlalchemy.orm import Session

from invest.db.enums import DataQualityFlag
from invest.db.models import Fundamental, PriceObservation, Security

#: Rows carrying this flag never reach an engine.
EXCLUDED_FLAGS = (DataQualityFlag.QUARANTINED,)


def _usable(stmt: Select, column) -> Select:
    return stmt.where(column.notin_([f.value for f in EXCLUDED_FLAGS]))


# --------------------------------------------------------------------------
# Prices
# --------------------------------------------------------------------------


def get_price_frame(
    session: Session,
    security_id: int,
    *,
    start: date | None = None,
    end: date | None = None,
    as_of: date | None = None,
    source: str | None = None,
) -> pd.DataFrame:
    """Daily bars as a DataFrame indexed by date, ascending.

    Columns: open, high, low, close, adj_close, volume, source.

    `as_of` caps the observation date. Prices are not restated the way
    fundamentals are, so for prices the cutoff is simply `obs_date <= as_of`.

    When several sources cover the same day, one row per date is returned,
    preferring the source named in `source`, else the alphabetically first —
    deterministic rather than arbitrary. Cross-source disagreement is already
    recorded in `data_conflicts` by the gate; this function's job is to hand
    the engines one coherent series.
    """
    stmt = select(
        PriceObservation.obs_date,
        PriceObservation.open,
        PriceObservation.high,
        PriceObservation.low,
        PriceObservation.close,
        PriceObservation.adj_close,
        PriceObservation.volume,
        PriceObservation.source,
    ).where(PriceObservation.security_id == security_id)

    stmt = _usable(stmt, PriceObservation.data_quality_flag)
    if start is not None:
        stmt = stmt.where(PriceObservation.obs_date >= start)
    effective_end = min(d for d in (end, as_of) if d is not None) if (end or as_of) else None
    if effective_end is not None:
        stmt = stmt.where(PriceObservation.obs_date <= effective_end)
    if source is not None:
        stmt = stmt.where(PriceObservation.source == source)

    stmt = stmt.order_by(PriceObservation.obs_date, PriceObservation.source)
    rows = session.execute(stmt).all()

    columns = ["obs_date", "open", "high", "low", "close", "adj_close", "volume", "source"]
    if not rows:
        empty = pd.DataFrame(columns=columns).set_index("obs_date")
        return empty

    frame = pd.DataFrame(rows, columns=columns)
    # Decimal -> float happens here, at the boundary of the numeric engines.
    for column in ("open", "high", "low", "close", "adj_close"):
        frame[column] = frame[column].astype(float)
    frame["volume"] = frame["volume"].astype("Int64")

    if source is None:
        frame = frame.drop_duplicates(subset="obs_date", keep="first")

    return frame.set_index("obs_date").sort_index()


def get_close_series(session: Session, security_id: int, **kwargs) -> pd.Series:
    """Close prices as a float Series. The workhorse input for the quant engine."""
    frame = get_price_frame(session, security_id, **kwargs)
    if frame.empty:
        return pd.Series(dtype=float, name="close")
    return frame["close"].astype(float).rename("close")


def latest_price(
    session: Session, security_id: int, *, as_of: date | None = None
) -> tuple[date, float] | None:
    """Most recent usable close on or before `as_of`. None when unavailable —
    never a stale carry-forward dressed up as current.
    """
    stmt = select(PriceObservation.obs_date, PriceObservation.close).where(
        and_(
            PriceObservation.security_id == security_id,
            PriceObservation.close.isnot(None),
        )
    )
    stmt = _usable(stmt, PriceObservation.data_quality_flag)
    if as_of is not None:
        stmt = stmt.where(PriceObservation.obs_date <= as_of)
    stmt = stmt.order_by(PriceObservation.obs_date.desc()).limit(1)

    row = session.execute(stmt).first()
    if row is None or row[1] is None:
        return None
    return row[0], float(row[1])


# --------------------------------------------------------------------------
# Fundamentals — point in time
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class FundamentalPoint:
    metric_name: str
    value: float | None
    unit: str
    period_start: date | None
    period_end: date
    fiscal_year: int | None
    fiscal_period: str | None
    filed_date: date
    form_type: str | None
    accession_number: str | None
    data_quality_flag: str

    @property
    def is_restated(self) -> bool:
        """True when the filing landed well after the period it reports on."""
        return (self.filed_date - self.period_end).days > 200


def _pit_subquery(entity_id: int, metric_name: str, as_of: date | None):
    """For each period_end, the latest filed_date visible at `as_of`.

    This is the whole point-in-time mechanism in one place: a restatement filed
    after the cutoff is simply not visible, so a backtest sees the figure that
    was actually public at the time.
    """
    stmt = select(
        Fundamental.period_end,
        Fundamental.fiscal_period,
        func.max(Fundamental.filed_date).label("max_filed"),
    ).where(
        and_(
            Fundamental.entity_id == entity_id,
            Fundamental.metric_name == metric_name,
        )
    )
    stmt = _usable(stmt, Fundamental.data_quality_flag)
    if as_of is not None:
        stmt = stmt.where(Fundamental.filed_date <= as_of)
    return stmt.group_by(Fundamental.period_end, Fundamental.fiscal_period).subquery()


def get_fundamental_series(
    session: Session,
    entity_id: int,
    metric_name: str,
    *,
    as_of: date | None = None,
    fiscal_period: str | None = None,
    limit: int | None = None,
) -> list[FundamentalPoint]:
    """History of one metric, oldest first, restatement-aware.

    Returns [] when the metric was never reported. An empty list means
    "we do not have this", and callers must treat it as INSUFFICIENT DATA
    rather than substituting zero.
    """
    pit = _pit_subquery(entity_id, metric_name, as_of)

    stmt = (
        select(Fundamental)
        .join(
            pit,
            and_(
                Fundamental.period_end == pit.c.period_end,
                Fundamental.filed_date == pit.c.max_filed,
                Fundamental.fiscal_period.is_not_distinct_from(pit.c.fiscal_period),
            ),
        )
        .where(
            and_(
                Fundamental.entity_id == entity_id,
                Fundamental.metric_name == metric_name,
            )
        )
    )
    stmt = _usable(stmt, Fundamental.data_quality_flag)
    if fiscal_period is not None:
        stmt = stmt.where(Fundamental.fiscal_period == fiscal_period)
    stmt = stmt.order_by(Fundamental.period_end)

    rows = session.scalars(stmt).all()

    # Guard against a filer reporting the same period twice in one filing under
    # different units: keep one point per (period_end, fiscal_period).
    seen: set[tuple] = set()
    points: list[FundamentalPoint] = []
    for row in rows:
        key = (row.period_end, row.fiscal_period)
        if key in seen:
            continue
        seen.add(key)
        points.append(
            FundamentalPoint(
                metric_name=row.metric_name,
                value=float(row.metric_value) if row.metric_value is not None else None,
                unit=row.unit,
                period_start=row.period_start,
                period_end=row.period_end,
                fiscal_year=row.fiscal_year,
                fiscal_period=row.fiscal_period,
                filed_date=row.filed_date,
                form_type=row.form_type,
                accession_number=row.accession_number,
                data_quality_flag=row.data_quality_flag,
            )
        )

    if limit is not None:
        points = points[-limit:]
    return points


def latest_fundamental(
    session: Session,
    entity_id: int,
    metric_name: str,
    *,
    as_of: date | None = None,
    fiscal_period: str | None = "FY",
) -> FundamentalPoint | None:
    """Most recent reported period visible at `as_of`, or None."""
    series = get_fundamental_series(
        session, entity_id, metric_name, as_of=as_of, fiscal_period=fiscal_period
    )
    return series[-1] if series else None


def get_annual_metrics(
    session: Session,
    entity_id: int,
    metric_names: list[str],
    *,
    as_of: date | None = None,
    years: int = 5,
) -> dict[str, list[FundamentalPoint]]:
    """Several annual metrics at once — the usual shape a model needs.

    A metric with no data maps to an empty list. It is never filled in.
    """
    return {
        name: get_fundamental_series(
            session, entity_id, name, as_of=as_of, fiscal_period="FY", limit=years
        )
        for name in metric_names
    }


def value_at(points: list[FundamentalPoint], index: int = -1) -> float | None:
    """Safe positional accessor: None rather than IndexError, so a model can
    ask for "last year" without knowing whether last year exists.
    """
    try:
        return points[index].value
    except IndexError:
        return None


# --------------------------------------------------------------------------
# Misc
# --------------------------------------------------------------------------


def shares_outstanding(
    session: Session, entity_id: int, *, as_of: date | None = None
) -> float | None:
    for metric in ("SharesOutstanding", "WeightedAverageDilutedShares"):
        point = latest_fundamental(session, entity_id, metric, as_of=as_of, fiscal_period=None)
        if point is not None and point.value:
            return point.value
    return None


def market_cap(
    session: Session, security_id: int, entity_id: int, *, as_of: date | None = None
) -> float | None:
    """None when either input is missing — never a partially-real number."""
    price = latest_price(session, security_id, as_of=as_of)
    shares = shares_outstanding(session, entity_id, as_of=as_of)
    if price is None or shares is None or shares <= 0:
        return None
    return price[1] * shares


def get_insider_transactions(
    session: Session,
    entity_id: int,
    *,
    as_of: date | None = None,
    lookback_days: int = 180,
) -> list:
    """Insider transactions visible at `as_of`, as provider records.

    Filtered on `filed_date`, never `transaction_date`: an insider has two
    business days to file, so a trade dated the 1st may not have been public
    until the 3rd. Filtering on the transaction date would let a backtest act
    on information nobody had yet.

    Returns provider-shaped records so `form4.InsiderSummary` can consume them
    without the aggregation logic needing to know about the ORM.
    """
    from datetime import timedelta

    from invest.db.models import InsiderTransaction
    from invest.providers.base import InsiderTransactionRecord

    stmt = select(InsiderTransaction).where(InsiderTransaction.entity_id == entity_id)
    stmt = _usable(stmt, InsiderTransaction.data_quality_flag)
    if as_of is not None:
        stmt = stmt.where(InsiderTransaction.filed_date <= as_of)
        stmt = stmt.where(InsiderTransaction.filed_date >= as_of - timedelta(days=lookback_days))
    stmt = stmt.order_by(InsiderTransaction.filed_date)

    records = []
    for row in session.scalars(stmt).all():
        records.append(
            InsiderTransactionRecord(
                cik=str(entity_id),
                insider_name=row.insider_name,
                insider_cik=row.insider_cik,
                is_director=row.is_director,
                is_officer=row.is_officer,
                is_ten_pct_owner=row.is_ten_pct_owner,
                officer_title=row.officer_title,
                transaction_date=row.transaction_date,
                filed_date=row.filed_date,
                transaction_code=row.transaction_code,
                acquired_disposed=row.acquired_disposed,
                shares=row.shares,
                price_per_share=row.price_per_share,
                shares_owned_after=row.shares_owned_after,
                is_derivative=row.is_derivative,
                accession_number=row.accession_number,
                source=row.source,
            )
        )
    return records


def get_recent_filings(
    session: Session,
    entity_id: int,
    *,
    as_of: date | None = None,
    forms: list[str] | None = None,
    limit: int = 20,
) -> list:
    """Filing index entries visible at `as_of`, newest first."""
    from invest.db.models import Filing

    stmt = select(Filing).where(Filing.entity_id == entity_id)
    if as_of is not None:
        stmt = stmt.where(Filing.filed_date <= as_of)
    if forms:
        stmt = stmt.where(Filing.form_type.in_(forms))
    stmt = stmt.order_by(Filing.filed_date.desc()).limit(limit)
    return list(session.scalars(stmt).all())


def security_currency(session: Session, security_id: int) -> str:
    sec = session.get(Security, security_id)
    return sec.currency if sec else "USD"


def to_decimal(value: float | None) -> Decimal | None:
    return None if value is None else Decimal(str(value))
