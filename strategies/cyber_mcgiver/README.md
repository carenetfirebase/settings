# CYBER MCGIVER v7 · XAUUSD 15m opportunity engine

v6 produced **11 trades in 10 years**. The objective is **1–3 legitimate trades
per normal trading day**, hard capped at 3, typically 1.3–1.8. This directory
holds the restructure, the preserved baseline, and the evidence that the new
architecture actually clears the frequency bar.

```
CYBER_MCGIVER_v7.pine              the deliverable — paste into TradingView
baseline/CYBER_MCGIVER_v6_BASELINE.pine   v6, untouched, for comparison
docs/01_architecture.md            what changed and why
docs/02_backtest_protocol.md       how to run it, and the report template
docs/03_synthetic_findings.md      what the reference run already tells us
validation/pine_lint.py            static checks on the Pine source
validation/synthetic.py            XAUUSD-like 15m bar generator
validation/reference.py            the engine written a second time, in Python
validation/frequency.py            prints the funnel, frequency and analytics
research/synthetic_frequency_report.txt   the saved output of that run
```

## The one-line diagnosis

v6 was a chain of ten binary vetoes. The joint probability of ten
independent-ish gates is the product of ten base rates, and that product was
about one per year. Widening the trendline tolerance would have moved 11 to 30.
It could never have moved 11 to 3,000.

v7 keeps **only the risk conditions as vetoes** and turns everything else into a
weighted **0–100 setup score**, then runs **four setup families in parallel**
into one shared score → risk → reward-room → execution pipeline.

## What the reference run says

Ten years of XAUUSD-like 15-minute bars, long only, default settings:

| | v6 baseline | v7 |
|---|---|---|
| trades | 11 | **3,193** |
| trades per trading day | ~0.004 | **1.22** |
| days with 1+ trade | — | 69.1% |
| candidates offered per day | — | 5.95 |

At the specified score floor of 72 the engine runs slightly under the 1.3–1.8
target (1.08–1.22 across three seeds); a floor of 70 puts it at 1.37. **The
floor has not been changed** — 72 is the stated research threshold and moving it
is a decision, not a bug fix.

Zero-trade days come in at 30.9%, above the 15–20% guideline, and the report
shows why: on days the higher timeframes spend pointing down, a **long-only**
engine has nothing to buy. Split by regime, the picture is unambiguous.

| bullish bars on the day | days | zero-trade | trades/day |
|---|---|---|---|
| 0–5% | 764 | 66.6% | 0.44 |
| 75–100% | 1,280 | **11.4%** | **1.71** |

On days it is allowed to trade, the engine is inside both targets. 80% of the
zero-trade days produced no eligible candidate at all — the engine was never
offered a trade and refused it. **The remedy is shorts, not looser filters**,
which is the phase-2 you had already planned.

## Running it

```bash
# static checks on the Pine source
python3 strategies/cyber_mcgiver/validation/pine_lint.py \
        strategies/cyber_mcgiver/CYBER_MCGIVER_v7.pine

# the funnel, frequency, score calibration and per-family analytics
python3 strategies/cyber_mcgiver/validation/frequency.py --sensitivity
```

The TradingView run is described in `docs/02_backtest_protocol.md`. **It needs
Deep Backtesting**: ten years of 15-minute bars is roughly 240,000 bars, an
order of magnitude past the standard 20,000-bar history cap, and without deep
backtesting the test silently covers about ten months.

## What is not claimed

The reference run uses **generated** bars. Frequency, funnel shape and score
distribution are properties of the setup geometry and survive that. Profit
factor and net P&L do not: the generator has no edge in it, so those columns
measure the exit model against a random walk. Nothing in
`research/synthetic_frequency_report.txt` is a backtest result, and the numbers
the objective asks for have to come from the TradingView run on real
OANDA:XAUUSD data.
