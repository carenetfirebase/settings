"""Point-in-time correctness — the guarantee the whole backtest rests on.

If any of these fail, every historical result the platform produces is
contaminated by look-ahead bias.
"""

from __future__ import annotations

from datetime import date

import pytest

from invest.db.enums import DataQualityFlag
from invest.db.models import Fundamental, PriceObservation
from invest.repository import (
    get_annual_metrics,
    get_close_series,
    get_fundamental_series,
    get_price_frame,
    latest_fundamental,
    latest_price,
    market_cap,
    shares_outstanding,
    value_at,
)
from invest.security_master import resolve, seed_universe


@pytest.fixture
def aapl(db_session):
    seed_universe(db_session)
    db_session.commit()
    return resolve(db_session, "AAPL")


def add_fact(session, entity_id, **kwargs):
    defaults = {
        "metric_name": "Revenues",
        "unit": "USD",
        "period_start": date(2025, 1, 1),
        "period_end": date(2025, 12, 31),
        "fiscal_period": "FY",
        "fiscal_year": 2025,
        "source": "sec_edgar",
    }
    defaults.update(kwargs)
    session.add(Fundamental(entity_id=entity_id, **defaults))
    session.flush()


# --------------------------------------------------------------------------
# The look-ahead guarantee
# --------------------------------------------------------------------------


def test_fact_filed_after_cutoff_is_invisible(db_session, aapl) -> None:
    add_fact(db_session, aapl.entity_id, metric_value=1000, filed_date=date(2026, 2, 1))
    db_session.commit()

    assert get_fundamental_series(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 1, 1)) == []
    assert len(
        get_fundamental_series(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 3, 1))
    ) == 1


def test_restatement_is_invisible_until_it_is_filed(db_session, aapl) -> None:
    """The heart of point-in-time: a simulation dated between the original and
    the restatement must see the ORIGINAL number, because that is what was
    public at the time.
    """
    add_fact(
        db_session,
        aapl.entity_id,
        metric_value=1000,
        filed_date=date(2026, 2, 1),
        accession_number="orig",
    )
    add_fact(
        db_session,
        aapl.entity_id,
        metric_value=950,
        filed_date=date(2026, 8, 1),
        accession_number="restated",
    )
    db_session.commit()

    before = latest_fundamental(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 5, 1))
    after = latest_fundamental(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 9, 1))

    assert before.value == 1000.0
    assert before.accession_number == "orig"
    assert after.value == 950.0
    assert after.accession_number == "restated"


def test_only_one_row_per_period_survives(db_session, aapl) -> None:
    """Restatements must not double-count into a growth series."""
    add_fact(db_session, aapl.entity_id, metric_value=1000, filed_date=date(2026, 2, 1), accession_number="a")
    add_fact(db_session, aapl.entity_id, metric_value=950, filed_date=date(2026, 8, 1), accession_number="b")
    db_session.commit()

    series = get_fundamental_series(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 9, 1))
    assert len(series) == 1
    assert series[0].value == 950.0


def test_multi_year_series_is_ordered_oldest_first(db_session, aapl) -> None:
    for year, value in ((2023, 800), (2024, 900), (2025, 1000)):
        add_fact(
            db_session,
            aapl.entity_id,
            metric_value=value,
            fiscal_year=year,
            period_start=date(year, 1, 1),
            period_end=date(year, 12, 31),
            filed_date=date(year + 1, 2, 1),
            accession_number=f"acc-{year}",
        )
    db_session.commit()

    series = get_fundamental_series(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 6, 1))
    assert [p.value for p in series] == [800.0, 900.0, 1000.0]
    assert [p.period_end.year for p in series] == [2023, 2024, 2025]


def test_as_of_truncates_history_not_just_the_latest(db_session, aapl) -> None:
    for year, value in ((2023, 800), (2024, 900), (2025, 1000)):
        add_fact(
            db_session,
            aapl.entity_id,
            metric_value=value,
            fiscal_year=year,
            period_start=date(year, 1, 1),
            period_end=date(year, 12, 31),
            filed_date=date(year + 1, 2, 1),
            accession_number=f"acc-{year}",
        )
    db_session.commit()

    series = get_fundamental_series(db_session, aapl.entity_id, "Revenues", as_of=date(2025, 6, 1))
    assert [p.value for p in series] == [800.0, 900.0]


# --------------------------------------------------------------------------
# Quarantined data is invisible
# --------------------------------------------------------------------------


def test_quarantined_fundamental_never_reaches_an_engine(db_session, aapl) -> None:
    add_fact(
        db_session,
        aapl.entity_id,
        metric_value=999999,
        filed_date=date(2026, 2, 1),
        data_quality_flag=DataQualityFlag.QUARANTINED,
    )
    db_session.commit()
    assert get_fundamental_series(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 6, 1)) == []


def test_flagged_but_usable_data_is_returned(db_session, aapl) -> None:
    """Flagged means 'lower confidence', not 'discard'."""
    add_fact(
        db_session,
        aapl.entity_id,
        metric_value=1000,
        filed_date=date(2026, 2, 1),
        data_quality_flag=DataQualityFlag.CONFLICTED,
    )
    db_session.commit()
    series = get_fundamental_series(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 6, 1))
    assert len(series) == 1
    assert series[0].data_quality_flag == DataQualityFlag.CONFLICTED


def test_quarantined_price_is_excluded(db_session, aapl) -> None:
    db_session.add_all(
        [
            PriceObservation(
                security_id=aapl.security_id, obs_date=date(2026, 6, 1), close=100, source="stooq"
            ),
            PriceObservation(
                security_id=aapl.security_id,
                obs_date=date(2026, 6, 2),
                close=99999,
                source="stooq",
                data_quality_flag=DataQualityFlag.QUARANTINED,
            ),
        ]
    )
    db_session.commit()

    frame = get_price_frame(db_session, aapl.security_id)
    assert len(frame) == 1
    assert frame.index[0] == date(2026, 6, 1)


# --------------------------------------------------------------------------
# Missing data reports as missing
# --------------------------------------------------------------------------


def test_absent_metric_returns_empty_not_zero(db_session, aapl) -> None:
    """INSUFFICIENT DATA, never a fabricated zero."""
    assert get_fundamental_series(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 6, 1)) == []
    assert latest_fundamental(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 6, 1)) is None
    assert value_at([]) is None


def test_null_value_stays_null(db_session, aapl) -> None:
    add_fact(db_session, aapl.entity_id, metric_value=None, filed_date=date(2026, 2, 1))
    db_session.commit()
    point = latest_fundamental(db_session, aapl.entity_id, "Revenues", as_of=date(2026, 6, 1))
    assert point is not None
    assert point.value is None


def test_market_cap_is_none_when_an_input_is_missing(db_session, aapl) -> None:
    db_session.add(
        PriceObservation(
            security_id=aapl.security_id, obs_date=date(2026, 6, 1), close=100, source="stooq"
        )
    )
    db_session.commit()
    # Price exists, share count does not -> no partially-real number.
    assert shares_outstanding(db_session, aapl.entity_id) is None
    assert market_cap(db_session, aapl.security_id, aapl.entity_id) is None


def test_market_cap_computes_when_both_inputs_exist(db_session, aapl) -> None:
    db_session.add(
        PriceObservation(
            security_id=aapl.security_id, obs_date=date(2026, 6, 1), close=100, source="stooq"
        )
    )
    add_fact(
        db_session,
        aapl.entity_id,
        metric_name="SharesOutstanding",
        metric_value=1_000_000,
        unit="shares",
        filed_date=date(2026, 2, 1),
    )
    db_session.commit()
    assert market_cap(db_session, aapl.security_id, aapl.entity_id) == pytest.approx(100_000_000)


# --------------------------------------------------------------------------
# Prices
# --------------------------------------------------------------------------


def test_price_frame_is_sorted_and_typed(db_session, aapl) -> None:
    for day, close in ((3, 102), (1, 100), (2, 101)):
        db_session.add(
            PriceObservation(
                security_id=aapl.security_id,
                obs_date=date(2026, 6, day),
                close=close,
                source="stooq",
            )
        )
    db_session.commit()

    frame = get_price_frame(db_session, aapl.security_id)
    assert list(frame.index) == [date(2026, 6, 1), date(2026, 6, 2), date(2026, 6, 3)]
    assert frame["close"].dtype == float


def test_as_of_caps_the_price_series(db_session, aapl) -> None:
    for day in (1, 2, 3):
        db_session.add(
            PriceObservation(
                security_id=aapl.security_id,
                obs_date=date(2026, 6, day),
                close=100 + day,
                source="stooq",
            )
        )
    db_session.commit()

    series = get_close_series(db_session, aapl.security_id, as_of=date(2026, 6, 2))
    assert len(series) == 2
    assert series.iloc[-1] == 102.0


def test_one_row_per_day_when_sources_overlap(db_session, aapl) -> None:
    db_session.add_all(
        [
            PriceObservation(
                security_id=aapl.security_id, obs_date=date(2026, 6, 1), close=100, source="stooq"
            ),
            PriceObservation(
                security_id=aapl.security_id, obs_date=date(2026, 6, 1), close=101, source="yfinance"
            ),
        ]
    )
    db_session.commit()

    frame = get_price_frame(db_session, aapl.security_id)
    assert len(frame) == 1

    only_yf = get_price_frame(db_session, aapl.security_id, source="yfinance")
    assert only_yf["close"].iloc[0] == 101.0


def test_latest_price_respects_as_of(db_session, aapl) -> None:
    for day in (1, 5):
        db_session.add(
            PriceObservation(
                security_id=aapl.security_id,
                obs_date=date(2026, 6, day),
                close=100 + day,
                source="stooq",
            )
        )
    db_session.commit()

    assert latest_price(db_session, aapl.security_id, as_of=date(2026, 6, 3)) == (
        date(2026, 6, 1),
        101.0,
    )
    assert latest_price(db_session, aapl.security_id) == (date(2026, 6, 5), 105.0)


def test_empty_price_history_returns_empty_frame(db_session, aapl) -> None:
    frame = get_price_frame(db_session, aapl.security_id)
    assert frame.empty
    assert get_close_series(db_session, aapl.security_id).empty
    assert latest_price(db_session, aapl.security_id) is None


def test_get_annual_metrics_reports_missing_as_empty(db_session, aapl) -> None:
    add_fact(db_session, aapl.entity_id, metric_value=1000, filed_date=date(2026, 2, 1))
    db_session.commit()

    result = get_annual_metrics(
        db_session, aapl.entity_id, ["Revenues", "NetIncomeLoss"], as_of=date(2026, 6, 1)
    )
    assert len(result["Revenues"]) == 1
    assert result["NetIncomeLoss"] == []
