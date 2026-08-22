"""Congressional trading summary. docs/UI_SPEC.md §4.7.

The panel's caption states how much older the underlying transactions are than
the disclosures, and that number is **computed**, never hardcoded — UI_SPEC is
explicit about it. A hardcoded "average 32d older" keeps saying 32 after the
data changes, which is the same class of error as a hardcoded source count.
"""

from __future__ import annotations

from datetime import timedelta
from typing import Annotated

from fastapi import APIRouter, Query
from pydantic import BaseModel
from sqlalchemy import func, select

from imt.api.deps import SessionDep, source_states
from imt.api.envelope import Envelope, Meta
from imt.core.clock import market_now, utc_now
from imt.db.models import CongressionalTransaction

router = APIRouter(tags=["congress"])

PERIOD_DAYS = {"7d": 7, "30d": 30, "90d": 90, "1y": 365, "2y": 730}


class CongressSlice(BaseModel):
    label: str
    count: int
    pct: float


class CongressSummary(BaseModel):
    total_trades: int
    slices: list[CongressSlice]
    #: None when there is nothing to average. The caption then says so rather
    #: than printing a zero that reads as "no lag".
    average_disclosure_lag_days: float | None
    max_disclosure_lag_days: int | None
    resolved_to_company: int
    unresolved: int
    period: str


@router.get("/congress/summary", response_model=Envelope[CongressSummary])
def summary(
    session: SessionDep,
    period: Annotated[str, Query(pattern="^(7d|30d|90d|1y|2y)$")] = "30d",
) -> Envelope[CongressSummary]:
    since = market_now().date() - timedelta(days=PERIOD_DAYS[period])

    # By DISCLOSURE date, not transaction date. The panel reports what became
    # public in the window; the transactions inside it are weeks older, which
    # is exactly what the lag caption exists to say.
    rows = session.execute(
        select(
            CongressionalTransaction.transaction_type,
            func.count().label("n"),
        )
        .where(CongressionalTransaction.disclosure_date >= since)
        .group_by(CongressionalTransaction.transaction_type)
        .order_by(CongressionalTransaction.transaction_type)
    ).all()

    total = sum(n for _, n in rows)
    slices = [
        CongressSlice(
            label=label,
            count=n,
            pct=round(100.0 * n / total, 1) if total else 0.0,
        )
        for label, n in rows
    ]

    avg_lag, max_lag = session.execute(
        select(
            func.avg(CongressionalTransaction.disclosure_lag_days),
            func.max(CongressionalTransaction.disclosure_lag_days),
        ).where(CongressionalTransaction.disclosure_date >= since)
    ).one()

    resolved = session.execute(
        select(func.count())
        .select_from(CongressionalTransaction)
        .where(
            CongressionalTransaction.disclosure_date >= since,
            CongressionalTransaction.cik.is_not(None),
        )
    ).scalar_one()

    return Envelope(
        data=CongressSummary(
            total_trades=total,
            slices=slices,
            average_disclosure_lag_days=round(float(avg_lag), 1) if avg_lag is not None else None,
            max_disclosure_lag_days=int(max_lag) if max_lag is not None else None,
            resolved_to_company=resolved,
            unresolved=total - resolved,
            period=period,
        ),
        meta=Meta(generated_at=utc_now(), sources=source_states(session)),
    )
