"""Delayed intraday quotes.

The tests that matter here all defend one claim: nothing in this system can
present a delayed price as a live one. No free source provides real-time
consolidated quotes, so a number that loses its delay label is a number that
will eventually be misread.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest
from sqlalchemy import select, text
from sqlalchemy.exc import DBAPIError, IntegrityError

from invest.db.models import IntradayObservation
from invest.ingest.intraday import (
    Quote,
    ingest_intraday_for_security,
    ingest_latest_quote,
    latest_quote,
)
from invest.providers.alphavantage import (
    QUOTE_DELAY_SECONDS,
    AlphaVantageProvider,
    parse_daily,
    parse_global_quote,
    parse_intraday,
)
from invest.providers.base import (
    IntradayBar,
    IntradayProvider,
    PriceProvider,
    ProviderError,
    ProviderUnavailable,
)
from invest.security_master import resolve, seed_universe

NOW = datetime(2026, 6, 15, 20, 0, tzinfo=UTC)


# --------------------------------------------------------------------------
# The record type refuses an unlabelled or ambiguous print
# --------------------------------------------------------------------------


def test_delay_seconds_has_no_default() -> None:
    """Every construction site must state the staleness explicitly."""
    with pytest.raises(Exception):  # noqa: B017 - pydantic ValidationError
        IntradayBar(
            symbol="AAPL",
            observed_at=NOW,
            close=Decimal(100),
            source="test",
        )


def test_naive_timestamp_is_rejected() -> None:
    """Exchange-local vs UTC must never be left to the reader to guess."""
    with pytest.raises(ValueError, match="timezone-aware"):
        IntradayBar(
            symbol="AAPL",
            observed_at=datetime(2026, 6, 15, 16, 0),  # noqa: DTZ001 - the point
            close=Decimal(100),
            source="test",
            delay_seconds=900,
        )


def test_negative_delay_is_rejected() -> None:
    with pytest.raises(ValueError, match="negative"):
        IntradayBar(
            symbol="AAPL", observed_at=NOW, close=Decimal(100), source="test",
            delay_seconds=-1,
        )


def test_is_delayed_derives_from_the_number() -> None:
    delayed = IntradayBar(
        symbol="AAPL", observed_at=NOW, close=Decimal(100), source="t", delay_seconds=900
    )
    live = IntradayBar(
        symbol="AAPL", observed_at=NOW, close=Decimal(100), source="t", delay_seconds=0
    )
    assert delayed.is_delayed is True
    assert live.is_delayed is False


# --------------------------------------------------------------------------
# The database enforces the same thing
# --------------------------------------------------------------------------


@pytest.fixture
def aapl(db_session):
    seed_universe(db_session)
    db_session.commit()
    return resolve(db_session, "AAPL")


def test_delay_seconds_is_not_nullable(db_session, aapl) -> None:
    """A caller cannot write a quote without saying how stale it was."""
    with pytest.raises(IntegrityError):
        db_session.execute(
            text(
                "INSERT INTO intraday_observations "
                "(security_id, observed_at, close, source, is_delayed) "
                "VALUES (:s, :t, 100, 'test', true)"
            ),
            {"s": aapl.security_id, "t": NOW},
        )
    db_session.rollback()


def test_flag_must_agree_with_the_number(db_session, aapl) -> None:
    """is_delayed=false alongside a 900-second delay is a lie the schema
    refuses to store.
    """
    with pytest.raises(IntegrityError):
        db_session.execute(
            text(
                "INSERT INTO intraday_observations "
                "(security_id, observed_at, close, source, delay_seconds, is_delayed) "
                "VALUES (:s, :t, 100, 'test', 900, false)"
            ),
            {"s": aapl.security_id, "t": NOW},
        )
    db_session.rollback()


def test_intraday_is_append_only(db_session, aapl) -> None:
    db_session.add(
        IntradayObservation(
            security_id=aapl.security_id,
            observed_at=NOW,
            close=100,
            source="test",
            delay_seconds=900,
            is_delayed=True,
        )
    )
    db_session.commit()

    row = db_session.scalars(select(IntradayObservation)).one()
    row.close = 999
    with pytest.raises(DBAPIError, match="append-only"):
        db_session.commit()
    db_session.rollback()


# --------------------------------------------------------------------------
# Alpha Vantage parsing — including the trap
# --------------------------------------------------------------------------


def test_rate_limit_arrives_as_a_200_and_is_caught() -> None:
    """The whole reason this adapter exists.

    Alpha Vantage answers a blown quota with HTTP 200 and a 'Note' key. Code
    that trusts the status and then looks for its data key sees nothing and
    concludes the security has no prices — a wrong answer wearing a success.
    """
    payload = {"Note": "Thank you for using Alpha Vantage! Our standard API rate limit is..."}
    with pytest.raises(ProviderUnavailable, match="quota or throttle"):
        parse_daily(payload, "AAPL")
    with pytest.raises(ProviderUnavailable):
        parse_intraday(payload, "AAPL", interval_seconds=300, delay_seconds=900)
    with pytest.raises(ProviderUnavailable):
        parse_global_quote(payload, "AAPL", delay_seconds=900)


def test_information_key_is_also_a_throttle() -> None:
    """They use at least two different keys for the same situation."""
    with pytest.raises(ProviderUnavailable):
        parse_daily({"Information": "premium endpoint"}, "AAPL")


def test_error_message_is_a_hard_error_not_a_retry() -> None:
    """A bad symbol is an answer; retrying will not change it."""
    with pytest.raises(ProviderError, match="rejected"):
        parse_daily({"Error Message": "Invalid API call"}, "NOSUCH")


DAILY = {
    "Meta Data": {"2. Symbol": "AAPL"},
    "Time Series (Daily)": {
        "2026-06-12": {
            "1. open": "185.00", "2. high": "187.50", "3. low": "184.25",
            "4. close": "186.75", "5. volume": "52000000",
        },
        "2026-06-11": {
            "1. open": "183.00", "2. high": "186.00", "3. low": "182.50",
            "4. close": "185.10", "5. volume": "48000000",
        },
    },
}


def test_daily_parses_and_sorts() -> None:
    bars = parse_daily(DAILY, "AAPL")
    assert len(bars) == 2
    assert [b.obs_date.day for b in bars] == [11, 12]
    assert bars[1].close == Decimal("186.75")
    assert bars[1].volume == 52000000


def test_daily_is_marked_unadjusted() -> None:
    """TIME_SERIES_DAILY is raw. Comparing it to Stooq's split-adjusted series
    across a split would otherwise raise a false cross-source conflict.
    """
    bar = parse_daily(DAILY, "AAPL")[0]
    assert bar.is_split_adjusted is False
    assert bar.adj_close is None


INTRADAY = {
    "Time Series (5min)": {
        "2026-06-12 15:55:00": {
            "1. open": "186.50", "2. high": "186.90", "3. low": "186.40",
            "4. close": "186.75", "5. volume": "120000",
        },
        "2026-06-12 15:50:00": {
            "1. open": "186.20", "2. high": "186.60", "3. low": "186.10",
            "4. close": "186.50", "5. volume": "98000",
        },
    }
}


def test_intraday_parses_with_delay_attached() -> None:
    bars = parse_intraday(INTRADAY, "AAPL", interval_seconds=300, delay_seconds=900)
    assert len(bars) == 2
    assert all(b.delay_seconds == 900 for b in bars)
    assert all(b.is_delayed for b in bars)
    assert bars[-1].close == Decimal("186.75")


def test_intraday_timestamps_are_localised_not_naive() -> None:
    """Alpha Vantage sends exchange-local time with no offset. Leaving it
    naive would silently mix zones downstream.
    """
    bar = parse_intraday(INTRADAY, "AAPL", interval_seconds=300, delay_seconds=900)[0]
    assert bar.observed_at.tzinfo is not None
    assert bar.observed_at.utcoffset() is not None


def test_unsupported_interval_raises() -> None:
    with pytest.raises(ProviderError, match="unsupported interval"):
        parse_intraday(INTRADAY, "AAPL", interval_seconds=7, delay_seconds=900)


def test_global_quote_stamps_the_close_rather_than_inventing_a_minute() -> None:
    """The endpoint reports a trading day, not a time. Fabricating a plausible
    minute would be a small lie of exactly the kind this project avoids.
    """
    payload = {
        "Global Quote": {
            "01. symbol": "AAPL", "02. open": "185.00", "03. high": "187.50",
            "04. low": "184.25", "05. price": "186.75", "06. volume": "52000000",
            "07. latest trading day": "2026-06-12",
        }
    }
    bar = parse_global_quote(payload, "AAPL", delay_seconds=900)
    assert bar is not None
    assert bar.close == Decimal("186.75")
    assert bar.observed_at.hour == 16  # exchange close, stated not guessed
    assert bar.delay_seconds == 900


def test_empty_global_quote_is_none_not_an_error() -> None:
    assert parse_global_quote({"Global Quote": {}}, "AAPL", delay_seconds=900) is None


def test_missing_series_key_raises_rather_than_returning_empty() -> None:
    """An unrecognised response shape must not read as 'no data exists'."""
    with pytest.raises(ProviderError, match="Time Series"):
        parse_daily({"Meta Data": {}}, "AAPL")


def test_provider_satisfies_both_protocols() -> None:
    from invest.providers.http import HttpClient

    provider = AlphaVantageProvider(
        api_key="test", client=HttpClient(source_name="t", user_agent="t")
    )
    assert isinstance(provider, PriceProvider)
    assert isinstance(provider, IntradayProvider)
    assert provider.quote_delay_seconds == QUOTE_DELAY_SECONDS


def test_provider_refuses_to_construct_without_a_key() -> None:
    with pytest.raises(ValueError, match="ALPHAVANTAGE_API_KEY"):
        AlphaVantageProvider(api_key="")


# --------------------------------------------------------------------------
# Ingestion and read-back
# --------------------------------------------------------------------------


class FakeIntraday:
    source_name = "alphavantage"
    quote_delay_seconds = 900

    def __init__(self, bars: list[IntradayBar], quote: IntradayBar | None = None) -> None:
        self._bars = bars
        self._quote = quote

    def fetch_intraday(self, symbol, *, interval_seconds=300, limit=100):
        return list(self._bars)

    def fetch_latest_quote(self, symbol):
        return self._quote


def bar(minutes_ago: int, price: str, delay: int = 900) -> IntradayBar:
    return IntradayBar(
        symbol="AAPL",
        observed_at=NOW - timedelta(minutes=minutes_ago),
        interval_seconds=300,
        close=Decimal(price),
        volume=100_000,
        source="alphavantage",
        delay_seconds=delay,
    )


def test_bars_are_written_with_their_delay(db_session, aapl) -> None:
    provider = FakeIntraday([bar(20, "186.50"), bar(15, "186.75")])
    result = ingest_intraday_for_security(db_session, provider, aapl, now=NOW)
    db_session.commit()

    assert result.ok
    assert result.written == 2
    rows = db_session.scalars(select(IntradayObservation)).all()
    assert all(r.delay_seconds == 900 for r in rows)
    assert all(r.is_delayed for r in rows)


def test_rerun_is_idempotent(db_session, aapl) -> None:
    provider = FakeIntraday([bar(15, "186.75")])
    ingest_intraday_for_security(db_session, provider, aapl, now=NOW)
    db_session.commit()
    second = ingest_intraday_for_security(db_session, provider, aapl, now=NOW)
    db_session.commit()
    assert second.written == 0
    assert second.skipped == 1


def test_future_timestamp_is_quarantined(db_session, aapl) -> None:
    """A delayed feed cannot produce a future print; that is a timezone bug,
    and letting it through would corrupt every freshness calculation.
    """
    provider = FakeIntraday([bar(-120, "999.00")])  # two hours ahead
    result = ingest_intraday_for_security(db_session, provider, aapl, now=NOW)
    db_session.commit()

    assert result.quarantined == 1
    assert latest_quote(db_session, aapl.security_id, now=NOW) is None


def test_old_prints_are_flagged_stale(db_session, aapl) -> None:
    provider = FakeIntraday([bar(60 * 24 * 10, "150.00")])  # ten days back
    ingest_intraday_for_security(db_session, provider, aapl, now=NOW)
    db_session.commit()
    row = db_session.scalars(select(IntradayObservation)).one()
    assert row.data_quality_flag == "stale"


def test_latest_quote_reports_its_full_age(db_session, aapl) -> None:
    """Age is publisher delay plus shelf time, not just one of them."""
    provider = FakeIntraday([bar(30, "186.75")])
    ingest_intraday_for_security(db_session, provider, aapl, now=NOW)
    db_session.commit()

    quote = latest_quote(db_session, aapl.security_id, now=NOW)
    assert quote is not None
    assert quote.price == pytest.approx(186.75)
    assert quote.age_seconds == 30 * 60
    assert quote.is_realtime is False


def test_quote_description_states_the_basis() -> None:
    quote = Quote(
        price=186.75,
        observed_at=NOW - timedelta(minutes=22),
        delay_seconds=900,
        source="alphavantage",
        retrieved_at=NOW,
    )
    text_out = quote.describe()
    assert "15-min delayed feed" in text_out
    assert "22 min old" in text_out
    assert quote.is_realtime is False


def test_max_age_returns_none_rather_than_a_stale_price(db_session, aapl) -> None:
    """Refusing to answer beats answering with yesterday's number."""
    provider = FakeIntraday([bar(60 * 8, "180.00")])
    ingest_intraday_for_security(db_session, provider, aapl, now=NOW)
    db_session.commit()

    assert latest_quote(db_session, aapl.security_id, now=NOW) is not None
    assert (
        latest_quote(db_session, aapl.security_id, now=NOW, max_age=timedelta(hours=1))
        is None
    )


def test_latest_quote_endpoint_writes_one_row(db_session, aapl) -> None:
    provider = FakeIntraday([], quote=bar(18, "187.10"))
    result = ingest_latest_quote(db_session, provider, aapl, now=NOW)
    db_session.commit()
    assert result.written == 1
    assert latest_quote(db_session, aapl.security_id, now=NOW).price == pytest.approx(187.10)


def test_no_quote_available_is_reported_not_faked(db_session, aapl) -> None:
    provider = FakeIntraday([], quote=None)
    result = ingest_latest_quote(db_session, provider, aapl, now=NOW)
    assert result.ok is False
    assert "no quote available" in result.error


def test_empty_database_yields_no_quote(db_session, aapl) -> None:
    assert latest_quote(db_session, aapl.security_id, now=NOW) is None


def test_point_quote_dedup_survives_a_null_interval(db_session, aapl) -> None:
    """A point quote has interval_seconds = NULL, and `= NULL` never matches —
    so a naive dedup check would re-insert the same quote on every poll.
    """
    provider = FakeIntraday(
        [],
        quote=IntradayBar(
            symbol="AAPL",
            observed_at=NOW - timedelta(minutes=18),
            interval_seconds=None,
            close=Decimal("187.10"),
            source="alphavantage",
            delay_seconds=900,
        ),
    )
    first = ingest_latest_quote(db_session, provider, aapl, now=NOW)
    db_session.commit()
    second = ingest_latest_quote(db_session, provider, aapl, now=NOW)
    db_session.commit()

    assert first.written == 1
    assert second.written == 0
    assert second.skipped == 1
    assert len(db_session.scalars(select(IntradayObservation)).all()) == 1
