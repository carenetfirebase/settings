# K · Backtesting protocol

The exact sequence. Run it in order; do not skip to step 8 because the equity
curve looked good in step 3.

The governing rule is S68: **the final 20% of the data is touched once.** Every
parameter decision, every ablation verdict, every "let's try 0.15 instead of
0.12" happens on the first 80%. If the final block is consulted twice, it is no
longer out-of-sample and there is nothing left to validate against.

---

## Step 0 · Environment

- [ ] Chart: XAUUSD, **5-minute**, the broker feed you will trade
- [ ] Timezone: chart timezone is irrelevant; the script uses
      `America/New_York` internally
- [ ] Strategy Properties per `05_execution_audit.md` — capital 100,000,
      commission 0.07/contract, slippage 2–4 ticks, **Bar Magnifier ON**,
      recalculate-on-tick OFF
- [ ] Dashboard shows neither `⚠ <timeframe>` nor `⚠capital`
- [ ] Contract size, minimum lot, lot step, tick value verified against the
      broker (S47)
- [ ] No synthetic chart types — no Heikin Ashi, Renko, Kagi (S79). They
      produce fills at prices that never traded.

## Step 1 · News calendar — before any run

Populate the blackout lists for the **entire** test period from a published
economic calendar, in ET:

- `High-impact events`: CPI, core CPI, PCE, core PCE, NFP, unemployment, average
  hourly earnings, GDP, retail sales
- `FOMC events`: decisions and press conferences (30-minute post-blackout)

Filling these in after seeing which days lost is hindsight laundering. Record
the calendar source and the date you loaded it. The dashboard displays the count
supplied so a run with an empty calendar is visible rather than assumed.

If populating a multi-year calendar is impractical, use the recurring daily
blackout (`08:30`) and **state that in the results**. It is blunter — it blocks
clean days too — but it is honest, and it is conservative in the right
direction.

## Step 2 · Warm-up

Confirm the strategy is alive before believing any number:

- [ ] Dashboard populates and the state machine advances through the morning
- [ ] The no-trade reason changes as the session develops
- [ ] Confirmation markets return data (GC / DXY rows are not blank)
- [ ] `NO TRADE — DATA FEED FAILURE` does not appear persistently

A blank GC row means the futures symbol is not available on your plan. Change it
or disable that component — but a disabled component must be disabled in the
*ablation preset*, not left mandatory and always failing.

## Step 3 · Establish the sample

Run over the longest history the plan allows and read only the trade count.

| Trades | Status |
|---|---|
| < 30 | not a sample; widen the window or relax the score threshold *for exploration only* |
| 30–99 | PRELIMINARY (S73) |
| 100–199 | ADEQUATE |
| ≥ 200 | reportable |

Trade count is what determines whether any of the following steps can conclude
anything. A highly selective NY-morning long-only setup on one instrument may
produce 1–3 trades a month. Two years of data is then 50 trades, and 50 trades
cannot distinguish a 55% strategy from a 70% one. If that is where you land,
the honest output of this whole protocol is "PRELIMINARY", and the correct next
step is forward testing, not tuning.

## Step 4 · Export and split

```
python -m validation.aurum_validate report trades.csv --json summary.json
```

Confirm the chronological split looks sane, then **work only on the development
and validation blocks** until step 9.

## Step 5 · Ablation (mandatory, S71)

Ten runs, one per preset, exported separately:

```
python -m validation.aurum_validate ablation \
  "A · ORB only=A.csv"  "B · + VWAP=B.csv"  "C · + Asia/London=C.csv" \
  "D · + pivots=D.csv"  "E · + third touch=E.csv"  "F · + DXY=F.csv" \
  "G · + GC=G.csv"      "H · + rates=H.csv"        "I · + VIX=I.csv" \
  "J · Full AURUM-NY PRIME=J.csv"
```

Read the `ΔexpR`, `ΔP(pass)` and `maxDD R` columns. A component stays only if it
improves robustness or provides a defensible risk-control benefit. `unproven ·
no measurable value` on a component means exactly that — it has not earned its
place, and keeping it "because it makes sense" is how a strategy acquires
twelve filters and no edge.

Expect the ladder to shrink the sample as it climbs: preset J is the most
selective and will have the fewest trades. A component that "improves
expectancy" while cutting the sample from 120 to 22 has improved nothing that
can be measured — the table flags `INSUFFICIENT SAMPLE` below 30.

## Step 6 · Interaction testing (S72)

Do not assume filters are independent. Using the exported columns, test whether:

* third touch works only with ORB retest acceptance;
* DXY only adds value when GC also confirms;
* sweep/reclaim needs the third touch more than continuation does;
* the VWAP filter is redundant given ORB retest.

See `08_trade_export_format.md` §5 for the pattern. Compare Wilson intervals, not
point estimates.

## Step 7 · Parameter stability (S70)

Perturb the bold parameters in `03_parameter_table.md` ±10–20%, one at a time,
three values each:

```
python -m validation.aurum_validate stability 0.08=t08.csv 0.12=t12.csv 0.16=t16.csv
```

`ISOLATED PEAK` rejects the parameter's current value outright. `EDGE PEAK`
means the range was too narrow. Only `PLATEAU` is a pass. A strategy that
survives every sweep is not necessarily good; a strategy that fails one is
definitely fitted.

## Step 8 · Walk-forward (S69)

```
python -m validation.aurum_validate walkforward trades.csv --train 12 --test 3
python -m validation.aurum_validate walkforward trades.csv --train 18 --test 6
```

Report the aggregate of the **test** halves only, and the count of windows with
positive expectancy. Three of four windows positive with one bad quarter is a
strategy. One spectacular window carrying the aggregate is a regime, and it is
over.

## Step 9 · The final block — once

Now, and only now, look at the out-of-sample section of the report and the S86
criteria:

```
  [ ] profit factor ≥ 1.5
  [ ] expectancy ≥ +0.25R
  [ ] P(expectancy > 0) ≥ 95%
  [ ] out-of-sample N ≥ 100
```

If it fails: **stop**. Do not re-optimise on this data. The strategy is
unproven, that is the result, and the data is spent (S85). Going back to step 5
with knowledge of the final block converts the validation into a fit.

## Step 10 · Evaluation simulation (S66)

```
python -m validation.aurum_validate montecarlo trades.csv --paths 10000 --blocks 3,5,10
```

Record `P(pass before failure)`, both failure probabilities, days to pass, and
the drawdown distribution. Set `i_ddKill` to the 95th-percentile drawdown.

Rank configurations by pass probability, not by net profit (S67).

---

## Reporting template

```
AURUM-NY PRIME v2.0 — backtest report
Instrument / feed  : XAUUSD, <broker>
Period             : <start> → <end>
Bars               : 5-minute, Bar Magnifier ON
Costs              : spread 0.30, slippage 0.10/side, commission 0.07/oz
Volume mode        : <XAUVolumeMode>
News calendar      : <source>, loaded <date>, N events   |   or: RECURRING 08:30 ONLY
Ablation preset    : J
Entry / stop model : Conservative / A

TARGET                          ACTUAL (untouched out-of-sample)
win rate 70%+                   nn.n%  [Wilson ll.l – hh.h]
≥1.5R initial reward            realised R:R n.nn
3R–7R runners                   n of N trades reached ≥3R
high pass probability           P(pass) nn.n%

Sample             : N (PRELIMINARY / ADEQUATE / VALIDATED)
Expectancy         : +n.nnnR   bootstrap [l, h]   P(>0) nn.n%
Profit factor      : n.nn
Max drawdown       : n.nnR / $n,nnn (n.n% of account)
Walk-forward       : n of m windows positive, aggregate +n.nnnR
Ablation           : components retained <list>; dropped <list>
Stability          : <parameter>: PLATEAU / ISOLATED PEAK
Monte Carlo        : P(pass) nn.n%, P(daily) n.n%, P(max) n.n%,
                     median nn days, 95th nn days, 95th DD $n,nnn

VERDICT            : <copied verbatim from the tool>
```

---

## Things that invalidate the whole run

* Heikin Ashi or any synthetic chart type
* Bar Magnifier off
* Zero commission or zero slippage
* Empty news calendar, when the results are presented as validated
* Any parameter changed after looking at the final out-of-sample block
* Reporting the win rate without its interval
* Reporting leg-level trades from TradingView's list instead of the
  position-level export
