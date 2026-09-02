# H · TradingView dashboard and diagnostics

Two tables and one label. Between them they answer the only three questions
worth asking at 09:15 on a Tuesday: *where is the setup, why is it not
trading, and what would it risk if it did?*

---

## 1. State panel (top right)

One row per variable from S60, with the current reading and a colour.

| Row | States | Green when |
|---|---|---|
| Gold HTF | Bull / Invalid | 4H and 1H regimes both bullish |
| Asia/London | Continuation / Sweep-Reclaim / Invalid | either model holds |
| ORB | Waiting / Break / Accepted / Failed | accepted |
| XAU VWAP | Above / Below | close above the anchored VWAP |
| VWAP slope | Rising / Falling + value in ATR | rising |
| VWAP extension | value in ATR | 0 < ext ≤ 1.25 |
| GC | Strong (n/4) / Moderate / Weak | ≥ 3 confirmations |
| DXY | Supportive (n/3) / Neutral / Opposing | ≥ 2 conditions |
| Gold/DXY corr | ρ and the score weight applied | ρ ≤ −0.20 |
| VIX | Supportive / Neutral / Unsupportive | support > 0 |
| Rates | Supportive / Neutral / Opposing | real yields falling |
| Pivot | Valid / Valid (strict) / Invalid | structure valid |
| Trendline | Valid m=… / Invalid | positive, non-parabolic slope |
| Touch | 1 / 2 / 3 | third interaction on this bar |
| Rejection | Confirmed / Confirmed +wick / Waiting | S33 satisfied |
| Volatility | Normal / SHOCK + ratio | ATR shock ≤ 1.75 |
| Spread | ratio + `MODELLED` | within the assumed budget |
| News | Clear + source / BLACKOUT | not in a blackout |
| Score | nn / 100 · need nn | at or above threshold |
| Grade | A / A+ / A++ / – | ≥ A |
| State | S57 state machine | ARMED or POSITION_OPEN |
| Planned risk | $nnn · n.nn% | informational |
| Lots · stop | n.nn · price | size is valid |
| R distance | price (✗ if out of band) | inside 0.20–1.25 ATR |
| Resistance space | n.nnR | ≥ 1.5R |
| Day P/L · lock | n.nn% · open/LOCKED | not locked |

Two warnings appear inline rather than in their own row:

* **`⚠ <timeframe>`** in the header when the chart is not 5m. The strategy is
  specified on 5-minute bars; every ATR-relative threshold assumes it.
* **`⚠capital`** on the last row when Strategy Properties' initial capital does
  not match `i_acctSize`. Position sizes would be right and the risk percentages
  wrong — the sort of mismatch that only shows up when the numbers are compared.

The **Gold/DXY correlation** row is the one most people will not expect. It
shows the live correlation and the multiplier being applied to the DXY score.
When it reads `0.12 · weight ×0.25`, the dollar is not behaving inversely to
gold today, and the strategy is discounting the dollar's opinion accordingly
(S37).

---

## 2. Target vs verified panel (bottom right)

S87 requires the aspiration and the measurement to be displayed separately and
never blurred. The panel has three columns: metric, TARGET, ACTUAL.

| Metric | TARGET | ACTUAL |
|---|---|---|
| Trades | ≥100 OOS | count + PRELIMINARY / ADEQUATE / VALIDATED-SIZE |
| Win rate | 70% | measured |
| 95% Wilson CI | — | measured interval |
| Expectancy | ≥ +0.25R | measured |
| Profit factor | ≥ 1.5 | measured |
| Avg win / loss | 1.5R / 1R | measured |
| Avg MAE / MFE | — | measured |
| Max consecutive W/L | — | measured |
| Max drawdown | low | $ and % of account |
| Trading days | ≥ 4 | measured |
| Equity | +10% | measured |
| Bootstrap · MC | external | `aurum_validate.py` |

The TARGET column is stated as a target, in grey, next to whatever the data
actually produced. If the strategy wins 58% with +0.45R expectancy, the panel
shows 58% next to the 70% target and does not editorialise. That is the required
behaviour (S1): a genuine 58% with positive expectancy and low drawdown is a
better result than a manufactured 70%.

**The win rate is never shown without its Wilson interval.** 70% from 30 trades
displays as `70.0%` with `[52.1% – 83.3%]` underneath, which is the honest way
to say "this could be a 52% strategy".

The final row is a pointer, not a result: bootstrapped expectancy and pass
probability are not computed in Pine (S80).

---

## 3. No-trade reason label (S59)

A label on the last bar naming the **first** failed gate, evaluated in priority
order — hard stops, then risk state, then news, then the signal chain, then
execution, then score and window.

```
NO TRADE — WEEKEND
NO TRADE — FTMO MAX LOSS
NO TRADE — DRAWDOWN KILL SWITCH
NO TRADE — DATA FEED FAILURE
NO TRADE — TARGET REACHED
NO TRADE — RISK LIMIT
NO TRADE — MORNING COMPLETE
NO TRADE — DAILY TRADE COUNT
NO TRADE — NEWS BLACKOUT
NO TRADE — HTF NOT BULL
NO TRADE — LONDON STRUCTURE
NO TRADE — OR NOT DEFINED
NO TRADE — ORB NOT ACCEPTED
NO TRADE — BELOW VWAP
NO TRADE — VWAP SLOPE
NO TRADE — EXTENDED FROM VWAP
NO TRADE — DXY
NO TRADE — GC NOT CONFIRMING
NO TRADE — NO PIVOT STRUCTURE
NO TRADE — TRENDLINE
NO TRADE — THIRD TOUCH
NO TRADE — WEAK REJECTION
NO TRADE — ATR SHOCK
NO TRADE — SPREAD
NO TRADE — STOP DISTANCE
NO TRADE — RESISTANCE < 1.5R
NO TRADE — INVALID POSITION SIZE
NO TRADE — SCORE nn/nn
NO TRADE — OUTSIDE WINDOW
IN POSITION
ORDER PENDING
ARMED
```

Ordering is deliberate: the reason shown is the *most fundamental* thing wrong,
not the last condition evaluated. A day that is both outside the trading window
and missing the HTF regime reports the regime, because that is the fact worth
knowing.

The state machine (`state` row) and the reason label answer different questions.
The state says how far the setup progressed; the reason says what stopped it. A
day can reach `WAIT_TOUCH_3` and report `NO TRADE — DXY`, meaning the price
structure was there and the dollar was not.

---

## 4. Chart drawings

| Plot | Colour | Shown |
|---|---|---|
| NY anchored VWAP | orange, 2px | during the NY session |
| ORH / ORL | teal | once locked, during the session |
| PDH / PDL | grey | always |
| Asia high / London high | purple / blue | once frozen |
| Ascending support (projected trendline) | lime, 2px | while valid, during the session |
| Active stop | red | while in a position |
| Touch #3 marker | lime triangle below the bar | on the touch bar |
| ARM label | green | on the bar the order is placed |

The trendline is plotted as the *projected* value at each bar, so what is drawn
is exactly what the third-touch test evaluated — not a line fitted afterwards
through two points, which would look tidier and mean less.

---

## 5. Alerts

Every closed position emits its full CSV row as an alert (`i_alertRows`),
which makes an alert webhook a live trade log. On the last historical bar the
whole export is written to the Pine Logs pane with a header, ready to paste into
`aurum_validate.py` — see `08_trade_export_format.md`.
