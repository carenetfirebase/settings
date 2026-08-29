# HERMICANE v2

Phase 0 research harness for the XAUUSD macro-release strategy.

---

## Status, stated plainly

**Phase 0 is built and tested. It has not been run on real data, because this
environment cannot reach any of the required data providers, so no
`calibrated_constants.json` exists.**

`HERMICANE_v2.pine` exists anyway, at the operator's explicit direction, and it
is built around that gap rather than pretending it is closed. What ships enabled
is the control rule, which has no thresholds to calibrate. Every filter that
would consume an uncalibrated number ships **off**, and every such input is
labelled `UNCALIBRATED` in the Settings pane. The script is a measuring
instrument for running the ablation by hand on TradingView's data — the data
this environment could not reach — not a strategy to trade.

The handoff is explicit that every threshold in v2 comes from
`calibrated_constants.json`, and that Phase 1 does not begin until that file
exists. It does not exist. Rather than invent the constants or quietly
substitute whatever data happened to be reachable, the harness is built to
produce them the moment the inputs are available, and it refuses to emit a
constants file from anything else.

That refusal is mechanical, not editorial. `report.write_outputs` gates the
filename on provenance, and `report.verify_constants` — which any Pine
generation step should call first — raises on a file that is not fully
calibrated. There is one test for each half of that gate.

### What blocked the data

Every host in §3.1 was probed. All seven were refused at the network layer by
this environment's egress policy:

```
xau_1m               datafeed.dukascopy.com       blocked_by_policy   403 to CONNECT
dxy_1m               datafeed.dukascopy.com       blocked_by_policy   403 to CONNECT
us2y_intraday        databento.com                blocked_by_policy   403 to CONNECT
dgs2_daily           fred.stlouisfed.org          blocked_by_policy   403 to CONNECT
gold_daily           fred.stlouisfed.org          blocked_by_policy   403 to CONNECT
actuals_first_print  alfred.stlouisfed.org        blocked_by_policy   403 to CONNECT
consensus            api.tradingeconomics.com     blocked_by_policy   403 to CONNECT
```

Reproduce with `python -m phase0.cli check`. This is a property of where the
harness is running, not of the URLs — FRED's `DGS2` is free and keyless and
would otherwise be the easiest series in the table.

### The degradation, proposed rather than applied

The ingest layer is separate from the analysis layer precisely so this is
recoverable without touching any of the arithmetic. Export the series by any
means — a Dukascopy pull from a machine with egress, a FirstRate or Databento
subscription, a scraped calendar — and hand the files to `run`:

```
python -m phase0.cli run \
    --bars xau_1m.csv --yields us2y_1m.csv --dxy dxy_1m.csv \
    --calendar events.csv --daily-gold gold_daily.csv --daily-2y dgs2.csv \
    --out out/real
python -m phase0.cli verify out/real/calibrated_constants.json
```

Everything downstream of ingest is offline arithmetic. `python -m phase0.cli
check` prints, for each unreachable series, what it is needed for and what the
documented degradation costs. The one series with **no acceptable
degradation** is the intraday 2Y: v2 defines direction as
`-sign(Δ2Y) × sign(beta)`, so without it there is no direction signal, no
control rule, and no Phase 0. A daily 2Y change is not a substitute — it spans
the whole session and is contaminated by everything else that happened that
day.

---

## What was built

```
phase0/
  sources.py    the §3.1 table made executable: every series, its provider,
                what it is needed for, and its documented degradation, plus a
                live probe that classifies why a host could not be reached
  loaders.py    local CSV ingest (bars, daily series, calendar) with a hard
                refusal to accept a revised series where a first print is due
  stats.py      percentile bootstrap, intervals, sample-health labels
  beta.py       the rolling regime estimator: OLS of gold daily returns on
                ΔDGS2 over 60/90/120 days, carrying beta, R² and t
  panel.py      one row per release: identity, z-scored surprise, pre-event
                regime, post-event reaction, outcome
  control.py    the §3.3 control rule, bar by bar
  filters.py    every v1 condition as an independent sweepable predicate
  ablation.py   control baseline, per-filter ablation, threshold sweeps with
                plateau detection, the beta regime table, cost curve,
                walk-forward
  report.py     ablation_report.md, panel.csv/parquet, and the constants gate
  synthetic.py  a labelled synthetic world for exercising the machinery
  cli.py        check / run / verify
```

Standard library only, matching the AURUM-NY PRIME validation stack next door.
`pyarrow` is used for `panel.parquet` when it happens to be installed and the
CSV carries the same data when it is not.

Run the tests with `python -m pytest strategies/hermicane` from the repository
root. 43 tests, no network.

---

## Findings so far

Three of these come from building the harness rather than from running it, so
they hold regardless of what the data eventually says.

### 1. "Stop at 1.0 ATR" is underspecified, and the gap dominates the rule

§3.3 fixes the control's stop at one ATR but not the *timeframe* the ATR is
measured on, and that turns out to matter more than anything else in the rule.
Averaging more 1-minute bars does not produce a larger risk unit — the mean
true range of a 1-minute gold bar is a few tens of cents however many are
averaged — so "1.0 ATR" off 1-minute data is a stop of well under a dollar
placed into a release that routinely moves ten. It is taken out by the
retracement before direction has had a chance to matter.

The harness therefore treats the ATR basis as an explicit **structural choice,
not a calibrated constant**: `ControlSpec` carries the timeframe and the
period, `ablation.atr_basis_sensitivity` re-runs the control across 5m / 15m /
1h / 4h / daily, and the report prints that table apart from anything the
sweeps produced. **This has to be settled before any other number in Phase 0
means anything.** The current default — ATR(14) on 15-minute bars — is a
placeholder that the sensitivity table exists to replace.

A related consequence, visible in the synthetic run and worth watching for on
real data: directional accuracy and mean R can point in opposite directions. A
bucket where gold moved as predicted 94% of the time still lost 0.64R, because
entering at T+3 sits at the top of the impulse and the pullback reaches the
stop first. If that survives contact with real data, the control's *entry
timing* is the thing to fix, not its direction signal.

### 2. Three of v1's conditions cannot be filters at all

The control enters at T+3. The pullback depth, the origin hold and the micro
breakout all describe the half hour *after* that bar. Filtering the control on
them selects trades using information that does not exist when the order is
placed — and this is the false positive that looks like a discovery rather than
a bug, because the filtered subset really does perform better.

The first version of this harness had exactly that bug. The fix is not to
delete the conditions but to notice what they actually are: preconditions of a
**delayed entry**, which is what v1 does. So each filter now declares which
entry rules it is causal under, `apply_filters` raises rather than obliging,
the ablation reports the excluded ones as `NOT EVALUABLE` with the reason, and
`ablation.entry_mode_comparison` asks the real question — does waiting for the
break beat entering at T+3? — by comparing the two entry rules on the events
both of them traded.

`micro_breakout` turns out not to be evaluable as a filter in *either* mode: at
T+3 it has not happened, and under the delayed entry it *is* the entry, so every
traded row has one. Only the entry-rule comparison can answer it.

### 3. A wide plateau is not evidence when the subsets are nested

§3.4's plateau-versus-spike heuristic assumes adjacent thresholds are
independent looks at the data. They are not — the sample at 0.25 contains
almost everything in the sample at 0.20 — so one lucky small subset propagates
rightward and manufactures a run of four or five thresholds that all beat the
control while being mostly the same trades. A noise test caught this
producing a confident `PLATEAU` verdict on coin flips.

`sweep_threshold` now requires a plateau to be wide **and** to contain at least
one threshold that clears the control on its own lower confidence bound.

### 4. Three v1 defects need no data to condemn

- **Score components that are constant at entry.** v1's entry condition already
  requires the breakout and the 5-minute confirmation, so `breakoutScore` and
  `fiveScore` are pinned at 10 on every trade that happens — a fixed +0.8 that
  looks variable. With the 5-minute filter switched *off*, `fiveScore` stays
  10, so disabling a filter raises the score.
- **Macro confirmation is not independent confirmation.** Gold, DXY and the 2Y
  reprice off the same headline in the same second; requiring agreement inside
  a three-minute window counts one piece of information several times, and in
  v1 that is 25% of the score plus part of the price score.
- **The global surprise unit is a bug, not a tuning choice.** A single divisor
  of 0.20 saturates instantly for Jobless Claims, GDP, ISM, Retail Sales and
  JOLTS, pinning them at 10/10 on every release. The z-score against the same
  event type's own recent dispersion removes the input entirely.

The full line-by-line audit, including the ten defects that are Pine
implementation bugs rather than design errors, is in
[`docs/01_v1_audit.md`](docs/01_v1_audit.md) — written as requirements for v2
so they cannot be reintroduced.

---

## What has *not* been established

Being blunt about this, per §5:

- **The v2 thesis is untested.** Whether gold's directional response to a
  release is conditional on beta regime is the central claim of v2, and no
  real data has touched it. `ablation.beta_regime_table` will return
  `SUPPORTED`, `NOT SUPPORTED`, `UNDERPOWERED` or `UNTESTED`, and the report
  prints all four with equal prominence.
- **No filter has been evaluated.** Every ablation verdict in the committed
  example output is a property of the synthetic generator.
- **The sample-size problem has not gone away.** At ~100–120 US events a year
  the control gets perhaps 500–600 observations over five years, and any filter
  that keeps a fifth of them is back at n≈100 with a standard error that cannot
  separate a good system from a coin. `stats.sample_health` labels every
  reported n, and `ablation.MIN_EVALUABLE` refuses to let a filter pass on
  fewer than 30 surviving events.

## The Pine script

`HERMICANE_v2.pine` — Pine v6, 1-minute XAUUSD. Paste it into the Pine Editor.

Two entry modes, both causal:

| Mode | Entry | Which filters are offered |
| --- | --- | --- |
| `CONTROL` (default) | T+3, unconditionally | those knowable at T+3 |
| `BREAKOUT` | the break of structure after a retracement | all of them |

The script **refuses to start** if you ask for the pullback or origin-hold
filters in CONTROL mode, for the reason in finding 2 above.

How to use it:

1. Put it on a 1-minute XAUUSD chart. Anything else raises immediately — the
   3-minute impulse window and the time exits are counted in 1-minute bars.
2. Paste the real release calendar into the timestamps box, in UTC. The six
   dates shipped are examples. Mind daylight saving: 08:30 New York is 13:30 UTC
   in winter and 12:30 UTC in summer.
3. **Sweep the ATR timeframe first** (5 / 15 / 60 / 240 / D). Finding 1 is not
   a footnote — the control's sign can change across that range, and until it is
   settled nothing else you measure means anything.
4. Run the control with every filter off and write down the trade count and net
   profit. That is your baseline.
5. Switch **one** filter on. If it does not clearly beat the baseline, it has
   not earned its place — delete it rather than tuning it.
6. Repeat at 20 / 100 / 200 / 400 ticks of slippage. If the edge dies by 200,
   it is not tradable through a news print.

The dashboard separates **NO DATA** from **rejected**, because `TVC:US02Y`
intraday history is short on many accounts and a run that could not read the 2Y
looks otherwise identical to a run that found no setups. If the "no data" count
is not zero, the rest of the numbers are not measuring what you think.

`Point value` defaults to 1.0, which is right for spot XAUUSD units and wrong by
two orders of magnitude for a 100oz COMEX contract. Check it.

The script writes a CSV trade log to the Pine Logs pane, in the shape the Phase 0
harness reads, so a TradingView run can feed the offline ablation.

### Verification

There is no Pine compiler here, so `phase0/pine_lint.py` is the only check the
script gets. It looks for the mistakes that are silent or that fail at runtime:
`ta.*` inside a conditional block, a cross-timeframe `request.security` with no
inner `[1]`, `array.get` guarded by `and` where Pine does not promise
short-circuit evaluation, a loop that counts down on an empty array, table
writes past the declared size, and each of the thirteen v1 defects as an
assertion.

    python -m phase0.pine_lint HERMICANE_v2.pine

Every check has a test that feeds it broken Pine and asserts it fires — a lint
that reports nothing is otherwise indistinguishable from a lint that checks
nothing. **This is static analysis, not compilation. Expect to fix something on
first paste.**

## Example output

[`examples/synthetic/`](examples/synthetic/) holds a full run against the
synthetic world. Its first screen is a warning that it is not calibrated
output, and the constants file beside it is named
`calibrated_constants.SYNTHETIC.json` and fails `verify`. It is committed to
show the shape of the deliverable, not to say anything about gold.
