"""The V1 signal engine: pullbacks in uptrends, from 10/10 inputs only.

Every input here is on the list in docs/ENGINE_INPUTS.md, and each is used
only in the role its evidence supports:

=====================  ======================================================
Input                  Role here
=====================  ======================================================
3  Trend               Market gate (S&P 500 vs its 10-month average) and a
                       per-stock filter (12-month return > 0, above 200-day)
4  Relative strength   Ranker: 12-month return skipping the latest month,
                       for the stock and for its sector fund
5  Short-term pullback Entry timing: a 1-week decline of 0.5-4 ATR
6  Volatility          ATR sets stop distance and size; market volatility
                       scales risk down when it runs hot
7  Earnings dates      Veto: no entry with earnings inside the holding window
8  Fundamental quality Veto: low F-score or a Beneish manipulation flag
9  Insider purchases   Tilt: a small bonus for opportunistic open-market buys
=====================  ======================================================

Nothing else can reach a score. Not RSI, not MACD, not breadth, not the macro
regime. Those may be displayed elsewhere as context.

## Evidence versus design choices

The *direction* of every rule comes from published evidence (cited on each
constant). The *exact thresholds* (0.5 ATR, 3 ATR, a 2R target, 15 days) are
design choices, stated once here as named constants. They are exactly what the
signal ledger and the Lab exist to test, and they will be changed only on
out-of-sample evidence, with MODEL_VERSION bumped when they do.

## Long only

V1 trades pullbacks in uptrends and nothing else. There are no short signals.

This module is pure: no database, no network, no clock. The same inputs always
produce the same signal, which is what lets a backfill be point-in-time.
"""

from __future__ import annotations

import math
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import date, timedelta
from enum import StrEnum

import pandas as pd

from invest.engines import quant
from invest.engines.fundamentals import BeneishResult, PiotroskiResult
from invest.engines.scoring import Score, SubScore
from invest.providers.base import InsiderTransactionRecord
from invest.providers.form4 import is_discretionary

#: Bump on any change to a rule, threshold or weight. Ledger rows record it, so
#: outcomes are always attributable to the rules that produced them.
MODEL_VERSION = "SIG-v1.0"

# ---------------------------------------------------------------- trend (3)
#: Faber (2007): hold when the month-end close is above its 10-month average.
TREND_GATE_MONTHS = 10
#: Moskowitz, Ooi & Pedersen (2012): the sign of the 12-month return.
TWELVE_MONTHS = 252
LONG_AVERAGE_DAYS = 200
MID_AVERAGE_DAYS = 50

# ------------------------------------------------------ relative strength (4)
#: Jegadeesh & Titman (1993): 12-month return, skipping the latest month,
#: because the latest month tends to reverse (Jegadeesh 1990).
MOMENTUM_SKIP_DAYS = 21

# --------------------------------------------------------------- pullback (5)
#: Short-term reversal (Jegadeesh 1990; Lehmann 1990): recent losers bounce.
PULLBACK_RETURN_DAYS = 5
PULLBACK_HIGH_WINDOW = 20
#: Shallower than this is noise, not a pullback.
PULLBACK_MIN_ATR = 0.5
#: Depth at which the pullback component reaches full marks.
PULLBACK_FULL_ATR = 3.0
#: Deeper than this is treated as a breakdown, not a pullback.
PULLBACK_MAX_ATR = 4.0

# ------------------------------------------------------------- volatility (6)
ATR_DAYS = 14
#: Market volatility scaling (Moreira & Muir 2017; Barroso & Santa-Clara 2015):
#: risk is cut when 1-month volatility runs above its 1-year median. Never
#: raised above 1, so the engine never levers up.
VOL_SHORT_DAYS = 21
VOL_LONG_DAYS = 252
VOL_SCALE_FLOOR = 0.5

# ---------------------------------------------------------------- the card
#: Buy-stop just above the signal day's high: enter only if price turns up.
ENTRY_BUFFER_ATR = 0.05
STOP_SWING_DAYS = 10
STOP_BUFFER_ATR = 0.25
MIN_STOP_ATR = 1.0
MAX_STOP_ATR = 4.0
TARGET_R = 2.0
#: Trading days a position is held before a time exit.
TIME_STOP_DAYS = 15
#: Trading days the buy-stop stays live before the signal expires.
TRIGGER_WINDOW_DAYS = 5
#: Risk per trade as a fraction of equity, before volatility scaling. Within
#: the 0.5-1% an unproven system should use.
BASE_RISK_FRACTION = 0.0075

# ---------------------------------------------------------------- vetoes (7, 8)
#: Piotroski's weak group is 0-1; 2 adds a margin for one missing signal.
QUALITY_VETO_MAX_FSCORE = 2
#: Quarterly cadence used to project the next earnings date.
EARNINGS_CADENCE_DAYS = 91
#: How far a projected date may miss either way.
EARNINGS_UNCERTAINTY_DAYS = 10
#: Calendar days spanned by TIME_STOP_DAYS trading days, plus the trigger window.
HOLD_WINDOW_CALENDAR_DAYS = 28

# ---------------------------------------------------------------- insiders (9)
#: Cohen, Malloy & Pomorski (2012): an insider who traded in the same calendar
#: month in each of the prior three years is "routine"; one who traded in each
#: of those years but not in a fixed month is "opportunistic".
ROUTINE_YEARS = 3
INSIDER_LOOKBACK_DAYS = 90
INSIDER_BONUS = 5.0

#: Bars needed before any signal is attempted.
MIN_BARS = TWELVE_MONTHS + 1

#: Equal weights until the Lab shows others hold up out of sample
#: (DeMiguel, Garlappi & Uppal 2009).
COMPONENT_WEIGHT = 25.0


class SignalStatus(StrEnum):
    """Why a symbol did or did not produce a trade card, in precedence order."""

    INSUFFICIENT_DATA = "insufficient_data"
    NOT_IN_UPTREND = "not_in_uptrend"
    NO_PULLBACK = "no_pullback"
    INVALID_LEVELS = "invalid_levels"
    GATE_CLOSED = "gate_closed"
    VETOED = "vetoed"
    CARD = "card"


@dataclass(frozen=True)
class Check:
    """A gate or veto. `passed` is None when it could not be evaluated."""

    name: str
    passed: bool | None
    detail: str

    def as_dict(self) -> dict:
        return {"name": self.name, "passed": self.passed, "detail": self.detail}


# --------------------------------------------------------------------------
# Small numeric helpers
# --------------------------------------------------------------------------


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _round_up_cent(value: float) -> float:
    return math.ceil(round(value * 100, 6)) / 100


def _round_down_cent(value: float) -> float:
    return math.floor(round(value * 100, 6)) / 100


def _last(series: pd.Series) -> float | None:
    cleaned = series.dropna()
    return float(cleaned.iloc[-1]) if len(cleaned) else None


def _pct(value: float) -> str:
    """Signed percentage. Moves too small for one decimal get two, so a tiny
    decline never prints as "-0.0%".
    """
    pct = value * 100
    return f"{pct:+.2f}%" if 0 < abs(pct) < 0.05 else f"{pct:+.1f}%"


# --------------------------------------------------------------------------
# Trend (input 3)
# --------------------------------------------------------------------------


def completed_month_end_closes(closes: pd.Series, as_of: date) -> pd.Series:
    """The last close of each calendar month that ended before `as_of`'s month.

    The current month is excluded because it is not over. On the last trading
    day of a month this lags by one month; that is the price of never using a
    month-end close before the month has ended.
    """
    clean = closes.dropna()
    clean = clean[[d <= as_of for d in clean.index]]
    if clean.empty:
        return clean
    index = pd.to_datetime(pd.Index(clean.index))
    frame = pd.Series(clean.to_numpy(), index=index)
    month_ends = frame.groupby(index.to_period("M")).last()
    current = pd.Period(as_of, freq="M")
    month_ends = month_ends[month_ends.index < current]
    month_ends.index = [p.end_time.date() for p in month_ends.index]
    return month_ends


def trend_gate(benchmark_closes: pd.Series, as_of: date) -> Check:
    """Open when the benchmark's last month-end close is above its 10-month
    average (Faber 2007). New longs are allowed only while it is open.
    """
    month_ends = completed_month_end_closes(benchmark_closes, as_of)
    if len(month_ends) < TREND_GATE_MONTHS:
        return Check(
            "trend_gate",
            None,
            f"Needs {TREND_GATE_MONTHS} completed month-end closes of the benchmark; "
            f"{len(month_ends)} available.",
        )
    window = month_ends.iloc[-TREND_GATE_MONTHS:]
    average = float(window.mean())
    last = float(window.iloc[-1])
    month = window.index[-1].strftime("%b %Y")
    gap = last / average - 1
    passed = last > average
    return Check(
        "trend_gate",
        passed,
        f"S&P 500 proxy closed {month} at {last:.2f}, {_pct(gap)} vs its "
        f"{TREND_GATE_MONTHS}-month average of {average:.2f}: "
        f"{'longs allowed' if passed else 'no new longs'}.",
    )


@dataclass(frozen=True)
class StockTrend:
    filter: Check
    score: SubScore
    twelve_month_return: float | None


def stock_trend(closes: pd.Series) -> StockTrend:
    """Per-stock trend: the filter requires a positive 12-month return and a
    close above the 200-day average; strength adds the 50-over-200 alignment.
    """
    clean = closes.dropna()
    if len(clean) < MIN_BARS:
        reason = f"needs {MIN_BARS} daily closes; {len(clean)} available"
        return StockTrend(
            Check("stock_trend", None, reason),
            SubScore("trend", None, COMPONENT_WEIGHT, "", unavailable_reason=reason),
            None,
        )

    close = float(clean.iloc[-1])
    ret_12m = close / float(clean.iloc[-1 - TWELVE_MONTHS]) - 1
    sma_long = float(clean.iloc[-LONG_AVERAGE_DAYS:].mean())
    sma_mid = float(clean.iloc[-MID_AVERAGE_DAYS:].mean())

    positive_year = ret_12m > 0
    above_long = close > sma_long
    aligned = sma_mid > sma_long
    passed = positive_year and above_long

    parts = [
        f"12-month return {_pct(ret_12m)}",
        f"{'above' if above_long else 'below'} the 200-day average",
        f"50-day {'above' if aligned else 'below'} 200-day",
    ]
    value = 100.0 * sum((positive_year, above_long, aligned)) / 3
    return StockTrend(
        Check("stock_trend", passed, "; ".join(parts).capitalize() + "."),
        SubScore("trend", value, COMPONENT_WEIGHT, "; ".join(parts)),
        ret_12m,
    )


# --------------------------------------------------------------------------
# Relative strength (input 4)
# --------------------------------------------------------------------------


def momentum_12_1(closes: pd.Series) -> float | None:
    """Return from 12 months ago to 1 month ago. None without enough history."""
    clean = closes.dropna()
    if len(clean) < MIN_BARS:
        return None
    start = float(clean.iloc[-1 - TWELVE_MONTHS])
    end = float(clean.iloc[-1 - MOMENTUM_SKIP_DAYS])
    if start <= 0:
        return None
    return end / start - 1


def percentile_ranks(values: dict[str, float | None]) -> dict[str, float | None]:
    """Each value's rank among the others, 0 (weakest) to 100 (strongest).

    Ties share their average rank. Fewer than two usable values cannot be
    ranked, and a missing value is never ranked as if it were the weakest.
    """
    usable = {k: v for k, v in values.items() if v is not None and math.isfinite(v)}
    out: dict[str, float | None] = {k: None for k in values}
    if len(usable) < 2:
        return out
    ranks = pd.Series(usable).rank(method="average")
    n = len(usable)
    for key, rank in ranks.items():
        out[str(key)] = float((rank - 1) / (n - 1) * 100)
    return out


def relative_strength_score(
    stock_percentile: float | None,
    sector_percentile: float | None,
    *,
    sector_fund: str | None,
) -> SubScore:
    """Average of the stock's and its sector's momentum percentiles."""
    parts: list[float] = []
    details: list[str] = []
    if stock_percentile is not None:
        parts.append(stock_percentile)
        details.append(f"stock momentum at the {stock_percentile:.0f}th percentile of the universe")
    if sector_percentile is not None:
        parts.append(sector_percentile)
        details.append(
            f"sector ({sector_fund}) at the {sector_percentile:.0f}th percentile of sectors"
        )
    if not parts:
        return SubScore(
            "relative_strength",
            None,
            COMPONENT_WEIGHT,
            "",
            unavailable_reason="no 12-1 month momentum for the stock or its sector",
        )
    return SubScore(
        "relative_strength", sum(parts) / len(parts), COMPONENT_WEIGHT, "; ".join(details)
    )


# --------------------------------------------------------------------------
# Pullback (input 5) and volatility (input 6)
# --------------------------------------------------------------------------


def average_true_range(frame: pd.DataFrame) -> float | None:
    if len(frame) < ATR_DAYS + 1:
        return None
    return _last(quant.atr(frame["high"], frame["low"], frame["close"], period=ATR_DAYS))


@dataclass(frozen=True)
class Pullback:
    present: bool | None
    depth_atr: float | None
    five_day_return: float | None
    score: SubScore


def pullback(frame: pd.DataFrame) -> Pullback:
    """A 1-week decline whose depth below the 20-day high is 0.5-4 ATR."""
    atr_value = average_true_range(frame)
    if atr_value is None or atr_value <= 0 or len(frame) < PULLBACK_HIGH_WINDOW + 1:
        reason = "not enough bars for ATR and the 20-day high"
        return Pullback(None, None, None, SubScore("pullback", None, COMPONENT_WEIGHT, "", reason))

    close = float(frame["close"].iloc[-1])
    recent_high = float(frame["high"].iloc[-PULLBACK_HIGH_WINDOW:].max())
    depth = (recent_high - close) / atr_value
    ret_5d = close / float(frame["close"].iloc[-1 - PULLBACK_RETURN_DAYS]) - 1

    present = ret_5d < 0 and PULLBACK_MIN_ATR <= depth <= PULLBACK_MAX_ATR
    detail = f"{_pct(ret_5d)} over 5 days, {depth:.1f} ATR below the 20-day high"
    if not present:
        if ret_5d >= 0:
            detail += " (not declining)"
        elif depth < PULLBACK_MIN_ATR:
            detail += f" (shallower than {PULLBACK_MIN_ATR} ATR)"
        else:
            detail += f" (deeper than {PULLBACK_MAX_ATR} ATR: a breakdown, not a pullback)"
        return Pullback(False, depth, ret_5d, SubScore("pullback", 0.0, COMPONENT_WEIGHT, detail))

    value = 100 * _clamp(
        (depth - PULLBACK_MIN_ATR) / (PULLBACK_FULL_ATR - PULLBACK_MIN_ATR), 0.0, 1.0
    )
    return Pullback(True, depth, ret_5d, SubScore("pullback", value, COMPONENT_WEIGHT, detail))


@dataclass(frozen=True)
class VolatilityScale:
    multiplier: float
    detail: str
    short_vol: float | None = None
    long_vol: float | None = None


def volatility_scale(benchmark_closes: pd.Series) -> VolatilityScale:
    """Cut risk when the market's 1-month volatility runs above its 1-year
    median. Never above 1. Unknown volatility sizes at the floor: when the
    engine cannot see the risk, it assumes the worst.
    """
    returns = quant.simple_returns(benchmark_closes.dropna())
    if len(returns) < VOL_LONG_DAYS:
        return VolatilityScale(
            VOL_SCALE_FLOOR,
            f"Market volatility unknown ({len(returns)} of {VOL_LONG_DAYS} daily returns): "
            f"risk sized at the {VOL_SCALE_FLOOR:.0%} floor.",
        )
    rolling = returns.rolling(VOL_SHORT_DAYS).std() * math.sqrt(quant.TRADING_DAYS_PER_YEAR)
    short = float(rolling.iloc[-1])
    long = float(rolling.iloc[-VOL_LONG_DAYS:].median())
    if short <= 0 or not math.isfinite(short):
        return VolatilityScale(VOL_SCALE_FLOOR, "Market volatility unreadable: risk at the floor.")
    multiplier = _clamp(long / short, VOL_SCALE_FLOOR, 1.0)
    return VolatilityScale(
        multiplier,
        f"Market 1-month volatility {short:.0%} vs 1-year median {long:.0%}: "
        f"risk at {multiplier:.0%} of base.",
        short,
        long,
    )


# --------------------------------------------------------------------------
# The trade card
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Levels:
    entry: float
    stop: float
    target: float
    atr: float

    @property
    def risk_per_share(self) -> float:
        return round(self.entry - self.stop, 4)

    def as_dict(self) -> dict:
        return {
            "entry": self.entry,
            "stop": self.stop,
            "target": self.target,
            "atr": self.atr,
            "risk_per_share": self.risk_per_share,
            "target_r": TARGET_R,
            "time_stop_days": TIME_STOP_DAYS,
            "trigger_window_days": TRIGGER_WINDOW_DAYS,
        }


def trade_levels(frame: pd.DataFrame) -> Levels | Check:
    """Buy-stop above the signal day's high; stop under the 10-day swing low
    (at least 1 ATR, at most 4 ATR away); target at 2R.
    """
    atr_value = average_true_range(frame)
    if atr_value is None or atr_value <= 0:
        return Check("levels", None, "ATR unavailable")
    high = float(frame["high"].iloc[-1])
    entry = _round_up_cent(high + ENTRY_BUFFER_ATR * atr_value)
    swing_low = float(frame["low"].iloc[-STOP_SWING_DAYS:].min())
    stop = min(swing_low - STOP_BUFFER_ATR * atr_value, entry - MIN_STOP_ATR * atr_value)
    stop = _round_down_cent(stop)
    distance = entry - stop
    if stop <= 0 or distance > MAX_STOP_ATR * atr_value:
        return Check(
            "levels",
            False,
            f"Stop would sit {distance / atr_value:.1f} ATR below entry (max {MAX_STOP_ATR}).",
        )
    target = round(entry + TARGET_R * distance, 2)
    return Levels(entry=entry, stop=stop, target=target, atr=round(atr_value, 4))


@dataclass(frozen=True)
class Sizing:
    risk_fraction: float
    shares: int | None
    risk_dollars: float | None
    detail: str

    def as_dict(self) -> dict:
        return {
            "risk_fraction": self.risk_fraction,
            "shares": self.shares,
            "risk_dollars": self.risk_dollars,
            "detail": self.detail,
        }


def size_position(levels: Levels, *, equity: float | None, vol_multiplier: float) -> Sizing:
    """Shares that lose `risk_fraction` of equity if the stop is hit."""
    fraction = BASE_RISK_FRACTION * vol_multiplier
    if equity is None or equity <= 0:
        return Sizing(
            fraction,
            None,
            None,
            f"Risk {fraction:.2%} of equity. Set ACCOUNT_EQUITY to size in shares "
            f"(V1.2 reads it from the broker).",
        )
    risk_dollars = equity * fraction
    shares = int(risk_dollars // levels.risk_per_share) if levels.risk_per_share > 0 else 0
    return Sizing(
        fraction,
        shares,
        round(shares * levels.risk_per_share, 2),
        f"{shares} shares risk ${shares * levels.risk_per_share:,.0f} ({fraction:.2%} of equity).",
    )


# --------------------------------------------------------------------------
# Vetoes (inputs 7 and 8)
# --------------------------------------------------------------------------


def quality_veto(piotroski: PiotroskiResult | None, beneish: BeneishResult | None) -> Check:
    """Fail on a reliable F-score of 2 or less, or a Beneish manipulation flag.

    Unknown quality is not treated as bad quality: the check reports `None`
    and the card says so, rather than inventing a verdict.
    """
    reasons: list[str] = []
    known = False
    failed = False
    if piotroski is not None and piotroski.is_reliable and piotroski.available_count:
        known = True
        f_score = piotroski.score
        reasons.append(f"F-score {f_score}/{piotroski.max_possible}")
        if f_score <= QUALITY_VETO_MAX_FSCORE:
            failed = True
    if beneish is not None and beneish.flags_manipulation is not None:
        known = True
        reasons.append(f"Beneish M {beneish.score:.2f} ({beneish.interpretation})")
        if beneish.flags_manipulation:
            failed = True
    if not known:
        return Check("quality_veto", None, "Quality unknown: no reliable F-score or M-score.")
    return Check("quality_veto", not failed, "; ".join(reasons) + ".")


def projected_earnings_date(announcement_dates: Iterable[date], as_of: date) -> date | None:
    """Next expected earnings date from past 8-K Item 2.02 filing dates.

    Rolls the last known date forward by quarters until it is no longer in
    the past (allowing for the uncertainty window), so a missed filing does
    not leave the projection stuck behind `as_of`.
    """
    past = sorted(d for d in announcement_dates if d <= as_of)
    if not past:
        return None
    projected = past[-1] + timedelta(days=EARNINGS_CADENCE_DAYS)
    while projected < as_of - timedelta(days=EARNINGS_UNCERTAINTY_DAYS):
        projected += timedelta(days=EARNINGS_CADENCE_DAYS)
    return projected


def earnings_veto(announcement_dates: Iterable[date], as_of: date) -> Check:
    """Fail when projected earnings (± the uncertainty window) fall inside the
    holding window. Earnings are a scheduled binary event (Savor & Wilson 2016).
    """
    projected = projected_earnings_date(announcement_dates, as_of)
    if projected is None:
        return Check("earnings_veto", None, "Earnings date unknown: no 8-K Item 2.02 history.")
    window_start = projected - timedelta(days=EARNINGS_UNCERTAINTY_DAYS)
    window_end = projected + timedelta(days=EARNINGS_UNCERTAINTY_DAYS)
    hold_end = as_of + timedelta(days=HOLD_WINDOW_CALENDAR_DAYS)
    overlaps = window_start <= hold_end and window_end >= as_of
    when = projected.strftime("%b %d")
    if overlaps:
        return Check(
            "earnings_veto",
            False,
            f"Earnings expected around {when} (±{EARNINGS_UNCERTAINTY_DAYS} days), "
            f"inside the holding window.",
        )
    return Check("earnings_veto", True, f"Next earnings expected around {when}, outside the hold.")


# --------------------------------------------------------------------------
# Insider tilt (input 9)
# --------------------------------------------------------------------------


def _insider_key(record: InsiderTransactionRecord) -> str:
    return record.insider_cik or record.insider_name.strip().upper()


def classify_insider(trade_dates: Iterable[date], as_of: date) -> str:
    """'routine', 'opportunistic' or 'unclassified' (Cohen, Malloy & Pomorski).

    Uses the three calendar years before `as_of`'s year. Routine: traded in
    the same calendar month in each of them. Opportunistic: traded in each of
    them, but never in one fixed month. Otherwise there is not enough history
    to say.
    """
    years = range(as_of.year - ROUTINE_YEARS, as_of.year)
    months: dict[int, set[int]] = {y: set() for y in years}
    for d in trade_dates:
        if d.year in months:
            months[d.year].add(d.month)
    if any(not m for m in months.values()):
        return "unclassified"
    shared = set.intersection(*months.values())
    return "routine" if shared else "opportunistic"


@dataclass(frozen=True)
class InsiderTilt:
    bonus: float
    detail: str
    opportunistic_buys: int
    other_buys: int


def insider_tilt(records: list[InsiderTransactionRecord], as_of: date) -> InsiderTilt:
    """A bonus when an opportunistic insider bought in the open market in the
    last 90 days. Absence, sales, grants and routine buys add nothing.
    """
    discretionary = [
        r for r in records if is_discretionary(r.transaction_code) and r.filed_date <= as_of
    ]
    history: dict[str, list[date]] = {}
    for record in discretionary:
        history.setdefault(_insider_key(record), []).append(record.transaction_date)

    since = as_of - timedelta(days=INSIDER_LOOKBACK_DAYS)
    recent_buys = [
        r
        for r in discretionary
        if r.acquired_disposed == "A" and r.transaction_code == "P" and r.filed_date >= since
    ]
    opportunistic = [
        r
        for r in recent_buys
        if classify_insider(history[_insider_key(r)], as_of) == "opportunistic"
    ]
    other = len(recent_buys) - len(opportunistic)

    if not records:
        return InsiderTilt(0.0, "No Form 4 data: neutral.", 0, 0)
    if opportunistic:
        names = sorted({r.insider_name for r in opportunistic})
        return InsiderTilt(
            INSIDER_BONUS,
            f"Opportunistic open-market buying by {', '.join(names)} in the last "
            f"{INSIDER_LOOKBACK_DAYS} days: +{INSIDER_BONUS:.0f}.",
            len(opportunistic),
            other,
        )
    if other:
        return InsiderTilt(
            0.0,
            f"{other} open-market buy(s), but by routine or unclassifiable insiders: neutral.",
            0,
            other,
        )
    return InsiderTilt(0.0, "No opportunistic insider buying: neutral.", 0, 0)


# --------------------------------------------------------------------------
# One symbol, end to end
# --------------------------------------------------------------------------


@dataclass
class MarketContext:
    as_of: date
    gate: Check
    volatility: VolatilityScale
    equity: float | None = None


@dataclass
class SymbolInputs:
    ticker: str
    frame: pd.DataFrame
    sector: str | None = None
    sector_fund: str | None = None
    stock_momentum_percentile: float | None = None
    sector_momentum_percentile: float | None = None
    piotroski: PiotroskiResult | None = None
    beneish: BeneishResult | None = None
    earnings_dates: list[date] = field(default_factory=list)
    insider_records: list[InsiderTransactionRecord] = field(default_factory=list)


@dataclass
class SymbolSignal:
    ticker: str
    as_of: date
    status: SignalStatus
    reasons: list[str]
    checks: list[Check]
    score: Score
    insider: InsiderTilt | None
    levels: Levels | None
    sizing: Sizing | None
    close: float | None
    momentum_12_1: float | None
    model_version: str = MODEL_VERSION

    @property
    def base_score(self) -> float | None:
        return self.score.value

    @property
    def final_score(self) -> float | None:
        if self.score.value is None:
            return None
        bonus = self.insider.bonus if self.insider else 0.0
        return min(100.0, self.score.value + bonus)

    @property
    def is_candidate(self) -> bool:
        """A setup exists: uptrend, pullback, valid levels. Recorded in the
        ledger whether or not it fired, so the Lab can test the gates too.
        """
        return self.levels is not None and self.status in (
            SignalStatus.GATE_CLOSED,
            SignalStatus.VETOED,
            SignalStatus.CARD,
        )

    @property
    def fired(self) -> bool:
        return self.status == SignalStatus.CARD

    def as_dict(self) -> dict:
        return {
            "ticker": self.ticker,
            "as_of": self.as_of.isoformat(),
            "status": self.status.value,
            "fired": self.fired,
            "is_candidate": self.is_candidate,
            "reasons": self.reasons,
            "checks": [c.as_dict() for c in self.checks],
            "score": self.score.as_dict(),
            "base_score": self.base_score,
            "insider_bonus": self.insider.bonus if self.insider else 0.0,
            "insider_detail": self.insider.detail if self.insider else None,
            "final_score": self.final_score,
            "levels": self.levels.as_dict() if self.levels else None,
            "sizing": self.sizing.as_dict() if self.sizing else None,
            "close": self.close,
            "momentum_12_1": self.momentum_12_1,
            "model_version": self.model_version,
        }


def _ecosystem_placeholder() -> SubScore:
    return SubScore(
        "ecosystem_lead_lag",
        None,
        COMPONENT_WEIGHT,
        "",
        unavailable_reason="V2: the customer-supplier graph is not built yet",
    )


def evaluate_symbol(inputs: SymbolInputs, market: MarketContext) -> SymbolSignal:
    """Run every rule for one stock and say exactly why it did or did not fire."""
    frame = inputs.frame.dropna(subset=["high", "low", "close"])
    closes = frame["close"] if not frame.empty else pd.Series(dtype=float)
    close = float(closes.iloc[-1]) if len(closes) else None

    trend = stock_trend(closes)
    setup = (
        pullback(frame)
        if not frame.empty
        else Pullback(None, None, None, SubScore("pullback", None, COMPONENT_WEIGHT, "", "no bars"))
    )
    rs = relative_strength_score(
        inputs.stock_momentum_percentile,
        inputs.sector_momentum_percentile,
        sector_fund=inputs.sector_fund,
    )
    score = Score("signal", components=[trend.score, rs, setup.score, _ecosystem_placeholder()])
    checks: list[Check] = [market.gate, trend.filter]
    reasons: list[str] = []
    levels: Levels | None = None
    sizing: Sizing | None = None
    tilt: InsiderTilt | None = None

    def result(status: SignalStatus) -> SymbolSignal:
        return SymbolSignal(
            ticker=inputs.ticker,
            as_of=market.as_of,
            status=status,
            reasons=reasons,
            checks=checks,
            score=score,
            insider=tilt,
            levels=levels,
            sizing=sizing,
            close=close,
            momentum_12_1=momentum_12_1(closes),
        )

    if len(frame) < MIN_BARS or trend.filter.passed is None:
        reasons.append(f"Needs {MIN_BARS} daily bars; {len(frame)} stored.")
        return result(SignalStatus.INSUFFICIENT_DATA)
    if not trend.filter.passed:
        reasons.append(f"Not in an uptrend: {trend.filter.detail}")
        return result(SignalStatus.NOT_IN_UPTREND)
    if not setup.present:
        reasons.append(f"No pullback: {setup.score.detail or setup.score.unavailable_reason}.")
        return result(SignalStatus.NO_PULLBACK)

    built = trade_levels(frame)
    if isinstance(built, Check):
        checks.append(built)
        reasons.append(f"Levels invalid: {built.detail}")
        return result(SignalStatus.INVALID_LEVELS)
    levels = built
    sizing = size_position(
        levels, equity=market.equity, vol_multiplier=market.volatility.multiplier
    )
    tilt = insider_tilt(inputs.insider_records, market.as_of)

    quality = quality_veto(inputs.piotroski, inputs.beneish)
    earnings = earnings_veto(inputs.earnings_dates, market.as_of)
    checks.extend([quality, earnings])

    for check in (quality, earnings):
        if check.passed is None:
            reasons.append(f"Unverified: {check.detail}")

    if market.gate.passed is not True:
        reasons.insert(0, f"Trend gate closed: {market.gate.detail}")
        return result(SignalStatus.GATE_CLOSED)
    failed = [c for c in (quality, earnings) if c.passed is False]
    if failed:
        for c in failed:
            reasons.insert(0, f"Vetoed: {c.detail}")
        return result(SignalStatus.VETOED)
    return result(SignalStatus.CARD)
