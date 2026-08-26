"""A faithful Python port of the CYBER MCGIVER state machine.

Purpose: answer "is the engine broken or is the setup rare?" without needing
TradingView. The port mirrors the Pine source bar for bar — same pivot
confirmation lag, same one-transition-per-bar rule, same gates in the same
order — and reports the same funnel.

It is a debugging instrument, not a backtester: fills are idealised and costs
are ignored. What it establishes is which gate rejects a candidate, which is
exactly what a zero-trade result fails to tell you.

    python -m validation.simulate            # textbook fixture + random walks
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field

Bar = tuple[float, float, float, float]  # open, high, low, close


# --------------------------------------------------------------------------
# indicators, matching Pine's definitions
# --------------------------------------------------------------------------
def ema(values: list[float], length: int) -> list[float | None]:
    out: list[float | None] = []
    alpha = 2.0 / (length + 1)
    prev: float | None = None
    for i, v in enumerate(values):
        if i + 1 < length:
            out.append(None)
            if i + 1 == length - 1:
                pass
            continue
        if prev is None:
            prev = sum(values[: length]) / length
        else:
            prev = alpha * v + (1 - alpha) * prev
        out.append(prev)
    return out


def atr_wilder(bars: list[Bar], length: int) -> list[float | None]:
    out: list[float | None] = []
    prev_close: float | None = None
    rma: float | None = None
    trs: list[float] = []
    for o, h, l, c in bars:
        tr = h - l if prev_close is None else max(h - l, abs(h - prev_close), abs(l - prev_close))
        trs.append(tr)
        if len(trs) < length:
            out.append(None)
        elif rma is None:
            rma = sum(trs[:length]) / length
            out.append(rma)
        else:
            rma = (rma * (length - 1) + tr) / length
            out.append(rma)
        prev_close = c
    return out


def pivot_low(bars: list[Bar], i: int, left: int, right: int) -> bool:
    """True when bar i is a confirmed pivot low, judged at bar i + right."""
    if i - left < 0 or i + right >= len(bars):
        return False
    low = bars[i][2]
    for j in range(i - left, i + right + 1):
        if j != i and bars[j][2] <= low:
            return False
    return True


def pivot_high(bars: list[Bar], i: int, left: int, right: int) -> bool:
    if i - left < 0 or i + right >= len(bars):
        return False
    high = bars[i][1]
    for j in range(i - left, i + right + 1):
        if j != i and bars[j][1] >= high:
            return False
    return True


# --------------------------------------------------------------------------
# funnel
# --------------------------------------------------------------------------
@dataclass
class Funnel:
    bars: int = 0
    regime_long: int = 0
    regime_short: int = 0
    bos: int = 0
    p1: int = 0
    p2_qualified: int = 0
    candidates: int = 0
    p3_tested: int = 0
    p3_miss_tol: int = 0
    p3_miss_close: int = 0
    p3_best: float = 999.0
    p3: int = 0
    t4_near: int = 0
    t4_contact: int = 0
    t4_miss_close: int = 0
    t4: int = 0
    rej_dir: int = 0
    rej_body: int = 0
    rej_clv: int = 0
    rejections: int = 0
    regime_blocked: int = 0
    skip_stop: int = 0
    skip_size: int = 0
    armed: int = 0
    filled: int = 0
    reanchor: int = 0
    kill_build: int = 0
    kill_expiry: int = 0
    expired_below: int = 0
    expired_above: int = 0
    p3_gap_total: int = 0
    slope_total: float = 0.0
    notes: list[str] = field(default_factory=list)

    def report(self) -> str:
        rows = [
            ("bars", self.bars), ("regime LONG bars", self.regime_long),
            ("regime SHORT bars", self.regime_short), ("BOS", self.bos),
            ("P1", self.p1), ("P2 qualified", self.p2_qualified),
            ("candidate lines", self.candidates),
            ("P3 tested", self.p3_tested), ("  missed tolerance", self.p3_miss_tol),
            ("  wrong close", self.p3_miss_close),
            ("  closest miss (ATR)", round(self.p3_best, 3) if self.p3_best < 900 else "n/a"),
            ("P3 confirmed", self.p3),
            ("T4 near line", self.t4_near), ("T4 contact", self.t4_contact),
            ("  wrong close", self.t4_miss_close), ("T4 events", self.t4),
            ("  rej fail direction", self.rej_dir), ("  rej fail body", self.rej_body),
            ("  rej fail close loc", self.rej_clv),
            ("valid rejections", self.rejections),
            ("blocked · regime at entry", self.regime_blocked),
            ("skipped · stop > max ATR", self.skip_stop),
            ("skipped · size", self.skip_size),
            ("ARMED", self.armed), ("FILLED", self.filled),
            ("re-anchored", self.reanchor), ("killed · build timeout", self.kill_build),
            ("killed · line expired", self.kill_expiry),
            ("  price BELOW line at expiry", self.expired_below),
            ("  price above line at expiry", self.expired_above),
            ("avg P2→P3 gap (bars)", round(self.p3_gap_total / max(self.p3, 1), 1)),
            ("avg confirmed slope (ATR/bar)", round(self.slope_total / max(self.p3, 1), 4)),
        ]
        width = max(len(r[0]) for r in rows)
        return "\n".join(f"  {name:<{width}}  {value}" for name, value in rows)


# --------------------------------------------------------------------------
# the state machine
# --------------------------------------------------------------------------
WAIT_BOS, WAIT_P1, WAIT_P2, CANDIDATE, CONFIRMED, ARMED, OPEN = range(7)


def run(
    bars: list[Bar],
    regime: list[int],
    *,
    piv_left: int = 2,
    piv_right: int = 2,
    atr_len: int = 14,
    bos_buf: float = 0.05,
    min_sep: float = 0.10,
    tol: float = 0.12,
    slope_max: float = 0.25,
    build_expiry: int = 60,
    tl_expiry: int = 20,
    body_min: float = 0.35,
    clv_min: float = 0.65,
    stop_buf: float = 0.10,
    max_stop_atr: float = 3.0,
    equity: float = 100_000.0,
    contract: float = 100.0,
    cost_per_lot: float = 57.0,
    min_lot: float = 0.01,
    lot_step: float = 0.01,
    p3_pivot_only: bool = False,   # matches the Pine default
    p3_min_gap: int = 0,
) -> Funnel:
    """One pass over the series, mirroring the Pine bar loop."""
    f = Funnel()
    atr = atr_wilder(bars, atr_len)

    state = WAIT_BOS
    direction = 0
    bos_bar = 0
    p1 = p2 = p3 = None  # (bar, price)
    slope = 0.0
    confirm_bar = 0
    arm_bar = 0
    swing_high: float | None = None
    swing_low: float | None = None

    def tl_at(bar: int) -> float:
        return p2[1] + slope * (bar - p2[0])

    for i in range(len(bars)):
        a = atr[i]
        if a is None or a <= 0:
            continue
        f.bars += 1
        mode = regime[i]
        if mode == 1:
            f.regime_long += 1
        elif mode == -1:
            f.regime_short += 1

        o, h, l, c = bars[i]

        # --- confirmed pivots, exactly as ta.pivotlow/high report them -------
        pb = i - piv_right
        has_pl = pb >= 0 and pivot_low(bars, pb, piv_left, piv_right)
        has_ph = pb >= 0 and pivot_high(bars, pb, piv_left, piv_right)
        if has_ph:
            swing_high = bars[pb][1]
        if has_pl:
            swing_low = bars[pb][2]

        # --- invalidation ----------------------------------------------------
        if state in (WAIT_P1, WAIT_P2, CANDIDATE) and (i - bos_bar) > build_expiry:
            f.kill_build += 1
            state, direction = WAIT_BOS, 0
            continue
        if state == CONFIRMED and (i - confirm_bar) > tl_expiry:
            f.kill_expiry += 1
            line_now = tl_at(i)
            if (c < line_now) if direction == 1 else (c > line_now):
                f.expired_below += 1
            else:
                f.expired_above += 1
            state, direction = WAIT_BOS, 0
            continue

        # --- one transition per bar, same order as the Pine chain ------------
        if state == WAIT_BOS and mode != 0:
            if mode == 1 and swing_high is not None and c > swing_high + bos_buf * a:
                direction, bos_bar, state = 1, i, WAIT_P1
                swing_high = None
                f.bos += 1
            elif mode == -1 and swing_low is not None and c < swing_low - bos_buf * a:
                direction, bos_bar, state = -1, i, WAIT_P1
                swing_low = None
                f.bos += 1

        elif state == WAIT_P1:
            got = has_pl if direction == 1 else has_ph
            if got and pb >= bos_bar:
                p1 = (pb, bars[pb][2] if direction == 1 else bars[pb][1])
                state = WAIT_P2
                f.p1 += 1

        elif state == WAIT_P2:
            got = has_pl if direction == 1 else has_ph
            if got and pb > p1[0]:
                pv = bars[pb][2] if direction == 1 else bars[pb][1]
                wrong = pv <= p1[1] if direction == 1 else pv >= p1[1]
                sep = (pv - p1[1]) if direction == 1 else (p1[1] - pv)
                if wrong:
                    p1 = (pb, pv)
                elif sep >= min_sep * a:
                    f.p2_qualified += 1
                    m = (pv - p1[1]) / max(pb - p1[0], 1)
                    mn = abs(m / a)
                    sign_ok = m > 0 if direction == 1 else m < 0
                    if sign_ok and mn <= slope_max:
                        p2, slope, state = (pb, pv), m, CANDIDATE
                        f.candidates += 1
                    else:
                        p1 = (pb, pv)
                        f.reanchor += 1

        elif state == CANDIDATE:
            if p3_pivot_only:
                got = has_pl if direction == 1 else has_ph
                cand_bar = pb
            else:
                # Touch #4 is tested on ANY bar that returns to the line. S31
                # never says touch #3 must be a pivot; testing it only on pivot
                # bars asks the line and the pivot to coincide, which is a much
                # narrower event than a touch.
                got = i > p2[0] + piv_right
                cand_bar = i
            if got and cand_bar > p2[0]:
                pb = cand_bar
                line = tl_at(pb)
                wick = bars[pb][2] if direction == 1 else bars[pb][1]
                pclose = bars[pb][3]
                contact = abs(wick - line) <= tol * a
                holds = pclose > line if direction == 1 else pclose < line
                through = wick < line - tol * a if direction == 1 else wick > line + tol * a
                f.p3_tested += 1
                f.p3_best = min(f.p3_best, abs(wick - line) / a)
                if not contact:
                    f.p3_miss_tol += 1
                elif not holds:
                    f.p3_miss_close += 1
                if contact and holds and (pb - p2[0]) >= p3_min_gap:
                    p3, confirm_bar, state = (pb, wick), i, CONFIRMED
                    f.p3 += 1
                    f.p3_gap_total += pb - p2[0]
                    f.slope_total += abs(slope / a)
                elif through:
                    p1, state = (pb, wick), WAIT_P2
                    f.reanchor += 1

        elif state == CONFIRMED and i > confirm_bar:
            line = tl_at(i)
            wick = l if direction == 1 else h
            miss = abs(wick - line) / a
            contact = miss <= tol
            holds = c > line if direction == 1 else c < line
            if miss <= tol * 3:
                f.t4_near += 1
            if contact:
                f.t4_contact += 1
                if not holds:
                    f.t4_miss_close += 1
            if contact and holds:
                f.t4 += 1
                rng = max(h - l, 0.01)
                body = abs(c - o) / rng
                clv = (c - l) / rng if direction == 1 else (h - c) / rng
                directional = c > o if direction == 1 else c < o
                if not directional:
                    f.rej_dir += 1
                elif body < body_min:
                    f.rej_body += 1
                elif clv < clv_min:
                    f.rej_clv += 1
                else:
                    if mode != direction:
                        f.regime_blocked += 1
                    else:
                        f.rejections += 1
                        entry = h + 0.01 if direction == 1 else l - 0.01
                        stop = (p3[1] - stop_buf * a) if direction == 1 else (p3[1] + stop_buf * a)
                        risk = entry - stop if direction == 1 else stop - entry
                        if risk <= 0 or risk / a > max_stop_atr:
                            f.skip_stop += 1
                        else:
                            per_lot = risk * contract + cost_per_lot
                            lots = math.floor((equity * 0.01) / per_lot / lot_step + 1e-9) * lot_step
                            if lots < min_lot:
                                f.skip_size += 1
                            else:
                                f.armed += 1
                                state, arm_bar = ARMED, i
                                arm_entry, arm_stop = entry, stop

        elif state == ARMED:
            hit = bars[i][1] >= arm_entry if direction == 1 else bars[i][2] <= arm_entry
            if hit:
                f.filled += 1
                state, direction = WAIT_BOS, 0
            elif i - arm_bar >= 3:
                state, direction = WAIT_BOS, 0

    return f


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------
def textbook_series(cycles: int = 40, slope: float = 0.30) -> list[Bar]:
    """A series built to contain nothing BUT the setup the spec describes.

    Every tenth bar dips to touch a rising line exactly and closes near its
    high with a large body — a textbook Touch. If the engine cannot trade
    this, the engine is broken; no property of real gold is involved.
    """
    bars: list[Bar] = []
    offsets = [3.0, 2.5, 2.0, 1.5, None, 1.5, 2.0, 2.5, 3.0, 3.5]
    for i in range(cycles * 10):
        line = 2000.0 + slope * i
        off = offsets[i % 10]
        if off is None:  # the touch bar
            low = line
            close = line + 2.5
            bars.append((line + 0.3, line + 2.7, low, close))
        else:
            mid = line + off
            bars.append((mid - 0.4, mid + 1.2, mid - 1.2, mid + 0.5))
    return bars


def random_series(n: int = 40_000, seed: int = 7, drift: float = 0.02) -> list[Bar]:
    """A drifting random walk: no engineered structure, realistic noise."""
    rng = random.Random(seed)
    bars: list[Bar] = []
    price = 2000.0
    for _ in range(n):
        step = rng.gauss(drift, 1.4)
        o = price
        c = price + step
        hi = max(o, c) + abs(rng.gauss(0, 0.9))
        lo = min(o, c) - abs(rng.gauss(0, 0.9))
        bars.append((o, hi, lo, c))
        price = c
    return bars


def regime_from_emas(bars: list[Bar], mult: int, fast: int, slow: int, look: int) -> list[int]:
    """Approximate one higher timeframe by resampling closes every `mult` bars."""
    closes = [b[3] for b in bars]
    sampled = closes[::mult]
    ef = ema(sampled, fast)
    es = ema(sampled, slow)
    out: list[int] = []
    for i in range(len(bars)):
        k = i // mult - 1  # only the CLOSED higher-timeframe bar, as Pine does
        if k < look or k >= len(ef) or ef[k] is None or es[k] is None or ef[k - look] is None:
            out.append(0)
            continue
        c, f_, s_, fp = sampled[k], ef[k], es[k], ef[k - look]
        if c > s_ and f_ > s_ and f_ > fp:
            out.append(1)
        elif c < s_ and f_ < s_ and f_ < fp:
            out.append(-1)
        else:
            out.append(0)
    return out


def unanimous(bars: list[Bar]) -> list[int]:
    """1D + 4H + 1H on a 15m chart: 96, 16 and 4 bars per higher-timeframe bar."""
    d = regime_from_emas(bars, 96, 50, 200, 5)
    h4 = regime_from_emas(bars, 16, 20, 50, 3)
    h1 = regime_from_emas(bars, 4, 20, 50, 3)
    return [d[i] if d[i] == h4[i] == h1[i] else 0 for i in range(len(bars))]


if __name__ == "__main__":
    print("=" * 72)
    print("FIXTURE 1 — textbook setup, regime forced LONG")
    print("If this does not produce a fill, the engine is broken.")
    print("=" * 72)
    bars = textbook_series()
    print(run(bars, [1] * len(bars)).report())

    print()
    print("=" * 72)
    print("FIXTURE 2 — drifting random walk, regime forced LONG")
    print("Isolates the structure engine from the regime gate.")
    print("=" * 72)
    bars = random_series()
    print(run(bars, [1] * len(bars)).report())

    print()
    print("=" * 72)
    print("FIXTURE 3 — drifting random walk, real unanimous 1D/4H/1H gate")
    print("=" * 72)
    print(run(bars, unanimous(bars)).report())
