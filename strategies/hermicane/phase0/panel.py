"""The event panel (§3.2) — one row per historical release.

Everything the ablation needs is computed once, here, and everything computed
here is either strictly pre-release or strictly post-release. The two are kept
apart in the row's field groups because the whole value of the panel is that a
filter written against the "regime" group cannot accidentally read the
"reaction" group.

The z-scored surprise deserves its own note, because it fixes a real bug rather
than a stylistic one. v1 divides every surprise by a single global
`surpriseUnit` whose default is 0.20. That is roughly sane for CPI in percent
and absurd for Jobless Claims in thousands, GDP, ISM, Retail Sales and JOLTS —
all of which saturate the ratio instantly and pin themselves at 10/10 on every
release. Dividing instead by the rolling standard deviation of the last twenty
surprises *of the same event type* puts every release on one comparable scale
and removes the input entirely.

Three structural choices are made here, flagged the same way `control` flags
its own, and listed by `report.py` under structural rather than calibrated:

1. **Impulse is measured T+0 → T+3**, matching v1's three-minute window, and
   against the pre-news level defined as the close of the last bar before the
   release.
2. **The pullback and breakout are searched for over the thirty minutes after
   the impulse.** v1 implies a timeout without fixing one.
3. **The surprise z-score uses a twenty-release lookback**, per §3.2's "~20".
   Fewer than five prior releases of a type yields NaN, not a guess.
"""

from __future__ import annotations

import bisect
import math
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

from .beta import BetaFit, DailyObservation, fit_prepared, prepare
from .control import (
    ControlResult,
    ControlSpec,
    average_true_range,
    control_direction,
    simulate,
    simulate_breakout,
)
from .loaders import Bar, BarSeries, MacroEvent

NAN = float("nan")

NEW_YORK = ZoneInfo("America/New_York")

#: §3.2's reaction grid.
REACTION_HORIZONS = (1, 3, 5, 15, 30, 60, 120)

#: Structural choices, not calibrated constants.
IMPULSE_MINUTES = 3
PULLBACK_SEARCH_MINUTES = 30
SURPRISE_LOOKBACK = 20
MIN_SURPRISE_HISTORY = 5
BREAKOUT_LOOKBACK_BARS = 3

#: Pre-event drift horizons from §3.2, in minutes.
DRIFT_HORIZONS = {"60m": 60, "4h": 240, "1d": 1440}

#: Reasons a row carries no tradable outcome. Kept as flags on the row rather
#: than as dropped rows, because §3.3's control has to know how many events it
#: could not evaluate and why.
FLAG_NO_PRICE = "no_price_data"
FLAG_NO_YIELD = "no_yield_data"
FLAG_NO_CONSENSUS = "no_consensus"
FLAG_NO_ATR = "no_atr"
FLAG_NO_SURPRISE_HISTORY = "no_surprise_history"
FLAG_NO_BETA = "no_beta"
FLAG_NO_DXY = "no_dxy"


@dataclass(frozen=True)
class EventRow:
    """One release. Field groups are ordered pre-event, then post-event."""

    # --- identity ---------------------------------------------------------
    ts_utc: datetime
    ts_ny: datetime
    event_type: str
    actual: float
    consensus: float
    consensus_sd: float

    # --- surprise ---------------------------------------------------------
    surprise_raw: float
    surprise_z: float

    # --- regime, measured strictly before the release ---------------------
    beta_fits: dict[int, BetaFit]
    realised_vol_20d: float
    atr: float
    drift_atr: dict[str, float]
    trend_15m: int
    trend_1h: int

    # --- reaction, measured strictly after --------------------------------
    d_yield: dict[int, float]
    d_dxy: dict[int, float]
    d_xau: dict[int, float]
    impulse_atr: float
    impulse_dir: int
    pullback_frac: float
    origin_held: bool
    micro_breakout: bool
    breakout_minute: float
    #: Causal versions of the retracement description: what a delayed entry
    #: actually knows at the moment it breaks structure. The plain
    #: `pullback_frac` above spans the whole window and is NOT knowable at T+3.
    pullback_at_breakout: float
    origin_held_at_breakout: bool
    macro_aligned: float
    five_min_dir: int

    # --- outcome ----------------------------------------------------------
    predicted_dir: int
    fwd_r: dict[int, float]
    #: The §3.3 control: entry at T+3, unconditionally.
    control: ControlResult
    #: v1's actual entry: wait for the break of structure. Carried alongside so
    #: the two entry rules can be compared head to head, which is the only
    #: causal way to ask whether the pullback machinery earns its place.
    control_breakout: ControlResult
    flags: tuple[str, ...] = ()

    @property
    def is_evaluable(self) -> bool:
        """Does this row carry a control outcome the ablation can use?"""
        return self.control.traded and not math.isnan(self.control.r_multiple)

    @property
    def is_evaluable_breakout(self) -> bool:
        return self.control_breakout.traded and not math.isnan(self.control_breakout.r_multiple)

    def outcome(self, entry_mode: str) -> ControlResult:
        return self.control_breakout if entry_mode == "breakout" else self.control

    def beta(self, window: int) -> BetaFit | None:
        return self.beta_fits.get(window)

    def as_dict(self) -> dict[str, object]:
        """Flat mapping, suitable for CSV or a parquet writer."""
        out: dict[str, object] = {
            "ts_utc": self.ts_utc.isoformat(),
            "ts_ny": self.ts_ny.isoformat(),
            "event_type": self.event_type,
            "actual": self.actual,
            "consensus": self.consensus,
            "consensus_sd": self.consensus_sd,
            "surprise_raw": self.surprise_raw,
            "surprise_z": self.surprise_z,
            "realised_vol_20d": self.realised_vol_20d,
            "atr": self.atr,
            "trend_15m": self.trend_15m,
            "trend_1h": self.trend_1h,
            "impulse_atr": self.impulse_atr,
            "impulse_dir": self.impulse_dir,
            "pullback_frac": self.pullback_frac,
            "origin_held": self.origin_held,
            "micro_breakout": self.micro_breakout,
            "breakout_minute": self.breakout_minute,
            "pullback_at_breakout": self.pullback_at_breakout,
            "origin_held_at_breakout": self.origin_held_at_breakout,
            "macro_aligned": self.macro_aligned,
            "five_min_dir": self.five_min_dir,
            "predicted_dir": self.predicted_dir,
            "flags": "|".join(self.flags),
        }
        for window, fit in sorted(self.beta_fits.items()):
            out[f"beta_{window}"] = fit.beta
            out[f"beta_r2_{window}"] = fit.r_squared
            out[f"beta_t_{window}"] = fit.t_stat
        for label, value in self.drift_atr.items():
            out[f"drift_atr_{label}"] = value
        for horizon in REACTION_HORIZONS:
            out[f"d_yield_{horizon}m"] = self.d_yield.get(horizon, NAN)
            out[f"d_dxy_{horizon}m"] = self.d_dxy.get(horizon, NAN)
            out[f"d_xau_{horizon}m"] = self.d_xau.get(horizon, NAN)
        for horizon, value in sorted(self.fwd_r.items()):
            out[f"fwd_r_{horizon}m"] = value
        for key, value in self.control.as_dict().items():
            out[f"control_{key}"] = value
        for key, value in self.control_breakout.as_dict().items():
            out[f"breakout_{key}"] = value
        return out


def resample(bars: BarSeries, minutes: int) -> BarSeries:
    """Aggregate 1-minute bars into `minutes`-minute bars on wall-clock boundaries.

    Boundaries are absolute (12:00, 12:15, …) rather than relative to the first
    bar, so the 15-minute series does not shift when the loaded history starts
    at a different minute.
    """
    buckets: dict[datetime, list[Bar]] = {}
    for bar in bars.bars:
        epoch_minutes = int(bar.ts.timestamp() // 60)
        anchor = datetime.fromtimestamp((epoch_minutes // minutes) * minutes * 60, tz=UTC)
        buckets.setdefault(anchor, []).append(bar)
    aggregated = [
        Bar(
            ts=anchor,
            open=group[0].open,
            high=max(b.high for b in group),
            low=min(b.low for b in group),
            close=group[-1].close,
            volume=sum(b.volume for b in group if not math.isnan(b.volume)),
        )
        for anchor, group in sorted(buckets.items())
    ]
    return BarSeries(bars.symbol, aggregated, minutes * 60)


def ema(values: list[float], length: int) -> float:
    """Final EMA value of a series. NaN when there is not a full length of it."""
    if len(values) < length:
        return NAN
    alpha = 2.0 / (length + 1)
    running = sum(values[:length]) / length
    for value in values[length:]:
        running = alpha * value + (1 - alpha) * running
    return running


def closed_before(higher: BarSeries, before: datetime, count: int) -> list[float]:
    """The last `count` closes of bars that had *closed* by `before`.

    A bar stamped 12:15 on a 15-minute series is still forming at 12:20, so the
    admissible bars are those whose stamp is at or before `before` minus one
    bar length. Bisecting a pre-built higher timeframe keeps this O(log n) per
    event instead of rescanning five years of bars for every release.
    """
    cutoff = before - timedelta(seconds=higher.timeframe_seconds)
    hi = bisect.bisect_right(higher._stamps, cutoff)
    if hi <= 0:
        return []
    return [b.close for b in higher.bars[max(0, hi - count):hi]]


def trend_state(higher: BarSeries, before: datetime, fast: int = 20, slow: int = 50) -> int:
    """+1 when EMA20 > EMA50, -1 when below, 0 when undecidable.

    Takes an already-resampled series so the caller resamples once per panel
    rather than once per event. Uses only bars that closed strictly before
    `before`, so a release at 12:30 never reads the bar it is about to move.
    """
    closes = closed_before(higher, before, slow * 4)
    if len(closes) < slow:
        return 0
    fast_value = ema(closes, fast)
    slow_value = ema(closes, slow)
    if math.isnan(fast_value) or math.isnan(slow_value):
        return 0
    return 1 if fast_value > slow_value else -1


def prepare_daily(observations: list[DailyObservation]) -> tuple[list, list]:
    """Sorted (dates, gold closes), computed once per panel."""
    ordered = sorted(observations, key=lambda o: o.day)
    return [o.day for o in ordered], [o.gold_close for o in ordered]


def realised_vol(prepared: tuple[list, list], as_of: datetime, days: int = 20) -> float:
    """Standard deviation of daily gold log returns over the `days` before the event.

    `prepared` is the (dates, closes) pair from `prepare_daily`, sorted once per
    panel so this is a bisection rather than a re-sort per event.
    """
    dates, all_closes = prepared
    cut = bisect.bisect_left(dates, as_of.date())
    if cut < days + 1:
        return NAN
    closes = all_closes[:cut]
    window = closes[-(days + 1):]
    returns = [
        math.log(later / earlier)
        for earlier, later in zip(window, window[1:])
        if earlier > 0 and later > 0
    ]
    if len(returns) < 2:
        return NAN
    mean_return = sum(returns) / len(returns)
    variance = sum((r - mean_return) ** 2 for r in returns) / (len(returns) - 1)
    return math.sqrt(variance)


def rolling_surprise_z(
    event: MacroEvent,
    history: list[MacroEvent],
    lookback: int = SURPRISE_LOOKBACK,
) -> float:
    """Surprise divided by the dispersion of recent surprises of the same type.

    `history` must contain only releases strictly before this one; the caller
    guarantees that, and the function does not re-sort or re-filter, so the
    lookahead guarantee lives in one place (`build_panel`) rather than two.
    """
    if not event.has_consensus:
        return NAN
    prior = [
        e.surprise_raw
        for e in history
        if e.event_type == event.event_type and e.has_consensus
    ][-lookback:]
    if len(prior) < MIN_SURPRISE_HISTORY:
        return NAN
    mean_prior = sum(prior) / len(prior)
    variance = sum((s - mean_prior) ** 2 for s in prior) / (len(prior) - 1)
    dispersion = math.sqrt(variance)
    if dispersion <= 0:
        return NAN
    return event.surprise_raw / dispersion


def _close_at(series: BarSeries | None, when: datetime) -> float:
    if series is None:
        return NAN
    bar = series.bar_at_or_after(when, tolerance_minutes=2)
    return NAN if bar is None or math.isnan(bar.close) else bar.close


def _delta_grid(series: BarSeries | None, event_ts: datetime) -> dict[int, float]:
    """Change from T+0 to each reaction horizon."""
    base = _close_at(series, event_ts)
    if math.isnan(base):
        return {h: NAN for h in REACTION_HORIZONS}
    return {
        h: (_close_at(series, event_ts + timedelta(minutes=h)) - base)
        for h in REACTION_HORIZONS
    }


@dataclass
class ImpulseShape:
    """The v1 price-action sequence, measured rather than asserted.

    Two versions of the pullback are carried, and the distinction is the whole
    reason this class exists in this shape:

    * `pullback_frac` and `origin_held` describe the **entire** search window.
      They are the honest description of what the retracement did, and they are
      **not knowable at T+3**. Filtering a T+3 entry on them reads the future.
    * `pullback_at_breakout` and `origin_held_at_breakout` are measured only up
      to the bar that broke structure. They are what a delayed entry actually
      knows when it places the order, and they are the only versions any filter
      may use.
    """

    pre_news: float = NAN
    impulse_atr: float = NAN
    direction: int = 0
    extreme: float = NAN
    pullback_frac: float = NAN
    origin_held: bool = False
    breakout: bool = False
    breakout_minute: float = NAN
    breakout_ts: datetime | None = None
    pullback_at_breakout: float = NAN
    origin_held_at_breakout: bool = False


def measure_impulse(prices: BarSeries, event_ts: datetime, atr: float) -> ImpulseShape:
    """Impulse extent, pullback depth, origin hold and micro breakout.

    The sequence mirrors v1 so that the ablation is testing v1's actual filters
    and not a charitable reimagining of them: a three-minute impulse away from
    the pre-news level, a retracement of it, a check that the pre-news level
    survived the retracement, and a break of the recent extreme in the impulse
    direction.
    """
    shape = ImpulseShape()
    if math.isnan(atr) or atr <= 0:
        return shape
    previous = prices.window(event_ts - timedelta(minutes=5), event_ts)
    if not previous:
        return shape
    shape.pre_news = previous[-1].close
    if math.isnan(shape.pre_news):
        return shape

    impulse_bars = prices.window(event_ts, event_ts + timedelta(minutes=IMPULSE_MINUTES))
    if not impulse_bars:
        return shape
    high = max(b.high for b in impulse_bars)
    low = min(b.low for b in impulse_bars)
    up_extent = high - shape.pre_news
    down_extent = shape.pre_news - low
    if up_extent <= 0 and down_extent <= 0:
        return shape
    shape.direction = 1 if up_extent >= down_extent else -1
    shape.extreme = high if shape.direction > 0 else low
    shape.impulse_atr = max(up_extent, down_extent) / atr
    span = abs(shape.extreme - shape.pre_news)
    if span <= 0:
        return shape

    search = prices.window(
        event_ts + timedelta(minutes=IMPULSE_MINUTES),
        event_ts + timedelta(minutes=IMPULSE_MINUTES + PULLBACK_SEARCH_MINUTES),
    )
    if not search:
        return shape

    # Deepest retracement, and whether the pre-news level survived it.
    retrace_extreme = min(b.low for b in search) if shape.direction > 0 else max(b.high for b in search)
    shape.pullback_frac = abs(shape.extreme - retrace_extreme) / span
    shape.origin_held = (
        retrace_extreme > shape.pre_news if shape.direction > 0 else retrace_extreme < shape.pre_news
    )

    # Micro-structure breakout: the first bar that takes out the prior
    # BREAKOUT_LOOKBACK_BARS extreme in the impulse direction.
    #
    # The scan below walks forward once, tracking the retracement as it deepens
    # and testing for a break of the prior extreme on every bar. Doing it in one
    # pass is what makes the "at breakout" measurements causal: at the bar that
    # breaks, `running_extreme` holds only what had already happened.
    running_extreme = search[0].low if shape.direction > 0 else search[0].high
    for i, bar in enumerate(search):
        running_extreme = (
            min(running_extreme, bar.low) if shape.direction > 0 else max(running_extreme, bar.high)
        )
        if i < BREAKOUT_LOOKBACK_BARS:
            continue
        window = search[i - BREAKOUT_LOOKBACK_BARS:i]
        broke = (
            bar.high > max(b.high for b in window)
            if shape.direction > 0
            else bar.low < min(b.low for b in window)
        )
        if not broke:
            continue
        shape.breakout = True
        shape.breakout_minute = (bar.ts - event_ts).total_seconds() / 60.0
        shape.breakout_ts = bar.ts
        shape.pullback_at_breakout = abs(shape.extreme - running_extreme) / span
        shape.origin_held_at_breakout = (
            running_extreme > shape.pre_news
            if shape.direction > 0
            else running_extreme < shape.pre_news
        )
        break
    return shape


def five_minute_direction(five: BarSeries, before: datetime) -> int:
    """Direction of the last 5-minute bar to have *closed* before `before`.

    The `+ timedelta(minutes=5) <= before` test is the whole point of this
    function. v1 asks Pine for 5-minute data with no offset, which returns the
    last closed bar when replaying history and the still-forming bar in real
    time — two different strategies wearing one name (§4.2 item 5). Here the
    bar must have closed, in backtest and in principle alike.
    """
    cutoff = before - timedelta(seconds=five.timeframe_seconds)
    hi = bisect.bisect_right(five._stamps, cutoff)
    if hi <= 0:
        return 0
    last = five.bars[hi - 1]
    if math.isnan(last.close) or math.isnan(last.open) or last.close == last.open:
        return 0
    return 1 if last.close > last.open else -1


def macro_alignment(d_yield: float, d_dxy: float, direction: int) -> float:
    """Share of the two macro legs agreeing with `direction` on gold.

    Retained only so §3.4 can ablate it. §1's argument that this is not
    independent confirmation — gold, DXY and the 2Y all reprice off the same
    headline in the same second — is a claim the ablation should be allowed to
    test rather than one the harness should assume.
    """
    if direction == 0:
        return NAN
    legs = []
    if not math.isnan(d_yield):
        legs.append(1.0 if (d_yield < 0) == (direction > 0) else 0.0)
    if not math.isnan(d_dxy):
        legs.append(1.0 if (d_dxy < 0) == (direction > 0) else 0.0)
    if not legs:
        return NAN
    return sum(legs) / len(legs)


@dataclass
class PanelInputs:
    """Everything `build_panel` needs, with the optional legs explicitly optional."""

    events: list[MacroEvent]
    prices: BarSeries
    yields: BarSeries
    daily: list[DailyObservation]
    dxy: BarSeries | None = None
    spec: ControlSpec = field(default_factory=ControlSpec)


def build_panel(inputs: PanelInputs) -> list[EventRow]:
    """One row per event, in chronological order.

    Every backward-looking feature is computed from `history`, the slice of
    events strictly before the current one, and every forward-looking feature
    from bars at or after the release. That boundary is enforced here so no
    individual feature function has to be trusted with it.
    """
    rows: list[EventRow] = []
    ordered = sorted(inputs.events, key=lambda e: e.ts_utc)

    # Everything derived from the whole history is built once. Doing it per
    # event turns a five-year panel into an overnight job.
    five_minute = resample(inputs.prices, 5)
    atr_series = resample(inputs.prices, inputs.spec.atr_timeframe_minutes)
    fifteen_minute = resample(inputs.prices, 15)
    hourly = resample(inputs.prices, 60)
    changes = prepare(inputs.daily)
    daily_closes = prepare_daily(inputs.daily)

    for position, event in enumerate(ordered):
        history = ordered[:position]
        flags: list[str] = []

        atr = average_true_range(atr_series, event.ts_utc, inputs.spec.atr_periods)
        if math.isnan(atr):
            flags.append(FLAG_NO_ATR)

        if not event.has_consensus:
            flags.append(FLAG_NO_CONSENSUS)
        surprise_z = rolling_surprise_z(event, history)
        if math.isnan(surprise_z) and event.has_consensus:
            flags.append(FLAG_NO_SURPRISE_HISTORY)

        beta_fits = {
            window: fit_prepared(changes, event.ts_utc.date(), window)
            for window in (60, 90, 120)
        }
        if all(math.isnan(fit.beta) for fit in beta_fits.values()):
            flags.append(FLAG_NO_BETA)

        drift = {}
        for label, minutes in DRIFT_HORIZONS.items():
            then = _close_at(inputs.prices, event.ts_utc - timedelta(minutes=minutes))
            now = _close_at(inputs.prices, event.ts_utc - timedelta(minutes=1))
            drift[label] = (
                (now - then) / atr if not math.isnan(then) and not math.isnan(now) and atr > 0 else NAN
            )

        d_yield = _delta_grid(inputs.yields, event.ts_utc)
        d_dxy = _delta_grid(inputs.dxy, event.ts_utc)
        d_xau = _delta_grid(inputs.prices, event.ts_utc)
        if math.isnan(d_yield.get(inputs.spec.entry_offset_minutes, NAN)):
            flags.append(FLAG_NO_YIELD)
        if inputs.dxy is None:
            flags.append(FLAG_NO_DXY)
        if math.isnan(d_xau.get(inputs.spec.entry_offset_minutes, NAN)):
            flags.append(FLAG_NO_PRICE)

        shape = measure_impulse(inputs.prices, event.ts_utc, atr)
        direction = control_direction(d_yield.get(inputs.spec.entry_offset_minutes, NAN))
        result = simulate(inputs.prices, event.ts_utc, direction, atr, inputs.spec)
        # The delayed entry only makes sense as a continuation of the impulse,
        # so it trades the impulse direction and requires it to agree with the
        # 2Y. A disagreement is a non-trade, not a reversal.
        breakout_dir = direction if shape.direction == direction else 0
        breakout_result = simulate_breakout(
            inputs.prices, shape.breakout_ts, breakout_dir, atr, inputs.spec
        )

        fwd_r: dict[int, float] = {}
        for horizon in REACTION_HORIZONS:
            move = d_xau.get(horizon, NAN)
            fwd_r[horizon] = (
                direction * move / atr
                if direction != 0 and not math.isnan(move) and atr > 0
                else NAN
            )

        rows.append(
            EventRow(
                ts_utc=event.ts_utc,
                ts_ny=event.ts_utc.astimezone(NEW_YORK),
                event_type=event.event_type,
                actual=event.actual,
                consensus=event.consensus,
                consensus_sd=event.consensus_sd,
                surprise_raw=event.surprise_raw,
                surprise_z=surprise_z,
                beta_fits=beta_fits,
                realised_vol_20d=realised_vol(daily_closes, event.ts_utc),
                atr=atr,
                drift_atr=drift,
                trend_15m=trend_state(fifteen_minute, event.ts_utc),
                trend_1h=trend_state(hourly, event.ts_utc),
                d_yield=d_yield,
                d_dxy=d_dxy,
                d_xau=d_xau,
                impulse_atr=shape.impulse_atr,
                impulse_dir=shape.direction,
                pullback_frac=shape.pullback_frac,
                origin_held=shape.origin_held,
                micro_breakout=shape.breakout,
                breakout_minute=shape.breakout_minute,
                pullback_at_breakout=shape.pullback_at_breakout,
                origin_held_at_breakout=shape.origin_held_at_breakout,
                macro_aligned=macro_alignment(
                    d_yield.get(inputs.spec.entry_offset_minutes, NAN),
                    d_dxy.get(inputs.spec.entry_offset_minutes, NAN),
                    direction,
                ),
                five_min_dir=five_minute_direction(
                    five_minute,
                    event.ts_utc + timedelta(minutes=inputs.spec.entry_offset_minutes),
                ),
                predicted_dir=direction,
                fwd_r=fwd_r,
                control=result,
                control_breakout=breakout_result,
                flags=tuple(flags),
            )
        )
    return rows
