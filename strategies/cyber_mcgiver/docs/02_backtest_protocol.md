# Backtest protocol and report template

## 1. Before anything else: Deep Backtesting

Ten years of XAUUSD 15-minute bars is roughly **240,000 bars**. TradingView's
standard history cap is 20,000 bars even on Premium, which is about **ten
months** at this resolution. Run the strategy without enabling Deep Backtesting
and it will produce a plausible-looking report covering a twelfth of the
requested window, and every frequency number in it will be wrong.

Deep Backtesting is on the Strategy Tester's own settings, alongside the date
range. Set it, then set the range, then check that the trade list starts in
2016 and not in 2025. **Verify before reading anything else.**

## 2. Chart and tester settings

| Setting | Value |
|---|---|
| Symbol | `OANDA:XAUUSD` |
| Chart timeframe | **15 minutes** — the script refuses anything else |
| Range | 26 Aug 2016 → 26 Aug 2026 |
| Initial capital | 100,000 USD |
| Order size | leave as-is; the script sizes every entry itself |
| Commission | 0.035 per contract *(declaration-time constant)* |
| Slippage | 25 ticks *(declaration-time constant)* |
| Margin long/short | 2% (50:1) *(declaration-time constant)* |
| Recalculate | after order is filled: **off**; on every tick: **off** |
| Bar Magnifier | **on** |

Commission, slippage and margin are Pine declaration constants and cannot be
wired to inputs. The STATE panel recomputes what the modelled cost inputs imply
and prints `TESTER MISMATCH` with the values to enter if they disagree. If that
row is red, the sizing and the tester are pricing two different instruments.

## 3. Script settings for the first pass

Everything at default, with these confirmed:

* **Direction under test** = `Long only`
* All four setup families **enabled**
* Score floor 72 · A 78 · A+ 85 · tier risk 0.25 / 0.40 / 0.50%
* Hard cap 3 trades/day · daily loss cutoff 1.25%
* Follow-through timeout **off**
* Drawing **off** — at this frequency Pine's 500-label ceiling makes a drawn
  chart both wrong and slow. Turn it on only for a short visual inspection over
  a few weeks.

## 4. Sanity checks before recording anything

Read these off the panels first. If any fails, the run is not usable.

1. **STATE · Timeframe** says `OK`.
2. **STATE · Tester costs** says `tester matches`, not `TESTER MISMATCH`.
3. **STATE · Symbol sanity** says `point value 1.0 as assumed`.
4. **FREQUENCY · days with more than 3** is **0**. Anything else means the hard
   cap leaked and the whole run is void.
5. **FREQUENCY · normal trading days** is somewhere near 2,500–2,600. A number
   near 200 means Deep Backtesting is off.
6. **FUNNEL · bars processed** is near 240,000, for the same reason.

## 5. The report

Fill this in from the panels. Panel names in brackets.

### Frequency  *[FREQUENCY]*

| Metric | Value |
|---|---|
| Total trading days | |
| Total trades | |
| Average trades / day | |
| Median trades / day | |
| Days with 0 trades | |
| Days with 1 trade | |
| Days with 2 trades | |
| Days with 3 trades | |
| Days with more than 3 | *(must be 0)* |
| Percentage of days with no trade | |

### Decision funnel  *[FUNNEL]*

Every row, verbatim. The point of the funnel is that no rejection is hidden, so
copy the rejection rows even when they are zero. Specifically record:

* raw structural events → candidates → cleared the score floor
* each mandatory-gate rejection (regime, momentum, shock, stop wide, stop tight,
  reward room, anchor)
* each availability block (position live, daily cap, daily loss, cooldown)
* armed → filled → same-bar round trips → trades completed

### Trades by family  *[FAMILY]*

| Family | Trades | Win % | PF | Expectancy R | Max DD R | Avg score of winners | Avg score of losers |
|---|---|---|---|---|---|---|---|
| 1 Trendline | | | | | | | |
| 2 Sweep | | | | | | | |
| 3 Breakout | | | | | | | |
| 4 VWAP pull | | | | | | | |

### Trades by score bucket  *[SCORE CALIBRATION]*

This is the table the whole score model is on trial for.

| Bucket | Candidates | cand/day ≥ | Trades | Win % | Expectancy R | PF |
|---|---|---|---|---|---|---|
| 72–74 | | | | | | |
| 75–77 | | | | | | |
| 78–80 | | | | | | |
| 81–84 | | | | | | |
| 85–89 | | | | | | |
| 90–94 | | | | | | |
| 95–100 | | | | | | |

**If expectancy does not rise with the bucket, the score model is not useful and
must be redesigned.** A single inversion between adjacent buckets with small
counts is noise; a flat or falling gradient across the whole range is not.

### Trades by tier and by session  *[SESSION panel, both halves]*

### Performance  *[PERFORMANCE]*

Wins · losses · win rate · profit factor · net P&L · net P&L % · max drawdown
(tester) · max drawdown (R) · average R · median R · average winner R · average
loser R · largest winner (R and $) · largest loser (R and $) · average bars held
· median bars held · max consecutive wins · max consecutive losses.

### Exit research  *[EXITS]*

The MFE and MAE survival curves, both columns, every row. These decide what
replaces the retired follow-through rule — do not invent a replacement before
reading them.

## 6. Reading the result, in the stated order

1. **Sample size.** Under ~1,500 trades, stop and fix frequency first. Nothing
   below that supports a per-bucket or per-family conclusion.
2. **Expectancy.** Average R across all trades. Sign first, size second.
3. **Profit factor.**
4. **Drawdown stability.**
5. **Consistency across years.** Re-run the date range one year at a time.
6. **Robustness across regimes.** Compare 2016–2019, 2020–2022, 2023–2026.
7. **Win rate.** Last. A 90% win rate on 40 trades is not a result.
8. **Frequency refinement.** Only now.

## 7. If frequency misses the target

Read the SCORE CALIBRATION table before touching any parameter. The
`cand/day ≥` column already says what each threshold would produce, so the
threshold can be re-picked from the table rather than by re-running the decade.

If the *candidate* rate is adequate but the *trade* rate is not, the throttle is
downstream and the funnel names it: reward room, the anchor rule, the cooldown,
or simply a position already being live. Change the one the funnel points at,
one at a time.

Do not widen a mandatory risk gate to buy frequency. Those gates exist so the
risk numbers mean what they say.
