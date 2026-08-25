# I · Trade export format

One row per **closed position**, not per exit leg. A position with three partial
exits produces three closed trades in TradingView's own list; pooling those as
independent observations would triple the sample and destroy every statistic
computed from it. The strategy therefore keeps its own log, aggregating legs
into the position that generated them.

---

## 1. Getting the file

1. Run the strategy on the chart with `Log trade CSV to Pine Logs` enabled.
2. Open the **Pine Logs** pane (right sidebar). On the last historical bar the
   script writes a preamble line, the header, then one line per position.
3. Select all, paste into a `.csv` file. The parser skips anything before the
   header, so the preamble does not need removing.

```
python -m validation.aurum_validate report trades.csv
```

For live capture, enable `Emit CSV alert on every closed position` and point an
alert webhook at a collector. The alert body is the same row.

---

## 2. Columns

| # | Column | Unit | Meaning |
|---|---|---|---|
| 1 | `ts_entry` | ET `YYYY-MM-DD HH:MM` | fill timestamp |
| 2 | `ts_exit` | ET | close timestamp of the last leg |
| 3 | `symbol` | — | chart ticker |
| 4 | `session_type` | enum | `SESSION_CONTINUATION` / `SESSION_SWEEP_RECLAIM` |
| 5 | `orb_model` | enum | `ORB_RETEST_ACCEPTANCE` / `ORB_MOMENTUM_ACCEPTANCE` |
| 6 | `entry` | price | **actual** average fill |
| 7 | `stop` | price | initial stop as placed |
| 8 | `init_R` | price | `entry − stop`, the R denominator |
| 9 | `units` | oz | filled size |
| 10 | `lots` | lots | `units / 100` |
| 11 | `risk_usd` | USD | actual dollar risk including commission |
| 12 | `realized_R` | R | position P/L ÷ `risk_usd` |
| 13 | `score` | 0–100 | confluence score at ARM time |
| 14 | `grade` | A / A+ / A++ | classification at ARM time |
| 15 | `htf_4h` | 0/1 | 4H regime bullish |
| 16 | `htf_1h` | 0/1 | 1H regime bullish |
| 17 | `vwap_ext` | ATR | extension at ARM |
| 18 | `vwap_slope` | ATR | VWAP slope at exit bar |
| 19 | `gc_count` | 0–4 | GC confirmations at ARM |
| 20 | `dxy_score` | 0–3 | DXY conditions at ARM |
| 21 | `corr_gold_dxy` | −1…1 | 60-day correlation at ARM |
| 22 | `ry_mom` | pp | 5-day real-yield change |
| 23 | `vix_support` | product | ρ(gold,VIX) × VIX momentum |
| 24 | `pivot_slope_norm` | ATR/bar | trendline slope |
| 25 | `strict_struct` | 0/1 | HH₂ > HH₁ |
| 26 | `touch3_dist_atr` | ATR | signed low-to-trendline distance |
| 27 | `rej_br` | 0–1 | rejection body ratio |
| 28 | `rej_clv` | 0–1 | rejection close location value |
| 29 | `atr_shock` | ratio | ATR ÷ median ATR |
| 30 | `modeled_spread` | price | the spread ASSUMED (not observed) |
| 31 | `vol_mode` | enum | which XAU volume mode produced the VWAP |
| 32 | `dist_pdh` | price | PDH − entry |
| 33 | `dist_london_high` | price | London high − entry |
| 34 | `mae_R` | R | maximum adverse excursion |
| 35 | `mfe_R` | R | maximum favourable excursion |
| 36 | `exit_type` | enum | `SL` / `BE/TRAIL` / `TRAIL` / `TP1+TRAIL` / `TP2/RUNNER` / `TIME` |
| 37 | `hold_bars` | bars | entry to final exit |
| 38 | `news_blackout` | 0/1 | blackout active at close |
| 39 | `rule_violation` | 0/1 | reserved; always 0 from Pine |
| 40 | `eval_mode` | enum | FTMO 2-Step / 1-Step / Research Only |
| 41 | `ablation` | enum | which preset produced the row |
| 42 | `entry_mode` | enum | Conservative / Moderate |
| 43 | `stop_model` | enum | A · Touch #3 / B · Pivot #2 |

Missing values are written `n/a` and parse to NaN.

---

## 3. Definitions that are easy to get wrong

**`realized_R`** is position P/L divided by *actual* dollar risk, where P/L is
the change in `strategy.netprofit` across the position — so it includes every
partial exit and every commission the tester charged. It is not
`(exit − entry) / (entry − stop)`, which would ignore both the partials and the
costs.

**`risk_usd`** uses the actual fill, not the planned entry. If the stop order
filled 0.20 worse, `init_R` is larger and `risk_usd` is larger, so slippage
shows up as a worse R rather than vanishing into the denominator.

**`mae_R` / `mfe_R`** come from the low and high the position actually traded
through, tracked bar by bar, not from TradingView's per-leg figures. `mae_R` is
what the Monte Carlo uses to model floating drawdown against the daily limit.

**ARM-time versus exit-time.** Columns 13–29 are the context that *justified* the
trade, frozen when the order was placed. Recording them at exit would describe
a decision nobody made.

---

## 4. What the export is for

**Ablation (S71).** Run each preset A…J, export each, then:

```
python -m validation.aurum_validate ablation \
  "A · ORB only=a.csv" "B · + VWAP=b.csv" ... "J · Full AURUM-NY PRIME=j.csv"
```

**Interaction testing (S72).** The per-trade columns let you split populations
without re-running Pine: third touch × ORB model (5 vs 26), DXY × GC (20 vs 19),
sweep/reclaim × third touch (4 vs 26), VWAP × ORB retest (17 vs 5). Filter, then
`summarize()`. Compare the Wilson intervals, not the point estimates.

**Regime analysis (S81).** Columns 21–23 classify each day by opportunity cost
and risk appetite, so "does this only work when the dollar is falling?" is a
query rather than a guess.

**Degradation monitoring (S75).** With live rows arriving by alert, rolling
20-trade expectancy, win rate, profit factor and average MAE can be compared
against the out-of-sample distribution. Falling below the validated threshold
sets `DEGRADED`: reduce risk or suspend. Do **not** re-optimise (S75).

---

## 5. Analysing a subset

```python
from validation.trades import load
from validation.stats import summarize, bootstrap_expectancy

trades = load("trades.csv")

sweep = [t for t in trades if t.session_type == "SESSION_SWEEP_RECLAIM"]
cont  = [t for t in trades if t.session_type == "SESSION_CONTINUATION"]

for name, subset in (("sweep/reclaim", sweep), ("continuation", cont)):
    s = summarize([t.realized_r for t in subset])
    b = bootstrap_expectancy([t.realized_r for t in subset])
    print(f"{name:16} N={s.n:4}  win {s.win_rate:.1%} "
          f"CI [{s.win_rate_ci.low:.1%}, {s.win_rate_ci.high:.1%}]  "
          f"exp {s.expectancy_r:+.3f}R  P(>0) {b.prob_positive:.1%}")
```

Splitting a sample into subgroups multiplies the ways to find a pattern that
is not there. Two subgroups of 40 trades each will differ; the question is
whether their Wilson intervals overlap. If they do, they are one population as
far as the evidence goes.
