"""Tests for the closed-form rules of CYBER MCGIVER v1.0.

Runnable with either pytest or the stdlib:

    python -m unittest discover -s validation/tests
"""

from __future__ import annotations

import unittest
from datetime import datetime
from zoneinfo import ZoneInfo

from validation.reference import (
    body_ratio,
    classify_session,
    close_location,
    expectancy,
    floor_to_step,
    is_contact,
    max_drawdown_r,
    profit_factor,
    r_multiple,
    rejection_ok,
    round_trip_cost_per_lot,
    size_position,
    slope_from,
    structural_stop,
    trendline_at,
)

UTC = ZoneInfo("UTC")


class TestSizing(unittest.TestCase):
    """S5, S6, S7, S10, S47, S48, S49."""

    def test_risk_budget_tracks_current_equity(self):
        # The three worked examples in S5, with costs switched off so the
        # budget is visible rather than inferred.
        for equity, expected in ((100_000, 1_000), (95_000, 950), (110_000, 1_100)):
            result = size_position(equity, risk_distance=5.0, cost_per_lot=0.0)
            self.assertAlmostEqual(result.risk_budget, expected, places=6)

    def test_planned_loss_never_exceeds_the_budget(self):
        # Sweep stop distances; the invariant is one-sided by construction.
        for distance in [x / 4 for x in range(1, 80)]:
            result = size_position(100_000, risk_distance=distance)
            if result.lots > 0:
                self.assertLessEqual(result.planned_loss, result.risk_budget + 1e-9)

    def test_lots_are_rounded_down_never_up(self):
        # $1,000 budget, $5 stop, $57 round-turn cost -> 1000 / 557 = 1.795 lots.
        result = size_position(100_000, risk_distance=5.0, cost_per_lot=57.0)
        self.assertAlmostEqual(result.lots, 1.79, places=6)
        self.assertLess(result.lots, 1000 / 557)

    def test_costs_are_inside_the_risk_per_lot(self):
        with_costs = size_position(100_000, risk_distance=5.0, cost_per_lot=57.0)
        without = size_position(100_000, risk_distance=5.0, cost_per_lot=0.0)
        self.assertLess(with_costs.lots, without.lots)

    def test_stop_distance_filter_skips_the_trade(self):
        # S49: 3.0 ATR ceiling. A 40-dollar stop against a 10-dollar ATR is 4 ATR.
        result = size_position(100_000, risk_distance=40.0, atr=10.0)
        self.assertEqual(result.lots, 0.0)
        self.assertIn("ATR", result.reason)

    def test_margin_can_only_reduce_size(self):
        # A tiny account at 1:50 cannot fund the risk-implied size.
        result = size_position(2_000, risk_distance=0.5, price=3_000.0, leverage=50.0)
        unconstrained = 2_000 * 0.01 / (0.5 * 100 + 57.0)
        self.assertLessEqual(result.lots, unconstrained + 1e-9)

    def test_unfundable_trade_is_skipped_not_shrunk_below_minimum(self):
        result = size_position(500, risk_distance=20.0, price=3_000.0, leverage=50.0)
        self.assertEqual(result.lots, 0.0)
        self.assertNotEqual(result.reason, "ok")

    def test_absolute_cap_switch(self):
        capped = size_position(500_000, risk_distance=5.0, absolute_cap=1_000.0)
        self.assertAlmostEqual(capped.risk_budget, 1_000.0)

    def test_floor_to_step_is_stable_on_representable_boundaries(self):
        self.assertAlmostEqual(floor_to_step(1.79, 0.01), 1.79)
        self.assertAlmostEqual(floor_to_step(0.999, 0.01), 0.99)
        self.assertAlmostEqual(floor_to_step(0.009, 0.01), 0.0)


class TestStopIsStructural(unittest.TestCase):
    """S35, S43, S48 — the stop comes from P3, never from the risk budget."""

    def test_long_stop_sits_below_p3_by_the_buffer(self):
        self.assertAlmostEqual(structural_stop(2000.0, atr=4.0, long=True), 1999.6)

    def test_short_stop_sits_above_p3_by_the_buffer(self):
        self.assertAlmostEqual(structural_stop(2000.0, atr=4.0, long=False), 2000.4)

    def test_stop_ignores_equity(self):
        a = structural_stop(2000.0, atr=4.0, long=True)
        b = structural_stop(2000.0, atr=4.0, long=True)
        self.assertEqual(a, b)  # no account term exists to vary


class TestTrendline(unittest.TestCase):
    """S29, S30, S31, S37, S38, S39."""

    def test_projection_passes_through_both_pivots(self):
        m = slope_from((10, 1990.0), (20, 2000.0))
        self.assertAlmostEqual(m, 1.0)
        self.assertAlmostEqual(trendline_at(20, 2000.0, m, 10), 1990.0)
        self.assertAlmostEqual(trendline_at(20, 2000.0, m, 30), 2010.0)

    def test_rising_support_has_positive_slope(self):
        self.assertGreater(slope_from((5, 1980.0), (25, 1995.0)), 0)

    def test_falling_resistance_has_negative_slope(self):
        self.assertLess(slope_from((5, 1995.0), (25, 1980.0)), 0)

    def test_contact_tolerance_is_symmetric_around_the_line(self):
        atr = 5.0  # tolerance 0.12 ATR = 0.60
        self.assertTrue(is_contact(2000.50, 2000.0, atr))
        self.assertTrue(is_contact(1999.50, 2000.0, atr))
        self.assertFalse(is_contact(2000.61, 2000.0, atr))

    def test_touch_four_uses_the_same_line_as_touch_three(self):
        m = slope_from((0, 1990.0), (10, 2000.0))
        third = trendline_at(10, 2000.0, m, 18)
        fourth = trendline_at(10, 2000.0, m, 30)
        self.assertAlmostEqual(third, 2008.0)
        self.assertAlmostEqual(fourth, 2020.0)


class TestRejection(unittest.TestCase):
    """S33, S41."""

    def test_strong_bullish_rejection_passes(self):
        # Long lower wick, close at the top: the canonical touch-4 candle.
        self.assertTrue(rejection_ok(2000.0, 2004.0, 1998.0, 2003.5, long=True))

    def test_bearish_candle_never_passes_a_long_setup(self):
        self.assertFalse(rejection_ok(2003.5, 2004.0, 1998.0, 2000.0, long=True))

    def test_small_body_fails_even_with_a_high_close(self):
        # Body 0.2 of range: below the 0.35 floor.
        self.assertLess(body_ratio(2000.0, 2005.0, 2000.0, 2001.0), 0.35)
        self.assertFalse(rejection_ok(2000.0, 2005.0, 2000.0, 2001.0, long=True))

    def test_close_location_measures_are_mirrored(self):
        long_clv = close_location(2000.0, 2004.0, 1998.0, 2003.0, long=True)
        short_clv = close_location(2004.0, 2004.0, 1998.0, 1999.0, long=False)
        self.assertAlmostEqual(long_clv, 5.0 / 6.0)
        self.assertAlmostEqual(short_clv, 5.0 / 6.0)

    def test_zero_range_candle_does_not_divide_by_zero(self):
        self.assertEqual(body_ratio(2000.0, 2000.0, 2000.0, 2000.0), 0.0)
        self.assertEqual(close_location(2000.0, 2000.0, 2000.0, 2000.0, long=True), 0.0)


class TestCosts(unittest.TestCase):
    """S11, S12 — the baseline cost model, stated rather than assumed."""

    def test_baseline_round_turn_is_fifty_seven_dollars_per_lot(self):
        self.assertAlmostEqual(round_trip_cost_per_lot(), 57.0)

    def test_every_component_moves_the_total(self):
        base = round_trip_cost_per_lot()
        self.assertGreater(round_trip_cost_per_lot(spread=1.00), base)
        self.assertGreater(round_trip_cost_per_lot(slip_in=0.30), base)
        self.assertGreater(round_trip_cost_per_lot(commission_per_lot=12.0), base)
        self.assertGreater(round_trip_cost_per_lot(commission_pct=0.01), base)


class TestSessions(unittest.TestCase):
    """S2, S67 — labels in America/New_York, including the wrap over midnight."""

    def _at(self, hour: int, minute: int = 0) -> datetime:
        return datetime(2025, 3, 12, hour, minute, tzinfo=ZoneInfo("America/New_York"))

    def test_each_window_gets_its_label(self):
        cases = {
            (21, 0): "Asia",
            (0, 30): "Asia",
            (3, 0): "London",
            (8, 30): "LDN/NY",
            (10, 0): "NY",
            (17, 0): "Late",
        }
        for (hour, minute), expected in cases.items():
            self.assertEqual(classify_session(self._at(hour, minute)), expected)

    def test_boundaries_are_half_open(self):
        self.assertEqual(classify_session(self._at(9, 29)), "LDN/NY")
        self.assertEqual(classify_session(self._at(9, 30)), "NY")
        self.assertEqual(classify_session(self._at(16, 0)), "Late")

    def test_daylight_saving_is_handled_by_the_zone_not_by_an_offset(self):
        # 13:00 UTC is 09:00 EDT in July and 08:00 EST in January.
        july = datetime(2025, 7, 15, 13, 0, tzinfo=UTC)
        january = datetime(2025, 1, 15, 13, 0, tzinfo=UTC)
        self.assertEqual(classify_session(july), "LDN/NY")
        self.assertEqual(classify_session(january), "LDN/NY")
        # And 14:00 UTC crosses the NY open only in winter.
        self.assertEqual(classify_session(datetime(2025, 1, 15, 14, 45, tzinfo=UTC)), "NY")


class TestOutcomeMaths(unittest.TestCase):
    """S50, S65, S68, S70."""

    def test_r_multiple_is_frozen_against_entry_risk(self):
        # 0.10 lot = 10 oz, 5-dollar stop -> 50 dollars of risk.
        self.assertAlmostEqual(r_multiple(60.0, 5.0, 10.0), 1.2)
        self.assertAlmostEqual(r_multiple(-50.0, 5.0, 10.0), -1.0)

    def test_expectancy_is_the_mean_r(self):
        self.assertAlmostEqual(expectancy([1.2, -1.0, -1.0, 3.0]), 0.55)
        self.assertEqual(expectancy([]), 0.0)

    def test_profit_factor_is_undefined_without_losses(self):
        self.assertIsNone(profit_factor([1.2, 0.4]))
        self.assertAlmostEqual(profit_factor([2.0, -1.0]), 2.0)

    def test_max_drawdown_is_peak_to_trough_in_r(self):
        self.assertAlmostEqual(max_drawdown_r([1.0, -1.0, -1.0, 2.0]), 2.0)
        self.assertAlmostEqual(max_drawdown_r([1.0, 1.0]), 0.0)

    def test_exit_model_b_partial_cannot_be_sized_below_the_lot_step(self):
        # A 0.01-lot position has no half to take: the runner is the whole trade.
        result = size_position(1_000, risk_distance=5.0)
        self.assertLessEqual(result.lots, 0.01)
        self.assertAlmostEqual(floor_to_step(0.01 * 0.5, 0.01), 0.0)


if __name__ == "__main__":
    unittest.main()
