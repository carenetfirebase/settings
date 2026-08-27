"""Opening-range-breakout model for the 08:30 New York session.

## Why this exists

A Pine Script strategy is only observable through TradingView's UI. This module
re-implements the same rule set as plain, deterministic Python so the rules can
be executed against bars we construct on purpose — including the awkward ones
(a gap through the range, a missing bar, a day where the break never confirms).
That is the only way to answer "does this do what I think it does" without
paper-trading it for a month.

## The rule set

1. The opening range (OR) is every bar timestamped in ``[or_start, or_end)``
   New York time. On 1-minute bars that is 08:30..08:34 inclusive — five bars.
2. From ``or_end`` until ``entry_end`` the model looks for a confirmed
   penetration:

   * an **interaction** bar reaches an OR boundary and stays inside the
     tolerance zone around it, then
   * a **later** bar (at most ``max_bars_since_touch`` bars afterwards) closes
     beyond that boundary by ``break_buf_atr`` ATR, in the same direction, with
     enough body and a close near the right extreme of its range.

   A bar can never confirm itself: interactions are recorded only after the
   bar's confirmation check has run. That ordering is the whole point of the
   rule, so it is asserted in the tests.
3. The stop sits ``stop_buf_atr`` ATR beyond the interaction bar's wick, floored
   at ``min_stop_atr`` ATR so a one-minute doji cannot manufacture a
   near-zero-risk position.
4. The target is exactly ``rr`` times the risk distance.
5. If no confirmation appears, a forced entry fires so the day still trades —
   at the first bar timestamped at or after ``forced_from``, and again as a
   safety net on the first bar after the entry window closes if that bar never
   arrived. Its stop is structural: the opposite side of the opening range.
6. One entry per New York day, and any open position is closed at
   ``flat_time``.

## Execution model

Signals are evaluated on the close of a completed bar and filled at that close
(TradingView's ``process_orders_on_close = true``). Protective orders go live
on the *following* bar — never the signal bar. When a single bar contains both
the stop and the target, the stop is taken: intrabar sequence is unknowable
from OHLC, so the model resolves the ambiguity against itself. A bar that gaps
straight through a level fills at the open, not at the level.

## What a run does and does not prove

It proves the rules behave as written on the bars supplied. It says nothing
about profitability, and results from synthetic bars are not a track record.
"""

from __future__ import annotations

import math
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from datetime import date, datetime, time
from enum import IntEnum, StrEnum

#: Sessions are specified in New York wall-clock time, like the Pine original.
NY_TZ = "America/New_York"


class Direction(IntEnum):
    LONG = 1
    SHORT = -1


class EntryReason(StrEnum):
    CONFIRMED = "confirmed"
    FORCED = "forced"


class ExitReason(StrEnum):
    STOP = "stop"
    TARGET = "target"
    FLAT = "flat"
    OPEN = "open"


class NoTradeReason(StrEnum):
    NO_OPENING_RANGE = "no_opening_range"
    NO_ENTRY_WINDOW_BARS = "no_entry_window_bars"
    ATR_NOT_READY = "atr_not_ready"
    FORCED_ENTRY_DISABLED = "forced_entry_disabled"


@dataclass(frozen=True, slots=True)
class Bar:
    """One completed OHLC bar, timestamped at its *open* in New York time.

    Naive timestamps are read as New York wall clock, which is what the session
    windows are written in.
    """

    ts: datetime
    open: float
    high: float
    low: float
    close: float

    def __post_init__(self) -> None:
        if self.high < self.low:
            raise ValueError(f"bar {self.ts}: high {self.high} below low {self.low}")
        if not (self.low <= self.open <= self.high):
            raise ValueError(f"bar {self.ts}: open {self.open} outside [{self.low}, {self.high}]")
        if not (self.low <= self.close <= self.high):
            raise ValueError(f"bar {self.ts}: close {self.close} outside [{self.low}, {self.high}]")

    @property
    def ny_time(self) -> time:
        return self.ts.time()

    @property
    def ny_date(self) -> date:
        return self.ts.date()

    @property
    def range(self) -> float:
        return self.high - self.low


@dataclass(frozen=True, slots=True)
class OrbConfig:
    """Every knob the Pine original exposes, plus the ones 1-minute bars need.

    The defaults describe the *intended* strategy: decisions taken on 1-minute
    bars, one trade per day, 2R target.
    """

    # --- sessions (New York wall clock) ---
    or_start: time = time(8, 30)
    or_end: time = time(8, 35)
    entry_end: time = time(9, 0)
    #: First bar eligible for the forced entry. On 1-minute bars 08:59 leaves
    #: the full window available to a real confirmation; the Pine original used
    #: 08:55, which on 1-minute bars throws away the last four minutes.
    forced_from: time = time(8, 59)
    flat_time: time = time(16, 55)

    # --- confirmation ---
    atr_len: int = 14
    touch_tol_atr: float = 0.05
    break_buf_atr: float = 0.02
    body_min: float = 0.35
    clv_min: float = 0.65
    #: How many bars after an interaction a confirmation still counts. 1 is the
    #: Pine original's strict "the very next bar". On 1-minute bars a two- or
    #: three-bar allowance matches how price actually probes a level.
    max_bars_since_touch: int = 1

    # --- risk ---
    rr: float = 2.0
    stop_buf_atr: float = 0.05
    #: Floor on the stop distance. Without it a 1-minute inside bar produces a
    #: risk distance near zero, and position size explodes.
    min_stop_atr: float = 0.50
    risk_pct: float = 0.50
    #: Cap on position notional as a multiple of equity. A risk-based size says
    #: nothing about whether the account could carry the position; on a tight
    #: 1-minute stop it happily asks for eight figures of gold.
    max_notional_mult: float = 5.0
    qty_step: float = 0.01
    min_qty: float = 0.01
    point_value: float = 1.0

    # --- behaviour ---
    force_daily_entry: bool = True
    initial_equity: float = 100_000.0

    def __post_init__(self) -> None:
        if not self.or_start < self.or_end <= self.entry_end:
            raise ValueError("require or_start < or_end <= entry_end")
        if not self.or_end <= self.forced_from < self.entry_end:
            raise ValueError("forced_from must sit inside [or_end, entry_end)")
        if self.rr <= 0:
            raise ValueError("rr must be positive")
        if self.atr_len < 2:
            raise ValueError("atr_len must be at least 2")
        if self.max_bars_since_touch < 1:
            raise ValueError("max_bars_since_touch must be at least 1")


@dataclass(slots=True)
class Trade:
    day: date
    direction: Direction
    reason: EntryReason
    entry_time: datetime
    entry_price: float
    stop: float
    target: float
    risk: float
    qty: float
    exit_time: datetime | None = None
    exit_price: float | None = None
    exit_reason: ExitReason = ExitReason.OPEN
    r_multiple: float | None = None
    pnl: float | None = None

    @property
    def is_open(self) -> bool:
        return self.exit_reason is ExitReason.OPEN


@dataclass(slots=True)
class DaySummary:
    """One New York day, whether or not it produced a trade."""

    day: date
    or_high: float | None = None
    or_low: float | None = None
    or_bars: int = 0
    entry_window_bars: int = 0
    interactions: int = 0
    trade: Trade | None = None
    no_trade_reason: NoTradeReason | None = None

    @property
    def traded(self) -> bool:
        return self.trade is not None


@dataclass(slots=True)
class SimulationResult:
    days: list[DaySummary] = field(default_factory=list)
    trades: list[Trade] = field(default_factory=list)
    equity: float = 0.0
    bar_seconds: int | None = None

    @property
    def days_with_opening_range(self) -> list[DaySummary]:
        return [d for d in self.days if d.or_bars > 0]

    @property
    def untraded_days(self) -> list[DaySummary]:
        return [d for d in self.days_with_opening_range if not d.traded]

    def counts_by_reason(self) -> dict[EntryReason, int]:
        out = {reason: 0 for reason in EntryReason}
        for trade in self.trades:
            out[trade.reason] += 1
        return out

    def counts_by_exit(self) -> dict[ExitReason, int]:
        out = {reason: 0 for reason in ExitReason}
        for trade in self.trades:
            out[trade.exit_reason] += 1
        return out

    def total_r(self) -> float:
        return sum(t.r_multiple for t in self.trades if t.r_multiple is not None)


def true_range(bar: Bar, prev_close: float | None) -> float:
    if prev_close is None:
        return bar.range
    return max(bar.range, abs(bar.high - prev_close), abs(bar.low - prev_close))


class WilderAtr:
    """``ta.atr`` as Pine computes it: an RMA of true range, seeded with an SMA.

    Returns ``None`` until ``length`` true ranges exist, because a partially
    warmed average is not an ATR and the model must not trade off one.
    """

    def __init__(self, length: int) -> None:
        self._length = length
        self._seed: list[float] = []
        self._value: float | None = None
        self._prev_close: float | None = None

    @property
    def value(self) -> float | None:
        return self._value

    def update(self, bar: Bar) -> float | None:
        tr = true_range(bar, self._prev_close)
        self._prev_close = bar.close
        if self._value is None:
            self._seed.append(tr)
            if len(self._seed) == self._length:
                self._value = sum(self._seed) / self._length
        else:
            self._value = (self._value * (self._length - 1) + tr) / self._length
        return self._value


def _floor_step(x: float, step: float) -> float:
    if step <= 0:
        return x
    # Guard the classic float-floor bite: 0.28/0.01 is 27.999999999999996.
    return math.floor(round(x / step, 9)) * step


def _modal_bar_seconds(bars: Sequence[Bar]) -> int | None:
    gaps: dict[int, int] = {}
    for prev, cur in zip(bars, bars[1:], strict=False):
        delta = int((cur.ts - prev.ts).total_seconds())
        if 0 < delta <= 3600:
            gaps[delta] = gaps.get(delta, 0) + 1
    if not gaps:
        return None
    return max(gaps.items(), key=lambda kv: (kv[1], -kv[0]))[0]


@dataclass(slots=True)
class _DayState:
    """Everything reset at the start of a New York day."""

    summary: DaySummary
    or_high: float | None = None
    or_low: float | None = None
    or_done: bool = False
    traded: bool = False
    window_closed: bool = False
    post_high: float | None = None
    post_low: float | None = None
    long_touch_bar: int | None = None
    long_touch_low: float | None = None
    short_touch_bar: int | None = None
    short_touch_high: float | None = None

    @property
    def or_mid(self) -> float | None:
        if self.or_high is None or self.or_low is None:
            return None
        return (self.or_high + self.or_low) / 2.0


class OrbStrategy:
    """Bar-by-bar simulator. Feed it bars in ascending time order."""

    def __init__(self, config: OrbConfig | None = None) -> None:
        self.config = config or OrbConfig()
        self._atr = WilderAtr(self.config.atr_len)
        self._result = SimulationResult(equity=self.config.initial_equity)
        self._day: _DayState | None = None
        self._open_trade: Trade | None = None
        self._bar_no = -1

    # -- public ----------------------------------------------------------

    def run(self, bars: Iterable[Bar]) -> SimulationResult:
        ordered = list(bars)
        for prev, cur in zip(ordered, ordered[1:], strict=False):
            if cur.ts <= prev.ts:
                raise ValueError(f"bars must ascend in time: {prev.ts} then {cur.ts}")
        self._result.bar_seconds = _modal_bar_seconds(ordered)
        for bar in ordered:
            self._on_bar(bar)
        return self._result

    # -- per bar ---------------------------------------------------------

    def _on_bar(self, bar: Bar) -> None:
        self._bar_no += 1
        cfg = self.config
        atr = self._atr.update(bar)

        if self._day is None or bar.ny_date != self._day.summary.day:
            self._start_day(bar.ny_date)
        day = self._day
        assert day is not None

        # 1. Protective orders from earlier bars resolve before anything else:
        #    a position opened yesterday cannot be ignored while today's range
        #    builds.
        if self._open_trade is not None:
            self._resolve_open_trade(bar)

        # 2. Opening range.
        if cfg.or_start <= bar.ny_time < cfg.or_end:
            day.or_high = bar.high if day.or_high is None else max(day.or_high, bar.high)
            day.or_low = bar.low if day.or_low is None else min(day.or_low, bar.low)
            day.summary.or_bars += 1
            day.summary.or_high = day.or_high
            day.summary.or_low = day.or_low
            return

        in_window = cfg.or_end <= bar.ny_time < cfg.entry_end
        past_window = bar.ny_time >= cfg.entry_end

        if in_window and day.or_high is not None and day.or_low is not None:
            day.or_done = True
            day.summary.entry_window_bars += 1
            day.post_high = bar.high if day.post_high is None else max(day.post_high, bar.high)
            day.post_low = bar.low if day.post_low is None else min(day.post_low, bar.low)

        # 3. Entry decisions, only while flat and untraded today.
        if day.or_done and not day.traded and self._open_trade is None:
            if in_window:
                self._try_entry(bar, atr, forced_eligible=bar.ny_time >= cfg.forced_from)
            elif past_window and not day.window_closed:
                # Safety net: the forced-entry bar itself can be missing from
                # the feed. The first bar after the window still trades the day.
                self._try_entry(bar, atr, forced_eligible=True)

        if past_window and not day.window_closed:
            day.window_closed = True
            self._record_no_trade(day, atr)

        # 4. End-of-day flat.
        if self._open_trade is not None and bar.ny_time >= cfg.flat_time:
            self._close_trade(self._open_trade, bar.ts, bar.close, ExitReason.FLAT)

        # 5. Interactions are recorded last, so the bar that touches a boundary
        #    can only ever confirm a *later* bar. Never itself.
        if in_window and day.or_done and not day.traded and atr is not None:
            self._record_interaction(bar, atr, day)

    # -- day boundaries --------------------------------------------------

    def _start_day(self, day: date) -> None:
        summary = DaySummary(day=day)
        self._result.days.append(summary)
        self._day = _DayState(summary=summary)

    def _record_no_trade(self, day: _DayState, atr: float | None) -> None:
        if day.traded:
            return
        if day.summary.or_bars == 0:
            day.summary.no_trade_reason = NoTradeReason.NO_OPENING_RANGE
        elif day.summary.entry_window_bars == 0:
            day.summary.no_trade_reason = NoTradeReason.NO_ENTRY_WINDOW_BARS
        elif atr is None:
            day.summary.no_trade_reason = NoTradeReason.ATR_NOT_READY
        elif not self.config.force_daily_entry:
            day.summary.no_trade_reason = NoTradeReason.FORCED_ENTRY_DISABLED

    # -- signals ---------------------------------------------------------

    def _record_interaction(self, bar: Bar, atr: float, day: _DayState) -> None:
        cfg = self.config
        assert day.or_high is not None and day.or_low is not None
        tol = cfg.touch_tol_atr * atr
        if bar.high >= day.or_high and bar.low <= day.or_high + tol:
            day.long_touch_bar = self._bar_no
            day.long_touch_low = bar.low
            day.summary.interactions += 1
        if bar.low <= day.or_low and bar.high >= day.or_low - tol:
            day.short_touch_bar = self._bar_no
            day.short_touch_high = bar.high
            day.summary.interactions += 1

    def _confirmed_direction(self, bar: Bar, atr: float, day: _DayState) -> Direction | None:
        cfg = self.config
        assert day.or_high is not None and day.or_low is not None
        rng = max(bar.range, 1e-12)
        body = abs(bar.close - bar.open) / rng
        clv_long = (bar.close - bar.low) / rng
        clv_short = (bar.high - bar.close) / rng

        def fresh(touch_bar: int | None) -> bool:
            if touch_bar is None:
                return False
            age = self._bar_no - touch_bar
            return 1 <= age <= cfg.max_bars_since_touch

        long_ok = (
            fresh(day.long_touch_bar)
            and bar.close > day.or_high + cfg.break_buf_atr * atr
            and bar.close > bar.open
            and body >= cfg.body_min
            and clv_long >= cfg.clv_min
        )
        short_ok = (
            fresh(day.short_touch_bar)
            and bar.close < day.or_low - cfg.break_buf_atr * atr
            and bar.close < bar.open
            and body >= cfg.body_min
            and clv_short >= cfg.clv_min
        )
        if long_ok and short_ok:
            mid = day.or_mid
            assert mid is not None
            return Direction.LONG if bar.close >= mid else Direction.SHORT
        if long_ok:
            return Direction.LONG
        if short_ok:
            return Direction.SHORT
        return None

    def _forced_direction(self, bar: Bar, day: _DayState) -> Direction:
        """Deterministic side for a forced entry: excursion plus close vs mid."""
        assert day.or_high is not None and day.or_low is not None
        mid = day.or_mid
        assert mid is not None
        up = max((day.post_high or day.or_high) - day.or_high, 0.0)
        down = max(day.or_low - (day.post_low or day.or_low), 0.0)
        long_pressure = up + max(bar.close - mid, 0.0)
        short_pressure = down + max(mid - bar.close, 0.0)
        return Direction.LONG if long_pressure >= short_pressure else Direction.SHORT

    # -- entry -----------------------------------------------------------

    def _try_entry(self, bar: Bar, atr: float | None, *, forced_eligible: bool) -> None:
        day = self._day
        assert day is not None
        if atr is None:
            return

        direction = self._confirmed_direction(bar, atr, day)
        reason = EntryReason.CONFIRMED
        if direction is None:
            if not (forced_eligible and self.config.force_daily_entry):
                return
            direction = self._forced_direction(bar, day)
            reason = EntryReason.FORCED

        self._enter(bar, atr, direction, reason, day)

    def _enter(
        self,
        bar: Bar,
        atr: float,
        direction: Direction,
        reason: EntryReason,
        day: _DayState,
    ) -> None:
        cfg = self.config
        assert day.or_high is not None and day.or_low is not None
        entry = bar.close

        # The structural wick: the interaction bar's far side. With no
        # interaction on this side — only possible on a forced entry — the
        # opposite edge of the opening range is the structure.
        if direction is Direction.LONG:
            wick = day.long_touch_low if day.long_touch_low is not None else day.or_low
            stop = min(wick, day.or_high) - cfg.stop_buf_atr * atr
            risk = entry - stop
        else:
            wick = day.short_touch_high if day.short_touch_high is not None else day.or_high
            stop = max(wick, day.or_low) + cfg.stop_buf_atr * atr
            risk = stop - entry

        floor_risk = max(cfg.min_stop_atr * atr, 1e-9)
        if risk < floor_risk:
            risk = floor_risk
            stop = entry - risk if direction is Direction.LONG else entry + risk

        target = entry + cfg.rr * risk if direction is Direction.LONG else entry - cfg.rr * risk

        budget = self._result.equity * cfg.risk_pct / 100.0
        raw_qty = budget / (risk * cfg.point_value) if risk > 0 and cfg.point_value > 0 else 0.0
        if cfg.max_notional_mult > 0 and entry > 0 and cfg.point_value > 0:
            cap = self._result.equity * cfg.max_notional_mult / (entry * cfg.point_value)
            raw_qty = min(raw_qty, cap)
        qty = max(cfg.min_qty, _floor_step(raw_qty, cfg.qty_step))

        trade = Trade(
            day=day.summary.day,
            direction=direction,
            reason=reason,
            entry_time=bar.ts,
            entry_price=entry,
            stop=stop,
            target=target,
            risk=risk,
            qty=qty,
        )
        day.traded = True
        day.summary.trade = trade
        self._open_trade = trade
        self._result.trades.append(trade)

    # -- exit ------------------------------------------------------------

    def _resolve_open_trade(self, bar: Bar) -> None:
        trade = self._open_trade
        assert trade is not None
        if bar.ts <= trade.entry_time:
            # Protective orders are live from the bar after the fill, never on
            # the signal bar itself.
            return

        if trade.direction is Direction.LONG:
            if bar.low <= trade.stop:
                # A gap through the stop fills at the open, not at the level.
                self._close_trade(trade, bar.ts, min(trade.stop, bar.open), ExitReason.STOP)
                return
            if bar.high >= trade.target:
                self._close_trade(trade, bar.ts, max(trade.target, bar.open), ExitReason.TARGET)
                return
        else:
            if bar.high >= trade.stop:
                self._close_trade(trade, bar.ts, max(trade.stop, bar.open), ExitReason.STOP)
                return
            if bar.low <= trade.target:
                self._close_trade(trade, bar.ts, min(trade.target, bar.open), ExitReason.TARGET)
                return

    def _close_trade(self, trade: Trade, ts: datetime, price: float, reason: ExitReason) -> None:
        trade.exit_time = ts
        trade.exit_price = price
        trade.exit_reason = reason
        move = (price - trade.entry_price) * int(trade.direction)
        trade.r_multiple = move / trade.risk if trade.risk > 0 else 0.0
        trade.pnl = move * trade.qty * self.config.point_value
        self._result.equity += trade.pnl
        self._open_trade = None


def simulate(bars: Iterable[Bar], config: OrbConfig | None = None) -> SimulationResult:
    """Run the model over ``bars`` and return what happened, day by day."""
    return OrbStrategy(config).run(bars)
