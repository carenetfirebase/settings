"""FRED parsing, macro ingestion, and the regime classifier."""

from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

import pytest
from sqlalchemy import select

from invest.db.enums import DataQualityFlag, JobStatus
from invest.db.models import MacroObservation, WorkflowJob
from invest.engines.regime import (
    MIN_SIGNALS_FOR_CLASSIFICATION,
    Regime,
    classify_from_database,
    classify_regime,
    credit_spread_signal,
    inflation_signal,
    sahm_signal,
    volatility_signal,
    yield_curve_signal,
)
from invest.ingest.macro import get_macro_series, ingest_series, latest_macro_value
from invest.providers.base import MacroPoint, ProviderError, ProviderUnavailable
from invest.providers.fred import parse_observations

TODAY = date(2026, 6, 15)


# --------------------------------------------------------------------------
# FRED parsing
# --------------------------------------------------------------------------


def test_parses_observations() -> None:
    payload = {
        "observations": [
            {"date": "2026-01-01", "value": "4.25", "realtime_start": "2026-01-02"},
            {"date": "2026-02-01", "value": "4.10", "realtime_start": "2026-02-02"},
        ]
    }
    points = parse_observations(payload, "DGS10")
    assert len(points) == 2
    assert points[0].obs_date == date(2026, 1, 1)
    assert points[0].value == Decimal("4.25")
    assert points[0].realtime_start == date(2026, 1, 2)
    assert points[0].unit == "percent"


def test_fred_missing_value_marker_becomes_null_not_zero() -> None:
    """FRED writes '.' for unavailable. A zero unemployment rate and an
    unpublished one are very different claims.
    """
    payload = {"observations": [{"date": "2026-01-01", "value": "."}]}
    assert parse_observations(payload, "UNRATE")[0].value is None


def test_unparseable_value_becomes_null() -> None:
    payload = {"observations": [{"date": "2026-01-01", "value": "not a number"}]}
    assert parse_observations(payload, "DGS10")[0].value is None


def test_observations_are_sorted() -> None:
    payload = {
        "observations": [
            {"date": "2026-03-01", "value": "1"},
            {"date": "2026-01-01", "value": "2"},
        ]
    }
    points = parse_observations(payload, "DGS10")
    assert [p.obs_date for p in points] == [date(2026, 1, 1), date(2026, 3, 1)]


def test_missing_observations_array_raises() -> None:
    with pytest.raises(ProviderError, match="no 'observations'"):
        parse_observations({"error": "bad request"}, "DGS10")


def test_non_percent_series_has_no_unit_assumption() -> None:
    payload = {"observations": [{"date": "2026-01-01", "value": "100"}]}
    assert parse_observations(payload, "CPIAUCSL")[0].unit is None


# --------------------------------------------------------------------------
# Ingestion
# --------------------------------------------------------------------------


class FakeFred:
    source_name = "fred"

    def __init__(self, points: list[MacroPoint]) -> None:
        self._points = points

    def fetch_series(self, series_id, start=None, end=None):
        return [p for p in self._points if p.series_id == series_id]


class FailingFred:
    source_name = "fred"

    def fetch_series(self, series_id, start=None, end=None):
        raise ProviderUnavailable("fred: HTTP 429")


def point(series_id: str, obs_date: date, value, **overrides) -> MacroPoint:
    base = {
        "series_id": series_id,
        "obs_date": obs_date,
        "value": None if value is None else Decimal(str(value)),
        "unit": "percent",
        "source": "fred",
    }
    base.update(overrides)
    return MacroPoint(**base)


def test_series_is_written(db_session) -> None:
    provider = FakeFred(
        [point("DGS10", date(2026, 1, 1), "4.25"), point("DGS10", date(2026, 2, 1), "4.10")]
    )
    result = ingest_series(db_session, provider, "DGS10", today=TODAY)
    db_session.commit()

    assert result.ok
    assert result.written == 2
    rows = db_session.scalars(select(MacroObservation)).all()
    assert len(rows) == 2


def test_rerun_is_idempotent(db_session) -> None:
    provider = FakeFred([point("DGS10", date(2026, 1, 1), "4.25")])
    ingest_series(db_session, provider, "DGS10", today=TODAY)
    db_session.commit()
    second = ingest_series(db_session, provider, "DGS10", today=TODAY)
    db_session.commit()

    assert second.written == 0
    assert second.skipped == 1


def test_null_values_are_stored_flagged_missing(db_session) -> None:
    """Kept so the gap is visible, but excluded from every read."""
    provider = FakeFred([point("UNRATE", date(2026, 1, 1), None)])
    result = ingest_series(db_session, provider, "UNRATE", today=TODAY)
    db_session.commit()

    assert result.null_values == 1
    row = db_session.scalars(select(MacroObservation)).one()
    assert row.value is None
    assert row.data_quality_flag == DataQualityFlag.MISSING
    assert get_macro_series(db_session, "UNRATE") == []


def test_future_observations_are_skipped(db_session) -> None:
    provider = FakeFred([point("DGS10", date(2027, 1, 1), "4.0")])
    result = ingest_series(db_session, provider, "DGS10", today=TODAY)
    db_session.commit()
    assert result.written == 0


def test_provider_failure_writes_nothing(db_session) -> None:
    result = ingest_series(db_session, FailingFred(), "DGS10", today=TODAY)
    db_session.commit()
    assert result.ok is False
    assert db_session.scalars(select(MacroObservation)).all() == []
    assert db_session.scalars(select(WorkflowJob)).one().status == JobStatus.FAILED


def test_vintage_after_cutoff_is_invisible(db_session) -> None:
    """A GDP figure describing Q1 but first published in Q3 must not be
    visible to a simulation dated Q2 — this is where naive macro backtests
    produce spectacular fake results.
    """
    provider = FakeFred(
        [
            point(
                "GDPC1",
                date(2026, 1, 1),
                "100",
                realtime_start=date(2026, 5, 1),  # published in May
                unit=None,
            )
        ]
    )
    ingest_series(db_session, provider, "GDPC1", today=TODAY)
    db_session.commit()

    assert get_macro_series(db_session, "GDPC1", as_of=date(2026, 3, 1)) == []
    assert len(get_macro_series(db_session, "GDPC1", as_of=date(2026, 6, 1))) == 1


def test_latest_value_returns_its_date(db_session) -> None:
    """So the caller can judge freshness rather than being handed a stale
    number dressed as current.
    """
    provider = FakeFred(
        [point("DGS10", date(2026, 1, 1), "4.25"), point("DGS10", date(2026, 2, 1), "4.10")]
    )
    ingest_series(db_session, provider, "DGS10", today=TODAY)
    db_session.commit()

    result = latest_macro_value(db_session, "DGS10")
    assert result == (date(2026, 2, 1), 4.10)


def test_latest_value_is_none_when_absent(db_session) -> None:
    assert latest_macro_value(db_session, "NOTHING") is None


# --------------------------------------------------------------------------
# Individual signals
# --------------------------------------------------------------------------


def test_inverted_curve_is_negative() -> None:
    signal = yield_curve_signal(-0.5)
    assert signal.direction == -1
    assert "inverted" in signal.detail


def test_steep_curve_is_positive() -> None:
    assert yield_curve_signal(1.5).direction == 1


def test_flat_curve_is_neutral() -> None:
    assert yield_curve_signal(0.2).direction == 0


def test_wide_credit_spreads_are_negative() -> None:
    signal = credit_spread_signal(7.5)
    assert signal.direction == -1
    assert "stress" in signal.detail


def test_tight_credit_spreads_are_positive() -> None:
    assert credit_spread_signal(3.0).direction == 1


def test_elevated_vix_is_negative() -> None:
    assert volatility_signal(35.0).direction == -1
    assert volatility_signal(12.0).direction == 1
    assert volatility_signal(20.0).direction == 0


def test_missing_inputs_produce_unavailable_signals() -> None:
    for signal in (
        yield_curve_signal(None),
        credit_spread_signal(None),
        volatility_signal(None),
    ):
        assert signal.available is False
        assert signal.direction is None
        assert signal.unavailable_reason


def test_sahm_rule_triggers_hand_checked() -> None:
    """12m low of 3.5%, recent 3m average of 4.1% -> gap 0.6pp, above the
    0.5pp threshold.
    """
    series = [(date(2025, m, 1), 3.5) for m in range(1, 10)]
    series += [(date(2025, 10, 1), 4.1), (date(2025, 11, 1), 4.1), (date(2025, 12, 1), 4.1)]
    signal = sahm_signal(series)
    assert signal.value == pytest.approx(0.6)
    assert signal.direction == -1
    assert "Sahm rule triggered" in signal.detail


def test_stable_unemployment_is_positive() -> None:
    series = [(date(2025, m, 1), 4.0) for m in range(1, 13)]
    signal = sahm_signal(series)
    assert signal.value == pytest.approx(0.0)
    assert signal.direction == 1


def test_sahm_refuses_a_short_window() -> None:
    """Approximating from 6 months would change what the indicator means."""
    series = [(date(2025, m, 1), 4.0) for m in range(1, 7)]
    signal = sahm_signal(series)
    assert signal.available is False
    assert "12 months" in signal.unavailable_reason


def test_inflation_yoy_hand_checked() -> None:
    """CPI 100 -> 105 over 13 monthly points is +5.0% year over year."""
    series = [(date(2025, 1, 1), 100.0)]
    series += [(date(2025, m, 1), 100.0) for m in range(2, 13)]
    series += [(date(2026, 1, 1), 105.0)]
    signal = inflation_signal(series)
    assert signal.value == pytest.approx(5.0)
    assert signal.direction == -1  # above target


def test_subdued_inflation_is_positive() -> None:
    series = [(date(2025, m, 1), 100.0) for m in range(1, 13)]
    series += [(date(2026, 1, 1), 101.0)]
    signal = inflation_signal(series)
    assert signal.value == pytest.approx(1.0)
    assert signal.direction == 1


def test_deflation_is_negative() -> None:
    series = [(date(2025, m, 1), 100.0) for m in range(1, 13)]
    series += [(date(2026, 1, 1), 98.0)]
    signal = inflation_signal(series)
    assert signal.direction == -1
    assert "deflation" in signal.detail


def test_inflation_refuses_a_short_series() -> None:
    assert inflation_signal([(date(2026, 1, 1), 100.0)]).available is False


# --------------------------------------------------------------------------
# Classification
# --------------------------------------------------------------------------


def test_benign_conditions_are_expansion() -> None:
    assessment = classify_regime(
        as_of=TODAY, spread_10y2y=1.5, hy_oas=3.0, vix=12.0
    )
    assert assessment.regime == Regime.EXPANSION
    assert assessment.risk_score == pytest.approx(1.0)


def test_inverted_curve_plus_wide_spreads_is_stress() -> None:
    """The combination that historically matters is named explicitly rather
    than being averaged away.
    """
    assessment = classify_regime(
        as_of=TODAY, spread_10y2y=-0.5, hy_oas=8.0, vix=14.0
    )
    assert assessment.regime == Regime.STRESS


def test_broad_deterioration_is_stress() -> None:
    assessment = classify_regime(as_of=TODAY, spread_10y2y=-0.3, hy_oas=7.0, vix=35.0)
    assert assessment.regime == Regime.STRESS
    assert assessment.risk_score == pytest.approx(-1.0)


def test_mixed_conditions_are_late_cycle() -> None:
    assessment = classify_regime(as_of=TODAY, spread_10y2y=-0.2, hy_oas=4.0, vix=20.0)
    assert assessment.regime == Regime.LATE_CYCLE


def test_too_few_signals_refuses_to_classify() -> None:
    """Two indicators is not a regime call."""
    assessment = classify_regime(as_of=TODAY, spread_10y2y=1.0, hy_oas=3.0)
    assert len(assessment.available_signals) < MIN_SIGNALS_FOR_CLASSIFICATION
    assert assessment.regime == Regime.INSUFFICIENT_DATA
    assert assessment.risk_score is None
    assert assessment.is_reliable is False


def test_no_data_at_all_is_insufficient() -> None:
    assessment = classify_regime(as_of=TODAY)
    assert assessment.regime == Regime.INSUFFICIENT_DATA
    assert assessment.coverage == 0.0


def test_every_signal_is_exposed() -> None:
    """A regime label with no visible signals is an opinion."""
    assessment = classify_regime(as_of=TODAY, spread_10y2y=1.0, hy_oas=3.0, vix=12.0)
    payload = assessment.as_dict()
    assert len(payload["signals"]) == 5
    names = {s["name"] for s in payload["signals"]}
    assert names == {
        "yield_curve",
        "credit_spreads",
        "volatility",
        "unemployment_trend",
        "inflation",
    }


def test_assessment_disclaims_being_a_forecast() -> None:
    payload = classify_regime(as_of=TODAY, spread_10y2y=1.0, hy_oas=3.0, vix=12.0).as_dict()
    assert "Not a forecast" in payload["note"]
    assert "no weight in any security score" in payload["note"]
    assert payload["value_type"] == "calculated"


def test_coverage_reports_partial_data() -> None:
    assessment = classify_regime(as_of=TODAY, spread_10y2y=1.0, hy_oas=3.0, vix=12.0)
    assert assessment.coverage == pytest.approx(3 / 5)


# --------------------------------------------------------------------------
# From the database
# --------------------------------------------------------------------------


def test_classify_from_database(db_session) -> None:
    points = [
        point("T10Y2Y", date(2026, 6, 1), "-0.40"),
        point("BAMLH0A0HYM2", date(2026, 6, 1), "7.50"),
        point("VIXCLS", date(2026, 6, 1), "30.0"),
    ]
    for series_id in ("T10Y2Y", "BAMLH0A0HYM2", "VIXCLS"):
        ingest_series(db_session, FakeFred(points), series_id, today=TODAY)
    db_session.commit()

    assessment = classify_from_database(db_session, as_of=TODAY)
    assert assessment.regime == Regime.STRESS
    assert assessment.is_reliable


def test_classify_from_database_is_point_in_time(db_session) -> None:
    """A reading published after the cutoff cannot influence a historical
    regime call.
    """
    points = [
        point("T10Y2Y", date(2026, 6, 1), "-0.40"),
        point("BAMLH0A0HYM2", date(2026, 6, 1), "7.50"),
        point("VIXCLS", date(2026, 6, 1), "30.0"),
    ]
    for series_id in ("T10Y2Y", "BAMLH0A0HYM2", "VIXCLS"):
        ingest_series(db_session, FakeFred(points), series_id, today=TODAY)
    db_session.commit()

    earlier = classify_from_database(db_session, as_of=date(2026, 1, 1))
    assert earlier.regime == Regime.INSUFFICIENT_DATA


def test_classify_from_empty_database_is_insufficient(db_session) -> None:
    assessment = classify_from_database(db_session, as_of=TODAY)
    assert assessment.regime == Regime.INSUFFICIENT_DATA
    assert assessment.risk_score is None


def test_sahm_from_database(db_session) -> None:
    """Enough monthly history for the Sahm rule to evaluate."""
    points = []
    day = date(2025, 1, 1)
    for i in range(15):
        value = "3.5" if i < 12 else "4.2"
        points.append(point("UNRATE", day, value))
        day = (day.replace(day=1) + timedelta(days=32)).replace(day=1)
    ingest_series(db_session, FakeFred(points), "UNRATE", today=TODAY)
    db_session.commit()

    series = get_macro_series(db_session, "UNRATE", as_of=TODAY, limit=24)
    assert len(series) == 15
    signal = sahm_signal(series)
    assert signal.available
    assert signal.direction == -1
