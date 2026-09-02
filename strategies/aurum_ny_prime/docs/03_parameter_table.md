# D · Parameter table

Defaults, research ranges, and — for the ones that matter — what a wrong value
does. Ranges are the values to perturb in the stability sweep (S70); they are
**not** a grid to search. Searching thousands of combinations is prohibited by
S85, and the sweep exists to find plateaus, not peaks.

Perturb one parameter at a time by ±10–20%, export one CSV per value, then:

```
python -m validation.aurum_validate stability 1.00=a.csv 1.25=b.csv 1.50=c.csv
```

The verdict line is what matters: `PLATEAU` keeps the value, `ISOLATED PEAK`
rejects it, `EDGE PEAK` means the range was too narrow to conclude anything.

---

## Mode

| Input | Default | Options | Note |
|---|---|---|---|
| Evaluation mode | FTMO 2-Step | 2-Step / 1-Step / Research Only | Research Only removes the target hard-stop |
| Evaluation phase | Phase 1 | Phase 1 / Verification | selects 10% or 5% target |
| Entry mode | Conservative | Conservative / Moderate | S35: compare out-of-sample, do not pick the winner on final OOS |
| Stop model | A · Touch #3 | A / B · Pivot #2 | S46: test independently |
| XAU volume mode | Broker volume | 5 options | recorded in every trade row |

## Sessions (America/New_York)

| Input | Default | Research | Note |
|---|---|---|---|
| Asia | 20:00 → 02:00 | fixed | S10 |
| London | 02:00 → 08:20 | fixed | S11 |
| NY opening range | 08:20 → 08:35 | 08:20–08:30 / 08:35 / 08:45 | wider range = fewer, larger setups |
| Entry window | 08:35 → 11:30 | end 10:30 / 11:00 / 11:30 | S9 |
| Flatten | 12:00 | 12:00 / 13:00 | runner mode moves this to 16:00 |
| Max sweep depth | 0.50 ATR₁₅ | 0.25 / 0.50 / 0.75 | deeper sweeps are trend breaks, not liquidity grabs |
| Reclaim window | 3 bars | 2 / 3 / 5 | S14 |
| Daily risk reset | 00:00 ET | set to the firm's server midnight in ET | affects daily-limit accounting only |

## Higher-timeframe regime

| Input | Default | Research |
|---|---|---|
| Timeframe A / EMA | 240 / 50 | 240 with 50; 480 with 50 |
| Timeframe B / fast / slow | 60 / 20 / 50 | 60 with 20-50; 30 with 20-50 |
| EMA slope lookback | 3 completed bars | 2 / 3 / 5 |

## Opening range

| Input | Default | Research | Wrong-value failure |
|---|---|---|---|
| ORB buffer | 0.05 ATR | 0.00 / 0.05 / 0.10 | 0 admits every tick-through as a breakout |
| Retest tolerance | 0.10 ATR | 0.05 / 0.10 / 0.15 | too wide and any pullback counts as a retest |
| Momentum low tolerance | 0.10 ATR | scored only | — |
| Invalidate after N closes < ORH | 2 | 1 / 2 / 3 | 1 invalidates on noise |

## VWAP

| Input | Default | Research | Wrong-value failure |
|---|---|---|---|
| Slope lookback | 3 bars | 2 / 3 / 5 | — |
| Max extension | 1.25 ATR | **1.00 / 1.25 / 1.50** | the anti-chase rule; too high and the strategy buys tops |
| "Not extended" bonus | 0.75 ATR | scored only | — |

## Pivots, trendline, third touch

| Input | Default | Research | Wrong-value failure |
|---|---|---|---|
| Pivot left / right | 3 / 3 | 2/2, 3/3, 4/4 | larger = later confirmation, fewer setups |
| Pivot memory anchor | London open | London open / NY OR / ET day | earlier anchor allows structure to predate NY |
| Minimum P2−P1 rise | 0.10 ATR | 0.05 / 0.10 / 0.20 | 0 admits a flat line as "ascending" |
| Pivot spacing | 4 – 36 bars | 4–24 / 4–36 / 6–48 | S28 |
| Max normalised slope | 0.25 ATR/bar | **0.20 / 0.25 / 0.30** | too high admits parabolic moves |
| Touch tolerance | 0.12 ATR | **0.08 / 0.12 / 0.16** | too wide and "touch" means "in the area" |
| Strict structure | off | on / off | on requires HH₂ > HH₁ |

## Rejection candle

| Input | Default | Research |
|---|---|---|
| Minimum body ratio | 0.35 | **0.28 / 0.35 / 0.42** |
| Minimum CLV | 0.70 | **0.60 / 0.70 / 0.80** |
| Preferred lower wick | 0.15 | scored only |
| Pending order lifetime | 2 bars | 1 / 2 / 3 |
| Micro pivot left / right | 1 / 1 | 1/1, 2/2 |

## Intermarket

| Input | Default | Research | Note |
|---|---|---|---|
| Minimum DXY score | 2 of 3 | 1 / 2 / 3 | mandatory by default (S36) |
| Intraday ROC length | 30 bars | 20 / 30 / 45 | |
| Minimum GC count | 2 of 4 | 1 / 2 / 3 | |
| Require GC volume | off | on / off | S24: off until ablation earns it |
| Correlation length | 60 days | 40 / 60 / 90 | |
| Normal correlation | ≤ −0.20 | −0.10 / −0.20 / −0.30 | drives the DXY score discount |
| Real-yield lookback | 5 days | 3 / 5 / 10 | |
| Nominal yield | off | on / off | correlated with real yields; test before enabling |

## Volatility and execution

| Input | Default | Research | Note |
|---|---|---|---|
| ATR length | 14 | 10 / 14 / 21 | |
| ATR median length | 50 | 30 / 50 / 100 | |
| Max ATR shock | 1.75 | **1.50 / 1.75 / 2.00** | S26 |
| Modelled spread | 0.30 | 0.20 / 0.30 / 0.50 | MODELLED, not observed — see `05_execution_audit.md` |
| Modelled slippage | 0.10 per side | 0.05 / 0.10 / 0.20 | |
| Commission per unit | 0.07 USD | broker-specific | $7 per 100 oz round turn |
| Max spread / ATR | 0.20 | 0.10 / 0.20 / 0.30 | |
| Feed stale after | 12 bars | 6 / 12 / 24 | kill switch (S76) |

## Risk and FTMO

| Input | Default | Note |
|---|---|---|
| Account size | 100,000 | must match Strategy Properties initial capital — the dashboard warns if it does not |
| Standard risk | 0.50% | S6 |
| Absolute max risk | 1.00% | hard ceiling |
| Hard risk cap | $1,000 | S7; binds on accounts above $100k |
| Internal daily stop | −1.50% | S6; sits well inside the firm limit |
| FTMO daily / max loss | 5% / 10% | S5; adjustable because the firm changes them |
| Phase 1 / verification target | 10% / 5% | |
| Minimum trading days | 4 | |
| Risk schedule 5–8 / 8–9 / 9–10% | 0.40 / 0.25 / 0.15% | S8: protect the pass |
| USD per point per unit | 1.0 | **verify against the broker before deployment** |
| Unit step / minimum units | 1.0 / 1.0 | 0.01 lot × 100 oz = 1 oz |
| Units per lot | 100 | display only |
| Max trades per day | 1 | S51 |
| Second-trade score / risk | 90 / 0.25% | |
| Stop after winning morning | on | S52 |
| Drawdown kill switch | 0 (off) | set to the validated 95th-percentile drawdown from the Monte Carlo (S76) |

## Targets and exits

| Input | Default | Research | Note |
|---|---|---|---|
| TP1 / TP2 / runner max | 1.5R / 3R / 7R | fixed by S48 | 7R is a right tail, not an expectation |
| TP1 / TP2 size | 50% / 25% | 40/30, 50/25, 60/20 | runner takes the remainder |
| Breakeven trigger | 1.0R on close | **0.75 / 1.00 / 1.25** | S49; wicks never count |
| Runner ATR trail | 2.0 ATR | **1.5 / 2.0 / 3.0** | |
| Structural trail buffer | 0.10 ATR | 0.05 / 0.10 / 0.20 | |
| Stop buffer | 0.10 ATR | **0.05 / 0.10 / 0.20** | floored at spread + slippage |
| Stop distance band | 0.20 – 1.25 ATR | 0.20–1.00 / 0.20–1.25 / 0.15–1.50 | outside the band the setup is REJECTED, not resized |
| Minimum clearance | 1.5R | 1.25 / 1.50 / 2.00 | S44 |

## Score

| Input | Default | Research |
|---|---|---|
| Weights | 10/12/12/10/14/8/8/4/8/7/7 | vary one block ±20%, never all at once |
| Threshold | 80 | **75 / 80 / 85 / 90** |

## News

| Input | Default | Note |
|---|---|---|
| Blackout before / after | 15 / 15 min | S41 |
| FOMC after | 30 min | S41 |
| Event lists | empty | **must be populated before any formal backtest** — see `09_backtesting_protocol.md` |

---

## Parameters that are not parameters

These are fixed by the specification and are not tuning knobs. Changing one
changes what the strategy *is*, and any change must be argued structurally
rather than by backtest improvement:

* long only, one position at a time, no pyramiding (S3);
* the third-touch requirement (S31) — the hypothesis under test;
* mandatory volatility and news gates (S55);
* risk never increases after a loss (S7);
* position size always rounds down (S47).

---

## The bold entries

Bold research ranges are the parameters most likely to be the difference
between a real edge and a fitted one: VWAP extension, trendline slope cap, touch
tolerance, rejection thresholds, stop buffer, ATR shock, trailing distance,
breakeven trigger, and the score threshold. Sweep those first. If the result
collapses when touch tolerance moves from 0.12 to 0.14 ATR, there was never a
third-touch edge — there was a fit to a particular set of wicks.
