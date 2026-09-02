# L · Forward-testing protocol

What has to happen between "the backtest looks acceptable" and "this is running
on an evaluation account". S74, S75, S76.

A backtest is a claim about a strategy running on data that already existed when
the code was written. A forward test is the first evidence about a strategy
running on data that did not. They are not the same evidence, and only the
second one can catch a repainting bug — which is why this step is not optional,
however good step 9 looked.

---

## 1. Freeze

Before the first forward session:

- [ ] Export the full input set (TradingView: **Save indicator template**) and
      commit the values alongside the backtest report
- [ ] Record the git commit of `AURUM_NY_PRIME.pine` in use
- [ ] Record the Monte Carlo output: `P(pass)`, expectancy interval, 95th
      percentile drawdown
- [ ] Set `i_ddKill` to that 95th-percentile drawdown
- [ ] Write down the expected trade frequency (trades per week from the
      backtest). If the forward test produces three times that, something is
      wrong with the configuration, not with the market.

**Nothing in this list may change during the forward test.** Not after a losing
week; not after a sequence of losses; not because a filter "obviously" needs
adjusting. S74 is explicit: do not alter parameters during the sample merely
because losses occur. A parameter changed mid-sample restarts the sample.

---

## 2. Run

**Duration.** The longer of:

* 40 trading sessions, or
* 20 valid setups, or
* one full calendar month covering an NFP and a CPI release.

Twenty trades cannot prove an edge. That is not what this phase is for — it is
for proving the *implementation* works in real time: that signals fire when
expected, that fills happen where expected, that spreads at 09:35 are what the
model assumed, and that nothing repaints.

**Method** — any one of:

| Method | Catches | Misses |
|---|---|---|
| TradingView alerts, manually logged | repainting, signal timing, spread reality | fill quality |
| TradingView paper trading | the above, plus order mechanics | real slippage |
| FTMO free trial / broker demo | the above, plus realistic fills and spreads | psychology |

Prefer the FTMO free trial or a demo on the intended broker feed. It is the only
option that tests the spread and slippage assumptions against the venue that
will actually price the trades.

**Record every valid setup**, including the ones that lost and the ones you
would rather not have taken. A forward test with the bad trades omitted is not a
sample, it is a highlight reel. If a signal fires and you do not take it, log it
as taken at the signal price — otherwise the record measures the operator, not
the strategy.

---

## 3. Log

For each session, one line:

| Field | Why |
|---|---|
| Date, ET time of signal | timing drift versus the backtest |
| Score, grade, state at signal | did the engine agree with the backtest's distribution |
| Planned entry / stop / size | before the fill |
| **Actual fill and slippage** | the assumption most likely to be wrong |
| **Observed spread at entry** | validates or refutes `i_spreadUSD` |
| Exit type and realised R | the result |
| MAE / MFE in R | feeds the Monte Carlo |
| Anything the dashboard said that surprised you | repainting shows up here first |

The Pine alert already emits the full CSV row; the two columns to add by hand
are observed spread and actual slippage, because Pine cannot see either.

---

## 4. Compare against the backtest distribution

At the end of the sample, compare — with intervals, not point estimates:

| Metric | Backtest OOS | Forward | Concerning when |
|---|---|---|---|
| Trades per week | | | forward > 2× backtest |
| Win rate | | | forward below the OOS Wilson lower bound |
| Expectancy R | | | forward below the bootstrap 5th percentile |
| Average MAE R | | | forward materially higher — stops are being hunted |
| Realised slippage | modelled | observed | observed > modelled |
| Observed spread | modelled | observed | observed > modelled |

**Signal-timing check (the repainting test).** Take five forward signals and
compare the alert timestamp with where the strategy shows the signal on the
chart *now*. They must be the same bar. If the historical chart shows a signal
the alert never fired for, something repaints and everything above is void.

**Cost check.** If observed spread or slippage exceeds the modelled value, the
backtest was run with the wrong costs. Re-run step 4 of
`09_backtesting_protocol.md` with the observed numbers before deploying. This is
the most common reason a validated strategy underperforms live, and it is
entirely preventable.

---

## 5. Go / no-go

Deploy to an evaluation only if **all** hold:

- [ ] No repainting observed: every alert matches its bar on the chart
- [ ] Observed spread and slippage within the modelled assumptions
- [ ] Trade frequency within 2× of the backtest
- [ ] Forward expectancy inside the backtest bootstrap interval
- [ ] No rule violations by the operator (every valid setup logged)
- [ ] Parameters unchanged throughout the sample

Any box unticked means another cycle, not a smaller position size.

---

## 6. After deployment — degradation monitoring (S75)

Compute rolling 20-trade statistics from the live rows:

```
Expectancy₂₀, WinRate₂₀, ProfitFactor₂₀, AvgMAE₂₀
```

Compare against the out-of-sample distribution from the validation run. The
threshold must be set **in advance**, from the bootstrap, not chosen after a
drawdown. A defensible one: rolling expectancy below the 5th percentile of the
bootstrap distribution of 20-trade means.

```
DEGRADED  →  reduce risk, or suspend, pending review
```

**Do not automatically re-optimise after deterioration** (S75). Re-optimising on
the data that just produced a drawdown fits the strategy to the drawdown. The
correct responses are: reduce risk, suspend, or accept that the edge was smaller
than the sample suggested — which is the most likely explanation when the
out-of-sample sample was under 100 trades.

---

## 7. Kill switch (S76)

Stop, and require manual review before resuming, on any of:

| Trigger | Automated in Pine |
|---|---|
| Internal daily limit −1.5% | yes |
| Drawdown beyond the validated 95th percentile | yes, via `i_ddKill` |
| Spread or slippage materially above assumptions | no — operator/bridge |
| DXY, GC or XAU feed missing or stale | yes, via `feedsOK` |
| Rolling expectancy below the validated threshold | no — external monitor |

Three of the five are automated. The two that are not are the ones that need a
human looking at the log weekly — which is the actual, unglamorous requirement
this document exists to state.

---

## 8. What "it works" would mean

At the end of all of this, the honest best case is:

> On N out-of-sample trades the setup produced expectancy of +x.xxR with a 95%
> bootstrap interval of [a, b] and P(expectancy > 0) of p%. Block-bootstrap
> simulation of the FTMO evaluation gives a pass probability of q% with a 95th
> percentile drawdown of $d. Forward testing over M sessions produced results
> inside that distribution with no repainting and costs within assumptions.

That is a defensible claim. It is not "70% win rate", and it should not be
turned into one. If the numbers come out at 58% and +0.45R with a low drawdown
and a high pass probability, report that — it is the better strategy, and S1
ranks it above a manufactured 70%.
