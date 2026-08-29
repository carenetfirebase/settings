# HERMICANE v2

Phase 0 research harness for the XAUUSD macro-release strategy.

---

## Status, stated plainly

**Phase 0 is built and tested. Phase 0 has not been run on real data, because
this environment cannot reach any of the required data providers. Phase 1
(the Pine v2 port) has therefore not been started, and must not be.**

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

### 2. A wide plateau is not evidence when the subsets are nested

§3.4's plateau-versus-spike heuristic assumes adjacent thresholds are
independent looks at the data. They are not — the sample at 0.25 contains
almost everything in the sample at 0.20 — so one lucky small subset propagates
rightward and manufactures a run of four or five thresholds that all beat the
control while being mostly the same trades. A noise test caught this
producing a confident `PLATEAU` verdict on coin flips.

`sweep_threshold` now requires a plateau to be wide **and** to contain at least
one threshold that clears the control on its own lower confidence bound.

### 3. Three v1 defects need no data to condemn

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

## Example output

[`examples/synthetic/`](examples/synthetic/) holds a full run against the
synthetic world. Its first screen is a warning that it is not calibrated
output, and the constants file beside it is named
`calibrated_constants.SYNTHETIC.json` and fails `verify`. It is committed to
show the shape of the deliverable, not to say anything about gold.
