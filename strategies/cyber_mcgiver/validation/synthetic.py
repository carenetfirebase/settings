"""XAUUSD-like 15-minute bars, generated rather than downloaded.

## Why generate

The frequency question — does the v7 architecture offer roughly one to three
candidates per day, or roughly eleven per decade — is a question about the
GEOMETRY of the setup families: how often price pulls back to VWAP, how often a
20-bar low is swept and reclaimed, how often a range breaks and is retested.
Those rates are driven by the shape of the price path, not by whether gold
happened to rally in 2019. A generator that reproduces the right volatility
scale, the right volatility clustering, the right intraday seasonality and the
right trend/range alternation answers the frequency question honestly.

## What it cannot answer

Expectancy. The generator has no edge in it, by construction, so any profit
factor measured on these bars is measuring the exit model against a random walk
and nothing else. Frequency, funnel shape and score distribution are the only
outputs of this module that mean anything.

The calendar follows spot gold: 15-minute bars from 18:00 ET Sunday to 17:00 ET
Friday, with the daily rollover at 17:00 ET, which is the boundary TradingView
uses for the OANDA:XAUUSD daily bar.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass
from datetime import date, datetime, timedelta

BARS_PER_DAY = 92          # 23 hours at 15 minutes
MINUTES = 15


@dataclass(frozen=True, slots=True)
class Bar:
    """One 15-minute candle, timestamped at its OPEN, in New York wall time."""

    ts: datetime
    open: float
    high: float
    low: float
    close: float
    dxy: float

    @property
    def trading_day(self) -> date:
        """The gold trading day this bar belongs to; rollover is 17:00 ET."""
        return (self.ts + timedelta(hours=7)).date()

    @property
    def minute_of_day(self) -> int:
        return self.ts.hour * 60 + self.ts.minute


#: Volatility multiplier by New York hour. London and the New York overlap carry
#: most of gold's range; the Asian session and the post-close hour carry little.
_SEASON = {
    0: 0.55, 1: 0.55, 2: 0.80, 3: 1.05, 4: 1.15, 5: 1.10,
    6: 1.05, 7: 1.10, 8: 1.35, 9: 1.55, 10: 1.50, 11: 1.25,
    12: 1.05, 13: 1.00, 14: 0.95, 15: 0.85, 16: 0.70,
    18: 0.45, 19: 0.45, 20: 0.50, 21: 0.55, 22: 0.55, 23: 0.55,
}


def _session_calendar(start: date, end: date) -> list[datetime]:
    """Bar open timestamps for every gold session between two dates."""
    stamps: list[datetime] = []
    day = start
    while day <= end:
        # Sessions open Sunday evening and run Monday to Friday evening.
        if day.weekday() == 5:                     # Saturday: closed
            day += timedelta(days=1)
            continue
        if day.weekday() == 6:                     # Sunday: evening open only
            opening = datetime(day.year, day.month, day.day, 18, 0)
            for k in range(24):                    # 18:00 to 23:45
                stamps.append(opening + timedelta(minutes=MINUTES * k))
            day += timedelta(days=1)
            continue
        opening = datetime(day.year, day.month, day.day, 0, 0)
        for k in range(68):                        # 00:00 to 16:45
            stamps.append(opening + timedelta(minutes=MINUTES * k))
        if day.weekday() != 4:                     # Friday has no evening re-open
            evening = datetime(day.year, day.month, day.day, 18, 0)
            for k in range(24):                    # 18:00 to 23:45
                stamps.append(evening + timedelta(minutes=MINUTES * k))
        day += timedelta(days=1)
    return stamps


def generate(
    start: date,
    end: date,
    *,
    seed: int = 20260826,
    start_price: float = 1325.0,
    end_price: float = 4400.0,
    base_vol_bps: float = 7.0,
    dxy_start: float = 95.0,
    gold_dxy_corr: float = -0.45,
) -> list[Bar]:
    """Generate bars whose scale and behaviour resemble XAUUSD 15m.

    `base_vol_bps` is the per-bar standard deviation in basis points before
    seasonality and clustering; 7bp puts the average 15-minute true range at
    about 0.10% of price, which is where the real series sits.

    The drift is set so the path travels from `start_price` to `end_price` over
    the window. That is a deliberate choice, not a forecast: a decade of gold
    trended up, and a flat generator would understate how often a directional
    regime and a continuation pullback coincide.
    """
    rng = random.Random(seed)
    stamps = _session_calendar(start, end)
    if not stamps:
        return []

    total_drift = math.log(end_price / start_price) / len(stamps)
    bars: list[Bar] = []
    price = start_price
    dxy = dxy_start

    # Volatility clustering: a slow mean-reverting multiplier, so quiet weeks and
    # violent weeks both last longer than one bar.
    vol_state = 1.0
    # Regime: a Markov chain over {trend up, range, trend down}. The transition
    # probabilities give a mean regime length of roughly three trading days,
    # which is the horizon the 4H and 1H filters are meant to be reading.
    regime = 1
    regime_weights = {1: 0.45, 0: 0.35, -1: 0.20}
    regime_drift = {1: 1.0, 0: 0.0, -1: -0.6}
    # The regime tilt has to be mean-zero, or it becomes a second drift term and
    # compounds: at these coefficients an un-demeaned tilt multiplied the ten-year
    # path by a hundred and put "gold" at 488,000.
    regime_mean = sum(regime_weights[k] * regime_drift[k] for k in regime_drift)
    switch_p = 1.0 / (3.0 * BARS_PER_DAY)

    for ts in stamps:
        if rng.random() < switch_p:
            regime = rng.choices([1, 0, -1], weights=[regime_weights[1], regime_weights[0], regime_weights[-1]])[0]
        vol_state += (1.0 - vol_state) * 0.02 + rng.gauss(0.0, 0.045)
        vol_state = min(max(vol_state, 0.35), 3.2)

        season = _SEASON.get(ts.hour, 0.6)
        sigma = base_vol_bps / 10000.0 * season * vol_state
        # The regime tilts the drift around zero, so it changes the SHAPE of
        # the path — trending stretches and choppy stretches — without changing
        # where the path ends up.
        mu = total_drift + (regime_drift[regime] - regime_mean) * sigma * 0.055
        shock = rng.gauss(0.0, 1.0)
        ret = mu + sigma * shock

        opening = price
        closing = opening * math.exp(ret)
        # Wicks: an intra-bar range at least as wide as the body, scaled by a
        # lognormal factor so occasional bars have long tails.
        span = abs(closing - opening) + opening * sigma * math.exp(rng.gauss(-0.25, 0.55))
        up = rng.random()
        high = max(opening, closing) + span * up * 0.5
        low = min(opening, closing) - span * (1.0 - up) * 0.5
        price = closing

        # Correlate DXY with gold's SHOCK, not with its decade-long drift:
        # otherwise a trending gold path drags the dollar index somewhere it has
        # never been, and the confluence component reads a trend that is really
        # just the generator's own drift reflected back at it.
        dxy_ret = gold_dxy_corr * (ret - total_drift) + rng.gauss(0.0, sigma * 0.55)
        dxy *= math.exp(dxy_ret)

        bars.append(Bar(ts=ts, open=opening, high=high, low=low, close=closing, dxy=dxy))

    return bars
