"""End-to-end price ingestion through a fake provider.

The fake satisfies the PriceProvider protocol and nothing else — which is the
point of the abstraction: the orchestration code cannot tell it apart from
Stooq, so these tests cover the real ingestion path without a network call.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import select

from invest.db.enums import DataQualityFlag, JobStatus, ValueType
from invest.db.models import DataConflict, PriceObservation, WorkflowJob
from invest.ingest.prices import ingest_prices_for_security
from invest.providers.base import PriceBar, PriceProvider, ProviderUnavailable
from invest.security_master import resolve, seed_universe

TODAY = date(2026, 6, 15)


class FakeProvider:
    """Implements the PriceProvider protocol."""

    def __init__(self, bars: list[PriceBar], source_name: str = "stooq") -> None:
        self.source_name = source_name
        self._bars = bars
        self.calls: list[tuple[str, date | None, date | None]] = []

    def fetch_daily_bars(self, symbol, start=None, end=None) -> list[PriceBar]:
        self.calls.append((symbol, start, end))
        return list(self._bars)


class FailingProvider:
    source_name = "stooq"

    def fetch_daily_bars(self, symbol, start=None, end=None):
        raise ProviderUnavailable("stooq: network down")


def make_bar(day: date, close: str, source: str = "stooq") -> PriceBar:
    price = Decimal(close)
    return PriceBar(
        symbol="aapl.us",
        obs_date=day,
        open=price,
        high=price,
        low=price,
        close=price,
        volume=1_000_000,
        currency="USD",
        source=source,
        is_split_adjusted=True,
        is_dividend_adjusted=False,
    )


@pytest.fixture
def aapl(db_session):
    seed_universe(db_session)
    db_session.commit()
    return resolve(db_session, "AAPL")


def test_fake_provider_satisfies_the_protocol() -> None:
    assert isinstance(FakeProvider([]), PriceProvider)


def test_bars_are_written(db_session, aapl) -> None:
    provider = FakeProvider(
        [make_bar(date(2026, 6, 10), "100"), make_bar(date(2026, 6, 11), "101")]
    )
    result = ingest_prices_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()

    assert result.ok
    assert result.written == 2
    rows = db_session.scalars(select(PriceObservation).order_by(PriceObservation.obs_date)).all()
    assert [float(r.close) for r in rows] == [100.0, 101.0]
    assert all(r.value_type == ValueType.OBSERVED for r in rows)
    assert all(r.security_id == aapl.security_id for r in rows)


def test_vendor_symbol_mapping_is_applied(db_session, aapl) -> None:
    """The provider gets 'aapl.us'; the database keys off security_id."""
    provider = FakeProvider([make_bar(date(2026, 6, 10), "100")])
    ingest_prices_for_security(db_session, provider, aapl, today=TODAY)
    assert provider.calls[0][0] == "aapl.us"


def test_rerun_is_idempotent(db_session, aapl) -> None:
    bars = [make_bar(date(2026, 6, 10), "100"), make_bar(date(2026, 6, 11), "101")]
    provider = FakeProvider(bars)

    first = ingest_prices_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()
    second = ingest_prices_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()

    assert first.written == 2
    assert second.written == 0
    assert second.report.skipped == 2
    assert len(db_session.scalars(select(PriceObservation)).all()) == 2


def test_duplicates_within_one_batch_are_caught(db_session, aapl) -> None:
    provider = FakeProvider([make_bar(date(2026, 6, 10), "100"), make_bar(date(2026, 6, 10), "999")])
    result = ingest_prices_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()

    assert result.written == 1
    assert result.report.skipped == 1


def test_quarantined_row_is_written_but_marked(db_session, aapl) -> None:
    """Kept for audit, excluded from the engines."""
    provider = FakeProvider([make_bar(date(2027, 1, 1), "100")])  # future-dated
    result = ingest_prices_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()

    assert result.report.quarantined == 1
    row = db_session.scalars(select(PriceObservation)).one()
    assert row.data_quality_flag == DataQualityFlag.QUARANTINED
    assert db_session.scalars(select(DataConflict)).all()


def test_provider_failure_writes_nothing_and_does_not_invent_data(db_session, aapl) -> None:
    """Ground rule 2: a failed fetch produces NULL/nothing, never an estimate."""
    result = ingest_prices_for_security(db_session, FailingProvider(), aapl, today=TODAY)
    db_session.commit()

    assert result.ok is False
    assert "network down" in result.error
    assert result.written == 0
    assert db_session.scalars(select(PriceObservation)).all() == []

    job = db_session.scalars(select(WorkflowJob)).one()
    assert job.status == JobStatus.FAILED
    assert "network down" in job.error


def test_second_source_coexists_and_disagreement_is_recorded(db_session, aapl) -> None:
    ingest_prices_for_security(
        db_session, FakeProvider([make_bar(date(2026, 6, 10), "100")]), aapl, today=TODAY
    )
    db_session.commit()

    other = FakeProvider([make_bar(date(2026, 6, 10), "130", source="yfinance")], "yfinance")
    result = ingest_prices_for_security(db_session, other, aapl, today=TODAY)
    db_session.commit()

    assert result.written == 1
    rows = db_session.scalars(select(PriceObservation)).all()
    assert {r.source for r in rows} == {"stooq", "yfinance"}

    conflicts = db_session.scalars(
        select(DataConflict).where(DataConflict.conflict_type == "cross_source_disagreement")
    ).all()
    assert len(conflicts) == 1
    assert conflicts[0].source_a == "yfinance"
    assert conflicts[0].source_b == "stooq"


def test_job_row_records_the_batch_stats(db_session, aapl) -> None:
    provider = FakeProvider([make_bar(date(2026, 6, 10), "100"), make_bar(date(2027, 1, 1), "101")])
    ingest_prices_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()

    job = db_session.scalars(select(WorkflowJob)).one()
    assert job.status == JobStatus.SUCCEEDED
    assert job.rows_written == 2
    assert job.rows_quarantined == 1
    assert job.stats_json["accepted"] == 1
    assert job.stats_json["quarantined"] == 1


def test_stale_series_is_flagged_at_series_level(db_session, aapl) -> None:
    provider = FakeProvider([make_bar(date(2026, 1, 5), "100")])
    result = ingest_prices_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()

    assert any(f.rule == "stale_series" for f in result.report.findings)
    conflicts = db_session.scalars(
        select(DataConflict).where(DataConflict.conflict_type == "staleness")
    ).all()
    assert len(conflicts) == 1


def test_engines_can_filter_out_unusable_rows(db_session, aapl) -> None:
    """The query shape every engine uses: exclude quarantined rows."""
    provider = FakeProvider([make_bar(date(2026, 6, 10), "100"), make_bar(date(2027, 1, 1), "101")])
    ingest_prices_for_security(db_session, provider, aapl, today=TODAY)
    db_session.commit()

    usable = db_session.scalars(
        select(PriceObservation).where(
            PriceObservation.data_quality_flag != DataQualityFlag.QUARANTINED
        )
    ).all()
    assert len(usable) == 1
    assert usable[0].obs_date == date(2026, 6, 10)
