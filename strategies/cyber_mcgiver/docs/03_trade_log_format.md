# Trade log format

With *Write one CSV log line per closed trade* enabled, every completed trade
emits one line to the Pine Logs pane at the moment it closes. Copy the pane into
a file to analyse the sample outside Pine.

```
CM,<timestamp>,<tf>,<direction>,<session>,<entry>,<stop>,<risk>,<lots>,<R>,<MFE_R>,<MAE_R>,<stop_ATR>,<slope_N>,<hold_bars>
```

| Field | Meaning |
| ----- | ------- |
| `CM` | row marker, so logs can be grepped out of a mixed pane |
| `timestamp` | bar time of the exit, `yyyy-MM-dd HH:mm`, in the session timezone |
| `tf` | `5m` or `15m` — never mix the two in one sample (S14, S66) |
| `direction` | `LONG` or `SHORT` |
| `session` | session of the **entry**, not of the exit (S67) |
| `entry` | actual fill price |
| `stop` | stop at exit: structural, breakeven, or trailed |
| `risk` | 1R in dollars per ounce, frozen at entry (S50) |
| `lots` | position size that S47 produced |
| `R` | realised R: net trade P/L ÷ (risk × units) |
| `MFE_R` | maximum favourable excursion, in R (S68) |
| `MAE_R` | maximum adverse excursion, in R (S69) |
| `stop_ATR` | stop distance in ATR at entry (S49, S69) |
| `slope_N` | normalised trendline slope `|m| / ATR` (S69) |
| `hold_bars` | execution-timeframe bars held |

`R` is computed from net P/L, so commission and slippage charged by the tester
are already inside it. A −1R loser will read slightly worse than −1.00; that gap
is the cost model, not an accounting error.
