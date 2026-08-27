# XAUUSD 08:30 NY opening-range breakout

Two Pine sources and the Python model they are checked against.

| File | What it is |
|---|---|
| `XAUUSD_0830_NY_ORB_v1_original.pine` | The submitted v1, unmodified, kept for diffing |
| `XAUUSD_0830_NY_ORB_1m_v2.pine` | v2: decisions on 1-minute bars |
| `../src/invest/strategies/orb.py` | The same rule set in Python, executable bar by bar |
| `../tests/test_orb_strategy.py` | 32 behavioural tests over constructed bars |

## The question v1 was audited against

> It must execute every day, and the decision must be made on the 1-minute
> timeframe when price interacts with the opening range.

v1 does not do that. On a 1-minute chart it takes **zero trades, on every day,
forever** — not worse trades, none at all.

## Findings

| # | Finding | v1 | v2 |
|---|---|---|---|
| 1 | Hard 5-minute gate: `tfOK = timeframe.in_seconds(...) == 300`, ANDed into every signal, every interaction record and the forced entry | 1m chart is silently inert | Runs on the chart's timeframe; refuses only timeframes too coarse to resolve a five-minute range |
| 2 | Forced entry at 08:55 | On 5m that was the window's last bar; on 1m it discards the final four minutes of the search | Fires on the window's last bar (08:59) |
| 3 | Forced entry depends on one specific bar existing | A missing 08:59 bar silently costs the day its "guaranteed" trade | Safety net on the first bar after the window closes |
| 4 | No floor on the stop distance | A tight 1-minute interaction candle gives near-zero risk and a position sized to match | `min_stop_atr`, default 0.5 ATR |
| 5 | No cap on position notional | Risk-based sizing alone asked for **$13.0M** of gold against a $100k account in the lab | Notional capped at a multiple of equity, default 5× |
| 6 | Confirmation must be the strictly next bar | Reasonable on 5m; on 1m price typically probes a level for two or three minutes first | `max_bars_since_touch`, default 2 (set 1 for v1's behaviour) |
| 7 | `symbolOK` requires "XAU" in the ticker, and gates trading | A broker feed named `GOLD` trades nothing, with no visible reason | Shown as a dashboard warning, not a trading gate |

Correct in v1 and preserved unchanged: a bar can never confirm itself
(interactions are recorded after the confirmation check), the structural stop
under the interaction wick, the exact-R target, one entry per NY day, and the
end-of-day flat.

## What the lab run shows

Same constructed tape, two decision granularities:

```
1m: confirmed 08:36  entry=2002.90  stop=2000.447  risk=2.453
5m: forced    09:00  entry=2003.00  stop=2000.443  risk=2.557
```

On 5-minute bars the interaction and the break fall inside one candle. A bar
cannot confirm itself, so the break is invisible, nothing confirms all window,
and the day ends on a forced entry instead. That is finding #1 and the reason
the request was made in the first place.

## Running it

```bash
pytest tests/test_orb_strategy.py -q
```

The tests use bars built on purpose, including the awkward ones: a bar that
touches and breaks at once, a rejection candle, a missing forced-entry bar, a
bar that spans both the stop and the target, a gap straight through the stop,
and five consecutive days that must each produce exactly one trade.

**Constructed bars prove behaviour, never profitability.** Nothing here is a
track record, and a forced daily entry is a constraint on the schedule, not an
edge. Before trading v2, backtest it on real XAUUSD 1-minute data with your
broker's spread, commission and slippage filled in — TradingView's defaults of
zero are not a cost model.
