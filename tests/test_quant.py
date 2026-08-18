"""Quant engine tests.

Expected values are hand-computed and the arithmetic is shown in the test, so
a reviewer can check the number without running the code. Where a closed form
exists (a constant-return series, a known-variance series), the test uses it
rather than asserting whatever the implementation happens to produce.
"""

from __future__ import annotations

import math

import numpy as np
import pandas as pd
import pytest

from invest.engines.quant import (
    TRADING_DAYS_PER_YEAR,
    atr,
    beta,
    bollinger_bands,
    cagr,
    cagr_from_series,
    calmar_ratio,
    correlation,
    distance_from_high,
    downside_deviation,
    ema,
    growth_rate,
    growth_series,
    log_returns,
    macd,
    margin,
    max_drawdown,
    max_drawdown_detail,
    position_in_52_week_range,
    relative_strength,
    rsi,
    safe_divide,
    sharpe_ratio,
    simple_returns,
    sma,
    sortino_ratio,
    total_return,
    true_range,
    volatility,
)


def series(values: list[float]) -> pd.Series:
    idx = pd.date_range("2025-01-01", periods=len(values), freq="B")
    return pd.Series(values, index=idx, dtype=float)


# --------------------------------------------------------------------------
# Returns
# --------------------------------------------------------------------------


def test_simple_returns_hand_checked() -> None:
    # 100 -> 110 -> 99: +10%, then -10%
    result = simple_returns(series([100, 110, 99]))
    assert result.tolist() == pytest.approx([0.10, -0.10])


def test_returns_do_not_average_to_zero_when_price_falls() -> None:
    """The classic volatility-drag check: +10% then -10% loses money."""
    assert total_return(series([100, 110, 99])) == pytest.approx(-0.01)


def test_log_returns_hand_checked() -> None:
    result = log_returns(series([100, 110]))
    assert result.iloc[0] == pytest.approx(math.log(1.1))


def test_log_returns_reject_non_positive_prices() -> None:
    with pytest.raises(ValueError, match="positive"):
        log_returns(series([100, 0, 50]))


def test_total_return_hand_checked() -> None:
    # 50 -> 75 is exactly +50%
    assert total_return(series([50, 60, 75])) == pytest.approx(0.50)


def test_single_observation_has_no_return() -> None:
    assert total_return(series([100])) is None
    assert simple_returns(series([100])).empty


# --------------------------------------------------------------------------
# CAGR and growth
# --------------------------------------------------------------------------


def test_cagr_doubling_over_ten_years() -> None:
    # 2^(1/10) - 1 = 0.07177...
    assert cagr(100, 200, 10) == pytest.approx(0.0717734625, rel=1e-9)


def test_cagr_exact_case() -> None:
    # 100 -> 121 over 2 years is exactly 10%/yr, since 1.1^2 = 1.21
    assert cagr(100, 121, 2) == pytest.approx(0.10, rel=1e-12)


def test_cagr_over_one_year_equals_simple_return() -> None:
    assert cagr(100, 115, 1) == pytest.approx(0.15)


def test_cagr_refuses_sign_changes_and_zero_bases() -> None:
    """Growth from a negative base is arithmetically computable and
    financially meaningless.
    """
    assert cagr(-100, 50, 5) is None
    assert cagr(100, -50, 5) is None
    assert cagr(0, 100, 5) is None
    assert cagr(100, 200, 0) is None


def test_cagr_from_series_uses_trading_day_count() -> None:
    # 253 points = 252 trading-day intervals = exactly 1 year
    prices = series([100.0] * 252 + [110.0])
    assert cagr_from_series(prices) == pytest.approx(0.10, rel=1e-9)


def test_growth_rate_hand_checked() -> None:
    assert growth_rate(100, 125) == pytest.approx(0.25)
    assert growth_rate(200, 150) == pytest.approx(-0.25)


def test_growth_rate_from_negative_base_is_none() -> None:
    """A loss shrinking from -100 to -50 is not '-50% growth'."""
    assert growth_rate(-100, -50) is None
    assert growth_rate(0, 100) is None
    assert growth_rate(None, 100) is None


def test_growth_series_hand_checked() -> None:
    assert growth_series([100, 110, 121]) == pytest.approx([0.10, 0.10])


def test_growth_series_propagates_gaps_as_none() -> None:
    result = growth_series([100, None, 121])
    assert result == [None, None]


# --------------------------------------------------------------------------
# Volatility
# --------------------------------------------------------------------------


def test_volatility_of_constant_returns_is_zero() -> None:
    prices = series([100 * (1.01**i) for i in range(60)])
    assert volatility(simple_returns(prices)) == pytest.approx(0.0, abs=1e-12)


def test_volatility_matches_hand_computed_sample_std() -> None:
    """Alternating +10%/-10% returns: sample std of [0.1,-0.1,...] is
    computed here independently with numpy ddof=1.
    """
    rets = pd.Series([0.10, -0.10] * 15)
    expected = float(np.std(rets.to_numpy(), ddof=1)) * math.sqrt(TRADING_DAYS_PER_YEAR)
    assert volatility(rets) == pytest.approx(expected)


def test_volatility_annualization_factor_is_sqrt_252() -> None:
    rets = pd.Series([0.10, -0.10] * 15)
    daily = volatility(rets, annualize=False)
    annual = volatility(rets, annualize=True)
    assert annual / daily == pytest.approx(math.sqrt(252))


def test_volatility_refuses_tiny_samples() -> None:
    """Four observations is not a small-sample estimate, it is noise."""
    assert volatility(pd.Series([0.01, -0.02, 0.03, -0.01])) is None


def test_downside_deviation_divides_by_full_count() -> None:
    """Sortino's original formulation: the denominator is N, not the count of
    losing periods. Here 4 of 40 returns are -10%, the rest +10%.
    """
    rets = pd.Series([-0.10] * 4 + [0.10] * 36)
    # sqrt(4 * 0.01 / 40) = sqrt(0.001)
    expected = math.sqrt(0.001) * math.sqrt(TRADING_DAYS_PER_YEAR)
    assert downside_deviation(rets) == pytest.approx(expected)


def test_downside_deviation_is_zero_when_nothing_falls_below_target() -> None:
    assert downside_deviation(pd.Series([0.01] * 40)) == pytest.approx(0.0)


# --------------------------------------------------------------------------
# Drawdown
# --------------------------------------------------------------------------


def test_max_drawdown_hand_checked() -> None:
    # Peak 120, trough 60 -> 60/120 - 1 = -0.50
    assert max_drawdown(series([100, 120, 90, 60, 80])) == pytest.approx(-0.50)


def test_max_drawdown_of_monotonic_rise_is_zero() -> None:
    assert max_drawdown(series([100, 110, 120, 130])) == pytest.approx(0.0)


def test_drawdown_measures_from_the_running_peak_not_the_start() -> None:
    """Starting at 100, rising to 200, falling to 150 is a 25% drawdown —
    not a 50% gain.
    """
    assert max_drawdown(series([100, 200, 150])) == pytest.approx(-0.25)


def test_drawdown_detail_identifies_dates_and_recovery() -> None:
    prices = series([100, 120, 60, 90, 130])
    detail = max_drawdown_detail(prices)
    assert detail.max_drawdown == pytest.approx(-0.50)
    assert detail.peak_date == prices.index[1]
    assert detail.trough_date == prices.index[2]
    assert detail.recovery_date == prices.index[4]
    assert detail.is_recovered


def test_drawdown_detail_reports_unrecovered() -> None:
    detail = max_drawdown_detail(series([100, 120, 60, 70]))
    assert detail.recovery_date is None
    assert detail.is_recovered is False


# --------------------------------------------------------------------------
# Risk-adjusted ratios
# --------------------------------------------------------------------------


def test_sharpe_of_constant_returns_is_none_not_infinity() -> None:
    """Zero volatility means the ratio is undefined, not infinitely good."""
    assert sharpe_ratio(pd.Series([0.001] * 40)) is None


def test_sharpe_hand_checked_against_closed_form() -> None:
    rets = pd.Series([0.02, -0.01] * 20)
    mean = float(rets.mean())
    std = float(rets.std(ddof=1))
    expected = mean / std * math.sqrt(252)
    assert sharpe_ratio(rets) == pytest.approx(expected)


def test_sharpe_deannualizes_the_risk_free_rate() -> None:
    """A 2.52% annual rate must be subtracted as 0.01%/day, not 2.52%/day."""
    rets = pd.Series([0.02, -0.01] * 20)
    with_rf = sharpe_ratio(rets, risk_free_rate=0.0252)
    without = sharpe_ratio(rets)
    daily_rf = 0.0252 / 252
    expected_shift = daily_rf / float(rets.std(ddof=1)) * math.sqrt(252)
    assert without - with_rf == pytest.approx(expected_shift)


def test_sortino_exceeds_sharpe_when_upside_is_volatile() -> None:
    """Big gains inflate total volatility but not downside deviation."""
    rets = pd.Series([0.20, -0.01] * 20)
    assert sortino_ratio(rets) > sharpe_ratio(rets)


def test_sortino_is_none_when_nothing_ever_falls() -> None:
    assert sortino_ratio(pd.Series([0.01] * 40)) is None


def test_ratios_refuse_short_samples() -> None:
    short = pd.Series([0.01, 0.02, -0.01])
    assert sharpe_ratio(short) is None
    assert sortino_ratio(short) is None


def test_calmar_hand_checked() -> None:
    # 253 points = 1 year; 100 -> 120 with a 100->80 dip = -20% drawdown
    prices = series([100.0] + [80.0] + [100.0] * 250 + [120.0])
    growth = cagr_from_series(prices)
    dd = max_drawdown(prices)
    assert calmar_ratio(prices) == pytest.approx(growth / abs(dd))


# --------------------------------------------------------------------------
# Beta
# --------------------------------------------------------------------------


def test_beta_of_identical_series_is_one() -> None:
    rng = np.random.default_rng(42)
    market = pd.Series(rng.normal(0, 0.01, 200))
    result = beta(market, market)
    assert result.beta == pytest.approx(1.0)
    assert result.r_squared == pytest.approx(1.0)
    assert result.alpha == pytest.approx(0.0, abs=1e-12)


def test_beta_of_doubled_series_is_two() -> None:
    rng = np.random.default_rng(7)
    market = pd.Series(rng.normal(0, 0.01, 200))
    result = beta(market * 2.0, market)
    assert result.beta == pytest.approx(2.0)
    assert result.r_squared == pytest.approx(1.0)


def test_beta_recovers_a_known_alpha() -> None:
    rng = np.random.default_rng(11)
    market = pd.Series(rng.normal(0, 0.01, 300))
    asset = 0.5 * market + 0.0004  # beta 0.5, daily alpha 4bp
    result = beta(asset, market)
    assert result.beta == pytest.approx(0.5)
    assert result.alpha == pytest.approx(0.0004)
    assert result.annualized_alpha == pytest.approx(0.0004 * 252)


def test_beta_aligns_on_overlapping_dates_only() -> None:
    """A holiday one market observes and the other does not must not shift
    every subsequent pair by a day.
    """
    idx_a = pd.date_range("2025-01-01", periods=100, freq="B")
    market = pd.Series(np.random.default_rng(3).normal(0, 0.01, 100), index=idx_a)
    asset = (market * 1.5).drop(market.index[50])  # asset misses one day
    result = beta(asset, market)
    assert result.observations == 99
    assert result.beta == pytest.approx(1.5)


def test_beta_refuses_short_samples() -> None:
    market = pd.Series(np.random.default_rng(1).normal(0, 0.01, 20))
    assert beta(market, market) is None


def test_beta_is_none_when_benchmark_never_moves() -> None:
    flat = pd.Series([0.0] * 100)
    asset = pd.Series(np.random.default_rng(5).normal(0, 0.01, 100))
    assert beta(asset, flat) is None


def test_correlation_of_inverse_series_is_minus_one() -> None:
    rng = np.random.default_rng(9)
    market = pd.Series(rng.normal(0, 0.01, 100))
    assert correlation(-market, market) == pytest.approx(-1.0)


# --------------------------------------------------------------------------
# Relative strength
# --------------------------------------------------------------------------


def test_relative_strength_hand_checked() -> None:
    # Asset +20%, benchmark +5% -> +15pp
    asset = series([100, 120])
    bench = series([100, 105])
    assert relative_strength(asset, bench) == pytest.approx(0.15)


def test_relative_strength_negative_when_lagging() -> None:
    # Asset -10%, benchmark +10% -> -20 percentage points
    assert relative_strength(series([100, 90]), series([100, 110])) == pytest.approx(-0.20)


# --------------------------------------------------------------------------
# Technical indicators
# --------------------------------------------------------------------------


def test_sma_hand_checked() -> None:
    result = sma(series([1, 2, 3, 4, 5]), 3)
    assert math.isnan(result.iloc[1])  # not enough data yet
    assert result.iloc[2] == pytest.approx(2.0)  # (1+2+3)/3
    assert result.iloc[4] == pytest.approx(4.0)  # (3+4+5)/3


def test_sma_needs_a_full_window() -> None:
    """A 200-day SMA computed from 50 days would be a different indicator."""
    assert sma(series([1, 2, 3]), 5).isna().all()


def test_ema_hand_checked() -> None:
    # span=2 -> alpha = 2/(2+1) = 2/3. With adjust=False the recursion is
    # seeded with the first observation (min_periods only masks the output):
    #   y0 = 10                                   (masked, below min_periods)
    #   y1 = 20*(2/3) + 10*(1/3)  = 50/3  = 16.667
    #   y2 = 30*(2/3) + (50/3)*(1/3) = 20 + 50/9 = 25.556
    result = ema(series([10, 20, 30]), 2)
    assert result.iloc[1] == pytest.approx(50 / 3)
    assert result.iloc[2] == pytest.approx(20 + 50 / 9)


def test_rsi_of_uninterrupted_gains_is_100() -> None:
    assert rsi(series([float(i) for i in range(1, 30)]), 14).iloc[-1] == pytest.approx(100.0)


def test_rsi_of_uninterrupted_losses_is_zero() -> None:
    assert rsi(series([float(i) for i in range(30, 1, -1)]), 14).iloc[-1] == pytest.approx(0.0)


def test_rsi_of_symmetric_moves_is_near_fifty() -> None:
    prices = series([100 + (1 if i % 2 else -1) for i in range(60)])
    assert rsi(prices, 14).iloc[-1] == pytest.approx(50.0, abs=5.0)


def test_rsi_stays_in_range() -> None:
    rng = np.random.default_rng(13)
    prices = series(list(100 * np.cumprod(1 + rng.normal(0, 0.02, 200))))
    values = rsi(prices, 14).dropna()
    assert values.min() >= 0.0
    assert values.max() <= 100.0


def test_macd_histogram_is_macd_minus_signal() -> None:
    rng = np.random.default_rng(17)
    prices = series(list(100 * np.cumprod(1 + rng.normal(0, 0.01, 200))))
    result = macd(prices)
    diff = (result.macd - result.signal).dropna()
    assert result.histogram.dropna().tolist() == pytest.approx(diff.tolist())


def test_macd_is_positive_in_an_uptrend() -> None:
    prices = series([100 * (1.01**i) for i in range(120)])
    assert macd(prices).macd.iloc[-1] > 0


def test_true_range_captures_gaps() -> None:
    """A gap down makes |low - prev_close| the widest leg — high-low alone
    would understate the day's real range.
    """
    high = series([100, 90])
    low = series([98, 88])
    close = series([99, 89])
    tr = true_range(high, low, close)
    # |88 - 99| = 11 beats the 2-point intraday range
    assert tr.iloc[1] == pytest.approx(11.0)


def test_atr_of_constant_range_equals_that_range() -> None:
    n = 40
    high = series([102.0] * n)
    low = series([100.0] * n)
    close = series([101.0] * n)
    assert atr(high, low, close, 14).iloc[-1] == pytest.approx(2.0, rel=1e-6)


def test_bollinger_bands_hand_checked() -> None:
    """Constant price -> zero std -> all three bands coincide."""
    prices = series([100.0] * 30)
    bands = bollinger_bands(prices, window=20)
    assert bands.middle.iloc[-1] == pytest.approx(100.0)
    assert bands.upper.iloc[-1] == pytest.approx(100.0)
    assert bands.lower.iloc[-1] == pytest.approx(100.0)


def test_bollinger_width_is_two_std_each_side() -> None:
    rng = np.random.default_rng(23)
    prices = series(list(100 + rng.normal(0, 5, 100)))
    bands = bollinger_bands(prices, window=20, num_std=2.0)
    sigma = prices.rolling(20).std(ddof=0)
    assert (bands.upper - bands.middle).dropna().tolist() == pytest.approx(
        (2 * sigma).dropna().tolist()
    )


def test_percent_b_is_zero_at_lower_band_and_one_at_upper() -> None:
    rng = np.random.default_rng(29)
    prices = series(list(100 + rng.normal(0, 5, 100)))
    bands = bollinger_bands(prices, window=20)
    at_upper = bands.percent_b(bands.upper).dropna()
    at_lower = bands.percent_b(bands.lower).dropna()
    assert at_upper.tolist() == pytest.approx([1.0] * len(at_upper))
    assert at_lower.tolist() == pytest.approx([0.0] * len(at_lower))


def test_52_week_position_hand_checked() -> None:
    # Range 50..150, currently 100 -> exactly halfway
    prices = series([50.0, 150.0, 100.0])
    assert position_in_52_week_range(prices) == pytest.approx(0.5)


def test_52_week_position_at_the_extremes() -> None:
    assert position_in_52_week_range(series([50.0, 150.0])) == pytest.approx(1.0)
    assert position_in_52_week_range(series([150.0, 50.0])) == pytest.approx(0.0)


def test_52_week_position_of_flat_series_is_none() -> None:
    """A degenerate range has no meaningful position within it."""
    assert position_in_52_week_range(series([100.0] * 10)) is None


def test_distance_from_high_hand_checked() -> None:
    # 80 against a high of 100 is -20%
    assert distance_from_high(series([100.0, 80.0])) == pytest.approx(-0.20)
    assert distance_from_high(series([80.0, 100.0])) == pytest.approx(0.0)


# --------------------------------------------------------------------------
# Ratio helpers
# --------------------------------------------------------------------------


def test_safe_divide_hand_checked() -> None:
    assert safe_divide(10, 4) == pytest.approx(2.5)


def test_safe_divide_reports_impossibility_as_none() -> None:
    """A ratio with a missing input is unknown, not zero."""
    assert safe_divide(10, 0) is None
    assert safe_divide(None, 5) is None
    assert safe_divide(10, None) is None


def test_margin_requires_positive_revenue() -> None:
    assert margin(25, 100) == pytest.approx(0.25)
    assert margin(25, 0) is None
    assert margin(25, -100) is None
    assert margin(None, 100) is None


def test_negative_margin_is_allowed() -> None:
    """Loss-making companies are real."""
    assert margin(-25, 100) == pytest.approx(-0.25)


def test_near_zero_volatility_does_not_produce_an_absurd_sharpe() -> None:
    """A perfectly smooth compounding series leaves float noise around 1e-16
    in its returns. Dividing by that yields a Sharpe in the millions, which is
    a degenerate input rather than a spectacular strategy — and reporting it
    would be worse than reporting nothing.
    """
    smooth = series([100 * (1.0008**i) for i in range(400)])
    returns = simple_returns(smooth)

    # The noise is real but negligible — measured at ~5.7e-9 for this series.
    assert 0 < float(returns.std(ddof=1)) < 1e-6

    assert sharpe_ratio(returns) is None
    assert sortino_ratio(returns) is None
    assert volatility(returns) == pytest.approx(0.0)


def test_exactly_constant_prices_also_give_no_ratio() -> None:
    flat = series([100.0] * 400)
    returns = simple_returns(flat)
    assert volatility(returns) == pytest.approx(0.0)
    assert sharpe_ratio(returns) is None


def test_a_real_volatility_series_still_produces_a_ratio() -> None:
    """The guard must not suppress genuine results."""
    rng = np.random.default_rng(31)
    prices = series(list(100 * np.cumprod(1 + rng.normal(0.0005, 0.01, 400))))
    returns = simple_returns(prices)
    assert volatility(returns) > 0.05
    assert sharpe_ratio(returns) is not None
    assert abs(sharpe_ratio(returns)) < 100
