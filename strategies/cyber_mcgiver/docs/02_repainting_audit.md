# Repainting audit (S60)

The rule: every decision may use only information that existed at the historical
decision timestamp. Below is each decision, what it reads, and why that is
knowable at the time.

| Decision | Reads | Why it cannot see the future |
| -------- | ----- | ---------------------------- |
| 1D / 4H / 1H regime | `request.security(..., expr[1], lookahead = barmerge.lookahead_off)` | Two independent protections. `lookahead_off` prevents the higher-timeframe bar from being resolved early, and the explicit `[1]` uses the *previous* higher-timeframe bar, so only closed candles are ever read. The current, still-forming 1D bar is invisible. |
| Swing highs / lows | `ta.pivothigh(high, L, R)` / `ta.pivotlow` | A pivot is returned only after its `R` right-hand bars have closed. The pivot's own bar is at `bar_index − R`, and the engine reads `high[R]`, `low[R]`, `close[R]` — values from a bar that closed `R` bars ago. |
| Break of structure | `close` of the current bar vs the last confirmed swing | Both terms are closed values at evaluation time. `calc_on_every_tick = false` means the script evaluates on bar close, so `close` is final. |
| P1, P2, P3 | confirmed pivots only | Same mechanism as above. A structure is never built from a pivot that has not yet earned confirmation, which is why P3 confirmation is stamped at `bar_index`, not at the pivot's own bar. |
| Trendline slope and projection | P1 and P2 bar indices and prices | Pure arithmetic on already-confirmed values. |
| Trendline expiry | `bar_index − confirmBar` | Counted from the confirmation bar, not the pivot bar, so the clock starts when the line actually became known. |
| Touch #4 and its rejection | the current bar's OHLC at close | Evaluated once, on the closed bar. |
| Entry | `strategy.entry(..., stop = high + tick)` | A stop order placed after the rejection bar closed. `process_orders_on_close = false`, so it can only fill on a *later* bar. The engine never assumes it knows the fill in advance. |
| Structural stop | P3's wick and ATR at arm time | Both already closed. |
| Position size | `strategy.equity` at arm time | The equity that existed when the order was armed. |
| Breakeven activation | a *closed* bar beyond 1.2R | S54 exists precisely to stop an intrabar wick from arming breakeven. |
| Trailing stop | confirmed pivots after activation, plus the running extreme of closed bars | Pivots again carry their `R`-bar confirmation lag. |
| Session label | `hour(time, tz)`, `minute(time, tz)` of the current bar | Bar time is known when the bar opens. |

## Structural checks

`validation/pine_lint.py` fails the build if any of these appear:

* `barmerge.lookahead_on` anywhere;
* a `request.security()` call without an explicit `lookahead` argument;
* the removed bare `security()` form;
* a stateful helper evaluated inside `request.security()`.

## What remains an assumption

Non-repainting is not the same as fill-realistic. Two residual assumptions:

1. **Intrabar order of stop and limit.** When one bar contains both the stop and
   the 1.2R target, TradingView's fill model decides. `use_bar_magnifier = true`
   narrows this; on plans without it, treat the 1.2R hit rate as an upper bound.
2. **Historical-vs-realtime symmetry.** Historical bars evaluate once at close.
   With `calc_on_every_tick = false` realtime bars do too, so live behaviour and
   backtest behaviour follow the same code path — but a broker feed whose bars
   differ from TradingView's will not reproduce the pivots exactly.
