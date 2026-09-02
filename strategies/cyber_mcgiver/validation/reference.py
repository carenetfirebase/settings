"""Executable reference implementation of the CYBER MCGIVER v7 opportunity engine.

## Why this exists

The Pine script is the deliverable, but TradingView owns the Pine compiler and
runtime, so the Pine source cannot be executed here and cannot be unit-tested.
The v7 rules are therefore written a second time, in Python, from the same
definitions: the same four setup families, the same ten score components with
the same weights, the same mandatory risk gates, the same daily frequency and
independence engine.

That buys two things the Pine file alone cannot buy:

* **The funnel can be counted before the backtest is run.** The first objective
  of v7 is frequency, and frequency is a property of the candidate geometry. If
  this engine says the architecture offers roughly 1.5 candidates a day, the
  restructure has done its job; if it says eleven a decade, no amount of chart
  time will fix it.
* **Writing the rules twice finds the places where they were never actually
  decided.** Anything ambiguous had to become arithmetic before this module
  would run.

## What it is NOT

It is not a bar-for-bar emulator of TradingView's broker. Fill simulation, ATR
seeding and pivot tie-breaking differ in the last decimal, and this module makes
no attempt to hide that. Run against `synthetic` bars it is not a backtest at
all: those bars carry no edge by construction, so profit factor there measures
the exit model against a random walk. Frequency, funnel shape and score
distribution are the outputs that mean something.

Order of operations inside one bar mirrors Pine: the broker acts first (a
resting entry fills, then protective orders are tested against the same bar),
and only then does the script run at the close, update the trail, evaluate the
families and possibly arm the next order.
"""

from __future__ import annotations

import math
from collections import deque
from dataclasses import dataclass, field
from datetime import date, datetime

# --- setup families ----------------------------------------------------------
FAM_TL, FAM_SW, FAM_BR, FAM_VW = 0, 1, 2, 3
FAM_NAMES = ("1 Trendline", "2 Sweep", "3 Breakout", "4 VWAP pull")
N_FAM = 4

# --- trendline family state machine ------------------------------------------
TL_WAIT_BOS, TL_WAIT_P1, TL_WAIT_P2, TL_CANDIDATE, TL_CONFIRMED = 0, 1, 2, 3, 4

# --- sessions ------------------------------------------------------------------
SE_ASIA, SE_LDN, SE_MID, SE_NY, SE_LATE = 0, 1, 2, 3, 4
SESS_NAMES = ("Asia", "London", "LDN/NY", "New York", "Late")

#: Fixed research buckets. Bucket 0 is everything below the trade floor.
SCORE_EDGES = (72.0, 75.0, 78.0, 81.0, 85.0, 90.0, 95.0)
SCORE_NAMES = ("below 72", "72-74", "75-77", "78-80", "81-84", "85-89", "90-94", "95-100")
N_SCORE = 8

TIER_NONE, TIER_BP, TIER_A, TIER_AP = 0, 1, 2, 3
TIER_NAMES = ("-", "B+", "A", "A+")


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def tent(value: float, best: float, width: float) -> float:
    """Symmetric tent: 1 at `best`, 0 at `best +/- width`."""
    if width <= 0.0:
        return 0.0
    return clamp(1.0 - abs(value - best) / width, 0.0, 1.0)


def ramp(value: float, lo: float, hi: float) -> float:
    if hi <= lo:
        return 1.0 if value >= hi else 0.0
    return clamp((value - lo) / (hi - lo), 0.0, 1.0)


def band(value: float, lo: float, hi: float, fade: float) -> float:
    """Flat-topped band: 1 inside [lo, hi], fading to 0 over `fade` outside."""
    if lo <= value <= hi:
        return 1.0
    if fade <= 0.0:
        return 0.0
    if value < lo:
        return clamp(1.0 - (lo - value) / fade, 0.0, 1.0)
    return clamp(1.0 - (value - hi) / fade, 0.0, 1.0)


def score_bucket(score: float) -> int:
    for i, edge in enumerate(SCORE_EDGES):
        if score < edge:
            return i
    return N_SCORE - 1


@dataclass(frozen=True, slots=True)
class Params:
    """Defaults mirror the Pine inputs one for one."""

    # direction
    long_only: bool = True
    short_allowed: bool = False
    # families enabled
    fam_tl: bool = True
    fam_sw: bool = True
    fam_br: bool = True
    fam_vw: bool = True
    # regime
    d_fast: int = 50
    d_slow: int = 200
    d_slope: int = 5
    h4_fast: int = 20
    h4_slow: int = 50
    h4_slope: int = 3
    h1_fast: int = 20
    h1_slow: int = 50
    h1_slope: int = 3
    w_d: float = 0.45
    w_h4: float = 0.35
    w_h1: float = 0.20
    reg_floor: float = 0.30
    # trendline family
    atr_len: int = 14
    piv_l: int = 2
    piv_r: int = 2
    bos_buf: float = 0.05
    min_sep: float = 0.10
    tl_tol: float = 0.20
    slope_max: float = 0.30
    slope_best: float = 0.11
    slope_wide: float = 0.12
    tl_build: int = 500
    tl_life: int = 250
    # sweep family
    sw_len: int = 20
    sw_pd: bool = True
    sw_sess: bool = True
    sw_pen: float = 0.05
    sw_pen_best: float = 0.35
    sw_pen_max: float = 1.50
    sw_rec: float = 0.02
    sw_max: int = 6
    # breakout family
    br_len: int = 30
    br_buf: float = 0.05
    br_tol: float = 0.30
    br_fail: float = 0.60
    br_max: int = 20
    # vwap family
    vw_ema: int = 20
    vw_tol: float = 0.45
    vw_fail: float = 1.20
    vw_max: int = 8
    vw_min_leg: float = 1.00
    # weights
    w_htf: float = 15.0
    w_vwap: float = 10.0
    w_struct: float = 15.0
    w_pull: float = 15.0
    w_sweep: float = 10.0
    w_mom: float = 10.0
    w_dxy: float = 10.0
    w_atr: float = 5.0
    w_room: float = 5.0
    w_sess: float = 5.0
    # shaping
    neutral_q: float = 0.50
    bos_fresh: int = 60
    bos_strong: float = 1.50
    vw_best: float = 1.00
    vw_fade: float = 4.00
    dxy_look: int = 8
    dxy_scale: float = 1.00
    atr_ref: int = 200
    atr_lo: float = 0.70
    atr_hi: float = 1.60
    atr_shock: float = 2.75
    pull_best: float = 0.90
    pull_wide: float = 1.60
    leg_len: int = 20
    q_sess: tuple[float, ...] = (0.35, 1.00, 0.80, 1.00, 0.25)
    mom_floor: float = 0.30
    # tiers
    thr_bp: float = 72.0
    thr_a: float = 78.0
    thr_ap: float = 85.0
    risk_bp: float = 0.25
    risk_a: float = 0.40
    risk_ap: float = 0.50
    # daily
    max_per_day: int = 3
    day_loss: float = 1.25
    scale2: float = 0.80
    scale3: float = 0.60
    scale_dd: bool = True
    min_day_bars: int = 60
    # independence
    cooldown: int = 4
    pivots_after: int = 1
    anchor_rule: bool = True
    # risk
    risk_ceil: float = 1.00
    stop_buf: float = 0.15
    stop_min: float = 0.25
    stop_max: float = 3.00
    min_room_r: float = 1.50
    room_full: float = 4.00
    room_len: int = 50
    room_sky: float = 5.00
    arm_bars: int = 3
    # costs, expressed in dollars per ounce round turn
    cost_per_oz: float = 0.57
    # exits
    partial_r: float = 1.20
    partial_pct: float = 50.0
    trail_atr: float = 2.00
    trail_buf: float = 0.10
    max_r: float = 10.0
    # account
    initial_capital: float = 100_000.0


@dataclass(slots=True)
class Trade:
    entered: datetime
    exited: datetime | None
    family: int
    tier: int
    score: float
    session: int
    direction: int
    entry: float
    stop: float
    risk_px: float
    risk_pct: float
    r_multiple: float = 0.0
    pnl: float = 0.0
    mfe_r: float = 0.0
    mae_r: float = 0.0
    bars_held: int = 0
    entry_bar: int = 0
    exit_bar: int = 0
    stop_atr: float = 0.0
    trigger_close: float = 0.0


@dataclass(slots=True)
class Funnel:
    bars: int = 0
    raw: list[int] = field(default_factory=lambda: [0] * N_FAM)
    candidates: list[int] = field(default_factory=lambda: [0] * N_FAM)
    passed: list[int] = field(default_factory=lambda: [0] * N_FAM)
    taken: list[int] = field(default_factory=lambda: [0] * N_FAM)
    score_fail: int = 0
    block_regime: int = 0
    block_mom: int = 0
    block_shock: int = 0
    block_sess: int = 0
    stop_bad: int = 0
    stop_wide: int = 0
    stop_tight: int = 0
    room_short: int = 0
    block_anchor: int = 0
    block_open: int = 0
    block_cap: int = 0
    block_loss: int = 0
    block_cool: int = 0
    size_small: int = 0
    budget_out: int = 0
    multi_bar: int = 0
    armed: int = 0
    filled: int = 0
    same_bar: int = 0
    arm_expired: int = 0
    arm_voided: int = 0
    trades: int = 0
    cand_by_score: list[int] = field(default_factory=lambda: [0] * N_SCORE)


class _Ema:
    """Incremental EMA that only ever consumes closed higher-timeframe bars."""

    __slots__ = ("length", "alpha", "value", "history")

    def __init__(self, length: int, history: int = 0) -> None:
        self.length = length
        self.alpha = 2.0 / (length + 1.0)
        self.value: float | None = None
        self.history: deque[float] = deque(maxlen=max(history, 1) + 1)

    def update(self, price: float) -> None:
        self.value = price if self.value is None else self.value + self.alpha * (price - self.value)
        self.history.append(self.value)

    def ago(self, n: int) -> float | None:
        if len(self.history) <= n:
            return None
        return self.history[-1 - n]


def _tf_score(close: float, fast: float, slow: float, fast_prev: float) -> float:
    s = 0.0
    s += 1.0 if close > slow else -1.0 if close < slow else 0.0
    s += 1.0 if fast > slow else -1.0 if fast < slow else 0.0
    s += 1.0 if fast > fast_prev else -1.0 if fast < fast_prev else 0.0
    return s / 3.0


class _Frame:
    """A higher timeframe: last CLOSED candle's close plus its EMAs."""

    __slots__ = ("fast", "slow", "slope", "_key", "_close", "last_close")

    def __init__(self, fast: int, slow: int, slope: int) -> None:
        self.fast = _Ema(fast, history=slope + 2)
        self.slow = _Ema(slow)
        self.slope = slope
        self._key: object | None = None
        self._close: float | None = None
        self.last_close: float | None = None

    def update(self, key: object, close: float) -> None:
        if self._key is not None and key != self._key and self._close is not None:
            self.fast.update(self._close)
            self.slow.update(self._close)
            self.last_close = self._close
        self._key = key
        self._close = close

    def signed(self) -> float | None:
        prev = self.fast.ago(self.slope)
        if self.last_close is None or self.fast.value is None or self.slow.value is None or prev is None:
            return None
        return _tf_score(self.last_close, self.fast.value, self.slow.value, prev)


class Engine:
    """The v7 opportunity engine, one bar at a time, never seeing the future."""

    def __init__(self, params: Params | None = None) -> None:
        self.p = params or Params()
        self.f = Funnel()
        self.trades: list[Trade] = []
        self.equity = self.p.initial_capital

        # --- rolling series ---------------------------------------------------
        self._high: list[float] = []
        self._low: list[float] = []
        self._close: list[float] = []
        self._atr: float | None = None
        self._atr_hist: deque[float] = deque(maxlen=self.p.atr_ref)
        self._ema_ref: _Ema = _Ema(self.p.vw_ema)
        self._dxy: deque[float] = deque(maxlen=self.p.dxy_look + 2)
        self._dxy_tr: float | None = None
        self._prev_dxy: float | None = None

        # --- higher timeframes -------------------------------------------------
        self._fd = _Frame(self.p.d_fast, self.p.d_slow, self.p.d_slope)
        self._f4 = _Frame(self.p.h4_fast, self.p.h4_slow, self.p.h4_slope)
        self._f1 = _Frame(self.p.h1_fast, self.p.h1_slow, self.p.h1_slope)

        # --- session / day -----------------------------------------------------
        self._sess_id = -1
        self._sess_hi: float | None = None
        self._sess_lo: float | None = None
        self._sess_lo_prev: float | None = None
        self._vw_pv = 0.0
        self._vw_wt = 0.0
        self._day: date | None = None
        self._prev_day_hi: float | None = None
        self._prev_day_lo: float | None = None
        self._cur_day_hi: float | None = None
        self._cur_day_lo: float | None = None
        self.day_trades = 0
        self._day_bars = 0
        self._day_equity0 = self.p.initial_capital
        self._day_realised = 0.0
        self.day_hist = [0] * 5
        self.normal_days = 0
        self.short_days = 0
        self.normal_trades = 0
        # Per normal day: (trades, share of bars whose blended regime was bullish,
        # eligible candidates). Kept so a zero-trade day can be attributed to the
        # engine being restrictive or to the day simply having no long setup.
        self.day_rows: list[tuple[int, float, int]] = []
        self._day_bull = 0
        self._day_elig = 0

        # --- structure ----------------------------------------------------------
        self._swing_hi: float | None = None
        self._swing_lo: float | None = None
        self._swing_hi_bar = 0
        self._swing_lo_bar = 0
        self.pivot_count = 0
        self._bos_bar = 0
        self._bos_dir = 0
        self._bos_level: float | None = None

        # --- family state --------------------------------------------------------
        self._tl_state = TL_WAIT_BOS
        self._tl = {"dir": 0, "bos": 0, "p1b": 0, "p1": 0.0, "p2b": 0, "p2": 0.0,
                    "m": 0.0, "mn": 0.0, "p3": 0.0, "conf": 0}
        self._sw = {"active": False, "bar": 0, "dir": 0, "level": 0.0, "ext": 0.0}
        self._br = {"active": False, "bar": 0, "dir": 0, "level": 0.0,
                    "retest": False, "px": None}
        self._vw = {"active": False, "bar": 0, "dir": 0, "px": None, "anchor": 0}
        self._last_anchor = [-1] * N_FAM

        # --- execution -----------------------------------------------------------
        self._arm: dict | None = None
        self._pos: dict | None = None
        self._last_exit_bar = -10**9
        self._pivots_at_exit = 0
        self.i = -1

    # -- indicator maintenance -------------------------------------------------

    def _update_atr(self, high: float, low: float, prev_close: float | None) -> None:
        tr = high - low if prev_close is None else max(high - low, abs(high - prev_close), abs(low - prev_close))
        n = self.p.atr_len
        self._atr = tr if self._atr is None else (self._atr * (n - 1) + tr) / n
        self._atr_hist.append(self._atr)

    def _window_max(self, series: list[float], length: int) -> float | None:
        """Highest value over the `length` bars ENDING ON THE PREVIOUS BAR."""
        end = self.i
        if end - length < 0:
            return None
        return max(series[end - length:end])

    def _window_min(self, series: list[float], length: int) -> float | None:
        end = self.i
        if end - length < 0:
            return None
        return min(series[end - length:end])

    def _pivot(self) -> tuple[bool, bool, int, float, float]:
        """Confirmed pivots, available only once the right-hand bars have closed."""
        l, r = self.p.piv_l, self.p.piv_r
        idx = self.i - r
        if idx - l < 0:
            return False, False, idx, 0.0, 0.0
        hi = self._high[idx]
        lo = self._low[idx]
        left = range(idx - l, idx)
        right = range(idx + 1, idx + r + 1)
        is_ph = all(self._high[k] < hi for k in left) and all(self._high[k] < hi for k in right)
        is_pl = all(self._low[k] > lo for k in left) and all(self._low[k] > lo for k in right)
        return is_ph, is_pl, idx, hi, lo

    # -- the bar loop ------------------------------------------------------------

    def step(self, bar) -> None:
        """Process one bar: broker phase first, then the script phase."""
        p = self.p
        self.i += 1
        i = self.i
        prev_close = self._close[-1] if self._close else None
        self._high.append(bar.high)
        self._low.append(bar.low)
        self._close.append(bar.close)
        self._update_atr(bar.high, bar.low, prev_close)
        self._ema_ref.update(bar.close)

        # ---- 1. broker phase: resting entry, then protective orders ----------
        self._broker(bar)

        # ---- 2. indicators ----------------------------------------------------
        atr = self._atr or 0.0
        if atr <= 0.0 or i < max(p.atr_len, p.room_len, p.br_len) + 5:
            self._roll_session_day(bar)
            return
        self.f.bars += 1

        atr_ref = sum(self._atr_hist) / len(self._atr_hist)
        atr_rel = atr / atr_ref if atr_ref > 0 else 1.0
        atr_shock = atr_rel > p.atr_shock

        sess = self._roll_session_day(bar)
        q_sess = p.q_sess[sess]

        # higher timeframes, closed candles only
        self._fd.update(bar.trading_day, bar.close)
        self._f4.update((bar.ts.date(), bar.ts.hour // 4), bar.close)
        self._f1.update((bar.ts.date(), bar.ts.hour), bar.close)
        sd, s4, s1 = self._fd.signed(), self._f4.signed(), self._f1.signed()
        if sd is None or s4 is None or s1 is None:
            return
        wsum = p.w_d + p.w_h4 + p.w_h1
        regime_signed = (sd * p.w_d + s4 * p.w_h4 + s1 * p.w_h1) / wsum if wsum > 0 else 0.0
        q_htf_long = clamp(0.5 + regime_signed / 2.0, 0.0, 1.0)
        market_mode = 1 if regime_signed > 0.15 else -1 if regime_signed < -0.15 else 0

        # VWAP, session anchored, unit weights (the no-volume fallback)
        self._vw_pv += (bar.high + bar.low + bar.close) / 3.0
        self._vw_wt += 1.0
        vwap = self._vw_pv / self._vw_wt
        ema_ref = self._ema_ref.value or bar.close
        vw_ref_l = max(vwap, ema_ref)

        # DXY confluence
        self._dxy.append(bar.dxy)
        if self._prev_dxy is not None:
            dxy_tr = abs(bar.dxy - self._prev_dxy)
            self._dxy_tr = dxy_tr if self._dxy_tr is None else (self._dxy_tr * 13 + dxy_tr) / 14
        self._prev_dxy = bar.dxy
        if len(self._dxy) > p.dxy_look and self._dxy_tr and self._dxy_tr > 0:
            dxy_norm = (self._dxy[-1] - self._dxy[-1 - p.dxy_look]) / (self._dxy_tr * p.dxy_scale)
            q_dxy_long = clamp(0.5 - dxy_norm / 2.0, 0.0, 1.0)
        else:
            q_dxy_long = p.neutral_q

        # pivots
        has_ph, has_pl, piv_bar, piv_hi, piv_lo = self._pivot()
        if has_ph:
            self._swing_hi, self._swing_hi_bar = piv_hi, piv_bar
            self.pivot_count += 1
        if has_pl:
            self._swing_lo, self._swing_lo_bar = piv_lo, piv_bar
            self.pivot_count += 1

        range_hi = self._window_max(self._high, p.br_len)
        sweep_lo = self._window_min(self._low, p.sw_len)
        room_hi = self._window_max(self._high, p.room_len)
        leg_hi = self._window_max(self._high, p.leg_len)
        leg_lo = self._window_min(self._low, p.leg_len)

        # global break of structure
        bos_new = False
        if self._swing_hi is not None and bar.close > self._swing_hi + p.bos_buf * atr \
                and (self._bos_dir != 1 or self._swing_hi != self._bos_level):
            self._bos_bar, self._bos_dir, self._bos_level = i, 1, self._swing_hi
            bos_new = True
        elif self._swing_lo is not None and bar.close < self._swing_lo - p.bos_buf * atr \
                and (self._bos_dir != -1 or self._swing_lo != self._bos_level):
            self._bos_bar, self._bos_dir, self._bos_level = i, -1, self._swing_lo

        bos_age = i - self._bos_bar
        bos_disp = abs(bar.close - self._bos_level) / atr if self._bos_level is not None else 0.0
        if self._bos_dir == 0:
            q_struct_base = p.neutral_q
        else:
            q_struct_base = 0.5 * clamp(1.0 - bos_age / max(p.bos_fresh, 1), 0.0, 1.0) + 0.5 * ramp(bos_disp, 0.0, p.bos_strong)
        q_struct_long = q_struct_base if self._bos_dir == 1 else (1.0 - q_struct_base if self._bos_dir == -1 else p.neutral_q)

        # trigger-bar geometry
        rng = max(bar.high - bar.low, 1e-9)
        body = abs(bar.close - bar.open) / rng
        clv_long = (bar.close - bar.low) / rng
        bull = bar.close > bar.open
        q_mom_long = clamp(0.5 * body + 0.5 * clv_long, 0.0, 1.0)
        mom_floor_long = clv_long >= p.mom_floor

        vw_dist = (bar.close - vwap) / atr
        if vw_dist < 0.0:
            q_vwap_long = clamp(0.5 + vw_dist * 0.5, 0.0, 0.5)
        elif vw_dist <= p.vw_best:
            q_vwap_long = 1.0
        else:
            q_vwap_long = clamp(1.0 - (vw_dist - p.vw_best) / max(p.vw_fade, 0.01), 0.0, 1.0)

        q_atr_env = band(atr_rel, p.atr_lo, p.atr_hi, 0.6)
        pull_depth = ((leg_hi or bar.high) - bar.low) / atr
        q_pull_gen = tent(pull_depth, p.pull_best, p.pull_wide)
        prev_low = self._low[i - 1]
        prev_close_v = self._close[i - 1]
        q_sweep_gen = clamp(0.40 + (0.30 if bar.low < prev_low else 0.0) + (0.15 if bar.close > prev_close_v else 0.0), 0.0, 1.0)

        # ---- 3. families ------------------------------------------------------
        cand: dict[int, dict] = {}
        if p.fam_tl:
            self._family_trendline(bar, atr, bos_new, has_pl, piv_bar, piv_lo, bull, cand, q_sweep_gen)
        if p.fam_sw:
            self._family_sweep(bar, atr, sweep_lo, bull, cand, q_pull_gen)
        if p.fam_br:
            self._family_breakout(bar, atr, range_hi, bull, cand, q_pull_gen, q_sweep_gen)
        if p.fam_vw:
            self._family_vwap(bar, atr, vw_ref_l, leg_hi, leg_lo, bull, market_mode, cand, q_pull_gen, q_sweep_gen, pull_depth)

        # ---- 4. the shared pipeline -------------------------------------------
        eligible: list[tuple[float, int, dict]] = []
        for fam, c in cand.items():
            self.f.candidates[fam] += 1
            stop_px = c["ref"] - p.stop_buf * atr
            risk_px = c["trig"] - stop_px
            stop_atr = risk_px / atr
            room_px = (room_hi - c["trig"]) if (room_hi is not None and room_hi > c["trig"]) else None
            room_r = 0.0 if risk_px <= 0 else (p.room_sky if room_px is None else room_px / risk_px)
            q_room = ramp(room_r, p.min_room_r, p.room_full)

            weights = (p.w_htf, p.w_vwap, p.w_struct, p.w_pull, p.w_sweep,
                       p.w_mom, p.w_dxy, p.w_atr, p.w_room, p.w_sess)
            quals = (q_htf_long, q_vwap_long, q_struct_long, c["q_pull"], c["q_sweep"],
                     q_mom_long, q_dxy_long, q_atr_env, q_room, q_sess)
            wtotal = sum(weights)
            sc = clamp(sum(q * w for q, w in zip(quals, weights)) * 100.0 / wtotal, 0.0, 100.0) if wtotal > 0 else 0.0
            self.f.cand_by_score[score_bucket(sc)] += 1

            if sc < p.thr_bp:
                self.f.score_fail += 1
                continue
            self.f.passed[fam] += 1
            if q_htf_long < p.reg_floor:
                self.f.block_regime += 1
            elif not mom_floor_long:
                self.f.block_mom += 1
            elif atr_shock:
                self.f.block_shock += 1
            elif risk_px <= 0.0:
                self.f.stop_bad += 1
            elif stop_atr > p.stop_max:
                self.f.stop_wide += 1
            elif stop_atr < p.stop_min:
                self.f.stop_tight += 1
            elif room_r < p.min_room_r:
                self.f.room_short += 1
            elif p.anchor_rule and c["anchor"] == self._last_anchor[fam]:
                self.f.block_anchor += 1
            else:
                eligible.append((sc, fam, {"trig": c["trig"], "stop": stop_px,
                                           "risk": risk_px, "anchor": c["anchor"],
                                           "room": room_r, "sess": sess}))

        if market_mode == 1:
            self._day_bull += 1
        self._day_elig += len(eligible)
        if len(eligible) > 1:
            self.f.multi_bar += 1
        if eligible:
            self._try_arm(bar, eligible)

    # -- families ---------------------------------------------------------------

    def _family_trendline(self, bar, atr, bos_new, has_pl, piv_bar, piv_lo, bull, cand, q_sweep_gen) -> None:
        p, i, tl = self.p, self.i, self._tl
        if self._tl_state not in (TL_WAIT_BOS, TL_CONFIRMED) and i - tl["bos"] > p.tl_build:
            self._tl_state, tl["dir"] = TL_WAIT_BOS, 0
        if self._tl_state == TL_CONFIRMED and i - tl["conf"] > p.tl_life:
            self._tl_state, tl["dir"] = TL_WAIT_BOS, 0

        if self._tl_state == TL_WAIT_BOS:
            if bos_new and self._bos_dir == 1:
                tl["dir"], tl["bos"] = 1, i
                self._tl_state = TL_WAIT_P1
                self.f.raw[FAM_TL] += 1
        elif self._tl_state == TL_WAIT_P1:
            if has_pl and piv_bar >= tl["bos"]:
                tl["p1b"], tl["p1"] = piv_bar, piv_lo
                self._tl_state = TL_WAIT_P2
        elif self._tl_state == TL_WAIT_P2:
            if has_pl and piv_bar > tl["p1b"]:
                if piv_lo <= tl["p1"]:
                    tl["p1b"], tl["p1"] = piv_bar, piv_lo
                elif piv_lo - tl["p1"] >= p.min_sep * atr:
                    m = (piv_lo - tl["p1"]) / max(piv_bar - tl["p1b"], 1)
                    mn = abs(m / atr)
                    if m > 0.0 and mn <= p.slope_max:
                        tl.update({"p2b": piv_bar, "p2": piv_lo, "m": m, "mn": mn})
                        self._tl_state = TL_CANDIDATE
                    else:
                        tl["p1b"], tl["p1"] = piv_bar, piv_lo
        elif self._tl_state == TL_CANDIDATE and i > tl["p2b"] + p.piv_r:
            line = tl["p2"] + tl["m"] * (i - tl["p2b"])
            if abs(bar.low - line) <= p.tl_tol * atr and bar.close > line:
                tl["p3"], tl["conf"] = bar.low, i
                self._tl_state = TL_CONFIRMED
            elif bar.close < line - p.tl_tol * atr:
                tl["p1b"], tl["p1"] = i, bar.low
                self._tl_state = TL_WAIT_P2
        elif self._tl_state == TL_CONFIRMED and i > tl["conf"]:
            line = tl["p2"] + tl["m"] * (i - tl["p2b"])
            miss = abs(bar.low - line) / atr
            if abs(bar.low - line) <= p.tl_tol * atr and bar.close > line and bull:
                q_tight = clamp(1.0 - miss / p.tl_tol, 0.0, 1.0)
                q_slope = tent(tl["mn"], p.slope_best, p.slope_wide)
                cand[FAM_TL] = {"trig": bar.high, "ref": min(bar.low, tl["p3"]),
                                "anchor": tl["p2b"], "q_pull": 0.5 * q_tight + 0.5 * q_slope,
                                "q_sweep": q_sweep_gen}
            elif bar.close < line - p.tl_tol * atr:
                self._tl_state, tl["dir"] = TL_WAIT_BOS, 0

    def _family_sweep(self, bar, atr, sweep_lo, bull, cand, q_pull_gen) -> None:
        p, i, sw = self.p, self.i, self._sw
        if sw["active"] and i - sw["bar"] > p.sw_max:
            sw["active"] = False
        if sw["active"]:
            sw["ext"] = min(sw["ext"], bar.low)
            if (sw["level"] - sw["ext"]) / atr > p.sw_pen_max:
                sw["active"] = False
        if not sw["active"]:
            level = None
            if sweep_lo is not None and bar.low < sweep_lo - p.sw_pen * atr:
                level = sweep_lo
            if p.sw_pd and self._prev_day_lo is not None and bar.low < self._prev_day_lo - p.sw_pen * atr:
                level = self._prev_day_lo if level is None else max(level, self._prev_day_lo)
            if p.sw_sess and self._sess_lo_prev is not None and bar.low < self._sess_lo_prev - p.sw_pen * atr:
                level = self._sess_lo_prev if level is None else max(level, self._sess_lo_prev)
            if level is not None:
                sw.update({"active": True, "dir": 1, "bar": i, "level": level, "ext": bar.low})
                self.f.raw[FAM_SW] += 1
        if sw["active"] and bar.close > sw["level"] + p.sw_rec * atr and bull:
            pen = (sw["level"] - sw["ext"]) / atr
            q_depth = tent(pen, p.sw_pen_best, max(p.sw_pen_max - p.sw_pen_best, 0.05) * 1.5)
            q_speed = clamp(1.0 - (i - sw["bar"]) / max(p.sw_max, 1), 0.0, 1.0)
            cand[FAM_SW] = {"trig": bar.high, "ref": sw["ext"], "anchor": sw["bar"],
                            "q_pull": q_pull_gen,
                            "q_sweep": clamp(0.65 * q_depth + 0.35 * q_speed, 0.0, 1.0)}
            sw["active"] = False

    def _family_breakout(self, bar, atr, range_hi, bull, cand, q_pull_gen, q_sweep_gen) -> None:
        p, i, br = self.p, self.i, self._br
        if br["active"] and i - br["bar"] > p.br_max:
            br["active"], br["retest"] = False, False
        if br["active"] and bar.close < br["level"] - p.br_fail * atr:
            br["active"], br["retest"] = False, False
        if not br["active"] and range_hi is not None and bar.close > range_hi + p.br_buf * atr:
            br.update({"active": True, "dir": 1, "bar": i, "level": range_hi,
                       "retest": False, "px": None})
            self.f.raw[FAM_BR] += 1
            return
        if br["active"] and i > br["bar"]:
            if bar.low <= br["level"] + p.br_tol * atr:
                br["retest"] = True
                br["px"] = bar.low if br["px"] is None else min(br["px"], bar.low)
            if br["retest"] and bull and bar.close > br["level"]:
                miss = abs((br["px"] if br["px"] is not None else br["level"]) - br["level"]) / atr
                q_tight = clamp(1.0 - miss / max(p.br_tol, 0.01), 0.0, 1.0)
                cand[FAM_BR] = {"trig": bar.high,
                                "ref": min(br["px"] if br["px"] is not None else bar.low, bar.low),
                                "anchor": br["bar"],
                                "q_pull": clamp(0.6 * q_tight + 0.4 * q_pull_gen, 0.0, 1.0),
                                "q_sweep": q_sweep_gen}
                br["active"], br["retest"] = False, False

    def _family_vwap(self, bar, atr, vw_ref, leg_hi, leg_lo, bull, market_mode, cand,
                     q_pull_gen, q_sweep_gen, pull_depth) -> None:
        p, i, vw = self.p, self.i, self._vw
        if vw["active"] and i - vw["bar"] > p.vw_max:
            vw["active"] = False
        if vw["active"]:
            if bar.close < vw_ref - p.vw_fail * atr:
                vw["active"] = False
            else:
                vw["px"] = bar.low if vw["px"] is None else min(vw["px"], bar.low)
        leg = ((leg_hi - leg_lo) / atr) if (leg_hi is not None and leg_lo is not None) else 0.0
        if not vw["active"] and leg >= p.vw_min_leg and market_mode >= 0:
            if bar.low <= vw_ref + p.vw_tol * atr and bar.close > vw_ref - p.vw_fail * atr:
                vw.update({"active": True, "dir": 1, "bar": i, "px": bar.low,
                           "anchor": self._swing_hi_bar})
                self.f.raw[FAM_VW] += 1
        if vw["active"] and bull and bar.close > vw_ref:
            ref_miss = abs((vw["px"] if vw["px"] is not None else bar.close) - vw_ref) / atr
            q_near = clamp(1.0 - ref_miss / max(p.vw_tol, 0.01), 0.0, 1.0)
            cand[FAM_VW] = {"trig": bar.high, "ref": vw["px"] if vw["px"] is not None else bar.low,
                            "anchor": vw["anchor"],
                            "q_pull": clamp(0.5 * tent(pull_depth, p.pull_best, p.pull_wide) + 0.5 * q_near, 0.0, 1.0),
                            "q_sweep": q_sweep_gen}
            vw["active"] = False

    # -- session, day and the frequency histogram --------------------------------

    def _roll_session_day(self, bar) -> int:
        p = self.p
        minute = bar.minute_of_day
        if minute >= 20 * 60 or minute < 2 * 60:
            sess = SE_ASIA
        elif minute < 8 * 60:
            sess = SE_LDN
        elif minute < 9 * 60 + 30:
            sess = SE_MID
        elif minute < 16 * 60:
            sess = SE_NY
        else:
            sess = SE_LATE

        if sess != self._sess_id:
            self._sess_id = sess
            self._vw_pv = 0.0
            self._vw_wt = 0.0
            self._sess_lo_prev = self._sess_lo
            self._sess_hi, self._sess_lo = bar.high, bar.low
        else:
            self._sess_lo_prev = self._sess_lo
            self._sess_hi = max(self._sess_hi, bar.high)
            self._sess_lo = min(self._sess_lo, bar.low)

        today = bar.trading_day
        if today != self._day:
            if self._day is not None:
                self._close_day()
            self._day = today
            self._prev_day_hi, self._prev_day_lo = self._cur_day_hi, self._cur_day_lo
            self._cur_day_hi, self._cur_day_lo = bar.high, bar.low
            self.day_trades = 0
            self._day_bars = 0
            self._day_equity0 = self.equity
            self._day_realised = 0.0
        else:
            self._cur_day_hi = max(self._cur_day_hi, bar.high)
            self._cur_day_lo = min(self._cur_day_lo, bar.low)
        self._day_bars += 1
        return sess

    def _close_day(self) -> None:
        """Book the day that just ended into the frequency histogram.

        Only days with a full-ish bar count are counted. A four-bar holiday
        fragment that produced no trade is not evidence that the engine is too
        selective, and letting it into the denominator would quietly flatter
        every zero-trade percentage in the report.
        """
        if self._day_bars >= self.p.min_day_bars:
            self.day_hist[min(self.day_trades, 4)] += 1
            self.normal_days += 1
            self.normal_trades += self.day_trades
            self.day_rows.append((self.day_trades, self._day_bull / self._day_bars, self._day_elig))
        else:
            self.short_days += 1
        self._day_bull = 0
        self._day_elig = 0

    def finalize(self) -> None:
        """The last day never sees a rollover bar, so it is booked by hand."""
        if self._day is not None:
            self._close_day()
            self._day = None

    # -- execution ----------------------------------------------------------------

    def _try_arm(self, bar, eligible: list[tuple[float, int, dict]]) -> None:
        p, i, f = self.p, self.i, self.f
        if self._pos is not None or self._arm is not None:
            f.block_open += 1
            return
        if self.day_trades >= p.max_per_day:
            f.block_cap += 1
            return
        day_loss = max(-self._day_realised, 0.0)
        if day_loss >= self._day_equity0 * p.day_loss / 100.0:
            f.block_loss += 1
            return
        if i - self._last_exit_bar < p.cooldown or self.pivot_count - self._pivots_at_exit < p.pivots_after:
            f.block_cool += 1
            return

        score, fam, c = max(eligible, key=lambda e: e[0])
        tier = TIER_AP if score >= p.thr_ap else TIER_A if score >= p.thr_a else TIER_BP
        tier_risk = {TIER_AP: p.risk_ap, TIER_A: p.risk_a, TIER_BP: p.risk_bp}[tier]
        n_scale = 1.0 if self.day_trades == 0 else p.scale2 if self.day_trades == 1 else p.scale3
        risk_pct = min(tier_risk * n_scale, p.risk_ceil)
        budget = self.equity * risk_pct / 100.0
        if p.scale_dd:
            # A single trade may never jump over the daily cutoff, only reach it.
            budget = min(budget, max(self._day_equity0 * p.day_loss / 100.0 - day_loss, 0.0))
        if budget <= 0.0:
            f.budget_out += 1
            return
        lots = math.floor(budget / (c["risk"] * 100.0 + p.cost_per_oz * 100.0) / 0.01) * 0.01
        if lots < 0.01:
            f.size_small += 1
            return

        self._arm = {"bar": i, "trig": c["trig"], "stop": c["stop"], "risk": c["risk"],
                     "score": score, "fam": fam, "tier": tier, "anchor": c["anchor"],
                     "sess": c["sess"], "risk_pct": risk_pct, "risk_usd": budget,
                     "trigger_close": bar.close, "stop_atr": c["risk"] / (self._atr or c["risk"])}
        f.armed += 1

    def _broker(self, bar) -> None:
        """Broker phase: manage an open position, then test a resting entry."""
        if self._pos is not None:
            self._manage(bar)
        if self._pos is None and self._arm is not None:
            a = self._arm
            if self.i > a["bar"] and bar.high >= a["trig"]:
                entry = max(a["trig"], bar.open)
                self._pos = {"entry": entry, "stop": a["stop"], "risk": a["risk"],
                             "fam": a["fam"], "tier": a["tier"], "score": a["score"],
                             "sess": a["sess"], "risk_pct": a["risk_pct"],
                             "risk_usd": a["risk_usd"], "bar": self.i, "ts": bar.ts,
                             "remaining": 1.0, "r_realised": 0.0, "partial_done": False,
                             "be_done": False, "extreme": entry, "mfe": 0.0, "mae": 0.0,
                             "trigger_close": a["trigger_close"], "stop_atr": a["stop_atr"]}
                self._last_anchor[a["fam"]] = a["anchor"]
                self.day_trades += 1
                self.f.filled += 1
                self.f.taken[a["fam"]] += 1
                self._arm = None
                # The protective stop went in with the entry, so it is live on
                # this bar too: a fill and a stop-out inside one bar is a real
                # trade, not an unfilled order.
                before = len(self.trades)
                self._manage(bar, entry_bar=True)
                if len(self.trades) > before:
                    self.f.same_bar += 1
                return
            if self.i - a["bar"] >= self.p.arm_bars:
                self.f.arm_expired += 1
                self._arm = None
            elif bar.close < a["stop"]:
                self.f.arm_voided += 1
                self._arm = None

    def _manage(self, bar, entry_bar: bool = False) -> None:
        p = self.p
        pos = self._pos
        assert pos is not None
        entry, risk = pos["entry"], pos["risk"]
        tp1 = entry + p.partial_r * risk
        tpx = entry + p.max_r * risk
        part = p.partial_pct / 100.0

        pos["mfe"] = max(pos["mfe"], bar.high - entry)
        pos["mae"] = max(pos["mae"], entry - bar.low)

        # Stop first when a bar touches both: the pessimistic reading is the
        # only honest one without tick data.
        if bar.low <= pos["stop"]:
            self._book(bar, exit_r=(pos["stop"] - entry) / risk)
            return
        if not pos["partial_done"] and bar.high >= tp1:
            pos["r_realised"] += part * p.partial_r
            pos["remaining"] -= part
            pos["partial_done"] = True
        if bar.high >= tpx:
            self._book(bar, exit_r=p.max_r)
            return

        if not pos["be_done"] and bar.close >= tp1:
            pos["be_done"] = True
            pos["extreme"] = bar.high
        if pos["be_done"]:
            pos["extreme"] = max(pos["extreme"], bar.high)
            atr = self._atr or risk
            wanted = max(pos["stop"], entry + p.cost_per_oz, pos["extreme"] - p.trail_atr * atr)
            pos["stop"] = max(pos["stop"], min(wanted, bar.close - 0.01))

    def _book(self, bar, exit_r: float) -> None:
        p = self.p
        pos = self._pos
        assert pos is not None
        r_total = pos["r_realised"] + pos["remaining"] * exit_r - p.cost_per_oz / pos["risk"]
        pnl = r_total * pos["risk_usd"]
        self.equity += pnl
        self._day_realised += pnl
        self._last_exit_bar = self.i
        self._pivots_at_exit = self.pivot_count
        self.trades.append(Trade(
            entered=pos["ts"], exited=bar.ts, family=pos["fam"], tier=pos["tier"],
            score=pos["score"], session=pos["sess"], direction=1, entry=pos["entry"],
            stop=pos["stop"], risk_px=pos["risk"], risk_pct=pos["risk_pct"],
            r_multiple=r_total, pnl=pnl,
            mfe_r=pos["mfe"] / pos["risk"], mae_r=pos["mae"] / pos["risk"],
            bars_held=self.i - pos["bar"], entry_bar=pos["bar"], exit_bar=self.i,
            stop_atr=pos["stop_atr"], trigger_close=pos["trigger_close"],
        ))
        self.f.trades += 1
        self._pos = None


def run(bars, params: Params | None = None) -> Engine:
    """Feed every bar through the engine and close the final day."""
    engine = Engine(params)
    for bar in bars:
        engine.step(bar)
    engine.finalize()
    return engine
