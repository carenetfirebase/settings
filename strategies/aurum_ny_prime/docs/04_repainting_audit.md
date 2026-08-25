# E · Repainting audit

Every mechanism in the strategy that *could* leak future information, what was
done about it, and how the claim is checked. S77 asks for the audit; S78 asks
specifically about `request.security()`.

The rule the whole audit reduces to: **a decision taken on bar *t* may only use
values that were final at the close of bar *t*.**

Six of the twelve hazards below are checked automatically — by the linter, by
the test suite, or by both. The rest are reasoned, and are re-checked whenever
the file changes. The coverage table at the end says which is which.

---

## 1. Pivot hindsight

**Hazard.** `ta.pivotlow(left, right)` describes a bar that is `right` bars in
the past. Reading the pivot as though it were known when it printed back-dates
knowledge by `right` bars, and on a 5-minute chart that is fifteen minutes of
free information.

**Treatment.** The pivot's own bar index is recorded as `bar_index - right`, and
the value is only *used* from the bar on which `ta.pivotlow()` returned it. The
third touch additionally requires `bar_index − i₂ > right`, which cannot be true
until P₂ has genuinely confirmed.

**Verification.** `test_pivots_are_only_reported_after_their_confirmation_bars`
asserts `index − p₂.index ≥ right` on every bar of the fixture.

---

## 2. The third touch is never a confirmed pivot (S32)

**Hazard.** The natural way to write "the third touch is a higher low" needs
three bars *after* the touch to confirm it — by which time the entry is stale
and the backtest has silently entered on information from the future.

**Treatment.** Touch #3 is a **candidate** higher low. It is proved by price
breaking the confirmation level, not by a pivot function. The engine arms on the
touch bar's close and the stop order rests above the swing.

**Verification.** Structural: no `ta.pivot*` call participates in the touch-3
condition. `test_future_bars_cannot_change_past_decisions` would fail if one
did.

---

## 3. Higher-timeframe contamination (S78)

**Hazard.** `request.security()` on a higher timeframe returns the *developing*
HTF bar on recent chart bars. Historically it looks clean; in real time the
value changes under you, and a backtest built on it is fiction.

**Treatment.** Two independent defences on every call:

1. `lookahead = barmerge.lookahead_off` — explicit on all eleven calls.
2. An **inner `[1]` offset** inside the requested expression, so the value
   returned is the last *completed* HTF bar even on the current chart bar.

```pine
f_htfA() =>
    e = ta.ema(close, i_ema4h)
    [close[1], e[1], e[1 + i_emaSlopeLB]]      // completed candles only
```

`lookahead_off` alone is not enough; the inner offset is what makes historical
and realtime behaviour identical.

**Verification.** `test_pine_declares_no_lookahead_anywhere` asserts that the
count of `request.security(` equals the count of
`lookahead = barmerge.lookahead_off`, and that the string `lookahead_on` does
not appear anywhere in the file. The linter flags any future call that omits the
argument.

---

## 4. Stateful expressions inside `request.security()`

**Hazard.** A helper with `var` state evaluated inside a request maintains that
state in the *requested symbol's* context, where bar alignment, gaps and session
boundaries differ from the chart. It is also the construct most likely to behave
differently between historical and realtime bars.

**Treatment.** No stateful helper is ever passed to `request.security()`. Only
raw series are requested (`close`, `hlc3`, `volume`, a built-in with an explicit
offset), and every derived quantity — anchored VWAP, ROC, EMA, correlation — is
computed on the chart, where bar alignment is one-to-one.

```pine
[dxC, dxTP] = request.security(i_symDXY, timeframe.period, [close, hlc3], ...)
// the DXY anchored VWAP is then accumulated locally, on chart bars
```

**Verification.** `pine_lint.py` rule `security-state` fails the build if a
helper containing `var` appears inside a request.

---

## 5. Pivot highs on higher timeframes

**Hazard.** Holding "the last confirmed 15m pivot high" inside the requested
expression is case 4 again.

**Treatment.** The request returns `ta.pivothigh(high, l, r)[1]`, which is
non-`na` only on the bar where the pivot confirmed; the last value is then held
in a chart-context `var`.

---

## 6. Future session knowledge

**Hazard.** Reading `AsiaHigh` while the Asia session is still running means
reading a number that will still change.

**Treatment.** Session extremes accumulate into `*_run` variables and are
published to the variables the strategy actually reads **only on the first bar
after the window closes**. The `ready` flag gates every consumer.

**Verification.** `test_session_ranges_are_not_visible_before_the_session_ends`.

---

## 7. Opening-range knowledge before the range exists

**Hazard.** Same as 6, and worse, because the ORB rule is the spine of the
setup.

**Treatment.** `orh`/`orl` are `na` until 08:35 ET and are then frozen for the
day. `orReady` gates every consumer, and `noTradeReason` reports
`NO TRADE — OR NOT DEFINED` before the lock.

**Verification.** `test_opening_range_is_locked_and_immutable` asserts the lock
happens at or after 08:35 and that the locked values never change for the rest
of the session.

---

## 8. Trendline hindsight

**Hazard.** Drawing a line through two pivots and then evaluating touches at
bars *between* them — the classic backtested-trendline error, which is
indistinguishable from precognition.

**Treatment.** `TL(j)` is only evaluated for `j > i₂ + right`, i.e. strictly
after P₂ is confirmed. The line is never evaluated in the past.

---

## 9. Daily levels from the wrong day

**Hazard.** `request.security(..., "D", ...)` returns the broker's daily bar,
whose boundary is a server rollover that varies by feed and by DST. Two feeds
would disagree on PDH, and the current developing daily bar can leak.

**Treatment.** PDH/PDL/PDC/DO and PWH/PWL are computed internally on ET calendar
boundaries from chart bars. No request is involved and the boundary is
reproducible.

---

## 10. Intrabar fills

**Hazard.** Assuming a stop entry, a target and a stop-loss can all be resolved
inside one bar in a known order. On a 5-minute bar the true path is unknown.

**Treatment.**
* `calc_on_every_tick = false`, `process_orders_on_close = false` — decisions are
  made on completed bars, orders execute on subsequent bars.
* The entry is a stop order; it can only fill at or worse than its trigger.
* Exit brackets are submitted while the entry order is still working, so the
  position is protected from the instant it fills rather than from the next bar.
* Bar Magnifier is **required** for formal testing (see `05_execution_audit.md`)
  precisely because intrabar order is otherwise assumed.

Residual risk is stated rather than solved: on a bar that contains both the
target and the stop, the emulator's assumption may flatter the result. That is
why the runner's contribution is examined separately in the trade export.

---

## 11. Repainting through the news list

**Hazard.** Populating the blackout list *after* looking at which days lost is
hindsight laundering — the most tempting form, because the code looks innocent.

**Treatment.** The list is an input, and the export records `news_blackout` per
trade. The protocol (`09_backtesting_protocol.md`) requires the calendar to be
filled from a published economic calendar for the whole test period **before**
the first backtest run, and the dashboard states how many events were supplied.

This one cannot be enforced by code. It is enforced by writing down what was
loaded and when.

---

## 12. Statistics computed over the whole file

**Hazard.** In-script performance statistics that re-scan the trade list every
bar can accidentally include trades that had not happened yet.

**Treatment.** Statistics are **incremental**: counters update only inside the
`justClosed` branch. There is no backward scan, and the panel on bar *t* can
only reflect positions closed at or before *t*. (It is also O(1) per bar rather
than O(n²) over the history.)

---

## Automated coverage

```
python -m validation.aurum_validate lint AURUM_NY_PRIME.pine
python -m pytest strategies/aurum_ny_prime/validation/tests -q
```

The linter also carries two rules that are not repainting hazards but are Pine
semantics that read as correct in every other language in this repository, and
that a review pass caught live in this file: `int / int` is integer division
(so a win rate computed that way is always 0), and `for k = 0 to array.size(x) - 1`
counts **down** when the array is empty, running with `k = -1` and throwing on
`array.get`.

| Hazard | Automated | Test |
|---|---|---|
| Pivot hindsight | yes | `test_pivots_are_only_reported_after_...` |
| HTF lookahead | yes | `test_pine_declares_no_lookahead_anywhere`, linter |
| Stateful security expressions | yes | linter rule `security-state` |
| Session knowledge | yes | `test_session_ranges_are_not_visible_...` |
| Opening-range lock | yes | `test_opening_range_is_locked_and_immutable` |
| General future leak | yes | `test_future_bars_cannot_change_past_decisions` |
| Trendline hindsight | reasoned | covered by the causality test |
| Intrabar fills | no | mitigated by Bar Magnifier + modelled costs |
| News-list hindsight | no | procedural (protocol) |

The causality test is the strongest of these: it mutates **every bar after bar
k** — flooding highs, collapsing lows, moving closes — and asserts the first k
decisions are bit-identical. Any future leak in the reference implementation
fails it immediately.

**What that test does not prove.** It exercises the Python reference, not the
Pine. The two are written from the same specification, and the structural
defences above (plus the linter) are what carry the claim across to Pine. That
gap is real, and it is the reason `10_forward_testing_protocol.md` requires a
live forward test on the finalised configuration before any evaluation
deployment: realtime bars are the only place where a repainting bug can no
longer hide.
