"""Quantitative primitives: returns, growth, volatility, beta, drawdown,
risk-adjusted ratios, and the standard technical indicators.

Every function here is deterministic Python. No LLM touches these numbers.

Conventions, applied consistently so results are comparable across the system:

* **Returns are simple (arithmetic), not log**, unless the name says otherwise.
  Simple returns aggregate correctly across a portfolio; log returns aggregate
  correctly across time. We compound across time explicitly where needed.
* **252 trading days per year** for annualization.
* **Sample standard deviation (ddof=1)**, matching the convention used by
  every published Sharpe ratio you would compare against.
* **Insufficient data returns None, never a number.** A Sharpe ratio computed
  from four observations is not a small-sample estimate, it is noise wearing a
  decimal point. Each function states its minimum.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
import pandas as pd

TRADING_DAYS_PER_YEAR = 252

#: Below this many observations, dispersion statistics are not reported.
MIN_OBS_FOR_VOLATILITY = 20
MIN_OBS_FOR_BETA = 60
MIN_OBS_FOR_RATIO = 30


def _clean(series: pd.Series) -> pd.Series:
    """Drop NaNs and sort by index. Never fills gaps — an interpolated price
    is a fabricated observation.
    """
    return series.dropna().sort_index()


# --------------------------------------------------------------------------
# Returns
# --------------------------------------------------------------------------


def simple_returns(prices: pd.Series) -> pd.Series:
    """Period-over-period simple returns: p_t / p_{t-1} - 1."""
    prices = _clean(prices)
    if len(prices) < 2:
        return pd.Series(dtype=float)
    return prices.pct_change().dropna()


def log_returns(prices: pd.Series) -> pd.Series:
    prices = _clean(prices)
    if len(prices) < 2:
        return pd.Series(dtype=float)
    if (prices <= 0).any():
        raise ValueError("log returns require strictly positive prices")
    return np.log(prices / prices.shift(1)).dropna()


def total_return(prices: pd.Series) -> float | None:
    """Cumulative return over the whole series."""
    prices = _clean(prices)
    if len(prices) < 2 or prices.iloc[0] == 0:
        return None
    return float(prices.iloc[-1] / prices.iloc[0] - 1.0)


def cagr(begin_value: float, end_value: float, years: float) -> float | None:
    """Compound annual growth rate.

    Returns None when it would be meaningless: a non-positive starting value,
    a non-positive period, or a sign change (you cannot express growth from
    -100 to +50 as an annual rate).
    """
    if years <= 0 or begin_value <= 0 or end_value <= 0:
        return None
    return float((end_value / begin_value) ** (1.0 / years) - 1.0)


def cagr_from_series(prices: pd.Series, *, periods_per_year: int = TRADING_DAYS_PER_YEAR
                     ) -> float | None:
    prices = _clean(prices)
    if len(prices) < 2:
        return None
    years = (len(prices) - 1) / periods_per_year
    return cagr(float(prices.iloc[0]), float(prices.iloc[-1]), years)


def growth_rate(previous: float | None, current: float | None) -> float | None:
    """Period-over-period growth.

    None when the base is missing, zero, or negative — growth from a negative
    base is arithmetically computable and financially meaningless (a loss
    shrinking from -100 to -50 is not "-50% growth").
    """
    if previous is None or current is None or previous <= 0:
        return None
    return float(current / previous - 1.0)


def growth_series(values: list[float | None]) -> list[float | None]:
    """Year-over-year growth for a metric history, oldest first."""
    return [growth_rate(values[i - 1], values[i]) for i in range(1, len(values))]


# --------------------------------------------------------------------------
# Dispersion and risk
# --------------------------------------------------------------------------


def volatility(
    returns: pd.Series, *, annualize: bool = True, min_obs: int = MIN_OBS_FOR_VOLATILITY
) -> float | None:
    """Sample standard deviation of returns, annualized by sqrt(252)."""
    returns = _clean(returns)
    if len(returns) < min_obs:
        return None
    sigma = float(returns.std(ddof=1))
    if math.isnan(sigma):
        return None
    return sigma * math.sqrt(TRADING_DAYS_PER_YEAR) if annualize else sigma


def downside_deviation(
    returns: pd.Series, *, target: float = 0.0, annualize: bool = True,
    min_obs: int = MIN_OBS_FOR_RATIO,
) -> float | None:
    """Root-mean-square of shortfalls below `target`.

    Note the denominator: the FULL observation count, not just the count of
    losing periods. This is Sortino's original formulation — dividing by the
    number of downside periods instead would flatter a strategy that rarely
    loses but loses badly.
    """
    returns = _clean(returns)
    if len(returns) < min_obs:
        return None
    shortfall = np.minimum(returns.to_numpy(dtype=float) - target, 0.0)
    dd = float(np.sqrt(np.sum(shortfall**2) / len(shortfall)))
    return dd * math.sqrt(TRADING_DAYS_PER_YEAR) if annualize else dd


def max_drawdown(prices: pd.Series) -> float | None:
    """Largest peak-to-trough decline, as a negative fraction.

    Returns e.g. -0.35 for a 35% drawdown. None if the series is too short.
    """
    prices = _clean(prices)
    if len(prices) < 2:
        return None
    running_peak = prices.cummax()
    drawdowns = prices / running_peak - 1.0
    return float(drawdowns.min())


@dataclass(frozen=True)
class DrawdownDetail:
    max_drawdown: float
    peak_date: object
    trough_date: object
    recovery_date: object | None  # None when still under water

    @property
    def is_recovered(self) -> bool:
        return self.recovery_date is not None


def max_drawdown_detail(prices: pd.Series) -> DrawdownDetail | None:
    """Drawdown with its dates — how deep, when, and whether it recovered."""
    prices = _clean(prices)
    if len(prices) < 2:
        return None
    running_peak = prices.cummax()
    drawdowns = prices / running_peak - 1.0
    trough_date = drawdowns.idxmin()
    trough_value = float(drawdowns.min())

    peak_slice = prices.loc[:trough_date]
    peak_date = peak_slice.idxmax()
    peak_value = float(peak_slice.max())

    after = prices.loc[trough_date:]
    recovered = after[after >= peak_value]
    recovery_date = recovered.index[0] if len(recovered) else None

    return DrawdownDetail(trough_value, peak_date, trough_date, recovery_date)


# --------------------------------------------------------------------------
# Risk-adjusted performance
# --------------------------------------------------------------------------


def sharpe_ratio(
    returns: pd.Series, *, risk_free_rate: float = 0.0, min_obs: int = MIN_OBS_FOR_RATIO
) -> float | None:
    """(annualized excess return) / (annualized volatility).

    `risk_free_rate` is an ANNUAL rate; it is de-annualized before subtraction
    so the excess is computed per period rather than subtracting a yearly rate
    from a daily return.
    """
    returns = _clean(returns)
    if len(returns) < min_obs:
        return None
    per_period_rf = risk_free_rate / TRADING_DAYS_PER_YEAR
    excess = returns - per_period_rf
    sigma = float(excess.std(ddof=1))
    if sigma == 0 or math.isnan(sigma):
        return None
    return float(excess.mean() / sigma * math.sqrt(TRADING_DAYS_PER_YEAR))


def sortino_ratio(
    returns: pd.Series, *, risk_free_rate: float = 0.0, min_obs: int = MIN_OBS_FOR_RATIO
) -> float | None:
    """Like Sharpe but penalising only downside deviation."""
    returns = _clean(returns)
    if len(returns) < min_obs:
        return None
    per_period_rf = risk_free_rate / TRADING_DAYS_PER_YEAR
    excess = returns - per_period_rf
    dd = downside_deviation(excess, target=0.0, annualize=False, min_obs=min_obs)
    if dd is None or dd == 0:
        return None
    return float(excess.mean() / dd * math.sqrt(TRADING_DAYS_PER_YEAR))


def calmar_ratio(prices: pd.Series) -> float | None:
    """Annualized return divided by the absolute max drawdown."""
    growth = cagr_from_series(prices)
    dd = max_drawdown(prices)
    if growth is None or dd is None or dd == 0:
        return None
    return float(growth / abs(dd))


# --------------------------------------------------------------------------
# Market relationship
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class BetaResult:
    beta: float
    alpha: float  # per-period intercept
    r_squared: float
    observations: int

    @property
    def annualized_alpha(self) -> float:
        return self.alpha * TRADING_DAYS_PER_YEAR


def beta(
    asset_returns: pd.Series,
    benchmark_returns: pd.Series,
    *,
    min_obs: int = MIN_OBS_FOR_BETA,
) -> BetaResult | None:
    """OLS beta of asset on benchmark, over their overlapping dates.

    Aligning on the intersection matters: a holiday one market observes and the
    other does not would otherwise shift every subsequent pair by one day and
    quietly destroy the estimate.
    """
    asset = _clean(asset_returns)
    bench = _clean(benchmark_returns)
    joined = pd.concat([asset, bench], axis=1, join="inner").dropna()
    if len(joined) < min_obs:
        return None

    y = joined.iloc[:, 0].to_numpy(dtype=float)
    x = joined.iloc[:, 1].to_numpy(dtype=float)

    var_x = float(np.var(x, ddof=1))
    if var_x == 0:
        return None

    cov = float(np.cov(y, x, ddof=1)[0, 1])
    b = cov / var_x
    a = float(np.mean(y) - b * np.mean(x))

    var_y = float(np.var(y, ddof=1))
    r2 = (cov**2) / (var_x * var_y) if var_y > 0 else 0.0

    return BetaResult(beta=float(b), alpha=a, r_squared=float(r2), observations=len(joined))


def correlation(a: pd.Series, b: pd.Series, *, min_obs: int = MIN_OBS_FOR_BETA) -> float | None:
    joined = pd.concat([_clean(a), _clean(b)], axis=1, join="inner").dropna()
    if len(joined) < min_obs:
        return None
    value = float(joined.iloc[:, 0].corr(joined.iloc[:, 1]))
    return None if math.isnan(value) else value


def relative_strength(
    prices: pd.Series, benchmark_prices: pd.Series, *, lookback: int = TRADING_DAYS_PER_YEAR
) -> float | None:
    """Asset return minus benchmark return over the lookback window.

    Positive means outperformance. Both legs are measured over the same
    overlapping dates so the comparison is like-for-like.
    """
    joined = pd.concat([_clean(prices), _clean(benchmark_prices)], axis=1, join="inner").dropna()
    if len(joined) < 2:
        return None
    window = joined.iloc[-(lookback + 1):] if lookback else joined
    if len(window) < 2:
        return None
    asset_ret = total_return(window.iloc[:, 0])
    bench_ret = total_return(window.iloc[:, 1])
    if asset_ret is None or bench_ret is None:
        return None
    return float(asset_ret - bench_ret)


# --------------------------------------------------------------------------
# Technical indicators
# --------------------------------------------------------------------------


def sma(prices: pd.Series, window: int) -> pd.Series:
    return _clean(prices).rolling(window=window, min_periods=window).mean()


def ema(prices: pd.Series, span: int) -> pd.Series:
    return _clean(prices).ewm(span=span, adjust=False, min_periods=span).mean()


def rsi(prices: pd.Series, period: int = 14) -> pd.Series:
    """Wilder's RSI.

    Uses Wilder's smoothing (an EMA with alpha = 1/period), not a simple moving
    average of gains and losses — the two give visibly different numbers, and
    Wilder's is what every charting package shows.
    """
    prices = _clean(prices)
    if len(prices) < period + 1:
        return pd.Series(dtype=float, index=prices.index)

    delta = prices.diff()
    gain = delta.clip(lower=0.0)
    loss = -delta.clip(upper=0.0)

    avg_gain = gain.ewm(alpha=1 / period, adjust=False, min_periods=period).mean()
    avg_loss = loss.ewm(alpha=1 / period, adjust=False, min_periods=period).mean()

    rs = avg_gain / avg_loss
    result = 100.0 - (100.0 / (1.0 + rs))
    # All-gain windows give avg_loss == 0 -> rs == inf; RSI is 100 there.
    result[avg_loss == 0] = 100.0
    result[(avg_gain == 0) & (avg_loss > 0)] = 0.0
    return result


@dataclass(frozen=True)
class MacdResult:
    macd: pd.Series
    signal: pd.Series
    histogram: pd.Series


def macd(prices: pd.Series, *, fast: int = 12, slow: int = 26, signal: int = 9) -> MacdResult:
    prices = _clean(prices)
    fast_ema = prices.ewm(span=fast, adjust=False, min_periods=fast).mean()
    slow_ema = prices.ewm(span=slow, adjust=False, min_periods=slow).mean()
    macd_line = fast_ema - slow_ema
    signal_line = macd_line.ewm(span=signal, adjust=False, min_periods=signal).mean()
    return MacdResult(macd_line, signal_line, macd_line - signal_line)


def true_range(high: pd.Series, low: pd.Series, close: pd.Series) -> pd.Series:
    """max(H-L, |H-C_prev|, |L-C_prev|) — captures gaps, which H-L alone misses."""
    prev_close = close.shift(1)
    ranges = pd.concat(
        [high - low, (high - prev_close).abs(), (low - prev_close).abs()], axis=1
    )
    return ranges.max(axis=1)


def atr(high: pd.Series, low: pd.Series, close: pd.Series, period: int = 14) -> pd.Series:
    """Average True Range, Wilder-smoothed."""
    tr = true_range(high, low, close)
    return tr.ewm(alpha=1 / period, adjust=False, min_periods=period).mean()


@dataclass(frozen=True)
class BollingerBands:
    middle: pd.Series
    upper: pd.Series
    lower: pd.Series

    def percent_b(self, prices: pd.Series) -> pd.Series:
        """Where price sits in the band: 0 at the lower, 1 at the upper."""
        width = self.upper - self.lower
        return (prices - self.lower) / width.replace(0, np.nan)


def bollinger_bands(prices: pd.Series, *, window: int = 20, num_std: float = 2.0
                    ) -> BollingerBands:
    prices = _clean(prices)
    middle = prices.rolling(window=window, min_periods=window).mean()
    # ddof=0: the band is a descriptive statistic of exactly these N points,
    # not an estimate of a wider population.
    sigma = prices.rolling(window=window, min_periods=window).std(ddof=0)
    return BollingerBands(middle, middle + num_std * sigma, middle - num_std * sigma)


def position_in_52_week_range(prices: pd.Series, *, window: int = TRADING_DAYS_PER_YEAR
                              ) -> float | None:
    """0.0 at the 52-week low, 1.0 at the high. None if the range is degenerate."""
    prices = _clean(prices)
    if len(prices) < 2:
        return None
    window_prices = prices.iloc[-window:]
    low = float(window_prices.min())
    high = float(window_prices.max())
    if high == low:
        return None
    return float((float(window_prices.iloc[-1]) - low) / (high - low))


def distance_from_high(prices: pd.Series, *, window: int = TRADING_DAYS_PER_YEAR
                       ) -> float | None:
    """Negative fraction below the window high; 0.0 when at the high."""
    prices = _clean(prices)
    if prices.empty:
        return None
    window_prices = prices.iloc[-window:]
    high = float(window_prices.max())
    if high == 0:
        return None
    return float(float(window_prices.iloc[-1]) / high - 1.0)


# --------------------------------------------------------------------------
# Ratios
# --------------------------------------------------------------------------


def safe_divide(numerator: float | None, denominator: float | None) -> float | None:
    """Division that reports impossibility as None rather than inf or a crash.

    Used everywhere a ratio is built from data that may be missing. A ratio
    with a missing input is not zero — it is unknown.
    """
    if numerator is None or denominator is None or denominator == 0:
        return None
    result = numerator / denominator
    if math.isnan(result) or math.isinf(result):
        return None
    return float(result)


def margin(numerator: float | None, revenue: float | None) -> float | None:
    """A margin needs positive revenue to mean anything."""
    if revenue is None or revenue <= 0:
        return None
    return safe_divide(numerator, revenue)
