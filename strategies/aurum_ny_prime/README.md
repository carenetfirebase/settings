# AURUM-NY PRIME v2.0

**XAUUSD FTMO New-York-open quantitative confluence research engine.**
Pine Script v6 strategy + external statistical validation framework.

Long only. One position at a time. No pyramiding. Non-repainting by
construction.

---

## What this is

A research engine for a specific hypothesis:

> During an established bullish gold regime, when Asia→London structure is
> bullish, macro opportunity-cost variables support gold, DXY behaviour is
> favourable, COMEX gold confirms, the New York opening range shows bullish
> acceptance, price holds above a rising NY-anchored VWAP, two mathematically
> confirmed 5-minute higher lows define ascending support, price returns for a
> third interaction with that support, rejects it, and then breaks short-term
> bullish microstructure — the resulting XAUUSD long has greater positive
> expectancy than a conventional NY-opening breakout.

The engine's job is to **test** that, not to prove it. Whether it holds is an
empirical question that this repository cannot answer, because answering it
requires running the strategy on real XAUUSD history in TradingView and feeding
the export through the validation tools here.

**No performance claims are made anywhere in this repository.** Every number in
the docs is either a target (labelled TARGET) or a worked example on clearly
labelled synthetic data.

## What is here

```
AURUM_NY_PRIME.pine          A · the strategy (Pine v6, ~1,540 lines)
docs/
  01_mathematical_spec.md    B · every formula, and the ambiguities resolved
  02_variable_dictionary.md  C · every variable and its unit
  03_parameter_table.md      D · defaults and research ranges
  04_repainting_audit.md     E · twelve hazards, what was done, how it is checked
  05_execution_audit.md      F · costs, fills, contract spec
  06_ftmo_risk_module.md     G · limits, schedule, kill switch, pass simulation
  07_dashboard.md            H · panels, diagnostics, alerts
  08_trade_export_format.md  I · 43-column export, one row per POSITION
  09_backtesting_protocol.md K · the exact sequence, in order
  10_forward_testing_protocol.md  L · what must happen before deployment
validation/                  J · external analytics (standard library only)
  aurum_validate.py            CLI: report / montecarlo / walkforward /
                               ablation / stability / lint
  stats.py                     Wilson intervals, summaries, IID bootstrap
  montecarlo.py                block bootstrap, FTMO pass paths
  trades.py                    export parsing, chronological split, walk-forward
  ablation.py                  ablation table, parameter-stability verdicts
  reference.py                 executable reference implementation of the setup
  pine_lint.py                 static checks on the Pine source
  tests/                       39 tests
examples/
  SYNTHETIC_trades_example.csv   randomly generated. NOT A RESULT.
```

## Quick start

**Chart.** XAUUSD, 5-minute. Set Strategy Properties per
`docs/05_execution_audit.md` — capital 100,000, commission 0.07 per contract,
slippage 2–4 ticks, **Bar Magnifier on**. The dashboard warns if the timeframe
or the capital does not match.

**Confirmation feeds.** `COMEX:GC1!`, `TVC:DXY`, `CBOE:VIX`, `FRED:DFII10`. All
are inputs; nothing is hard-coded to one broker.

**News.** Populate the blackout lists *before* the first run. Pine has no
economic-event calendar (S42), so the events are supplied manually and the
dashboard states how many were loaded.

**Then follow `docs/09_backtesting_protocol.md` in order.** Export the trades
from the Pine Logs pane and run:

```bash
python -m validation.aurum_validate report      trades.csv
python -m validation.aurum_validate montecarlo  trades.csv --paths 10000 --blocks 3,5,10
python -m validation.aurum_validate walkforward trades.csv --train 12 --test 3
python -m validation.aurum_validate lint        AURUM_NY_PRIME.pine
```

Run from `strategies/aurum_ny_prime/`. Standard library only — no numpy, no
pandas, no install step.

## Testing

```bash
python -m pytest strategies/aurum_ny_prime/validation/tests -q     # 39 tests
python -m validation.aurum_validate lint AURUM_NY_PRIME.pine       # 0 findings
```

TradingView owns the only Pine compiler, so the tests attack the problem from
two directions instead:

**Static checks on the Pine source.** Version header, declaration ordering,
comma-separated declarations (valid Python, invalid Pine), `lookahead_on`,
`request.security()` without an explicit lookahead, stateful helpers evaluated
inside a request, v5-era removals, integer division (`int / int` truncates in
Pine, so `wins / n` is 0), unguarded loops over possibly-empty arrays (Pine
counts *down* when `to < from`, so `0 to array.size(x) - 1` runs with k = -1 and
throws), and the presence of every S55 mandatory condition in the entry gate.
Three tests feed the checker deliberately broken scripts to prove it is not
passing vacuously.

The last two rules exist because the review pass that added them found live
instances of both classes in this file.

**Behavioural checks on a reference implementation.** The deterministic core of
the setup is implemented a second time, in Python (`validation/reference.py`),
from the same specification — where causality can be attacked directly. The
strongest test mutates **every bar after bar k** (flooding highs, collapsing
lows, moving closes) and asserts the first k decisions are bit-identical. Others
assert the opening range is immutable once locked, that pivots are never
reported before their confirmation bars, that session ranges are invisible until
their session ends, that position size always rounds down and never breaches the
budget, that the hard risk cap binds, and that removing any single mandatory
condition removes the trade.

There is also an end-to-end fixture: a textbook S83 day, built bar by bar, on
which the engine arms with score 94, grade A++, R = 2.05 and 2.39R of clearance.

**The gap this leaves, stated plainly:** the behavioural tests exercise the
Python reference, not the Pine. The two are written from one specification, and
the structural defences plus the linter are what carry the claim across. That is
why `docs/10_forward_testing_protocol.md` requires a live forward test before
any evaluation deployment — realtime bars are the only place a repainting bug
can no longer hide.

## Design decisions worth knowing before you read the code

**No realtime spread filter, and the script says so.** Pine has no bid/ask. What
exists is a *modelled* cost used in sizing and stop buffers, labelled
`MODELLED` on the dashboard and `modeled_spread` in the export. The real filter
belongs in the execution bridge (S27).

**No economic calendar.** `request.economic()` is not an event calendar. Events
are user-supplied timestamps, and the dashboard shows the count so an empty
calendar is visible rather than assumed (S42).

**Ablation changes the denominator.** Switching a component off removes its
weight from *both* sides of the score, so the 80 threshold keeps its meaning.
Leaving the denominator at 100 while some blocks can never score would silently
move the threshold (S71).

**One row per position, not per exit leg.** Three partial exits produce three
closed trades in TradingView's list. Treating those as independent observations
would triple the sample and wreck every statistic.

**Floating loss counts.** `strategy.equity` includes open positions, and the
Monte Carlo applies each trade's MAE to running equity before its result — so a
day that dipped 5.2% and recovered is scored as a breach, as it would be at the
firm.

**Risk falls near the target.** At +9% the strategy risks 0.15% to make the last
1%. It takes longer. The objective near completion is to protect the pass, not
to finish quickly (S8).

**Zero trades is a valid day.** Sixteen mandatory conditions gate every entry
(S84).

## The honest summary

Win rate is *not* the primary optimisation objective. The ranked priorities are
capital preservation, setup quality, positive expectancy, FTMO survival
probability, low drawdown, statistical robustness, execution realism,
profitability — and only then win rate.

If the genuine out-of-sample result is 58% with +0.45R expectancy and a low
drawdown, that is a better strategy than a 70% win rate obtained by tuning, and
the tools here are built to report it that way. The dashboard shows TARGET and
ACTUAL in separate columns and never blurs them (S87); the report prints
`VERDICT: PRELIMINARY. The sample is too small to conclude anything` whenever
the out-of-sample block is under 100 trades, however good the numbers look.

The strategy's edge has to survive attempts to disprove it. Only then is it a
candidate for forward testing — and forward testing is not deployment either.
