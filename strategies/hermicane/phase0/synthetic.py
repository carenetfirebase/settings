"""A synthetic world for exercising the harness — NOT a source of constants.

Everything this module produces is labelled synthetic at every layer: the
`Provenance` it returns records origin ``synthetic`` for every series, and
`report.py` refuses to emit `calibrated_constants.json` from a provenance that
is not entirely real. There is no path by which a number generated here reaches
the Pine port.

Its purpose is narrow and worth stating plainly. Phase 0's computation core —
the panel, the control rule, the ablation, the sweeps, the regime table — is
arithmetic that has to be right before real data arrives, and the only way to
know it is right is to run it against a world whose answers are known in
advance. So this generator embeds the v2 thesis by construction:

* In the **classic** stretch, gold moves against the 2Y, so a control that
  trades ``-sign(Δ2Y)`` should be profitable.
* In the **inverted** stretch, gold moves *with* the 2Y, so the same control
  should lose — while DXY keeps confirming exactly as before, which is §1's
  argument about macro confirmation made mechanical.

If the ablation cannot recover that structure from this data, the ablation is
broken. If it can, the ablation is at least capable of finding an effect that
is really there — which is a much weaker claim than "the effect exists in
gold", and is not offered as more.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta

from .beta import DailyObservation
from .loaders import Bar, BarSeries, MacroEvent
from .sources import Provenance

#: Roughly the release mix and cadence of the tracked US calendar: a couple of
#: prints a week, all at the 08:30 or 10:00 New York slots.
EVENT_TYPES = (
    ("CPI", 0.20, 13, 30),
    ("CORE_CPI", 0.15, 13, 30),
    ("PCE", 0.12, 13, 30),
    ("PPI", 0.25, 13, 30),
    ("NFP", 45.0, 13, 30),
    ("RETAIL_SALES", 0.35, 13, 30),
    ("ISM", 1.40, 15, 0),
    ("JOBLESS_CLAIMS", 12.0, 13, 30),
    ("GDP", 0.45, 13, 30),
    ("JOLTS", 320.0, 15, 0),
    ("FOMC", 0.06, 19, 0),
)

CLASSIC_SHARE = 0.55
DECOUPLED_SHARE = 0.20

SESSION_START_HOUR = 11
SESSION_END_HOUR = 21


@dataclass(frozen=True)
class SyntheticWorld:
    prices: BarSeries
    yields: BarSeries
    dxy: BarSeries
    daily: list[DailyObservation]
    events: list[MacroEvent]
    provenance: Provenance
    #: Which regime each event was generated under. Used only by the tests, to
    #: check the regime table recovers what was planted; never by the report.
    truth: dict[datetime, str]


def _regime_for(index: int, total: int) -> str:
    position = index / max(total - 1, 1)
    if position < CLASSIC_SHARE:
        return "CLASSIC"
    if position < CLASSIC_SHARE + DECOUPLED_SHARE:
        return "DECOUPLED"
    return "INVERTED"


def generate(
    years: int = 3,
    start: date = date(2022, 1, 3),
    seed: int = 20260829,
) -> SyntheticWorld:
    """Build the world. Deterministic for a given seed."""
    rng = random.Random(seed)

    days = [start + timedelta(days=i) for i in range(int(years * 365))]
    trading_days = [d for d in days if d.weekday() < 5]

    # --- daily legs, with a beta that changes character over the sample -----
    daily: list[DailyObservation] = []
    gold_level = 1800.0
    yield_level = 1.20
    for i, day in enumerate(trading_days):
        regime = _regime_for(i, len(trading_days))
        d_yield = rng.gauss(0.0, 0.055)
        sensitivity = {"CLASSIC": -0.075, "DECOUPLED": -0.004, "INVERTED": 0.045}[regime]
        idiosyncratic = {"CLASSIC": 0.0035, "DECOUPLED": 0.0125, "INVERTED": 0.0060}[regime]
        yield_level = max(0.15, yield_level + d_yield)
        gold_level *= math.exp(sensitivity * d_yield + rng.gauss(0.0, idiosyncratic))
        daily.append(DailyObservation(day, gold_level, yield_level))

    daily_by_date = {o.day: o for o in daily}

    # --- releases ----------------------------------------------------------
    events: list[MacroEvent] = []
    truth: dict[datetime, str] = {}
    # A release roughly every third trading day, always on a session day.
    release_days = [d for i, d in enumerate(trading_days) if i % 3 == 0 and i > 130]
    for i, day in enumerate(release_days):
        name, dispersion, hour, minute = EVENT_TYPES[i % len(EVENT_TYPES)]
        z = rng.gauss(0.0, 1.0)
        consensus = round(rng.uniform(1.0, 4.0) * dispersion, 4)
        actual = consensus + z * dispersion
        ts = datetime(day.year, day.month, day.day, hour, minute, tzinfo=UTC)
        events.append(MacroEvent(ts, name, actual, consensus, dispersion))
        truth[ts] = _regime_for(trading_days.index(day), len(trading_days))

    events_by_ts = {e.ts_utc: e for e in events}

    # --- intraday session bars --------------------------------------------
    price_bars: list[Bar] = []
    yield_bars: list[Bar] = []
    dxy_bars: list[Bar] = []

    for day in trading_days:
        observation = daily_by_date[day]
        # Anchor the session to that day's daily close so the intraday series
        # and the beta estimator describe the same asset.
        price = observation.gold_close
        yield_value = observation.dgs2
        dollar = 100.0 + (yield_value - 1.2) * 2.0

        session_start = datetime(day.year, day.month, day.day, SESSION_START_HOUR, 0, tzinfo=UTC)
        minutes = (SESSION_END_HOUR - SESSION_START_HOUR) * 60

        # Is there a release in this session, and what did it do?
        release = next(
            (e for ts, e in events_by_ts.items() if ts.date() == day and SESSION_START_HOUR <= ts.hour < SESSION_END_HOUR),
            None,
        )
        schedule: dict[int, float] = {}
        yield_schedule: dict[int, float] = {}
        if release is not None:
            regime = truth[release.ts_utc]
            offset = int((release.ts_utc - session_start).total_seconds() // 60)
            z = (release.actual - release.consensus) / release.consensus_sd
            noise_scale = price * 0.00035

            d_yield_total = 0.022 * z + rng.gauss(0.0, 0.006)
            direction_sign = {"CLASSIC": -1.0, "DECOUPLED": 0.0, "INVERTED": 1.0}[regime]
            move = direction_sign * d_yield_total * price * 0.28 + rng.gauss(0.0, noise_scale * 2.0)

            impulse = move * rng.uniform(1.15, 1.55)
            pullback = rng.uniform(0.10, 0.90)
            after_pullback = impulse * (1.0 - pullback)
            # The move continues in whatever direction gold actually went, in
            # both coupled regimes. What differs between them is whether that
            # direction agrees with -sign(d2Y), which is the only thing the
            # control is betting on.
            follow_through = rng.gauss(1.0 if regime == "DECOUPLED" else 1.8, 0.8)
            final = impulse * follow_through

            for step in range(1, 4):
                schedule[offset + step - 1] = impulse * step / 3.0
                yield_schedule[offset + step - 1] = d_yield_total * step / 3.0
            for step in range(1, 11):
                schedule[offset + 2 + step] = impulse + (after_pullback - impulse) * step / 10.0
            for step in range(1, 91):
                schedule[offset + 12 + step] = after_pullback + (final - after_pullback) * step / 90.0

        cumulative = 0.0
        cumulative_yield = 0.0
        # A session-long random walk on top of the level, so that a
        # higher-timeframe ATR is a meaningful width rather than a restatement
        # of the tick noise. Calibrated to a gold-like intraday range: roughly
        # three sigma over a six-hour session on a four-figure price.
        walk = 0.0
        walk_yield = 0.0
        for m in range(minutes):
            ts = session_start + timedelta(minutes=m)
            target = schedule.get(m)
            if target is not None:
                cumulative = target
            target_yield = yield_schedule.get(m)
            if target_yield is not None:
                cumulative_yield = target_yield

            walk += rng.gauss(0.0, price * 0.00013)
            walk_yield += rng.gauss(0.0, 0.00035)
            drift = rng.gauss(0.0, price * 0.00006)
            mid = price + walk + cumulative + drift
            spread = abs(rng.gauss(0.0, price * 0.00012)) + price * 0.00005
            price_bars.append(Bar(ts, mid, mid + spread, mid - spread, mid + rng.gauss(0, spread / 3)))

            y_mid = yield_value + walk_yield + cumulative_yield + rng.gauss(0.0, 0.0004)
            yield_bars.append(Bar(ts, y_mid, y_mid + 0.0008, y_mid - 0.0008, y_mid))

            # The dollar tracks the 2Y regardless of what gold is doing. That
            # is the whole point of §1's objection to macro confirmation.
            d_mid = dollar + (walk_yield + cumulative_yield) * 1.8 + rng.gauss(0.0, 0.004)
            dxy_bars.append(Bar(ts, d_mid, d_mid + 0.006, d_mid - 0.006, d_mid))

    provenance = Provenance(quality="synthetic")
    for key in ("xau_1m", "dxy_1m", "us2y_intraday", "dgs2_daily", "gold_daily",
                "actuals_first_print", "consensus"):
        provenance.record(key, "synthetic", "generated by phase0.synthetic")
    provenance.note(
        "SYNTHETIC DATA. Generated to exercise the Phase 0 computation core. "
        "Every constant derived from this run is a property of the generator, "
        "not of gold, and must not be ported to Pine."
    )

    return SyntheticWorld(
        prices=BarSeries("XAUUSD.SYNTH", price_bars),
        yields=BarSeries("US2Y.SYNTH", yield_bars),
        dxy=BarSeries("DXY.SYNTH", dxy_bars),
        daily=daily,
        events=events,
        provenance=provenance,
        truth=truth,
    )
