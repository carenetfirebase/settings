"""Macro regime and positioning. docs/PHASES.md Phase 7.

Criteria 1 (≥20 FRED series with 10 years) and 2 (COT percentiles over 5 years
for 10 markets) need live data and are not met here. **Criteria 3 and 4 are
fully met** — they are schema and grep assertions, and both are in
``TestShortInterestIsNotShortVolume`` and ``TestNoFloatAnywhere``.
"""

from __future__ import annotations

from decimal import Decimal
from pathlib import Path

import pytest

from imt.features.macro import (
    Factor,
    Regime,
    ShortInterestReading,
    ShortVolumeReading,
    build_positioning,
    classify_regime,
    cot_reading,
    historical_percentile,
)

REPO = Path(__file__).resolve().parents[1]


class TestRegimeClassifier:
    """Phase 7 criterion 5: one of five labels, with contributing factors."""

    def test_risk_on_factors_produce_a_risk_on_label(self) -> None:
        result = classify_regime(
            [
                Factor("growth", 0.8, "GDPC1"),
                Factor("liquidity", 0.9, "WALCL"),
                Factor("risk_appetite", 0.85, "VIXCLS"),
            ]
        )
        assert result.regime in {Regime.STRONG_RISK_ON, Regime.MODERATE_RISK_ON}

    def test_inflation_and_rates_invert(self) -> None:
        """Rising inflation is risk-off even though the input is positive.

        The direction table is explicit so this judgement is visible and
        disputable rather than buried in arithmetic.
        """
        result = classify_regime(
            [Factor("inflation", 0.9, "CPIAUCSL"), Factor("rates", 0.9, "DFF")]
        )
        assert result.regime in {Regime.STRONG_RISK_OFF, Regime.MODERATE_RISK_OFF}

    def test_output_is_always_one_of_the_five_labels(self) -> None:
        for value in (-1.0, -0.5, 0.0, 0.5, 1.0):
            result = classify_regime([Factor("growth", value, "GDPC1")])
            assert result.regime in set(Regime)

    def test_contributing_factors_are_reported(self) -> None:
        """UI_SPEC §4.7: each row's tooltip names the FRED series behind it."""
        result = classify_regime([Factor("growth", 0.5, "GDPC1")])
        assert result.contributing[0].series_id == "GDPC1"

    def test_missing_factors_are_named_not_hidden(self) -> None:
        """A regime from three inputs must not present as one from eight."""
        result = classify_regime([Factor("growth", 0.5, "GDPC1")])
        assert "inflation" in result.unavailable
        assert result.coverage < 1.0

    def test_no_factors_gives_neutral_with_zero_coverage(self) -> None:
        result = classify_regime([])
        assert result.regime is Regime.NEUTRAL
        assert result.coverage == 0.0

    def test_order_does_not_change_the_result(self) -> None:
        factors = [
            Factor("growth", 0.4, "a"),
            Factor("inflation", 0.2, "b"),
            Factor("liquidity", 0.7, "c"),
        ]
        assert classify_regime(factors).score == classify_regime(factors[::-1]).score

    def test_an_unnormalized_factor_raises(self) -> None:
        """Values outside -1..+1 would silently dominate the weighted mean."""
        with pytest.raises(ValueError, match="outside"):
            Factor("growth", 5.0, "GDPC1")

    def test_labels_render_readably(self) -> None:
        assert Regime.MODERATE_RISK_ON.label == "Moderate Risk-On"


class TestCot:
    def test_percentile_needs_enough_history(self) -> None:
        """A percentile from six points is not a percentile, and COT extremes
        are where an unreliable one is most tempting to act on."""
        assert historical_percentile([1.0, 2.0, 3.0], 2.0) is None
        assert historical_percentile([float(i) for i in range(50)], 25.0) is not None

    def test_changes_over_multiple_windows(self) -> None:
        history = list(range(0, 130, 10))  # 13 weeks
        reading = cot_reading("GOLD", report_date="2026-08-21", net_positions=history)
        assert reading.net_position == 120
        assert reading.change_1w == 10
        assert reading.change_4w == 40
        assert reading.change_12w == 120

    def test_short_history_leaves_changes_none(self) -> None:
        reading = cot_reading("GOLD", report_date="2026-08-21", net_positions=[10, 20])
        assert reading.change_1w == 10
        assert reading.change_4w is None

    def test_extreme_requires_a_computable_percentile(self) -> None:
        """A short history cannot produce a false extreme."""
        short = cot_reading("GOLD", report_date="2026-08-21", net_positions=[1, 2, 3])
        assert short.percentile is None
        assert not short.is_extreme

    def test_top_decile_is_extreme(self) -> None:
        history = [*range(100), 500]
        reading = cot_reading("GOLD", report_date="2026-08-21", net_positions=history)
        assert reading.is_extreme

    def test_empty_history_raises(self) -> None:
        with pytest.raises(ValueError, match="No COT history"):
            cot_reading("GOLD", report_date="2026-08-21", net_positions=[])


class TestShortInterestIsNotShortVolume:
    """Phase 7 criterion 3, at the type and schema level.

    Short interest is a bi-monthly snapshot of open positions. Short-sale
    volume is a daily count that includes market-maker hedging closing the
    same day. A single "short" figure built from both would be meaningless in
    a way nobody would notice.
    """

    def test_they_are_different_types(self) -> None:
        assert ShortInterestReading is not ShortVolumeReading
        assert not issubclass(ShortInterestReading, ShortVolumeReading)

    def test_they_are_separate_tables(self) -> None:
        from imt.db.models import ShortInterest, ShortVolume

        assert ShortInterest.__tablename__ == "short_interest"
        assert ShortVolume.__tablename__ == "short_volume"
        assert ShortInterest.__tablename__ != ShortVolume.__tablename__

    def test_no_source_module_joins_them(self) -> None:
        """The criterion as written: no view or query combines them."""
        offenders: list[str] = []
        for path in sorted((REPO / "src" / "imt").rglob("*.py")):
            text = path.read_text(encoding="utf-8")
            if "short_interest" in text and "short_volume" in text:
                # Both names may appear in one file only in commentary that
                # explains why they are separate -- never in a join.
                for line in text.splitlines():
                    lowered = line.lower()
                    if (
                        "short_interest" in lowered
                        and "short_volume" in lowered
                        and ("join" in lowered or "union" in lowered)
                    ):
                        offenders.append(f"{path.name}: {line.strip()}")
        assert offenders == [], f"short interest joined to short volume:\n{offenders}"

    def test_short_volume_ratio_is_not_a_percent_of_shares(self) -> None:
        """It is a share of the day's trading, not of the company."""
        reading = ShortVolumeReading(
            trade_date="2026-08-21", short_volume=400_000, total_volume=1_000_000
        )
        assert reading.short_volume_ratio == Decimal("40.00")
        assert not hasattr(reading, "pct_shares_outstanding")


class TestNoFloatAnywhere:
    """Phase 7 criterion 4, and API_CONTRACT's schema assertion.

    Free float is not available at $0 (SPEC §4). The two denominators differ
    materially, often by a factor of two for closely-held companies, so
    calling one by the other's name overstates crowding.
    """

    def test_the_field_is_named_for_its_denominator(self) -> None:
        reading = ShortInterestReading(
            settlement_date="2026-08-15",
            publication_date="2026-08-23",
            shares_short=6_210_000,
            shares_outstanding=100_000_000,
        )
        assert reading.pct_shares_outstanding == Decimal("6.2100")
        assert not hasattr(reading, "pct_float")

    def test_no_float_field_in_the_orm(self) -> None:
        from imt.db.models import ShortInterest

        columns = set(ShortInterest.__table__.columns.keys())
        assert "pct_shares_outstanding" in columns
        for forbidden in ("float", "pct_float", "short_pct_float", "free_float"):
            assert forbidden not in columns

    def test_no_percent_of_float_in_backend_source(self) -> None:
        offenders: list[str] = []
        for path in sorted((REPO / "src" / "imt").rglob("*.py")):
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                lowered = line.lower()
                if "% of float" in lowered or "pct_float" in lowered:
                    # Prose forbidding it is fine; a field or label is not.
                    if "never" in lowered or "not available" in lowered:
                        continue
                    offenders.append(f"{path.name}:{number}")
        assert offenders == []

    def test_positioning_summary_declares_float_unavailable(self) -> None:
        """Stated explicitly so the UI says so, rather than leaving the reader
        to assume the percentage is float-based."""
        summary = build_positioning([])
        assert summary.float_available is False


class TestPositioning:
    def _reading(self, settlement: str, shares_short: int) -> ShortInterestReading:
        return ShortInterestReading(
            settlement_date=settlement,
            publication_date="2026-08-23",
            shares_short=shares_short,
            shares_outstanding=100_000_000,
            average_daily_volume=1_500_000,
        )

    def test_computes_the_change_in_percentage_points(self) -> None:
        summary = build_positioning(
            [self._reading("2026-07-31", 7_000_000), self._reading("2026-08-15", 6_210_000)]
        )
        assert summary.change_30d_pp == Decimal("-0.7900")

    def test_days_to_cover(self) -> None:
        summary = build_positioning([self._reading("2026-08-15", 6_000_000)])
        assert summary.days_to_cover == Decimal("4.00")

    def test_unknown_volume_gives_null_with_a_reason(self) -> None:
        """Dividing by an assumed volume would invent the most quoted number
        on the panel."""
        reading = ShortInterestReading(
            settlement_date="2026-08-15",
            publication_date="2026-08-23",
            shares_short=6_000_000,
            shares_outstanding=100_000_000,
            average_daily_volume=None,
        )
        summary = build_positioning([reading])
        assert summary.days_to_cover is None
        assert summary.reason_codes["days_to_cover"] == "average_daily_volume_unavailable"

    def test_unknown_shares_outstanding_gives_null_not_zero(self) -> None:
        reading = ShortInterestReading(
            settlement_date="2026-08-15",
            publication_date="2026-08-23",
            shares_short=6_000_000,
            shares_outstanding=None,
        )
        assert reading.pct_shares_outstanding is None

    def test_publication_lag_is_computed_from_the_two_dates(self) -> None:
        """SPEC §4: bi-monthly settlement with ~8-day publication lag, and the
        panel caption states it."""
        summary = build_positioning([self._reading("2026-08-15", 6_000_000)])
        assert summary.publication_lag_days == 8

    def test_single_reading_reports_insufficient_history(self) -> None:
        summary = build_positioning([self._reading("2026-08-15", 6_000_000)])
        assert summary.change_30d_pp is None
        assert summary.reason_codes["change_30d_pp"] == "insufficient_history"
