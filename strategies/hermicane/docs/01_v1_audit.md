# v1 defects, written as requirements for v2

The thirteen findings from the line-by-line audit of
`Hermicane_Macro_Shock_v1.pine`, restated so each one is a thing v2 must do
rather than a thing v1 did. Each will change backtest results; none is
cosmetic except where marked.

Note on scope: **the v1 source was not attached to this session**, so nothing
here has been re-verified against the file. These are recorded from the
handoff's audit so they survive into Phase 1 as a checklist, and the line
numbers are the handoff's.

Where a defect can be checked mechanically once v2 exists, the check is named.
The AURUM-NY PRIME stack next door has a `pine_lint.py` for exactly this
purpose and is the model to follow.

---

## Design errors — no amount of data changes these

### 1. A hard gate must never also contribute a score term

v1's `entryCondition` already requires `breakout` and `fiveMinOK`, so
`breakoutScore` and `fiveScore` are pinned at 10 on every trade that actually
happens: a fixed +0.8 on every final score, wearing the appearance of a
variable. Worse, with `use5mConfirm` off, `fiveScore` stays 10 — so *disabling*
a filter raises the score.

**v2**: a condition is either a gate or a score term. `filters.SCORE_COMPONENTS_TO_DROP`
records the two that must not return.

### 2. Macro confirmation is not independent confirmation

Gold, DXY and the 2Y all reprice off the same headline in the same second.
Requiring all four to agree within three minutes counts one piece of
information four times, and in v1 it is 25% of the score plus part of the price
score.

**v2**: rolling beta is the only orthogonal input in the design, because it is
estimated outside the event window. Macro alignment survives only if
`ablation` shows it beating the control on its own.

### 3. The global surprise unit saturates every non-CPI event

Dividing every surprise by a single `surpriseUnit` (default 0.20) is roughly
sane for CPI in percent and absurd for Jobless Claims in thousands, and for
GDP, ISM, Retail Sales and JOLTS. All of them pin at 10/10 on every release.

**v2**: `panel.rolling_surprise_z` divides by the rolling standard deviation of
the last ~20 surprises of the *same event type*, which puts every release on
one scale and deletes the input.

### 4. NFP surprise uses `|goldBias|`

An internally offsetting report — hot payrolls with a hot unemployment rate —
scores near zero and is silently discarded rather than flagged ambiguous.

**v2**: an event whose legs disagree is a distinct outcome and must be
recorded as such, not folded into "small surprise".

### 5. `impulseScore` rewards extension

`impulseATR / 0.40 × 5` maxes out at 0.80 ATR and stays at 10 all the way to
the 2.25 cap, so "too chasey" is penalised by the hard cap and rewarded by the
score at the same time.

**v2**: if an impulse-quality term survives ablation at all, it is a tent
function like the pullback term. `filters` splits the band into
`impulse_min` and `impulse_max` so the ablation can say which half, if either,
is doing the work.

---

## Implementation bugs — each changes backtest results

### 6. The runner trail un-trails itself

Lines 403/409 gate the trail on `favorableR >= tp1R`, recomputed from the
*current bar's* high/low. Once price pulls back, the else-branch fires
`runnerStop := activeStop`, discarding the trailed level and reverting to
breakeven. The runner effectively never trails.

**v2**: a latched `var bool tp1Reached`, reset at entry. Lint check: the trail
condition must not read a bar-local high/low.

### 7. Silent failure on missing macro data

v1 pulls `TVC:US02Y` and `TVC:DXY` at chart timeframe. Intraday history for
those is short, so older replays return `na`, `macroScore` becomes `na`, the
gate fails, and no trade fires with no error shown.

**v2**: surface the raw macro deltas on the dashboard, and distinguish
**rejected** from **no data**. A filter that cannot be evaluated is not a
filter that said no. The Phase 0 panel makes the same distinction with its
`FLAG_NO_*` flags.

### 8. `eventTrigger` misfires on chart load

`nz(time[1], 0) < eventTime` is true on the dataset's first bar, so an event
older than the loaded history triggers on bar 1 with a garbage baseline.

**v2**: guard with `bar_index > 0` and a sanity check on `time[1]`.

### 9. 5-minute confirmation differs between backtest and live

`request.security(sym, "5", close > open ? …)` with no offset returns the last
*closed* 5-minute bar historically and the *developing* bar in real time — two
different strategies wearing one name.

**v2**: `close[1] > open[1]` inside the security call. Phase 0's
`panel.five_minute_direction` applies the same rule and has a test.

### 10. Exit orders are not live on the entry bar

The management block is gated on `strategy.position_size`, which only updates
the bar after the fill under `process_orders_on_close`. That leaves one bar
unprotected.

**v2**: place the initial `strategy.exit` inside the entry block.

### 11. No timeframe guard

The three-minute window, the three-bar breakout and the minute arithmetic all
assume a 1-minute chart.

**v2**: `runtime.error` unless `timeframe.in_seconds() == 60`.

### 12. Stale anti-chase measurement

v1 combines `lookahead_off` with a `[1]`/`[2]` offset on 15-minute data, so at
08:30 it measures the 07:45→08:15 move — ending fifteen to thirty minutes
before the release it is meant to describe.

**v2**: measure pre-event drift on the chart timeframe. Phase 0's
`drift_atr` columns do this at 60m / 4h / 1d.

---

## Assumptions that must be made loud

### 13. Costs

v1 assumes 20 ticks of slippage — twenty cents on gold — and zero commission.
Real CPI-minute gold spreads are dollars wide.

**v2**: default to 100–200 ticks with a realistic commission, and report
results across the whole ladder. Phase 0's `control.COST_LADDER_TICKS` runs
20 / 100 / 200 / 400 and the report prints the curve. If the edge dies by 200
ticks it is not tradable through a news print, and that is the finding.

### 14. `pointValue = 1.0`

Correct for OANDA-style XAU units, wrong for 100oz contracts.

**v2**: make the broker assumption explicit and loud, on the dashboard and in
the inputs.

### 15. Cosmetic

Table cells default to black text, invisible on dark charts; the ARMED marker
never prints when arming and entry land on the same bar.

---

## What v2 must not reintroduce, in one list

A Phase 1 lint should assert all of these mechanically:

1. No score term that duplicates a hard gate.
2. No `request.security()` without both `lookahead_off` and an inner `[1]`.
3. No stateful helper evaluated inside `request.security()`.
4. No trail state recomputed from a bar-local extreme.
5. A `bar_index > 0` guard on every event trigger.
6. A `runtime.error` timeframe guard.
7. Initial `strategy.exit` placed in the entry block, not the management block.
8. Every threshold traceable to a key in `calibrated_constants.json`.
9. No filter present as a disabled input or an optional toggle — if Phase 0
   deleted it, it is gone.

---

## Addendum: a fourteenth defect, found while porting

### 16. Three conditions cannot be filters on a T+3 entry

Not a v1 defect — v1's entry waits for the breakout, so v1 is causal here — but
a defect the *port* introduced and which anyone reimplementing this will hit.

The control rule enters at T+3. The pullback depth, the origin hold and the
micro breakout all describe the half hour after that bar. Applying them as
filters to a T+3 entry selects trades on information that does not exist when
the order is placed. It is the dangerous kind of lookahead: the filtered subset
genuinely does perform better, so the result looks like a discovery.

**Requirement**: every filter declares the entry rules under which it is causal.
`phase0.filters.Filter.entry_modes` carries that, `apply_filters` raises
`NotCausal` rather than obliging, and the ablation prints the excluded ones as
NOT EVALUABLE with the reason. The Pine enforces the same rule with a
`runtime.error` when the pullback filters are requested in CONTROL mode.

The conditions themselves remain testable — as the entry rule, which is what
they are. `phase0.ablation.entry_mode_comparison` compares T+3 against the
delayed break on the events both rules traded.
