"""Executable reference implementation of the AURUM-NY PRIME setup logic.

## Why this exists

The Pine script is the deliverable, but Pine cannot be unit-tested: TradingView
owns the compiler and the runtime. So the deterministic core of the setup —
session ranges, the opening-range lock, the anchored VWAP, confirmed pivots, the
ascending trendline, the third touch, the rejection candle, the stop, the size,
the reward space — is written here a second time, in Python, from the same
specification, and tested.

That gives two things:

* **The specification is proven deterministic.** Every ambiguity in the master
  instruction had to be resolved into arithmetic before this module would run,
  which is what S90 asks for.
* **Causality is testable.** The engine consumes one bar at a time and can never
  see the future. `tests/test_aurum_validation.py` mutates future bars and
  asserts that past decisions do not move.

## What it is NOT

It is not a bar-for-bar emulator of TradingView. Pivot tie-breaking, ATR seeding
and fill simulation differ in the last decimal from the broker emulator, and
this module makes no attempt to hide that. Nothing here should be quoted as a
backtest result. The Pine strategy produces the trades; this produces confidence
that the rules the Pine strategy implements are well defined.

Intermarket context (DXY, GC, VIX, rates) is supplied per bar rather than
recomputed, because those are separate feeds and inventing them here would be
a simulation of a simulation.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field, replace
from datetime import datetime
from enum import StrEnum

ET = "America/New_York"


def hm(text: str) -> int:
    """'HH:MM' -> minutes since midnight."""
    hours, _, minutes = text.partition(":")
    return int(hours) * 60 + int(minutes)


def in_window(minute: int, start: int, end: int) -> bool:
    """Window membership, wrapping past midnight when start > end."""
    if start <= end:
        return start <= minute < end
    return minute >= start or minute < end


class State(StrEnum):
    """S57 state machine."""

    IDLE = "IDLE"
    HTF_BULL = "HTF_BULL"
    ASIA_COMPLETE = "ASIA_COMPLETE"
    LONDON_CONFIRMED = "LONDON_CONFIRMED"
    NY_OR_DEFINED = "NY_OR_DEFINED"
    ORB_BREAK = "ORB_BREAK"
    ORB_ACCEPTED = "ORB_ACCEPTED"
    PIVOTS_VALID = "PIVOTS_VALID"
    TRENDLINE_VALID = "TRENDLINE_VALID"
    WAIT_TOUCH_3 = "WAIT_TOUCH_3"
    TOUCH_3 = "TOUCH_3"
    REJECTION = "REJECTION"
    ARMED = "ARMED"
    INVALIDATED = "INVALIDATED"


@dataclass(frozen=True)
class Bar:
    """One completed chart bar, timestamped at its OPEN in America/New_York."""

    ts: datetime
    open: float
    high: float
    low: float
    close: float
    volume: float = 0.0

    @property
    def et_minute(self) -> int:
        return self.ts.hour * 60 + self.ts.minute

    @property
    def et_date(self) -> int:
        return self.ts.year * 10000 + self.ts.month * 100 + self.ts.day


@dataclass(frozen=True)
class Context:
    """Per-bar intermarket and regime context (S16, S24, S36-S40)."""

    gold_bull: bool = True
    bull_4h: bool = True
    bull_1h: bool = True
    dxy_score: int = 3
    gc_count: int = 4
    vix_support: float = 0.0
    ry_momentum: float = -0.01
    corr_gold_dxy: float = -0.45
    news_blackout: bool = False
    atr15: float = 3.0
    feeds_ok: bool = True


@dataclass(frozen=True)
class Params:
    """Defaults mirror the Pine inputs; docs/03_parameter_table.md holds ranges."""

    asia_start: str = "20:00"
    asia_end: str = "02:00"
    london_start: str = "02:00"
    london_end: str = "08:20"
    or_start: str = "08:20"
    or_end: str = "08:35"
    trade_start: str = "08:35"
    trade_end: str = "11:30"
    flat_time: str = "12:00"

    atr_len: int = 14
    atr_median_len: int = 50
    atr_shock_max: float = 1.75

    orb_buffer_atr: float = 0.05
    orb_retest_tol_atr: float = 0.10
    orb_hold_tol_atr: float = 0.10
    orb_fail_n: int = 2

    vwap_slope_lookback: int = 3
    vwap_ext_max: float = 1.25

    pivot_left: int = 3
    pivot_right: int = 3
    min_rise_atr: float = 0.10
    min_spacing: int = 4
    max_spacing: int = 36
    slope_max_norm: float = 0.25
    touch_tol_atr: float = 0.12

    min_body_ratio: float = 0.35
    min_clv: float = 0.70
    min_lwr: float = 0.15
    micro_left: int = 1
    micro_right: int = 1

    max_sweep_atr15: float = 0.50
    sweep_reclaim_bars: int = 3

    stop_buffer_atr: float = 0.10
    min_stop_atr: float = 0.20
    max_stop_atr: float = 1.25
    min_room_r: float = 1.5

    spread: float = 0.30
    slippage: float = 0.10
    commission_per_unit: float = 0.07
    max_spread_atr: float = 0.20
    usd_per_point: float = 1.0
    unit_step: float = 1.0
    min_units: float = 1.0
    units_per_lot: float = 100.0

    risk_std_pct: float = 0.50
    risk_abs_max_pct: float = 1.00
    risk_hard_cap: float = 1000.0
    risk_5_8_pct: float = 0.40
    risk_8_9_pct: float = 0.25
    risk_9_10_pct: float = 0.15

    dxy_min_score: int = 2
    gc_min_count: int = 2
    score_threshold: float = 80.0
    entry_mode: str = "Conservative"
    stop_model: str = "A"
    strict_structure: bool = False
    tick: float = 0.01


@dataclass
class Signal:
    """What the engine decided on one bar, and why."""

    ts: datetime
    state: State
    score: float = 0.0
    grade: str = "-"
    armed: bool = False
    entry: float | None = None
    stop: float | None = None
    r_distance: float | None = None
    units: float | None = None
    risk_usd: float | None = None
    room_r: float | None = None
    reason: str = ""
    session_type: str = "NONE"
    touch_number: int = 0

    def key(self) -> tuple:
        """Comparable fingerprint used by the causality tests."""
        return (
            self.ts,
            self.state,
            round(self.score, 6),
            self.grade,
            self.armed,
            None if self.entry is None else round(self.entry, 6),
            None if self.stop is None else round(self.stop, 6),
            None if self.units is None else round(self.units, 6),
            self.reason,
        )


def _floor_step(value: float, step: float) -> float:
    """Round DOWN to a step. Position size is never rounded up (S47)."""
    if step <= 0:
        return value
    return math.floor(value / step + 1e-9) * step


@dataclass
class _SessionRange:
    high: float | None = None
    low: float | None = None
    close: float | None = None
    ready: bool = False

    @property
    def mid(self) -> float | None:
        if self.high is None or self.low is None:
            return None
        return (self.high + self.low) / 2


class Engine:
    """Streaming setup engine. One bar in, one Signal out. No lookahead is
    possible: `update()` never sees a bar it has not already emitted for."""

    def __init__(self, params: Params | None = None, equity: float = 100_000.0) -> None:
        self.p = params or Params()
        self.equity = equity
        self.account = equity

        self._m = {
            "asia_start": hm(self.p.asia_start),
            "asia_end": hm(self.p.asia_end),
            "london_start": hm(self.p.london_start),
            "london_end": hm(self.p.london_end),
            "or_start": hm(self.p.or_start),
            "or_end": hm(self.p.or_end),
            "trade_start": hm(self.p.trade_start),
            "trade_end": hm(self.p.trade_end),
            "flat": hm(self.p.flat_time),
        }

        self.bars: list[Bar] = []
        self._atr: float | None = None
        self._tr_seed: list[float] = []
        self._atr_history: list[float] = []

        self._asia_run = _SessionRange()
        self._london_run = _SessionRange()
        self.asia = _SessionRange()
        self.london = _SessionRange()
        self._was_asia = False
        self._was_london = False

        self._day_high: float | None = None
        self._day_low: float | None = None
        self._day_close: float | None = None
        self.pdh: float | None = None
        self.pdl: float | None = None
        self.pdc: float | None = None
        self._et_date: int | None = None

        self._or_run_high: float | None = None
        self._or_run_low: float | None = None
        self._was_or = False
        self.orh: float | None = None
        self.orl: float | None = None
        self.or_ready = False

        self.orb_broke = False
        self.orb_break_index: int | None = None
        self.orb_accept_momentum = False
        self.orb_hold_tight = False
        self.orb_accept_retest = False
        self.orb_failed = False
        self._below_orh = 0

        self._vwap_pv = 0.0
        self._vwap_wv = 0.0
        self.vwap: float | None = None
        self._vwap_history: list[float | None] = []
        self._was_anchored = False

        self.p1: tuple[int, float] | None = None
        self.p2: tuple[int, float] | None = None
        self.hh1: float | None = None
        self.hh2: float | None = None
        self._last_ph: tuple[int, float] | None = None
        self._last_mph: float | None = None

        self.sweep_seen = False
        self.sweep_low: float | None = None
        self.sweep_index: int | None = None
        self.reclaimed = False

        self.trades_today = 0
        self.day_locked = False

    # -- indicators ------------------------------------------------------
    def _update_atr(self, bar: Bar) -> None:
        if not self.bars:
            true_range = bar.high - bar.low
        else:
            prev_close = self.bars[-1].close
            true_range = max(
                bar.high - bar.low,
                abs(bar.high - prev_close),
                abs(bar.low - prev_close),
            )
        n = self.p.atr_len
        if self._atr is None:
            self._tr_seed.append(true_range)
            if len(self._tr_seed) == n:
                self._atr = sum(self._tr_seed) / n
        else:
            # Wilder smoothing, which is what ta.atr() uses.
            self._atr = (self._atr * (n - 1) + true_range) / n
        if self._atr is not None:
            self._atr_history.append(self._atr)

    @property
    def atr(self) -> float | None:
        return self._atr

    @property
    def atr_shock(self) -> float | None:
        if self._atr is None or len(self._atr_history) < 2:
            return None
        window = self._atr_history[-self.p.atr_median_len:]
        median = sorted(window)[len(window) // 2]
        return self._atr / median if median > 0 else None

    # -- pivots ----------------------------------------------------------
    def _confirmed_pivot(self, kind: str, left: int, right: int) -> tuple[int, float] | None:
        """A pivot is only ever reported `right` bars after it printed, which is
        the whole point: no retrospective pivot knowledge (S28)."""
        idx = len(self.bars) - 1 - right
        if idx - left < 0:
            return None
        window = self.bars[idx - left: idx + right + 1]
        centre = self.bars[idx]
        if kind == "low":
            values = [b.low for b in window]
            if centre.low == min(values) and values.count(centre.low) == 1:
                return idx, centre.low
        else:
            values = [b.high for b in window]
            if centre.high == max(values) and values.count(centre.high) == 1:
                return idx, centre.high
        return None

    # -- main ------------------------------------------------------------
    def update(self, bar: Bar, ctx: Context | None = None) -> Signal:
        ctx = ctx or Context()
        p = self.p
        minute = bar.et_minute
        new_day = self._et_date is not None and bar.et_date != self._et_date
        first_bar = self._et_date is None

        self._update_atr(bar)
        self.bars.append(bar)
        index = len(self.bars) - 1

        # ---- ET calendar day levels (S12) ------------------------------
        if new_day or first_bar:
            self.pdh, self.pdl, self.pdc = self._day_high, self._day_low, self._day_close
            self._day_high, self._day_low = bar.high, bar.low
            self.trades_today = 0
            self.day_locked = False
            self.orb_broke = False
            self.orb_break_index = None
            self.orb_accept_momentum = False
            self.orb_hold_tight = False
            self.orb_accept_retest = False
            self.orb_failed = False
            self._below_orh = 0
            self.or_ready = False
            self.orh = self.orl = None
            self._or_run_high = self._or_run_low = None
            self.sweep_seen = False
            self.reclaimed = False
            self.sweep_low = None
            self.sweep_index = None
        else:
            self._day_high = max(self._day_high, bar.high) if self._day_high is not None else bar.high
            self._day_low = min(self._day_low, bar.low) if self._day_low is not None else bar.low
        self._day_close = bar.close
        self._et_date = bar.et_date

        # ---- sessions (S10, S11) ---------------------------------------
        in_asia = in_window(minute, self._m["asia_start"], self._m["asia_end"])
        in_london = in_window(minute, self._m["london_start"], self._m["london_end"])
        in_or = in_window(minute, self._m["or_start"], self._m["or_end"])

        if in_asia and not self._was_asia:
            self._asia_run = _SessionRange(bar.high, bar.low, bar.close)
        elif in_asia:
            self._asia_run.high = max(self._asia_run.high, bar.high)
            self._asia_run.low = min(self._asia_run.low, bar.low)
            self._asia_run.close = bar.close
        if self._was_asia and not in_asia:
            self.asia = replace(self._asia_run, ready=True)

        if in_london and not self._was_london:
            self._london_run = _SessionRange(bar.high, bar.low, bar.close)
        elif in_london:
            self._london_run.high = max(self._london_run.high, bar.high)
            self._london_run.low = min(self._london_run.low, bar.low)
            self._london_run.close = bar.close
        if self._was_london and not in_london:
            self.london = replace(self._london_run, ready=True)

        # ---- Asia low sweep and reclaim (S14) --------------------------
        if in_london and self.asia.ready and self.asia.low is not None:
            if bar.low < self.asia.low:
                self.sweep_seen = True
                self.sweep_index = index
                self.sweep_low = bar.low if self.sweep_low is None else min(self.sweep_low, bar.low)
            if (
                self.sweep_seen
                and not self.reclaimed
                and bar.close > self.asia.low
                and index - (self.sweep_index or index) <= p.sweep_reclaim_bars
            ):
                self.reclaimed = True

        # ---- opening range, locked at the end of the window (S17) ------
        if in_or and not self._was_or:
            self._or_run_high, self._or_run_low = bar.high, bar.low
        elif in_or:
            self._or_run_high = max(self._or_run_high, bar.high)
            self._or_run_low = min(self._or_run_low, bar.low)
        if self._was_or and not in_or and self._or_run_high is not None:
            self.orh, self.orl = self._or_run_high, self._or_run_low
            self.or_ready = True

        self._was_asia, self._was_london, self._was_or = in_asia, in_london, in_or

        # ---- anchored VWAP (S22) ---------------------------------------
        anchored = minute >= self._m["or_start"]
        if anchored and not self._was_anchored:
            self._vwap_pv = self._vwap_wv = 0.0
            self.vwap = None
        if anchored:
            weight = bar.volume if bar.volume and bar.volume > 0 else 1.0
            self._vwap_pv += (bar.high + bar.low + bar.close) / 3 * weight
            self._vwap_wv += weight
            self.vwap = self._vwap_pv / self._vwap_wv if self._vwap_wv else None
        self._was_anchored = anchored
        self._vwap_history.append(self.vwap)

        atr = self._atr
        signal = Signal(ts=bar.ts, state=State.IDLE, session_type="NONE")

        if atr is None or atr <= 0:
            signal.reason = "WARMUP"
            return signal

        # ---- ORB acceptance (S18-S21) ----------------------------------
        if self.or_ready and self.orh is not None:
            if not self.orb_broke and bar.close > self.orh + p.orb_buffer_atr * atr:
                self.orb_broke = True
                self.orb_break_index = index
            elif self.orb_broke and not self.orb_failed and index > (self.orb_break_index or index):
                if index == (self.orb_break_index or 0) + 1 and bar.close > self.orh:
                    self.orb_accept_momentum = True
                    self.orb_hold_tight = bar.low >= self.orh - p.orb_hold_tol_atr * atr
                if (
                    abs(bar.low - self.orh) <= p.orb_retest_tol_atr * atr
                    and bar.close > self.orh
                    and bar.close > bar.open
                ):
                    self.orb_accept_retest = True
                self._below_orh = self._below_orh + 1 if bar.close < self.orh else 0
                if self._below_orh >= p.orb_fail_n:
                    self.orb_failed = True
            if self.orl is not None and bar.close < self.orl:
                self.orb_failed = True

        orb_accepted = self.orb_broke and (self.orb_accept_momentum or self.orb_accept_retest) and not self.orb_failed

        # ---- pivots and trendline (S28-S31) ----------------------------
        anchor_minute = self._m["london_start"]
        if minute >= anchor_minute and not in_window(
            self.bars[-2].et_minute if len(self.bars) > 1 else 0, anchor_minute, 24 * 60
        ):
            self.p1 = self.p2 = None
            self.hh1 = self.hh2 = None
            self._last_ph = None
            self._last_mph = None

        found_high = self._confirmed_pivot("high", p.pivot_left, p.pivot_right)
        if found_high:
            self._last_ph = found_high
            if self.p2 and found_high[0] > self.p2[0]:
                self.hh2 = found_high[1]

        micro_high = self._confirmed_pivot("high", p.micro_left, p.micro_right)
        if micro_high:
            self._last_mph = micro_high[1]

        found_low = self._confirmed_pivot("low", p.pivot_left, p.pivot_right)
        if found_low:
            self.hh1 = (
                self._last_ph[1]
                if self._last_ph and self.p2 and self._last_ph[0] > self.p2[0]
                else None
            )
            self.p1, self.p2 = self.p2, found_low
            self.hh2 = None

        spacing = rise = slope = slope_norm = None
        pivot_struct = strict_struct = trendline_valid = False
        tl_value = None
        if self.p1 and self.p2:
            spacing = self.p2[0] - self.p1[0]
            rise = self.p2[1] - self.p1[1]
            slope = rise / spacing if spacing > 0 else None
            slope_norm = slope / atr if slope is not None else None
            pivot_struct = (
                self.p2[1] > self.p1[1]
                and rise >= p.min_rise_atr * atr
                and p.min_spacing <= spacing <= p.max_spacing
            )
            strict_struct = bool(pivot_struct and self.hh1 and self.hh2 and self.hh2 > self.hh1)
            trendline_valid = bool(
                pivot_struct and slope_norm is not None and 0 < slope_norm <= p.slope_max_norm
            )
            if trendline_valid:
                tl_value = self.p2[1] + slope * (index - self.p2[0])

        # ---- third touch and rejection (S31-S33) -----------------------
        touch3 = False
        touch3_strong = False
        if trendline_valid and tl_value is not None and self.p2:
            bars_after = index - self.p2[0]
            touch3 = (
                bars_after > p.pivot_right
                and abs(bar.low - tl_value) <= p.touch_tol_atr * atr
                and bar.close > tl_value
            )
            touch3_strong = touch3 and bar.low > self.p2[1]

        rng = bar.high - bar.low
        body_ratio = abs(bar.close - bar.open) / rng if rng > 0 else 0.0
        clv = (bar.close - bar.low) / rng if rng > 0 else 0.0
        lwr = (min(bar.open, bar.close) - bar.low) / rng if rng > 0 else 0.0
        rejection = bar.close > bar.open and body_ratio >= p.min_body_ratio and clv >= p.min_clv
        rejection_strong = rejection and lwr >= p.min_lwr

        # ---- session model (S13-S15) -----------------------------------
        cont_bull = bool(
            self.asia.ready
            and self.london.ready
            and self.london.high > self.asia.high
            and self.london.low > self.asia.low
            and self.london.close > self.london.mid
        )
        cont_strong = cont_bull and self.london.close > self.asia.high
        sweep_depth = (
            (self.asia.low - self.sweep_low) / ctx.atr15
            if self.sweep_seen and self.sweep_low is not None and self.asia.low is not None and ctx.atr15 > 0
            else None
        )
        sweep_bull = bool(
            self.sweep_seen
            and self.reclaimed
            and sweep_depth is not None
            and sweep_depth <= p.max_sweep_atr15
            and self.asia.mid is not None
            and bar.close > self.asia.mid
        )
        sweep_strong = sweep_bull and self.asia.high is not None and bar.close > self.asia.high
        session_bull = cont_bull or sweep_bull
        signal.session_type = (
            "SESSION_CONTINUATION" if cont_bull else "SESSION_SWEEP_RECLAIM" if sweep_bull else "NONE"
        )

        # ---- VWAP state (S22, S25) -------------------------------------
        above_vwap = self.vwap is not None and bar.close > self.vwap
        prior = (
            self._vwap_history[-1 - p.vwap_slope_lookback]
            if len(self._vwap_history) > p.vwap_slope_lookback
            else None
        )
        vwap_slope = (self.vwap - prior) / atr if self.vwap is not None and prior is not None else None
        vwap_rising = vwap_slope is not None and vwap_slope > 0
        vwap_ext = (bar.close - self.vwap) / atr if self.vwap is not None else None
        vwap_ext_ok = vwap_ext is not None and 0 < vwap_ext <= p.vwap_ext_max

        # ---- score (S53) -----------------------------------------------
        corr_factor = 1.0 if ctx.corr_gold_dxy <= -0.20 else 0.5 if ctx.corr_gold_dxy < 0 else 0.25
        blocks = [
            (5.0 * ctx.bull_4h + 4.0 * ctx.bull_1h, 10.0, 10.0),
            (
                8.0 * session_bull + 2.0 * (cont_strong or sweep_strong)
                + 2.0 * (self.asia.mid is not None and bar.close > self.asia.mid),
                12.0,
                12.0,
            ),
            (
                4.0 * self.orb_broke + 4.0 * orb_accepted + 2.0 * self.orb_accept_retest
                + 1.0 * self.orb_hold_tight + 1.0 * (not self.orb_failed),
                12.0,
                12.0,
            ),
            (5.0 * above_vwap + 3.0 * vwap_rising + 2.0 * bool(vwap_ext is not None and 0 < vwap_ext <= 0.75), 10.0, 10.0),
            (min(ctx.dxy_score, 3) * 14.0 / 3.0 * corr_factor, 14.0, 14.0),
            (ctx.gc_count * 2.0, 8.0, 8.0),
            (5.0 * (ctx.ry_momentum < 0), 8.0, 8.0),
            (4.0 if ctx.vix_support > 0 else 2.0 if ctx.vix_support == 0 else 0.0, 4.0, 4.0),
            (5.0 * pivot_struct + 3.0 * strict_struct, 8.0, 8.0),
            (4.0 * touch3 + 3.0 * touch3_strong, 7.0, 7.0),
            (4.0 * rejection + 1.0 * rejection_strong + 2.0, 7.0, 7.0),
        ]
        raw = sum(min(value / cap, 1.0) * weight for value, cap, weight in blocks)
        total = sum(weight for _, _, weight in blocks)
        signal.score = raw / total * 100.0 if total else 0.0
        signal.touch_number = 3 if touch3 else 2 if pivot_struct else 1 if self.p2 else 0

        # ---- trade construction (S44-S48) ------------------------------
        buffer_ = max(p.stop_buffer_atr * atr, p.spread + p.slippage)
        stop_a = bar.low - buffer_
        stop_b = self.p2[1] - buffer_ if self.p2 else None
        stop = stop_b if (p.stop_model == "B" and stop_b is not None) else stop_a
        entry = (
            bar.high + p.tick
            if p.entry_mode == "Moderate" or self._last_mph is None
            else max(bar.high, self._last_mph) + p.tick
        )
        r_distance = entry - stop
        stop_ok = r_distance > 0 and p.min_stop_atr * atr <= r_distance <= p.max_stop_atr * atr

        levels = [self.asia.high, self.london.high, self.pdh]
        above = [lvl for lvl in levels if lvl is not None and lvl > entry]
        map_populated = any(lvl is not None for lvl in levels)
        nearest = min(above) if above else None
        room_r = (nearest - entry) / r_distance if nearest is not None and r_distance > 0 else None
        room_ok = map_populated and (room_r is None or room_r >= p.min_room_r)

        gain_pct = (self.equity - self.account) / self.account * 100.0
        risk_pct = (
            p.risk_std_pct if gain_pct < 5
            else p.risk_5_8_pct if gain_pct < 8
            else p.risk_8_9_pct if gain_pct < 9
            else p.risk_9_10_pct
        )
        risk_pct = min(risk_pct, p.risk_abs_max_pct)
        risk_budget = min(self.equity * risk_pct / 100.0, p.risk_hard_cap)
        cost_per_unit = (p.spread + p.slippage) * p.usd_per_point + p.commission_per_unit
        risk_per_unit = r_distance * p.usd_per_point + cost_per_unit if r_distance > 0 else None
        units = _floor_step(risk_budget / risk_per_unit, p.unit_step) if risk_per_unit else None
        size_ok = units is not None and units >= p.min_units and units * risk_per_unit <= risk_budget * (1 + 1e-9)

        atr_shock = self.atr_shock
        volatility_normal = atr_shock is not None and atr_shock <= p.atr_shock_max
        spread_atr = p.spread / atr
        spread_ok = spread_atr <= p.max_spread_atr
        window_ok = in_window(minute, self._m["trade_start"], self._m["trade_end"]) and minute < self._m["flat"]

        # ---- mandatory conditions (S55) --------------------------------
        checks = [
            (ctx.gold_bull, "NO TRADE — HTF NOT BULL"),
            (session_bull, "NO TRADE — LONDON STRUCTURE"),
            (self.or_ready, "NO TRADE — OR NOT DEFINED"),
            (orb_accepted, "NO TRADE — ORB NOT ACCEPTED"),
            (above_vwap, "NO TRADE — BELOW VWAP"),
            (vwap_rising, "NO TRADE — VWAP SLOPE"),
            (vwap_ext_ok, "NO TRADE — EXTENDED FROM VWAP"),
            (ctx.dxy_score >= p.dxy_min_score, "NO TRADE — DXY"),
            (ctx.gc_count >= p.gc_min_count, "NO TRADE — GC NOT CONFIRMING"),
            (pivot_struct and (not p.strict_structure or strict_struct), "NO TRADE — NO PIVOT STRUCTURE"),
            (trendline_valid, "NO TRADE — TRENDLINE"),
            (touch3, "NO TRADE — THIRD TOUCH"),
            (rejection, "NO TRADE — WEAK REJECTION"),
            (volatility_normal, "NO TRADE — ATR SHOCK"),
            (spread_ok, "NO TRADE — SPREAD"),
            (stop_ok, "NO TRADE — STOP DISTANCE"),
            (room_ok, f"NO TRADE — RESISTANCE < {p.min_room_r}R"),
            (size_ok, "NO TRADE — INVALID POSITION SIZE"),
            (not ctx.news_blackout, "NO TRADE — NEWS BLACKOUT"),
            (ctx.feeds_ok, "NO TRADE — DATA FEED FAILURE"),
            (not self.day_locked and self.trades_today == 0, "NO TRADE — RISK LIMIT"),
            (signal.score >= p.score_threshold, "NO TRADE — SCORE"),
            (window_ok, "NO TRADE — OUTSIDE WINDOW"),
        ]
        failed = next((message for ok, message in checks if not ok), None)

        if self.orb_failed:
            signal.state = State.INVALIDATED
        elif not ctx.gold_bull:
            signal.state = State.IDLE
        elif not self.london.ready:
            signal.state = State.ASIA_COMPLETE if self.asia.ready else State.HTF_BULL
        elif not session_bull:
            signal.state = State.LONDON_CONFIRMED
        elif not self.or_ready:
            signal.state = State.NY_OR_DEFINED
        elif not self.orb_broke:
            signal.state = State.NY_OR_DEFINED
        elif not orb_accepted:
            signal.state = State.ORB_BREAK
        elif not pivot_struct:
            signal.state = State.ORB_ACCEPTED
        elif not trendline_valid:
            signal.state = State.PIVOTS_VALID
        elif not touch3:
            signal.state = State.WAIT_TOUCH_3
        elif not rejection:
            signal.state = State.TOUCH_3
        elif failed:
            signal.state = State.REJECTION
        else:
            signal.state = State.ARMED

        if failed is None:
            signal.armed = True
            signal.entry = entry
            signal.stop = stop
            signal.r_distance = r_distance
            signal.units = units
            signal.risk_usd = units * risk_per_unit
            signal.room_r = room_r
            signal.reason = "ARMED"
            signal.grade = (
                "A++"
                if signal.score >= 90 and ctx.dxy_score == 3 and rejection_strong
                and room_r is not None and room_r >= 2.0
                else "A+"
                if signal.score >= 85 and (strict_struct or not p.strict_structure)
                else "A"
            )
            self.trades_today += 1
        else:
            signal.reason = failed
            signal.room_r = room_r
        return signal


def run(bars: list[Bar], contexts: list[Context] | None = None, params: Params | None = None) -> list[Signal]:
    """Replay a bar series and return one Signal per bar."""
    engine = Engine(params)
    ctxs = contexts or [Context()] * len(bars)
    return [engine.update(bar, ctx) for bar, ctx in zip(bars, ctxs, strict=True)]
