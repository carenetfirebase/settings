# CYBER MCGIVER v1.0

A deterministic, non-repainting Pine Script v6 `strategy()` that tests one
hypothesis on XAUUSD:

> Does a mathematically confirmed trendline retest, taken only in the direction
> of unanimous 1D / 4H / 1H trend, have positive expectancy after realistic
> costs?

It is a **research engine**. It is not optimised, not calibrated toward a win
rate, and not tuned to any particular result. Version 1 exists to *measure*.

```
strategies/cyber_mcgiver/
├── CYBER_MCGIVER.pine          the strategy
├── docs/
│   ├── 01_specification_map.md S1–S75 → line of code, plus every deviation
│   ├── 02_repainting_audit.md  what each decision could see when it was made
│   ├── 03_trade_log_format.md  the CSV emitted to Pine Logs
│   └── 04_test_protocol.md     tests A–D and the report template
└── validation/
    ├── pine_lint.py            static checks on the Pine source
    ├── reference.py            executable reference for the closed-form maths
    └── tests/                  32 tests pinning that maths
```

## The hypothesis, as implemented

1. **Regime.** 1D, 4H and 1H must agree (S16–S24). Disagreement is `NEUTRAL` and
   nothing is traded. No countertrend trades exist in the code.
2. **Break of structure.** Price must close through the most recent confirmed
   swing extreme, plus a 0.05 ATR buffer (S25, S26).
3. **P1 → P2.** Two confirmed pivots in the trend direction, separated by at
   least 0.10 ATR, define a candidate line `TL_j = L2 + m(j − i2)` whose
   normalised slope `|m| / ATR` must not exceed 0.25 (S29, S30, S37, S38).
4. **P3 confirms.** A third confirmed pivot must contact the projected line
   within 0.12 ATR and close on the correct side of it (S31, S39). The line is
   only now real.
5. **Touch #4 is the setup.** The first subsequent return to the same line,
   within the same tolerance, with a rejection candle: directional close, body
   ratio ≥ 0.35, close location ≥ 0.65 (S32–S33, S40–S41).
6. **Entry is a break, not a touch.** A stop order one tick beyond the rejection
   candle's extreme (S34, S42).
7. **Stop is structural, and it is P3.** `P3low − 0.10 ATR` for longs (S35, S43).
   The account never moves the stop; the stop moves the position size (S48).
8. **Size is the consequence.** 1% of *current equity*, costs inside the
   risk-per-lot, rounded **down**, re-verified, margin-checked, else skipped
   (S46, S47, S7, S10).
9. **Exit model B only.** 50% at +1.2R, cost-adjusted breakeven on a *confirmed
   close* beyond 1.2R, then a structural + ATR trail to a 10R ceiling
   (S51–S57).
10. **One trade per trendline.** Fill, stop-out, expiry or invalidation kills the
    line. The next trade needs a completely new BOS (S44, S45).

## Running the four tests

Load the script on **XAUUSD** and set the chart to **5m** or **15m** — any other
timeframe blocks entries and the panel reads `CYBER MCGIVER REQUIRES 5m OR 15m`.

| Test | Chart | `Direction under test` |
| ---- | ----- | ---------------------- |
| A    | 15m   | Long only              |
| B    | 15m   | Short only             |
| C    | 5m    | Long only              |
| D    | 5m    | Short only             |

Run them separately and record them separately (S66). Set Strategy Properties
to match the modelled costs before reading any result — the panel tells you the
exact numbers and turns red if they disagree. Full procedure and the report
template: `docs/04_test_protocol.md`.

## Reading the chart

Five panels, each switchable:

* **top right** — regime, state, why it is not trading right now, line expiry
  countdown, live equity and 1R budget, cost agreement.
* **bottom right** — the funnel (S64): bars → regime → BOS → P1 → P2 →
  candidate → P3 → Touch #4 → rejection → armed → filled → completed, with the
  pass rate at each stage and a full attrition breakdown underneath.
* **bottom left** — performance (S65) split LONG / SHORT / ALL, including the
  MFE distribution from 1.2R to 10R.
* **top left** — the same edge statistics grouped by session (S67).
* **middle left** — loss analysis (S69).

On the chart itself: BOS markers, P1/P2/P3 labels, the candidate line dashed and
the confirmed line solid, the Touch #4 candle coloured and labelled `T4 ✓` or
`T4 ✗`, entry, structural stop, 1.2R, cost-adjusted breakeven and the 10R
ceiling. This is there so the line Pine drew can be checked against the line you
would have drawn (S63).

## What this repository can and cannot verify

Verified here, by `validation/`:

* the sizing arithmetic, including the three worked examples in S5, the
  round-down rule, the post-rounding re-check, the margin reduction, and the
  skip when the minimum lot cannot be funded;
* the trendline projection, contact tolerance, and rejection measures;
* session classification across a daylight-saving boundary;
* R, expectancy, profit factor and drawdown definitions;
* structural properties of the Pine source: no `lookahead_on`, no bare
  `security()`, no integer division, no use-before-declaration, every specified
  state constant, funnel counter and diagnostic string present.

**Not verified here:** that the script compiles, and every historical result.
TradingView owns the only Pine compiler and the only XAUUSD history this
strategy is meant to run on. Sections C–J of the S72 report — funnel counts,
per-timeframe results, session breakdown, MFE distribution — can only be filled
in by pasting the script into a chart and reading the panels. Nothing in this
repository should be read as a claim about how the strategy performs.

## Known limitations, stated rather than buried

* **Spread is modelled, not observed.** Pine has no bid/ask. Spread, slippage
  and commission are inputs that feed sizing and the breakeven stop; the
  backtester's own costs are compile-time constants (25 ticks, $0.035 per
  contract per side) because Pine forbids wiring them to inputs. Change the
  inputs and the panel tells you what to change in Strategy Properties.
* **Intrabar sequencing is an assumption.** When a bar contains both the stop
  and the 1.2R limit, the result depends on TradingView's fill model.
  `use_bar_magnifier = true` is requested; on plans without it, the assumption
  is coarser and the 1.2R hit rate is the number most affected.
* **One position at a time.** Structure search is suspended while a trade is
  open, so setups that form during a trade are never counted. The funnel counts
  what the engine could act on, not what a chart contains.
* **Quantity is passed in ounces.** Sizing assumes the symbol earns $1 per
  ounce per $1 move, which is true of spot XAUUSD CFD tickers and false of some
  index and futures tickers. The panel prints the resulting P/L per lot per $1
  move and turns red if the symbol's point value is not 1.0. If it is red, every
  dollar figure — including the 1% risk — is scaled wrong; change the symbol.
* **`request.security` history.** The 1D EMA200 needs 200 daily closes before
  any regime is emitted, so the first months of any backtest are inert by
  construction.

Every place the specification was silent and a choice had to be made is listed
in `docs/01_specification_map.md` under *Deviations and judgement calls*. None
of them are hidden in the code.
