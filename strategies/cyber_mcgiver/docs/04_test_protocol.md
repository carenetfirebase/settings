# Test protocol and report template (S66, S71, S72)

## Before the first run

1. Chart: **XAUUSD**, spot/CFD feed — not `GC1!` (S8). Use one broker feed for
   every test; pivots differ between feeds and a mixed sample is not a sample.
2. Timeframe: **15m** or **5m**. Anything else blocks entries by design.
3. Strategy Properties → set them to match the modelled costs. The top-right
   panel prints the required numbers and turns red if they disagree:
   * Slippage: **25 ticks** (= spread ÷ 2 + per-side slippage, at the baseline
     $0.30 / $0.10).
   * Commission: **0.035 USD per contract**, cash per contract (= $7.00 per lot
     round turn at 100 oz).
   * Initial capital: **100,000**; Order size: leave as the script sets it —
     quantity is passed per order and Properties must not override it.
4. Recalculate: leave *After order is filled* and *On every tick* **off**. Both
   change the code path and neither is part of the hypothesis.
5. History: use as much as the plan and feed provide, at least three years
   (S71). Note the actual first and last dates in the report — a 15m XAUUSD
   chart on a lower plan may reach back only a fraction of that, and the sample
   size claim depends on it.

## The four tests (S66)

Run each on its own, record each on its own. Do not read the combined column as
if it were a system.

| Test | Chart | Direction under test | What it answers |
| ---- | ----- | -------------------- | --------------- |
| A | 15m | Long only | Does the hypothesis work at all? |
| B | 15m | Short only | Is it symmetric, or is it just long gold? |
| C | 5m | Long only | Does the same structure survive at higher frequency? |
| D | 5m | Short only | Both of the above at once |

For each test capture: the funnel panel, the performance panel, the session
panel, the loss panel, and the Pine Logs CSV.

Then, and only then, produce the combined statistics — as a separate table, not
as a replacement for the four.

## Report template (S72)

Fill this in from the panels. Leave a section empty rather than estimating it.

**A. Compile status.** Errors and warnings, and what was changed to clear them.

**B. Visual validation.** Screenshots of at least five separate P1/P2/P3/Touch-4
structures, half long and half short. For each, state whether the line Pine drew
is the line you would have drawn manually. This is the check that matters most:
if the trendlines are wrong, every number below is noise.

**C. Funnel.** The stage counts and pass rates, plus the attrition rows. The
question to answer is *where* candidates are lost, not whether there are few.

**D. 15m long results.** Every metric in the performance panel.

**E. 15m short results.** Same.

**F. 5m long results.** Same.

**G. 5m short results.** Same.

**H. Session breakdown.** Trades, win %, expectancy R, PF, avg MFE, max DD per
session. No session is removed on this pass, whatever it shows (S67).

**I. MFE distribution.** P(MFE ≥ 1.2R) through P(MFE ≥ 10R). This is what
decides whether "50% at 1.2R plus a runner" is an intelligent architecture or an
assumption — if P(MFE ≥ 3R) is negligible, the runner is paying for nothing.

**J. Problems.** Any rule producing behaviour that surprised you, including
rules that behaved exactly as written but not as intended.

**K. Recommendation.** Exactly one next calibration experiment. One.

## Rules for reading the results (S70, S73)

* The question is `E[R] > 0`, after costs, in both directions, across the whole
  sample. Nothing else is being asked yet.
* Few trades is a finding. Show which gate causes the rarity; do not loosen it.
* Zero trades is a finding. The funnel says which stage emptied.
* If 5m fails and 15m works, report that. If shorts fail and longs work, report
  that. If it loses money, report that.
* Do not change a parameter and re-run before the baseline has been recorded.
  Once you do, keep a chronological split: calibrate on the earlier portion and
  leave the most recent portion untouched for validation (S71).
