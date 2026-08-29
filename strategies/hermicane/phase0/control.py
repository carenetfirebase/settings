"""The control rule (§3.3) — the most important deliverable of Phase 0.

HERMICANE v1 only ever observes the events its filter stack approved, and never
records what happened on the ones it rejected. That makes the filter
unfalsifiable: it could be adding edge, removing edge, or merely shrinking the
sample, and the equity curve looks the same in all three cases.

The control fixes that by trading **every** event with no filtering at all:

* enter at T+3 in the direction implied by ``-sign(Δ2Y)`` over T+0→T+3,
* stop at 1.0 ATR, target at 2.0 ATR,
* time exit at 120 minutes.

Its bootstrapped mean-R interval is the bar every filter in §3.4 has to clear.
A filter that does not clear it is deleted, not tuned.

Three modelling choices are made here that the handoff does not specify. Each
is a **structural choice, not a calibrated constant**, and each is reported as
such by `report.py` so that nobody later mistakes one for a measured value:

1. **ATR is the mean true range of the fourteen 15-minute bars ending before
   the release.** The handoff says "1.0 ATR" without fixing either a period or
   a *timeframe*, and the timeframe turns out to matter more than anything
   else in the rule. Averaging more 1-minute bars does not produce a larger
   risk unit — the mean true range of a 1-minute gold bar is a few tens of
   cents no matter how many of them are averaged — so a stop of "1.0 ATR" off
   1-minute data is a stop of well under a dollar placed into a release that
   routinely moves ten. It is hit by noise before the trade has begun.
   `ATR_BASES` and `ablation.atr_basis_sensitivity` exist because this choice
   dominates the control's results and must be made with evidence rather than
   by reading past it.
2. **A bar that touches both stop and target resolves as a stop.** 1-minute
   OHLC cannot say which came first, and the conservative reading is the one
   that does not flatter the strategy.
3. **Costs are deducted round-trip in R at exit.** This is first-order: it
   ignores that worse entry fills also shift where the stop sits. It is stated
   rather than buried, and §4.3's cost curve is run across 20/100/200/400 ticks
   precisely because the level matters more than the model.
"""

from __future__ import annotations

import bisect
import math
from dataclasses import dataclass
from datetime import datetime, timedelta

from .loaders import BarSeries

NAN = float("nan")

#: XAUUSD quotes to the cent on the retail feeds this strategy targets, so one
#: tick is $0.01 and v1's "20 ticks" of slippage was twenty cents on gold —
#: roughly an order of magnitude below a real CPI-minute spread (§4.2 item 10).
TICK_SIZE = 0.01

#: §4.3. Reported as a curve, never as a single number: if the edge dies by 200
#: ticks it is not tradable through a news print, and that is the finding.
COST_LADDER_TICKS = (20, 100, 200, 400)

#: Structural choice 1 above. Not calibrated — swept, and reported separately.
#: The timeframe the risk unit is measured on, and how many of those bars.
STRUCTURAL_ATR_TIMEFRAME_MINUTES = 15
STRUCTURAL_ATR_PERIODS = 14

#: The bases `ablation.atr_basis_sensitivity` compares. Spanning 5-minute to
#: daily is deliberate: if the control's sign changes across this range then
#: nothing else in the report means anything until the basis is settled.
ATR_BASES: tuple[tuple[int, int], ...] = ((5, 14), (15, 14), (60, 14), (240, 14), (1440, 14))

EXIT_STOP = "stop"
EXIT_TARGET = "target"
EXIT_TIME = "time"
EXIT_NO_DATA = "no_data"
EXIT_NO_DIRECTION = "no_direction"


@dataclass(frozen=True)
class ControlSpec:
    """Every parameter of the control rule, in one place.

    Frozen and passed explicitly so a report can never be produced without the
    exact rule that generated it being printable alongside.
    """

    entry_offset_minutes: int = 3
    stop_atr: float = 1.0
    target_atr: float = 2.0
    time_exit_minutes: int = 120
    atr_timeframe_minutes: int = STRUCTURAL_ATR_TIMEFRAME_MINUTES
    atr_periods: int = STRUCTURAL_ATR_PERIODS
    cost_ticks: int = 0
    tick_size: float = TICK_SIZE

    def as_dict(self) -> dict[str, float | int]:
        return {
            "entry_offset_minutes": self.entry_offset_minutes,
            "stop_atr": self.stop_atr,
            "target_atr": self.target_atr,
            "time_exit_minutes": self.time_exit_minutes,
            "atr_timeframe_minutes": self.atr_timeframe_minutes,
            "atr_periods": self.atr_periods,
            "cost_ticks": self.cost_ticks,
            "tick_size": self.tick_size,
        }


@dataclass(frozen=True)
class ControlResult:
    traded: bool
    direction: int
    entry_ts: datetime | None
    entry_price: float
    stop_price: float
    target_price: float
    risk_price: float
    exit_ts: datetime | None
    exit_price: float
    exit_reason: str
    r_multiple: float
    mae_r: float
    mfe_r: float
    minutes_held: int

    def as_dict(self) -> dict[str, object]:
        return {
            "traded": self.traded,
            "direction": self.direction,
            "entry_ts": self.entry_ts.isoformat() if self.entry_ts else None,
            "entry_price": self.entry_price,
            "stop_price": self.stop_price,
            "target_price": self.target_price,
            "risk_price": self.risk_price,
            "exit_ts": self.exit_ts.isoformat() if self.exit_ts else None,
            "exit_price": self.exit_price,
            "exit_reason": self.exit_reason,
            "r_multiple": self.r_multiple,
            "mae_r": self.mae_r,
            "mfe_r": self.mfe_r,
            "minutes_held": self.minutes_held,
        }


def _no_trade(reason: str) -> ControlResult:
    return ControlResult(
        traded=False, direction=0, entry_ts=None, entry_price=NAN, stop_price=NAN,
        target_price=NAN, risk_price=NAN, exit_ts=None, exit_price=NAN,
        exit_reason=reason, r_multiple=NAN, mae_r=NAN, mfe_r=NAN, minutes_held=0,
    )


def average_true_range(bars: BarSeries, end: datetime, periods: int) -> float:
    """Mean true range of the last `periods` bars of `bars` closed before `end`.

    `bars` must already be at the intended timeframe — the caller resamples
    once per panel rather than once per event. A bar counts as closed only if
    its stamp plus one bar length is at or before `end`, so a release at 12:30
    never sees the 12:30 bar it is about to move.

    True range needs the previous close, so one extra bar is taken and used
    only as that predecessor. Returns NaN — never a fallback number — when the
    history is not there, so the event is flagged rather than traded on a
    guessed risk unit.
    """
    if periods < 1:
        return NAN
    cutoff = end - timedelta(seconds=bars.timeframe_seconds)
    hi = bisect.bisect_right(bars._stamps, cutoff)
    window = bars.bars[max(0, hi - periods - 1):hi]
    if len(window) < 2:
        return NAN
    ranges: list[float] = []
    for previous, current in zip(window, window[1:]):
        if any(math.isnan(v) for v in (current.high, current.low, previous.close)):
            continue
        ranges.append(
            max(
                current.high - current.low,
                abs(current.high - previous.close),
                abs(current.low - previous.close),
            )
        )
    if not ranges:
        return NAN
    value = sum(ranges) / len(ranges)
    return value if value > 0 else NAN


def yield_change(yields: BarSeries, event_ts: datetime, minutes: int) -> float:
    """Δ2Y from the release minute to `minutes` after it.

    Measured close-to-close on the 2-year series. The baseline is the bar *at*
    T+0, not the bar before it: the release lands inside the T+0 bar, so using
    T-1 would fold a minute of pre-release drift into the signal.
    """
    base = yields.bar_at_or_after(event_ts, tolerance_minutes=2)
    later = yields.bar_at_or_after(event_ts + timedelta(minutes=minutes), tolerance_minutes=2)
    if base is None or later is None:
        return NAN
    if math.isnan(base.close) or math.isnan(later.close):
        return NAN
    return later.close - base.close


def control_direction(delta_yield: float) -> int:
    """The v2 direction signal before the beta gate: ``-sign(Δ2Y)``.

    An exactly flat 2Y returns 0 and the event is not traded. That is a real
    outcome and is counted in the rejection tally rather than dropped, because
    "the 2Y did not move" is information about the release.
    """
    if math.isnan(delta_yield) or delta_yield == 0.0:
        return 0
    return -1 if delta_yield > 0 else 1


def simulate(
    prices: BarSeries,
    event_ts: datetime,
    direction: int,
    atr: float,
    spec: ControlSpec = ControlSpec(),
) -> ControlResult:
    """Walk the control rule forward bar by bar from T+entry_offset.

    Returns a non-traded result rather than raising on any missing input, so a
    panel build over five years does not abort on one bad session.
    """
    if direction == 0:
        return _no_trade(EXIT_NO_DIRECTION)
    if math.isnan(atr) or atr <= 0:
        return _no_trade(EXIT_NO_DATA)

    entry_bar = prices.bar_at_or_after(
        event_ts + timedelta(minutes=spec.entry_offset_minutes), tolerance_minutes=5
    )
    if entry_bar is None or math.isnan(entry_bar.close):
        return _no_trade(EXIT_NO_DATA)

    entry = entry_bar.close
    risk = spec.stop_atr * atr
    stop = entry - direction * risk
    target = entry + direction * spec.target_atr * risk
    deadline = event_ts + timedelta(
        minutes=spec.entry_offset_minutes + spec.time_exit_minutes
    )
    forward = prices.window(entry_bar.ts + timedelta(minutes=1), deadline + timedelta(minutes=1))
    cost_r = (spec.cost_ticks * spec.tick_size) / risk if risk > 0 else 0.0

    mfe = 0.0
    mae = 0.0
    for bar in forward:
        if math.isnan(bar.high) or math.isnan(bar.low):
            continue
        best = direction * ((bar.high if direction > 0 else bar.low) - entry) / risk
        worst = direction * ((bar.low if direction > 0 else bar.high) - entry) / risk
        mfe = max(mfe, best)
        mae = min(mae, worst)

        hit_stop = bar.low <= stop if direction > 0 else bar.high >= stop
        hit_target = bar.high >= target if direction > 0 else bar.low <= target
        if hit_stop:
            # Structural choice 2: ambiguity inside a bar resolves against us.
            return ControlResult(
                True, direction, entry_bar.ts, entry, stop, target, risk, bar.ts, stop,
                EXIT_STOP, -1.0 - cost_r, mae, mfe,
                int((bar.ts - entry_bar.ts).total_seconds() // 60),
            )
        if hit_target:
            return ControlResult(
                True, direction, entry_bar.ts, entry, stop, target, risk, bar.ts, target,
                EXIT_TARGET, spec.target_atr / spec.stop_atr - cost_r, mae, mfe,
                int((bar.ts - entry_bar.ts).total_seconds() // 60),
            )

    if not forward:
        return _no_trade(EXIT_NO_DATA)
    last = forward[-1]
    gross = direction * (last.close - entry) / risk
    return ControlResult(
        True, direction, entry_bar.ts, entry, stop, target, risk, last.ts, last.close,
        EXIT_TIME, gross - cost_r, mae, mfe,
        int((last.ts - entry_bar.ts).total_seconds() // 60),
    )
