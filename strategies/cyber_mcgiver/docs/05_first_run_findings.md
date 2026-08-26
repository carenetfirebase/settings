# First run: zero trades, and what caused it

## What was observed

| Run | History | Result |
| --- | ------- | ------ |
| 15m, deep backtest | 10 years | Completed cleanly. **0 trades.** |
| 5m, deep backtest | 10 years | Pine runtime abort: `label.new() bar offset too far from current bar`. Re-ran with drawing disabled: **0 trades.** |
| 5m, deep backtest | 20 years (2006–2026) | **0 trades.** |

Funnel evidence: BOS fired and candidate trendlines formed, but nothing
survived to P3 confirmation.

Zero trades over twenty years on both timeframes is not a rare setup. It is a
broken engine, and it was broken in v1.0 in four places — **all four of them
choices I made where the specification is silent, not requirements of the
hypothesis.** The hypothesis has not been tested yet.

## Cause 1 — the regime was a survival condition, not a gate

S1 says the higher timeframes determine *which direction may be traded*. v1.0
also required unanimity on **every bar** of the structure build, and killed the
structure the moment it lapsed.

The 1H bull condition includes `close_1H > EMA20_1H`. The pullback that creates
Touch #3 and Touch #4 is *precisely* a move back below the 1H EMA20. So the
engine destroyed each structure at the exact moment it was about to become a
setup. Building BOS → P1 → P2 → P3 takes 20–50 execution bars; the requirement
that a flickering 1H condition hold continuously across all of them is close to
unsatisfiable.

**Fix:** `Higher-timeframe regime is applied` — default *Gate at BOS and entry*.
Unanimity is now checked when the break of structure is taken and again when the
order is armed, which is what S1 actually asks for. The old behaviour is still
available as *Continuous (kill on loss)*, and blocked entries are counted.

## Cause 2 — no timeout on the build states

S3 gives the confirmed line an expiry. v1.0 gave `WAIT_P1`, `WAIT_P2` and
`CANDIDATE` none at all. A structure that never found its next pivot sat forever,
and — because the state machine only returns to `WAIT_BOS` through an
invalidation — **blocked every subsequent break of structure indefinitely**.

This is also the cause of the 5m crash. A candidate line anchored thousands of
bars back eventually exceeded Pine's ~10,000-bar drawing offset limit.

**Fix:** `Structure build expiry after BOS`, default 60 bars, counted as its own
funnel row. Drawing calls are additionally bounds-guarded.

## Cause 3 — a failed sub-condition destroyed the whole structure

Three separate paths threw away everything and returned to `WAIT_BOS`:

* a P1→P2 line whose slope exceeded the ceiling;
* a pivot that formed through the candidate line;
* a close through the line by more than the contact tolerance.

The third is the worst. A rising line extended right climbs at up to 0.25 ATR
per bar; price does not reliably climb with it, so the candidate was usually
broken within a handful of bars.

**Fix:** all three now *re-anchor* — the offending pivot becomes the new P1 and
the search continues, which is what a chartist does with a bad line. Each
original behaviour remains as an input (`i_slopeKills`, `i_throughKills`,
`i_killBrk`, now off by default) so the strict variant stays measurable.

## Cause 4 — one trade per trendline, applied to setups that never armed

S44 gives a confirmed line one opportunity. v1.0 applied that to any Touch #4
that failed to *arm* — weak rejection, unfundable size — consuming the line
without a trade.

**Fix:** `One trade per trendline (S44)` is now an input, **off by default at
the operator's direction**. The confirmed line trades every qualifying touch
until it expires or breaks. This is a deliberate departure from S44 and is
recorded here rather than hidden.

## New instrumentation: rare, or broken?

The funnel could say *that* candidates died, not *why*. It now reports:

```
— why P3 fails —
P3 candidates tested          how many pivots were even evaluated against the line
· missed the tolerance        wick outside 0.12 ATR
· contact, wrong close        touched the line but closed through it
· closest miss (ATR)          the best contact ever achieved

— why Touch #4 fails —
T4 within 3× tolerance        price came back to the neighbourhood at all
T4 contact                    inside the tolerance
· contact, wrong close
· rejection: direction / body ratio / close location

— structure attrition —
re-anchored P1, killed · build timeout, killed · regime lost,
killed · line expired / broken / weak Touch #4 / slope filter,
blocked at entry · regime, skipped · stop / size / margin
```

The reading rule:

* **`P3 candidates tested` = 0** → the engine is not reaching the test. Still a
  bug; look upstream at BOS and P2.
* **Many tested, `closest miss` large (> 0.5 ATR)** → the geometry never comes
  near the line. The tolerance is not the problem; the line construction is.
* **Many tested, `closest miss` small, few passes** → genuinely rare. *This* is
  the finding S73 is about, and the tolerance becomes a legitimate experiment.
* **P3 passes but `T4 within 3× tolerance` = 0** → confirmed lines are never
  revisited; the expiry window is too short for the slope.

## What has not changed

The hypothesis is untouched. Regime definitions, BOS, P1/P2/P3 geometry,
contact tolerance, slope ceiling, rejection thresholds, the P3 structural stop,
1% sizing, exit model B, the 10R ceiling: all exactly as specified. Nothing was
loosened to manufacture trades — what was removed was bookkeeping that had no
basis in the specification.

Per S73: the first run produced zero trades, and that is reported here as a
result, not quietly designed away.
