"""The activity feed and dashboard KPIs. docs/API_CONTRACT.md.

Every computed figure here is computed in Python. The frontend formats and
never calculates (non-negotiable #8), so `disclosure_lag_days` arrives as an
integer rather than two dates the client subtracts — one source of truth per
figure, and no chance of the client and the scorer disagreeing about what a
lag is.

Cursor pagination, not offset: the feed changes underneath the reader, and
offset paging would silently skip or repeat rows as new events land.
"""

from __future__ import annotations

import base64
import binascii
from datetime import date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Query
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from imt.api.deps import SessionDep, source_states
from imt.api.envelope import Envelope, Meta
from imt.core.clock import utc_now
from imt.db.enums import SignalCategory
from imt.db.models import Company, Filing, SignalEvent, TickerMapRow

router = APIRouter(tags=["feed"])

DATED_CATEGORIES = {"political", "corporate_insider", "institutional"}


class Money(BaseModel):
    low: int
    high: int
    currency: str


class EntityMatchInfo(BaseModel):
    confidence: float
    method: str


class SourceRef(BaseModel):
    id: str
    document_url: str
    record_id: str


class FeedItem(BaseModel):
    """Field names are normative — docs/API_CONTRACT.md."""

    event_id: str
    category: str
    detected_at: datetime
    transaction_date: date | None
    disclosure_date: date | None
    disclosure_lag_days: int | None
    public_available_at: datetime
    headline: str
    cik: str
    ticker: str | None
    company_name: str | None
    value_range: Money | None
    value_exact: int | None
    currency: str
    entity_match: EntityMatchInfo | None
    source: SourceRef


class KpiCard(BaseModel):
    key: str
    label: str
    value: int | None
    delta: int | None
    unit: str
    # Present when the card cannot be computed yet. The UI renders the reason
    # rather than a zero -- "0 congressional trades" and "we have not ingested
    # congressional data" are different claims.
    reason_code: str | None = None


def _encode_cursor(detected_at: datetime, event_id: str) -> str:
    raw = f"{detected_at.isoformat()}|{event_id}"
    return base64.urlsafe_b64encode(raw.encode()).decode()


def _decode_cursor(cursor: str) -> tuple[datetime, str] | None:
    try:
        raw = base64.urlsafe_b64decode(cursor.encode()).decode()
        stamp, event_id = raw.split("|", 1)
        return datetime.fromisoformat(stamp), event_id
    except (ValueError, binascii.Error, UnicodeDecodeError):
        # A malformed cursor restarts the feed rather than 500ing. The reader
        # sees the top of the list, which is recoverable; an error page is not.
        return None


def _ticker_for(session: Session, cik: str, as_of: date) -> str | None:
    """Point-in-time ticker. Never a bare ticker lookup (SPEC §2)."""
    return session.execute(
        select(TickerMapRow.ticker)
        .where(
            TickerMapRow.cik == cik,
            TickerMapRow.valid_from <= as_of,
            (TickerMapRow.valid_to.is_(None)) | (TickerMapRow.valid_to >= as_of),
        )
        .limit(1)
    ).scalar_one_or_none()


@router.get("/feed", response_model=Envelope[list[FeedItem]])
def feed(
    session: SessionDep,
    category: Annotated[str | None, Query()] = None,
    cursor: Annotated[str | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> Envelope[list[FeedItem]]:
    stmt = (
        select(SignalEvent, Company.name)
        .join(Company, Company.cik == SignalEvent.cik)
        .order_by(SignalEvent.detected_at.desc(), SignalEvent.event_id.desc())
        .limit(limit + 1)
    )
    if category:
        stmt = stmt.where(SignalEvent.category == SignalCategory(category))
    if cursor:
        decoded = _decode_cursor(cursor)
        if decoded:
            stamp, last_id = decoded
            stmt = stmt.where(
                (SignalEvent.detected_at < stamp)
                | ((SignalEvent.detected_at == stamp) & (SignalEvent.event_id < last_id))
            )

    rows = session.execute(stmt).all()
    has_more = len(rows) > limit
    rows = rows[:limit]

    items: list[FeedItem] = []
    for event, company_name in rows:
        as_of = event.transaction_date or event.disclosure_date or event.detected_at.date()
        value_range = (
            Money(
                low=event.value_low_minor,
                high=event.value_high_minor,
                currency=event.currency,
            )
            if event.value_low_minor is not None and event.value_high_minor is not None
            else None
        )
        items.append(
            FeedItem(
                event_id=event.event_id,
                category=event.category.value,
                detected_at=event.detected_at,
                transaction_date=event.transaction_date,
                disclosure_date=event.disclosure_date,
                disclosure_lag_days=event.disclosure_lag_days,
                public_available_at=event.public_available_at,
                headline=event.headline,
                cik=event.cik,
                ticker=_ticker_for(session, event.cik, as_of),
                company_name=company_name,
                value_range=value_range,
                value_exact=event.value_exact_minor,
                currency=event.currency,
                entity_match=(
                    EntityMatchInfo(
                        confidence=float(event.entity_match_confidence),
                        method="cik_direct" if event.entity_match_confidence == 1 else "resolved",
                    )
                    if event.entity_match_confidence is not None
                    else None
                ),
                source=SourceRef(
                    id=event.source_id,
                    document_url=event.source_document_url,
                    record_id=event.source_record_id,
                ),
            )
        )

    next_cursor = (
        _encode_cursor(rows[-1][0].detected_at, rows[-1][0].event_id) if has_more and rows else None
    )
    return Envelope(
        data=items,
        meta=Meta(
            generated_at=utc_now(),
            sources=source_states(session),
            next_cursor=next_cursor,
        ),
    )


def _count_since(session: Session, category: SignalCategory, hours: int) -> int:
    cutoff = utc_now() - timedelta(hours=hours)
    return session.execute(
        select(func.count())
        .select_from(SignalEvent)
        .where(SignalEvent.category == category, SignalEvent.detected_at >= cutoff)
    ).scalar_one()


@router.get("/dashboard/kpis", response_model=Envelope[list[KpiCard]])
def kpis(session: SessionDep) -> Envelope[list[KpiCard]]:
    """The six KPI cards. UI_SPEC §4.3.

    Card 3 counts congressional trades **disclosed** in the last 24 hours, not
    transacted — the underlying transactions average weeks older, and the
    card's tooltip says so. Counting by transaction date would be a different
    and much smaller number, and presenting it as "24h activity" would be the
    exact misreading UI_SPEC correction #2 exists to prevent.
    """
    form4_24h = session.execute(
        select(func.count())
        .select_from(Filing)
        .where(
            Filing.form_type.in_(["4", "4/A"]),
            Filing.public_available_at >= utc_now() - timedelta(hours=24),
        )
    ).scalar_one()

    activist_24h = _count_since(session, SignalCategory.INSTITUTIONAL, 24)
    congress_24h = _count_since(session, SignalCategory.POLITICAL, 24)

    has_congress = session.execute(
        select(func.count())
        .select_from(SignalEvent)
        .where(SignalEvent.category == SignalCategory.POLITICAL)
    ).scalar_one()

    cards = [
        # Scoring lands in Phase 3; until then this is unavailable rather
        # than zero, so the card cannot read as "no high-priority signals".
        KpiCard(
            key="high_priority_signals",
            label="High Priority Signals",
            value=None,
            delta=None,
            unit="count",
            reason_code="scoring_not_available_until_phase_3",
        ),
        KpiCard(
            key="form4_filings_24h",
            label="Form 4 Filings (24h)",
            value=form4_24h,
            delta=None,
            unit="count",
        ),
        KpiCard(
            key="congress_trades_24h",
            label="Congress Trades (24h)",
            value=congress_24h if has_congress else None,
            delta=None,
            unit="count",
            reason_code=None
            if has_congress
            else "congressional_ingest_not_available_until_phase_4",
        ),
        KpiCard(
            key="activist_alerts",
            label="13D/13G Alerts",
            value=activist_24h,
            delta=None,
            unit="count",
        ),
        KpiCard(
            key="market_regime",
            label="Market Regime",
            value=None,
            delta=None,
            unit="label",
            reason_code="macro_ingest_not_available_until_phase_7",
        ),
        KpiCard(
            key="data_sources",
            label="Data Sources",
            value=sum(1 for s in source_states(session) if s.status == "current"),
            delta=None,
            unit="count",
        ),
    ]
    return Envelope(data=cards, meta=Meta(generated_at=utc_now(), sources=source_states(session)))
