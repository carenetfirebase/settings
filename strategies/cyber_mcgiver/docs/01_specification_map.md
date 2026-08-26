# Specification map — S1 to S75

Every numbered section of the Cyber Mcgiver specification, and where it lives in
`CYBER_MCGIVER.pine`. Section markers appear as comments in the source, so this
table and the code cannot drift silently.

| S | Requirement | Where |
| - | ----------- | ----- |
| S1 | Trade only with the larger trend; HTF picks direction, execution TF picks location | §6, §11 |
| S2 | Scan the full trading day; classify by session; never veto on session | §7 (`sessionId`), §14 |
| S3 | Trendline expires if Touch #4 does not arrive (20 bars on 15m, 48 on 5m) | §10 (`tlExpired`) |
| S4 | $100,000 starting equity | `strategy(initial_capital = 100000)` |
| S5 | Risk 1% of current live equity | §11 (`budget = strategy.equity * i_riskPct / 100`) |
| S6 | Equity, not closed balance; no martingale | §11 — size is computed from `strategy.equity` at arm time and never references prior outcomes |
| S7 | Model margin; reduce, then skip | §11 (`lotsMarginMax`, `marginCut`) |
| S8 | Spot XAUUSD, not futures | no futures symbol is requested anywhere |
| S9 | 1.00 lot = 100 oz, exposed as an input | `i_contract` |
| S10 | Minimum lot, lot step, always round DOWN | `f_floorStep`, `f_lots` |
| S11 | Configurable spread, slippage, commission | §1.6, §5 |
| S12 | Breakeven means net of all four cost components | §5 (`costPerOz`), §13 (`beLevel`) |
| S13 | ATR(14) on the execution timeframe, Wilder/RMA | §4 (`ta.atr`) |
| S14 | 5m or 15m only, else block and say so | §3, §16 |
| S15 | Market mode from completed HTF candles only | §6 |
| S16–S18 | Daily / 4H / 1H bull conditions | §6 (`dailyBull`, `h4Bull`, `h1Bull`) |
| S19 | Unanimous bull ⇒ LONG | §6 (`bullRegime`) |
| S20–S22 | Daily / 4H / 1H bear conditions | §6 (`dailyBear`, `h4Bear`, `h1Bear`) |
| S23 | Unanimous bear ⇒ SHORT | §6 (`bearRegime`) |
| S24 | Disagreement ⇒ NEUTRAL ⇒ no trade | §6 (`marketMode == 0`), §11 gate |
| S25/S26 | BOS through the last confirmed swing plus an ATR buffer | §11 |
| S27 | Confirmed pivots only, 2/2 on 15m and 3/3 on 5m | §8, `pivLeft` / `pivRight` |
| S28/S36 | Touch #1 after BOS | §11 `STATE_WAIT_P1` |
| S29/S37 | Touch #2, correct side, ≥ 0.10 ATR separation | §11 `STATE_WAIT_P2` |
| S30/S38 | The line, its sign, and the normalised slope ceiling | §11, `f_tl` |
| S31/S39 | Touch #3 confirms: contact within tolerance and a close on the right side | §11 `STATE_CANDIDATE` |
| S32/S40 | Touch #4 on the same projected line | §11 `STATE_CONFIRMED` |
| S33/S41 | Rejection: direction, body ratio ≥ 0.35, close location ≥ 0.65 | §11 (`t4Body`, `t4Clv`) |
| S34/S42 | Entry one tick beyond the rejection candle, as a stop order | §11 (`entryPx`, `strategy.entry`) |
| S35/S43 | Structural stop beyond **P3** | §11 (`stopPx` from `p3Price`) |
| S44 | One trade per trendline; no Touch #5 | §11 (touch-4 consumption block), §12, §14 |
| S45 | After a stop-out return to `WAIT_BOS`, never to the retest state | §14 |
| S46 | Risk distance must be positive | §11 (`riskPx > 0`) |
| S47 | Exact 1% sizing, floored, re-verified, minimum-lot skip | `f_lots` |
| S48 | Structure → stop → size → risk, never the reverse | `f_lots` takes a risk distance and returns lots; no path writes a stop from a budget (asserted by `pine_lint`) |
| S49 | Maximum stop distance 3.0 ATR | §11 (`stopAtr <= i_stopAtrMax`) |
| S50 | Freeze 1R at entry | §12 (`posRisk` set once at fill) |
| S51–S53 | Exit model B: 50% at +1.2R, the rest runs | §11 (orders submitted with the entry), §13 |
| S54 | Breakeven needs a confirmed close beyond 1.2R, not a wick | §13 (`posBEdone`) |
| S55/S56 | Structural + ATR trail, monotone | §13 |
| S57 | 10R ceiling | §13 (`tpMaxLevel`) |
| S58 | Build scope: nothing from the "do not yet implement" list appears | no VWAP, ORB, DXY, VIX, alternate stops or exit models exist in the source |
| S59 | Pine v6, bar magnifier where supported | `strategy(use_bar_magnifier = true)` |
| S60 | No look-ahead anywhere | `docs/02_repainting_audit.md` |
| S61/S62 | The long and short state machines | §9 state constants, §11–§14 transitions |
| S63 | Visualise every structural element | §15 |
| S64 | The historical funnel with pass rates | §9 counters, §17 funnel panel |
| S65 | Performance analytics | §14 accumulators, §17 performance panel |
| S66 | Four separate tests | `i_dirMode` + chart timeframe; `docs/04_test_protocol.md` |
| S67 | Session breakdown | §17 session panel |
| S68 | MFE distribution 1.2R → 10R | §14 (`mHit*`), §17 |
| S69 | Loss analysis | §14 (`l*` accumulators), §17 loss panel |
| S70 | No win-rate target | nothing in the source references a target win rate |
| S71 | Use as much reliable history as available | a run-time choice, not a code constant |
| S72 | First report | template in `docs/04_test_protocol.md` |
| S73 | Report bad results; never quietly redesign | the funnel exists so a zero-trade result is explainable |
| S74 | Symmetric long/short | both engines share one code path parameterised by `dirState`; `pine_lint` fails if either side disappears |
| S75 | Core rules | all of the above |

## Deviations and judgement calls

The specification is silent on each of these. A choice had to be made to make
the engine deterministic; each one is an input, and each one is listed here
rather than buried.

1. **Armed-order expiry — `i_armBars`, default 3 bars.** S44 says an expired
   order kills the trendline but never says when an order expires. Three bars
   is a choice, not a finding.
2. **A Touch #4 that fails to arm consumes the line.** S32 says the *first*
   subsequent return is Touch #4 and S44 says a line gets exactly one
   opportunity. So a weak rejection, an impossible stop or an unfundable size
   all kill the structure. `i_killRej` relaxes this for the weak-rejection case
   only, for measurement.
3. **A lower low before P2 re-anchors P1.** If the next pivot violates the
   P1 level rather than building from it, the base has moved; that pivot becomes
   the new P1 instead of being discarded. The alternative — discarding the
   structure — would make P1 nearly unreachable.
4. **A pivot too close to P1 is ignored, not fatal.** Separation below 0.10 ATR
   simply does not qualify as P2; the search continues.
5. **A candidate whose slope fails the ceiling kills the structure** and is
   counted separately (`killed · slope filter`) so the funnel shows its cost.
6. **Losing the regime kills an unfilled structure** (`killed · regime lost`).
   An open position is *not* force-closed on a regime change; the specification
   gives exits, and inventing one would change the hypothesis.
7. **A close through the line by more than the tolerance kills the structure** —
   `i_killBrk`, default on. A support line closed through is not support.
8. **Protective orders are submitted with the entry**, not on the bar after the
   fill. Otherwise the first bar of every trade would run without a stop and the
   1%-risk claim would be false.
9. **Sizing uses the planned entry; R uses the actual fill.** S47 must size
   before the fill exists; S50 freezes R at entry. When the fill slips, realised
   risk differs slightly from planned risk — visible as MAE beyond −1R.
10. **A minimum-lot position has no partial.** Half of 0.01 lot floors to zero,
    so the whole position becomes the runner. It is not silently rounded up.
11. **Structure search pauses while a position is open.** One position at a
    time, per the state machine, so the funnel counts only actionable setups.
