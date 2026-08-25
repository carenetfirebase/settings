# C · Variable dictionary

Every non-input variable in `AURUM_NY_PRIME.pine` that carries meaning, with its
unit. Inputs are catalogued separately in `03_parameter_table.md`.

Units matter here more than usual: the strategy mixes **price units** (USD per
ounce), **ATR multiples** (dimensionless), **R multiples** (dimensionless),
**USD** (account currency) and **units** (ounces). Most position-sizing bugs are
unit confusion, so each row states which one it is.

---

## Time

| Variable | Unit | Meaning |
|---|---|---|
| `etMin` | minutes | minutes since ET midnight of the bar's OPEN |
| `etDate` | yyyymmdd | ET calendar date as an integer |
| `newDay` | bool | first bar of a new ET calendar day |
| `isWeekday` | bool | Monday–Friday in ET |
| `mAsiaS`…`mRunEnd` | minutes | parsed session boundaries |
| `inAsia` / `inLon` / `inOR` | bool | inside the respective window, end-exclusive |
| `inTrade` | bool | inside the entry window and a weekday |
| `pastFlat` | bool | at or past the flatten time |
| `riskDayBoundary` | bool | the daily risk accounting reset fired |

## Price and volatility

| Variable | Unit | Meaning |
|---|---|---|
| `atr` | price | `ta.atr(14)` on the chart timeframe |
| `atrMed` | price | median of `atr` over 50 bars |
| `atrShock` | ratio | `atr / atrMed`; > 1.75 is abnormal (S26) |
| `atr15` | price | 15-minute ATR, completed bars only; scales sweep depth |
| `tick` | price | `syminfo.mintick` |
| `rng` | price | `high − low` |
| `bodyRat` | ratio 0–1 | `|C − O| / range` |
| `clv` | ratio 0–1 | close location value |
| `lwr` | ratio 0–1 | lower-wick ratio |

## Higher-timeframe regime

| Variable | Unit | Meaning |
|---|---|---|
| `c4`, `ema4`, `ema4Prev` | price | 4H close and EMA50, completed candles; `ema4Prev` is 3 completed bars back |
| `c1`, `ema1f`, `ema1s` | price | 1H close, EMA20, EMA50, completed candles |
| `ph1h`, `ph15` | price | last confirmed 1H / 15m pivot high |
| `bull4h`, `bull1h`, `str1h` | bool | regime conditions (S16) |
| `goldBull` | bool | `bull4h ∧ bull1h` |
| `goldBullGate` | bool | `goldBull`, or bypassed when the HTF block is ablated |

## Sessions and liquidity

| Variable | Unit | Meaning |
|---|---|---|
| `asiaHr/Lr/Cr`, `lonHr/Lr/Cr` | price | **running** accumulators; never read by the strategy |
| `asiaH/L/C/M`, `asiaRange` | price | **frozen** Asia values, valid once `asiaReady` |
| `lonH/L/C/M`, `lonRange` | price | frozen London values, valid once `lonReady` |
| `asiaReady`, `lonReady` | bool | the session has ended and its range is final |
| `dHi/dLo/dCl` | price | running ET-day extremes |
| `pdh/pdl/pdc`, `dayOpen` | price | previous ET day high/low/close, current day open |
| `wHi/wLo`, `pwh/pwl` | price | running and previous ET-week extremes |
| `sweepSeen`, `sweepBar`, `sweepLow`, `reclaimOK` | bool/index/price | Asia-low sweep state |
| `sweepDepth` | ATR₁₅ multiples | `(asiaL − sweepLow) / atr15` |
| `contBull`, `contStrong`, `sweepBull`, `sweepStrong` | bool | the two session models and their strong variants |
| `sessionBull`, `sessionGate` | bool | S15 state and its (ablatable) gate |
| `sessionType` | string | `SESSION_CONTINUATION` / `SESSION_SWEEP_RECLAIM` / `NONE` |

## Opening range

| Variable | Unit | Meaning |
|---|---|---|
| `orHr`, `orLr` | price | running accumulators inside the window |
| `orh`, `orl`, `orw` | price | LOCKED range, `na` before 08:35 |
| `orReady` | bool | the range is locked |
| `orbBuf` | price | `0.05 · atr` |
| `breakout` | bool | close above `orh + orbBuf` |
| `orbBroke`, `orbBreakBar` | bool/index | first breakout of the day |
| `orbAcceptMom`, `orbHoldTight`, `orbAcceptRetest` | bool | acceptance models A and B (S19, S20) |
| `belowORHCount` | count | consecutive closes below ORH |
| `orbFailed` | bool | S21 invalidation |
| `orbAccepted`, `orbGate` | bool | acceptance state; the ORB block is never ablated |

## VWAP

| Variable | Unit | Meaning |
|---|---|---|
| `vwapPV`, `vwapWV` | price·weight, weight | anchored VWAP accumulators |
| `vwap` | price | anchored VWAP from 08:20 ET |
| `aboveVWAP` | bool | `close > vwap` |
| `vwapSlope` | ATR multiples | `(vwap − vwap[3]) / atr` |
| `vwapRising` | bool | `vwapSlope > 0` |
| `vwapExt` | ATR multiples | `(close − vwap) / atr` |
| `vwapExtOK` | bool | `0 < vwapExt ≤ 1.25` (S25) |
| `volStrength` | bool | volume above its 20-bar average, or `true` when volume is unusable |
| `priceOnlyVWAP` | bool | the volume mode selects equal weighting |

## Intermarket

| Variable | Unit | Meaning |
|---|---|---|
| `dxC`, `dxTP` | index points | DXY close and typical price, chart timeframe |
| `dxV` | index points | DXY anchored VWAP, price-only (no usable volume) |
| `dxRoc`, `dxEf`, `dxEs` | % / index points | DXY ROC(30), EMA20, EMA50 |
| `dxyD1/D2/D3`, `dxyScore` | bool / 0–3 | S36 conditions and their sum |
| `gcC`, `gcTP`, `gcVol`, `gcV` | price / contracts | COMEX gold close, typical price, volume, anchored VWAP |
| `gc1…gc4`, `gcCount` | bool / 0–4 | S24 confirmations |
| `gcConfirm`, `gcGate` | bool | GC confirmation and its gate |
| `dxyDaily`, `vixDaily`, `ryDaily`, `ustDaily` | mixed | completed daily closes of each feed |
| `goldSer`, `dxySer`, `vixSer`, `rySer`, `ustSer` | arrays of daily closes | one value appended per ET day |
| `corrGD`, `corrGV` | correlation −1…1 | 60-day correlation of daily log returns |
| `vixMom` | log return | `ln(VIX_t / VIX_{t−5})` |
| `vixSupport` | product | `corrGV · vixMom`; sign is what matters |
| `ryMom`, `ustMom` | percentage points | 5-day change in yield; negative supports gold |
| `dxyCorrFactor` | 0.25 / 0.5 / 1.0 | discount applied to the DXY score when the correlation regime is not normal (S37) |
| `dxyStale`, `gcStale`, `feedsOK` | bool | data-failure kill switch (S76) |

## Pivots and trendline

| Variable | Unit | Meaning |
|---|---|---|
| `pivLow`, `pivHigh`, `mphRaw` | price | raw pivot returns, non-`na` only on the confirmation bar |
| `p1v/p1i`, `p2v/p2i` | price / bar index | the two confirmed pivot lows; the index is the pivot's OWN bar |
| `hh1`, `hh2` | price | confirmed pivot high between P1 and P2, and after P2 |
| `lastPHVal`, `lastPHIdx` | price / index | most recent confirmed pivot high |
| `lastMPH` | price | most recent confirmed micro pivot high (entry trigger source) |
| `spacing` | bars | `p2i − p1i` |
| `rise` | price | `p2v − p1v` |
| `slope` | price per bar | `rise / spacing` |
| `slopeNorm` | ATR per bar | `slope / atr`; must be in (0, 0.25] |
| `pivotStruct`, `strictStruct` | bool | S29 standard and strict structure |
| `trendlineValid` | bool | positive, non-parabolic slope |
| `tlValue` | price | projected trendline at the current bar |
| `touchTol` | price | `0.12 · atr` |
| `touch3`, `touch3Strong` | bool | third interaction, and whether it is above P2 |
| `touchDistATR` | ATR multiples | signed distance from the low to the trendline |

## Rejection and trigger

| Variable | Unit | Meaning |
|---|---|---|
| `rejBull`, `rejStrong` | bool | S33 rejection candle, and the wick bonus |
| `confLevel` | price | `max(H, lastMPH) + tick`, or `H + tick` in Moderate mode |

## Risk state

| Variable | Unit | Meaning |
|---|---|---|
| `acct`, `equityNow`, `gainPct` | USD, USD, % | account size, live equity (includes open P/L), gain vs account |
| `riskPctSchedule`, `riskPct`, `riskPctEff` | % of equity | S8 schedule, absolute cap applied, second-trade cap applied |
| `dayStartEquity`, `dayPnlPct` | USD, % | daily accounting baseline and result |
| `internalDailyHit`, `ftmoDailyHit`, `ftmoMaxHit`, `targetHit`, `ddKillHit` | bool | limit breaches |
| `dayLocked`, `hardStop` | bool | no new trades today / no new trades at all |
| `tradesToday`, `tradingDays`, `countedToday` | counts | trade and trading-day counters |
| `lastTradeLost`, `tookWinToday` | bool | S51 and S52 state |
| `newStructure`, `allowSecond`, `tradeSlotOK` | bool | second-trade permission |
| `scoreNeeded` | 0–100 | threshold in force (raised for a second trade) |

## Trade construction

| Variable | Unit | Meaning |
|---|---|---|
| `stopBuffer` | price | `max(0.10·atr, spread + slippage)` |
| `slA`, `slB`, `stopPx` | price | stop candidates and the selected stop |
| `entryPx` | price | the stop-order trigger |
| `rDist` | price | initial risk `entry − stop`; the denominator of every R |
| `stopDistOK` | bool | `rDist` inside [0.20, 1.25] ATR |
| `resLevel`, `room` | price | nearest overhead level, and the distance to it |
| `roomR` | R multiples | `room / rDist` |
| `mapPopulated`, `roomOK` | bool | clearance gate (S44) |
| `riskBudget` | USD | `min(equity·riskPct, $1,000)` |
| `costPerUnit`, `riskPerUnit` | USD per unit | modelled costs, and total risk per ounce |
| `unitsRaw`, `units` | units (oz) | unrounded and step-floored position size |
| `sizeOK` | bool | size is at least the minimum and inside the budget |
| `lotsDisp` | lots | `units / 100`, display only |
| `q1`, `q2`, `q3` | units | TP1, TP2 and runner allocations; they sum to `units` |
| `tp1Px`, `tp2Px`, `tpRun` | price | 1.5R, 3R, 7R targets |

## Gates, score, state

| Variable | Unit | Meaning |
|---|---|---|
| `useHTF`…`useVIX` | bool | ablation switches resolved from the preset (S71) |
| `sHTF`…`sRej` | block-natural points | raw score components |
| `scoreRaw`, `scoreMax`, `score` | weighted points, weighted points, 0–100 | numerator, denominator over ENABLED blocks, and the percentage |
| `technicalValid`, `intermarketOK`, `executionOK`, `riskValid`, `scoreOK`, `windowOK`, `flat` | bool | the S82 conjunction terms |
| `armed` | bool | all of the above |
| `gradeAPP`, `gradeAP`, `grade` | bool / string | S56 classification |
| `noTradeReason` | string | the first failed gate, in priority order (S59) |
| `state`, `invalidReason` | string | S57 state machine |

## Position and logging

| Variable | Unit | Meaning |
|---|---|---|
| `aEntry`…`aStopModel` | mixed | ARM-time snapshot: the context that justified the trade, frozen when the order was placed |
| `pendingOrder`, `pendingBar` | bool / index | resting entry order and the bar it was placed on |
| `posEntry` | price | **actual** average fill price |
| `posR` | price | actual initial risk, `posEntry − aStop` |
| `posUnits`, `posRiskUSD` | units, USD | filled size and the dollar risk it represents |
| `posStop` | price | live stop; monotone non-decreasing (S50) |
| `posMinLow`, `posMaxHigh` | price | excursion extremes since entry, used for MAE/MFE |
| `netAtEntry` | USD | `strategy.netprofit` at fill, so position P/L is exact |
| `posBar`, `posTime` | index / ms | entry bar and timestamp |
| `beDone`, `tp1Done`, `tp2Done` | bool | breakeven armed, TP1 filled, TP2 filled |
| `bePx` | price | breakeven price including costs |
| `lastConfHL` | price | latest confirmed higher low, the structural trail source |
| `logRows` | array of CSV strings | one row per **closed position**, not per exit leg |
| `nTrades`…`sumMfeR` | counts / R | incremental statistics (S62) |
| `winRate`, `avgWinR`, `avgLossR`, `expectancyR`, `profitFactor` | ratio / R | derived statistics |
| `wLo`, `wHi` | proportion | 95% Wilson interval on the win rate (S63) |
| `sampleLabel` | string | PRELIMINARY < 100 trades, ADEQUATE < 200, VALIDATED-SIZE otherwise (S73) |

---

## Two distinctions worth stating explicitly

**Running versus frozen.** `asiaHr` is a running accumulator; `asiaH` is the
frozen, published value. The strategy reads only the frozen ones. Reading a
running accumulator is the repainting bug this naming exists to prevent.

**Planned versus actual.** `aEntry`/`aStop`/`aR` are what was *planned* at arm
time; `posEntry`/`posR`/`posRiskUSD` are what actually *happened* at the fill.
Realised R is always computed against the actual dollar risk, so slippage makes
results worse rather than disappearing into the denominator.
