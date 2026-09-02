# What the reference run proves, and what it cannot

## The instrument

`validation/reference.py` is the v7 engine written a second time, in Python,
from the same rules: the same four families, the same ten weighted components,
the same mandatory gates, the same daily and independence engine. It runs over
`validation/synthetic.py` bars — **generated**, not downloaded — calibrated so
the average 15-minute true range is 0.103% of price, which is where real
XAUUSD sits, with volatility clustering, intraday seasonality, a regime chain
averaging about three days, and a DXY series correlated to gold's shocks.

Run: 240,028 bars, 2,609 normal trading days, 26 Aug 2016 → 26 Aug 2026,
long only, defaults, seed 20260826.

## What survives generated data

**Frequency and funnel shape.** How often price pulls back to VWAP, sweeps a
20-bar low and reclaims it, or breaks a range and retests it, is a property of
the path's geometry — its volatility scale, its clustering, its trend/range
alternation. Those are exactly what the generator reproduces.

**Score distribution.** Same reason: the components measure geometry.

## What does not survive

**Expectancy, profit factor, net P&L.** The generator has no edge in it by
construction. Those columns measure the exit model against a random walk.

## Finding 1 · the architecture clears the frequency bar

| | v6 baseline | v7 |
|---|---|---|
| trades in 10 years | 11 | **3,193** |
| trades per trading day | ~0.004 | **1.224** |
| candidates offered per day | — | 5.95 |
| days with ≥1 trade | — | 69.1% |

Three orders of magnitude, from a restructure rather than from loosening the
trendline. The daily distribution: 805 days with 0, 798 with 1, 623 with 2, 383
with 3, and **0 days above the cap** — the hard limit holds.

At the specified floor of 72 the engine runs at 1.224/day, just under the
1.3–1.8 target. **The default has not been changed**: 72 is the stated research
threshold, and moving it is your decision, not a bug fix. For reference, the
sensitivity sweep:

| variant | trades | trades/day | zero-day % | candidates/day |
|---|---|---|---|---|
| score floor 70 | 3,583 | **1.373** | 26.9% | 7.50 |
| **baseline (72)** | **3,193** | **1.224** | 30.9% | 5.95 |
| score floor 75 | 2,430 | 0.931 | 40.9% | 3.84 |
| score floor 80 | 1,229 | 0.471 | 65.0% | 1.38 |
| min reward room 1.2R | 3,311 | 1.269 | 29.9% | 6.01 |
| min reward room 2.0R | 3,041 | 1.166 | 32.0% | 5.88 |
| cooldown 0 bars | 3,273 | 1.255 | 30.4% | 5.95 |
| no anchor rule | 3,199 | 1.226 | 30.9% | 5.95 |
| regime floor 0.15 | 3,216 | 1.233 | 30.0% | 5.95 |
| daily cap 2 | 2,878 | 1.103 | 30.0% | 5.95 |

The score floor is the only lever with real leverage. Everything else moves
frequency by a few percent, which is worth knowing: the independence rules and
the reward-room gate are **not** what is holding the trade count down, so
relaxing them to buy frequency would give up protection for almost nothing.

## Finding 2 · the zero-trade days are a long-only artefact, not over-selectivity

30.9% of days produce no trade, against a 15–20% guideline. Splitting the days
by how much of the session the blended higher-timeframe regime spent bullish:

| bullish bars on the day | days | zero-trade | trades/day | eligible/day |
|---|---|---|---|---|
| 0–5% | 764 | 66.6% | 0.44 | 0.88 |
| 5–25% | 130 | 33.8% | 0.95 | 2.06 |
| 25–50% | 236 | 24.6% | 1.20 | 2.69 |
| 50–75% | 199 | 24.1% | 1.29 | 3.22 |
| **75–100%** | **1,280** | **11.4%** | **1.71** | 5.25 |

On days the engine is allowed to trade it delivers **1.71 trades/day with 11.4%
zero-trade days** — inside both targets. Of the 805 zero-trade days, **645 (80%)
produced no eligible candidate at all**: the engine was never offered a trade
and turned it down.

The conclusion is not "loosen the filters". It is that roughly 29% of the
decade is time a long-only engine has nothing to buy. **Shorts are the frequency
fix**, and that is already your phase 2.

## Finding 3 · the score orders outcomes, even on a random walk

| bucket | candidates | trades | win % | expectancy R |
|---|---|---|---|---|
| 72–74 | 5,506 | 1,264 | 34.3% | -0.477 |
| 75–77 | 4,306 | 872 | 35.8% | -0.438 |
| 78–80 | 2,927 | 551 | 39.0% | -0.293 |
| 81–84 | 2,071 | 372 | 40.6% | -0.224 |
| 85–89 | 658 | 124 | 37.1% | -0.267 |
| 90–94 | 55 | 10 | 40.0% | -0.013 |
| 95–100 | 1 | 0 | — | — |

Expectancy improves by about 0.46 R from the bottom bucket to the top, with one
inversion at 85–89 on 124 trades. **On data with no edge in it.**

Read that carefully. It does not mean the score predicts direction — it cannot,
there is no direction to predict. It means the score is separating trades by the
*shape* of their payoff: higher-scoring candidates have more reward room, better
stop placement and better-located entries, and those pay off differently even in
a random walk. That is a real and useful property, and it is the necessary
condition for the model. Whether the score also carries directional information
is the question only the TradingView run on real bars can answer — and the score
bucket table is where you will read the answer.

The A+ tier is very thin: 658 candidates in a decade above 85, 1 above 95. If
real data behaves similarly, A+ is a label with almost no trades under it, and
the tier boundaries are worth revisiting after the first real run.

## Finding 4 · one family is doing most of the work

| family | raw | candidates | ≥ floor | trades | share |
|---|---|---|---|---|---|
| 1 Trendline | 2,634 | 2,030 | 314 | 47 | 1.5% |
| 2 Sweep | 47,952 | 16,619 | 1,309 | 294 | 9.2% |
| 3 Breakout | 7,214 | 5,121 | 2,409 | 366 | 11.5% |
| 4 VWAP pull | 54,244 | 44,317 | 11,492 | 2,486 | 77.9% |

The VWAP continuation pullback supplies four trades in five. The trendline
family — the original v6 idea — supplies 1.5%, and its scarcity is exactly the
v6 problem in miniature: a four-stage state machine has a four-stage base rate.
It is preserved because it was the hypothesis, but it is no longer the engine,
and per-family analytics is how you will find out whether it earns its place.

## Finding 5 · a real accounting hole in v6, quantified

**15.6% of all fills are same-bar round trips** — the entry stop and the
protective stop both trigger inside one 15-minute bar. v6's lifecycle treated
those as unfilled orders, so they vanished from every custom table while
TradingView's own trade list still counted them. Because those trades are
overwhelmingly losers, the drop is biased: v6's own panels flattered themselves.
v7 detects them on the closed-trade counter and books them, and reports the
count as its own funnel row.

## Finding 6 · what a stop entry costs when there is no momentum

Average R across all 3,193 trades is -0.396, of which about -0.19 R is the
modelled round-turn cost. The rest is structural: entering on a stop above the
trigger bar's high means paying roughly half that bar's upper wick, and on a
driftless series nothing pays it back. Real markets may or may not compensate
through follow-through after a trigger — **that is precisely the thing the real
backtest measures, and the thing this generated run cannot.**

It is worth stating plainly because it sets the bar: v7 on real data has to earn
back roughly 0.4 R per trade of entry mechanics and costs before it is flat.

## Reproducing

```bash
python3 strategies/cyber_mcgiver/validation/frequency.py --sensitivity \
        --out strategies/cyber_mcgiver/research/synthetic_frequency_report.txt
```

Deterministic given the seed. Across three seeds the conclusions hold, with
enough spread to be worth quoting as a range rather than a point:

| seed | trades | trades/day | zero-day % | candidates/day | family 4 share |
|---|---|---|---|---|---|
| 20260826 | 3,193 | 1.224 | 30.9% | 5.95 | 77.9% |
| 7 | 2,825 | 1.083 | 36.9% | 5.27 | 78.5% |
| 424242 | 3,155 | 1.209 | 32.7% | 6.01 | 77.3% |

So: **roughly 1.1–1.2 trades/day and 31–37% zero-trade days at a floor of 72**,
with the VWAP family supplying about 78% of trades regardless of path. The
three-orders-of-magnitude result against v6 is not seed-dependent; the exact
distance below the 1.3 target is, by about a tenth of a trade per day.
