"""The signal runner against a real database: scan, record, evaluate, backfill.

Prices here are synthetic: an uptrending market, one stock pulling back in an
uptrend, one in a downtrend. They put the engine in a known state; they are
not market data.
"""

from __future__ import annotations

from datetime import date, timedelta

import pytest
from sqlalchemy import select, text
from sqlalchemy.exc import DBAPIError

from invest.db.models import Filing, PriceObservation, SignalOutcome, SignalRecord
from invest.engines.signals import SignalStatus
from invest.security_master import resolve, seed_funds, seed_universe
from invest.signal_runner import backfill, evaluate_ledger, record_signals, scan
from tests.test_signals import business_days, rising, uptrend_with_pullback

AS_OF = date(2026, 9, 24)


def add_bars(
    session, ticker: str, closes: list[float], *, end: date = AS_OF, spread: float = 0.01
) -> list[date]:
    security = resolve(session, ticker)
    days = business_days(end, len(closes))
    prev = closes[0]
    for day, close in zip(days, closes, strict=True):
        session.add(
            PriceObservation(
                security_id=security.security_id,
                obs_date=day,
                open=prev,
                high=close * (1 + spread),
                low=close * (1 - spread),
                close=close,
                volume=1_000_000,
                source="stooq",
            )
        )
        prev = close
    session.flush()
    return days


def add_bars_after(
    session, ticker: str, ohlc: list[tuple[float, float, float, float]], *, start: date
) -> None:
    security = resolve(session, ticker)
    day = start
    for o, h, low, c in ohlc:
        day += timedelta(days=1)
        while day.weekday() >= 5:
            day += timedelta(days=1)
        session.add(
            PriceObservation(
                security_id=security.security_id,
                obs_date=day,
                open=o,
                high=h,
                low=low,
                close=c,
                volume=1_000_000,
                source="stooq",
            )
        )
    session.flush()


@pytest.fixture
def market(db_session):
    """An uptrending market and sector, NVDA pulling back, XOM falling."""
    seed_universe(db_session)
    seed_funds(db_session)
    add_bars(db_session, "SPY", rising(330, start=400.0, daily=0.0008))
    add_bars(db_session, "XLK", rising(330, start=150.0, daily=0.0012))
    add_bars(db_session, "XLE", rising(330, start=90.0, daily=-0.0005))
    add_bars(db_session, "NVDA", uptrend_with_pullback(330))
    add_bars(db_session, "XOM", rising(330, start=110.0, daily=-0.001))
    db_session.commit()
    return db_session


def by_ticker(result, ticker):
    return next(s for s in result.signals if s.ticker == ticker)


def test_scan_with_no_prices_degrades_honestly(db_session) -> None:
    seed_universe(db_session)
    seed_funds(db_session)
    result = scan(db_session, as_of=AS_OF)
    assert result.gate.passed is None
    assert any("SPY" in w for w in result.warnings)
    assert all(s.status == SignalStatus.INSUFFICIENT_DATA for s in result.signals)
    assert result.cards == []


def test_scan_finds_the_pullback_and_rejects_the_downtrend(market) -> None:
    result = scan(market, as_of=AS_OF, equity=100_000)
    assert result.gate.passed is True
    nvda = by_ticker(result, "NVDA")
    assert nvda.status == SignalStatus.CARD, nvda.reasons
    assert nvda.sizing.shares and nvda.sizing.shares > 0
    assert by_ticker(result, "XOM").status == SignalStatus.NOT_IN_UPTREND
    assert [s.ticker for s in result.cards] == ["NVDA"]
    # Funds are scanned for sector strength, never for cards.
    assert "SPY" not in {s.ticker for s in result.signals}
    xlk = next(r for r in result.sectors if r.ticker == "XLK")
    xle = next(r for r in result.sectors if r.ticker == "XLE")
    assert xlk.relative_12_1 > 0 > xle.relative_12_1
    assert result.sectors[0].ticker == "XLK"  # strongest first


def test_scan_never_sees_prices_after_as_of(market) -> None:
    before = scan(market, as_of=AS_OF).as_of
    baseline = by_ticker(scan(market, as_of=AS_OF), "NVDA").as_dict()
    add_bars_after(market, "NVDA", [(1.0, 1.0, 1.0, 1.0)] * 5, start=AS_OF)
    add_bars_after(market, "SPY", [(1.0, 1.0, 1.0, 1.0)] * 5, start=AS_OF)
    market.commit()
    after = by_ticker(scan(market, as_of=AS_OF), "NVDA").as_dict()
    assert before == AS_OF
    assert after == baseline


def test_earnings_filing_vetoes_through_the_database(market) -> None:
    nvda = resolve(market, "NVDA")
    market.add(
        Filing(
            entity_id=nvda.entity_id,
            accession_number="0000000000-26-000001",
            form_type="8-K",
            filed_date=AS_OF - timedelta(days=80),
            items="2.02,9.01",
            source="sec_edgar",
        )
    )
    market.commit()
    signal = by_ticker(scan(market, as_of=AS_OF), "NVDA")
    assert signal.status == SignalStatus.VETOED
    assert any("Earnings" in r for r in signal.reasons)


def test_record_is_idempotent_and_keeps_every_candidate(market) -> None:
    result = scan(market, as_of=AS_OF)
    first = record_signals(market, result, origin="live")
    second = record_signals(market, result, origin="live")
    market.commit()
    assert first.written == len(result.candidates) == 1
    assert second.written == 0 and second.already_recorded == 1
    row = market.scalars(select(SignalRecord)).one()
    assert row.fired is True and row.status == "card" and row.origin == "live"
    assert row.signal_json["levels"]["entry"] == pytest.approx(float(row.entry))
    with pytest.raises(ValueError):
        record_signals(market, result, origin="paper")


def test_evaluate_appends_only_when_the_outcome_changes(market) -> None:
    result = scan(market, as_of=AS_OF)
    record_signals(market, result, origin="live")
    market.commit()

    pending = evaluate_ledger(market)
    assert pending.appended == 1
    assert market.scalars(select(SignalOutcome)).one().status == "pending"
    assert evaluate_ledger(market).appended == 0  # nothing new: nothing written

    levels = result.cards[0].levels
    e, t = levels.entry, levels.target
    add_bars_after(
        market, "NVDA", [(e - 0.5, e + 0.5, e - 1.0, e), (e + 1, t + 1, e, t)], start=AS_OF
    )
    market.commit()
    report = evaluate_ledger(market)
    assert report.appended == 1
    latest = market.scalars(select(SignalOutcome).order_by(SignalOutcome.id.desc())).first()
    assert latest.status == "target"
    assert float(latest.r_gross) == pytest.approx(2.0, abs=0.01)
    # Default costs are pessimistic on purpose: net is always below gross.
    assert 1.8 < float(latest.r_net) < float(latest.r_gross)
    assert evaluate_ledger(market).final == 1  # final outcomes are never re-scored


def test_ledger_rows_cannot_be_edited(market) -> None:
    record_signals(market, scan(market, as_of=AS_OF), origin="live")
    market.commit()
    with pytest.raises(DBAPIError):
        market.execute(text("UPDATE signals SET final_score = 100"))
    market.rollback()
    with pytest.raises(DBAPIError):
        market.execute(text("DELETE FROM signals"))
    market.rollback()


def test_backfill_is_labelled_and_point_in_time(market) -> None:
    report = backfill(market, start=AS_OF - timedelta(days=10), end=AS_OF)
    market.commit()
    assert report.days >= 6
    origins = set(market.scalars(select(SignalRecord.origin)).all())
    assert origins <= {"backfill"}
    for row in market.scalars(select(SignalRecord)).all():
        assert row.as_of_date <= AS_OF
        assert row.signal_json["as_of"] == row.as_of_date.isoformat()
