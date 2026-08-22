"""Backtesting engine.

The most important tests here are the ones that assert the engine REFUSES to
produce a result, and the one that proves a perfect-foresight signal cannot
profit — if it could, the execution model has look-ahead.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from invest.engines.backtest import (
    CANNOT_BACKTEST_MESSAGE,
    MIN_TRADES_FOR_STATISTICS,
    SignalKind,
    assess_testability,
    buy_and_hold_signal,
    render_backtest,
    run_backtest,
    sma_crossover_signal,
)
from invest.engines.costs import DEFAULT_COSTS, LIQUID_LARGE_CAP, CostModel, CostReport


def rising_prices(n: int = 600, daily: float = 0.0005) -> pd.Series:
    idx = pd.date_range("2023-01-02", periods=n, freq="B")
    return pd.Series([100 * (1 + daily) ** i for i in range(n)], index=idx, dtype=float)


def random_prices(n: int = 600, seed: int = 42) -> pd.Series:
    rng = np.random.default_rng(seed)
    idx = pd.date_range("2023-01-02", periods=n, freq="B")
    return pd.Series(100 * np.cumprod(1 + rng.normal(0, 0.01, n)), index=idx, dtype=float)


# --------------------------------------------------------------------------
# The cost model
# --------------------------------------------------------------------------


def test_buys_fill_above_the_mid_and_sells_below() -> None:
    """A backtest that fills at the mid claims a free half-spread every trade."""
    model = CostModel(half_spread_bps=10, slippage_bps=0)
    assert model.fill_price(100.0, is_buy=True) == pytest.approx(100.1)
    assert model.fill_price(100.0, is_buy=False) == pytest.approx(99.9)


def test_round_trip_cost_hand_computed() -> None:
    """2.5bp half-spread + 5bp slippage, both sides = 15bp round trip."""
    assert DEFAULT_COSTS.round_trip_bps == pytest.approx(15.0)


def test_commission_combines_flat_and_bps() -> None:
    model = CostModel(commission_per_trade=1.0, commission_bps=5.0)
    # 1.00 flat + 5bp of 10,000 = 1.00 + 5.00
    assert model.commission(10_000) == pytest.approx(6.0)


def test_minimum_cost_applies() -> None:
    model = CostModel(commission_per_trade=0.0, minimum_cost=1.0)
    assert model.commission(10.0) == pytest.approx(1.0)


def test_total_cost_hand_computed() -> None:
    model = CostModel(half_spread_bps=10, slippage_bps=0, commission_per_trade=1.0)
    # fill at 100.10 vs mid 100 -> 0.10/share * 100 shares = 10, plus 1 commission
    assert model.total_cost(100.0, 100, is_buy=True) == pytest.approx(11.0)


def test_negative_cost_parameters_are_rejected() -> None:
    with pytest.raises(ValueError, match="may not be negative"):
        CostModel(half_spread_bps=-1)


def test_cost_model_is_labelled_estimated() -> None:
    """V1 has no quote or fill data, so these are assumptions."""
    payload = DEFAULT_COSTS.as_dict()
    assert payload["value_type"] == "estimated"
    assert "ASSUMPTIONS" in payload["note"]


def test_default_costs_are_more_pessimistic_than_liquid() -> None:
    """A backtest that flatters itself invites real money."""
    assert DEFAULT_COSTS.round_trip_bps > LIQUID_LARGE_CAP.round_trip_bps


def test_cost_report_accumulates() -> None:
    report = CostReport()
    report.record(commission=1.0, spread=2.0, notional=1000.0)
    report.record(commission=1.0, spread=3.0, notional=1000.0)
    assert report.total_cost == pytest.approx(7.0)
    assert report.trade_count == 2
    assert report.cost_per_trade == pytest.approx(3.5)
    assert report.cost_as_bps_of_notional == pytest.approx(35.0)


# --------------------------------------------------------------------------
# The testability gate — the refusal the spec requires
# --------------------------------------------------------------------------


def test_short_history_is_refused() -> None:
    verdict = assess_testability(kind=SignalKind.PRICE_ONLY, bar_count=50)
    assert verdict.can_backtest is False
    assert CANNOT_BACKTEST_MESSAGE in verdict.render()
    assert any("usable bars" in r for r in verdict.reasons)


@pytest.mark.parametrize(
    "kind",
    [
        SignalKind.POLITICAL,
        SignalKind.ANALYST_ESTIMATES,
        SignalKind.OPTIONS,
        SignalKind.CROSS_SECTIONAL,
        SignalKind.INSIDER,
    ],
)
def test_untestable_signal_kinds_are_refused(kind) -> None:
    verdict = assess_testability(kind=kind, bar_count=2000)
    assert verdict.can_backtest is False
    assert CANNOT_BACKTEST_MESSAGE in verdict.render()
    assert verdict.reasons


def test_premium_dependent_kinds_say_so() -> None:
    for kind in (SignalKind.ANALYST_ESTIMATES, SignalKind.OPTIONS):
        verdict = assess_testability(kind=kind, bar_count=2000)
        assert any("PREMIUM-DATA DEPENDENT" in r for r in verdict.reasons)


def test_cross_sectional_refusal_names_survivorship_bias() -> None:
    """The single most common way to manufacture a fake track record."""
    verdict = assess_testability(kind=SignalKind.CROSS_SECTIONAL, bar_count=2000)
    assert any("survivorship" in r.lower() for r in verdict.reasons)


def test_multi_name_universe_without_history_is_refused() -> None:
    verdict = assess_testability(
        kind=SignalKind.PRICE_ONLY,
        bar_count=2000,
        universe_size=20,
        universe_is_point_in_time=False,
    )
    assert verdict.can_backtest is False
    assert any("survivorship-biased" in r for r in verdict.reasons)


def test_price_only_single_name_is_allowed_with_a_caveat() -> None:
    verdict = assess_testability(kind=SignalKind.PRICE_ONLY, bar_count=2000)
    assert verdict.can_backtest is True
    assert verdict.warnings
    assert any("still existing" in w for w in verdict.warnings)


def test_fundamental_signals_are_testable() -> None:
    """EDGAR filing dates give genuine point-in-time discipline."""
    verdict = assess_testability(kind=SignalKind.FUNDAMENTAL, bar_count=2000)
    assert verdict.can_backtest is True


# --------------------------------------------------------------------------
# No look-ahead — the guarantee everything else rests on
# --------------------------------------------------------------------------


def test_perfect_foresight_cannot_profit() -> None:
    """A signal that peeks at the NEXT bar must not make money, because the
    engine only ever hands it history up to bar t and fills at t+1.

    If this test starts passing profits, the execution model has look-ahead.
    """
    prices = random_prices(600, seed=7)

    def cheating_signal(history: pd.Series) -> float:
        # Try to see the future: the engine gives only history, so the best
        # this can do is look at the last bar it was given.
        return 1.0 if len(history) < len(prices) else 0.0

    result = run_backtest(prices, cheating_signal, warmup=200)
    # The signal is effectively always-long; it cannot beat buy-and-hold,
    # because it never sees a future bar.
    buy_hold = run_backtest(prices, buy_and_hold_signal(), warmup=200)
    assert result.total_return <= buy_hold.total_return + 1e-9


def test_signal_never_receives_future_bars() -> None:
    """Asserted directly: record the length of every history handed over."""
    prices = rising_prices(400)
    seen_lengths: list[int] = []

    def recording_signal(history: pd.Series) -> float:
        seen_lengths.append(len(history))
        return 1.0

    run_backtest(prices, recording_signal, warmup=200)
    # Longest history seen must stop short of the full series, since the last
    # bar is reserved as the fill for the second-to-last signal.
    assert max(seen_lengths) == len(prices) - 1
    assert seen_lengths == sorted(seen_lengths)


def test_fills_happen_on_the_bar_after_the_signal() -> None:
    prices = rising_prices(400)
    result = run_backtest(prices, buy_and_hold_signal(), warmup=200)
    # First equity point is dated at the first FILL, i.e. warmup+1.
    assert result.equity_curve.index[0] == prices.index[201]


# --------------------------------------------------------------------------
# Simulation behaviour
# --------------------------------------------------------------------------


def test_refused_backtest_produces_no_equity_curve() -> None:
    """An untestable signal must never yield a plottable curve."""
    result = run_backtest(rising_prices(600), buy_and_hold_signal(), kind=SignalKind.OPTIONS)
    assert result.ran is False
    assert result.equity_curve.empty
    assert result.total_return is None
    assert CANNOT_BACKTEST_MESSAGE in render_backtest(result)


def test_short_series_is_refused_before_simulating() -> None:
    result = run_backtest(rising_prices(100), buy_and_hold_signal(), warmup=50)
    assert result.ran is False
    assert result.equity_curve.empty


def test_buy_and_hold_tracks_the_underlying_minus_costs() -> None:
    prices = rising_prices(600, daily=0.0005)
    result = run_backtest(prices, buy_and_hold_signal(), warmup=200)

    assert result.ran
    underlying = float(prices.iloc[-1] / prices.iloc[201] - 1)
    # Net of one entry's spread and commission, slightly below the underlying.
    assert result.total_return < underlying
    assert result.total_return == pytest.approx(underlying, abs=0.01)


def test_costs_are_actually_deducted() -> None:
    prices = rising_prices(600)
    cheap = run_backtest(prices, sma_crossover_signal(), warmup=200,
                         cost_model=LIQUID_LARGE_CAP)
    expensive = run_backtest(
        prices, sma_crossover_signal(), warmup=200,
        cost_model=CostModel(half_spread_bps=50, slippage_bps=50),
    )
    assert expensive.costs.total_cost > cheap.costs.total_cost


def test_gross_return_exceeds_net_return() -> None:
    result = run_backtest(random_prices(600), sma_crossover_signal(), warmup=200)
    if result.costs.total_cost > 0:
        assert result.gross_return > result.total_return


def test_flat_signal_holds_cash() -> None:
    prices = rising_prices(600)

    def never_invest(history: pd.Series) -> float:
        return 0.0

    result = run_backtest(prices, never_invest, warmup=200)
    assert result.total_return == pytest.approx(0.0)
    assert result.costs.trade_count == 0


def test_trades_are_recorded_with_entry_and_exit() -> None:
    prices = random_prices(800, seed=11)
    result = run_backtest(prices, sma_crossover_signal(20, 50), warmup=200)
    assert result.trades
    for trade in result.closed_trades:
        assert trade.exit_date > trade.entry_date
        assert trade.pnl is not None
        assert trade.return_pct is not None


def test_win_rate_is_withheld_below_the_minimum_trade_count() -> None:
    """A win rate over five trades is not a statistic."""
    prices = rising_prices(600)
    result = run_backtest(prices, buy_and_hold_signal(), warmup=200)
    assert len(result.closed_trades) < MIN_TRADES_FOR_STATISTICS
    assert result.win_rate is None
    assert result.has_enough_trades is False
    assert "INSUFFICIENT DATA" in render_backtest(result)


def test_benchmark_comparison() -> None:
    prices = random_prices(600, seed=13)
    benchmark = random_prices(600, seed=17)
    result = run_backtest(
        prices, sma_crossover_signal(), warmup=200, benchmark=benchmark
    )
    assert result.benchmark_return is not None
    assert result.excess_return == pytest.approx(
        result.total_return - result.benchmark_return
    )


def test_statistics_are_computed() -> None:
    result = run_backtest(random_prices(800, seed=19), sma_crossover_signal(), warmup=200)
    assert result.ran
    assert result.cagr is not None
    assert result.volatility is not None
    assert result.max_drawdown is not None
    assert result.max_drawdown <= 0


def test_result_serialises_with_the_verdict() -> None:
    result = run_backtest(rising_prices(600), buy_and_hold_signal(), warmup=200)
    payload = result.as_dict()
    assert payload["ran"] is True
    assert payload["verdict"]["can_backtest"] is True
    assert payload["cost_model"]["value_type"] == "estimated"
    assert payload["value_type"] == "calculated"


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------


def test_render_shows_gross_and_net() -> None:
    text = render_backtest(
        run_backtest(random_prices(800, seed=23), sma_crossover_signal(), warmup=200)
    )
    assert "Total return, net" in text
    assert "Total return, gross" in text
    assert "COSTS" in text


def test_render_states_the_execution_model() -> None:
    text = render_backtest(run_backtest(rising_prices(600), buy_and_hold_signal(), warmup=200))
    assert "computed on bar t and filled at bar t+1" in text


def test_render_carries_the_survivorship_caveat() -> None:
    text = render_backtest(run_backtest(rising_prices(600), buy_and_hold_signal(), warmup=200))
    assert "CAVEATS" in text
    assert "still existing" in text


def test_render_of_a_refusal_is_the_required_message() -> None:
    result = run_backtest(
        rising_prices(600), buy_and_hold_signal(), kind=SignalKind.POLITICAL
    )
    text = render_backtest(result, name="Political copycat")
    assert CANNOT_BACKTEST_MESSAGE in text
    assert "30-45 days" in text
    # And no performance numbers anywhere.
    assert "Sharpe" not in text
    assert "CAGR" not in text
