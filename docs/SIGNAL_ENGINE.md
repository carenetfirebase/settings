# The V1 signal engine

One setup, long only: **a pullback inside an uptrend, in a leading stock and
sector, when the market's trend is up.** It is built only from the 10/10
inputs in [ENGINE_INPUTS.md](ENGINE_INPUTS.md), and a test fails the build if
the engine so much as references RSI, MACD, 52-week position, breadth or the
macro regime.

Code: `src/invest/engines/signals.py` (rules), `engines/outcomes.py` (scoring
what happened), `signal_runner.py` (database), `ledger.py` (the Lab).

## Daily use

```bash
invest ingest prices                 # stocks, SPY and the sector funds
invest signals scan                  # today's cards; records nothing
invest signals record                # append today's candidates to the ledger, as 'live'
invest signals evaluate              # score every open signal against new bars
invest signals ledger                # what happened
invest signals lab                   # calibration and attribution
```

To give the Lab something to chew on immediately, reconstruct history:

```bash
invest signals backfill --start 2024-01-01
```

Each backfilled day sees only what was public that day. The universe, though,
is today's, so backfilled rows carry survivorship bias. They are labelled
`backfill` everywhere and never pooled with `live` by default.

## The rules

Every threshold below is a named constant in `engines/signals.py`. The
direction of each rule comes from the cited evidence; the exact numbers are
design choices the Lab exists to test. Changing any of them bumps
`MODEL_VERSION` (now `SIG-v1.0`), so ledger rows always name the rules that
produced them.

| Step | Rule | Evidence for the direction |
|---|---|---|
| **Trend gate** (market) | SPY's last completed month-end close above its 10-month average. Unknown counts as closed. | Faber 2007 |
| **Stock uptrend** (filter) | 12-month return > 0 and close above the 200-day average | Moskowitz, Ooi & Pedersen 2012 |
| **Pullback** (setup) | 5-day return < 0 and 0.5–4 ATR below the 20-day high. Deeper than 4 ATR is a breakdown | Jegadeesh 1990; Lehmann 1990 |
| **Levels** | Buy-stop 0.05 ATR above the signal day's high. Stop below the 10-day low (−0.25 ATR), at least 1 and at most 4 ATR away. Target +2R. Time stop 15 trading days. Buy-stop live for 5 days | design |
| **Quality veto** | Reliable F-score ≤ 2, or a Beneish M-score manipulation flag. Unknown warns, never blocks | Piotroski 2000; Beneish, Lee & Nichols 2013 |
| **Earnings veto** | Projected earnings (last 8-K Item 2.02 + 91 days, ±10) inside the 28-day hold. Unknown warns | Savor & Wilson 2016 |
| **Size** | 0.75% of equity at risk × volatility scale | design; Moreira & Muir 2017 |
| **Volatility scale** | SPY 1-month vol vs its 1-year median; risk cut up to half, never raised | Barroso & Santa-Clara 2015 |

## The score (0–100)

Four equal components (DeMiguel, Garlappi & Uppal 2009), averaged over those
available, so coverage is 75% until V2:

| Component | Measures |
|---|---|
| Trend strength | 12-month return > 0, above 200-day, 50-day above 200-day |
| Relative strength | Average of the stock's 12-1 month momentum percentile in the universe and its sector fund's percentile among sectors |
| Pullback entry | Depth below the 20-day high, 0.5 ATR → 0, 3 ATR → 100 |
| Ecosystem lead-lag | V2 (customer–supplier graph); shown as unavailable |

Plus a **+5 tilt** when an *opportunistic* insider (Cohen, Malloy & Pomorski
2012: traded in each of the three prior years, never in one fixed month) made
an open-market purchase filed in the last 90 days. Absence, sales, grants and
routine buys add nothing. Capped at 100.

The score ranks setups. It is **not a probability**: the Calibration page says
whether it has earned that reading yet.

## The ledger

`signals` and `signal_outcomes` are append-only, enforced by database
triggers. Every *candidate* is recorded, fired or blocked (gate closed or
vetoed), because the only way to know whether a veto helps is to watch what
it blocks.

Outcomes are scored from daily bars, and every ambiguity goes against the trade:

- A buy-stop gapped over fills at the open. A stop gapped through fills at the open.
- A bar that touches both stop and target counts as a stop.
- The fill bar can stop out.
- Spread and slippage (7.5 bp a side by default) are charged in R.
- Excursions (MFE/MAE) count only prices the position actually held through.

## The Lab

- **Calibration:** fired signals by score bucket. It reports mean R, win rate,
  and how often +1R came before −1R. Monotonic is only claimed once every
  bucket has 20 closed trades.
- **Attribution:** each block (trend gate, quality veto, earnings veto) and
  the insider tilt, compared with fired signals. A rule is trusted only when
  the difference clears |t| > 3 (Harvey, Liu & Zhu 2016).
- **Clustered errors.** Signals in the same week share one market path, so
  standard errors are clustered by week. On random-walk test data an
  unclustered t-statistic reached 4.2 for a gate with no real effect; the
  clustered one is 2.5, below the bar, which is the right answer.
- **A sanity check.** On random-walk prices the engine loses money after
  costs, as it should. A system that shows an edge on random data is broken.

## V1 milestones

| Milestone | What | Status |
|---|---|---|
| **V1.1** | Signal engine, ledger, outcome scoring, Scanner, Trade Cards, Ledger, Sectors, Calibration, Attribution | **Built** |
| **V1.2** | Alpaca: real-time SIP data, paper trading with bracket orders from a card, positions, portfolio heat and the halt switch, sign-in | Next |
| **V1.3** | Survivorship-free history and index membership (Norgate or an alternative), breadth, macro event calendar, walk-forward backtests | After |

V1.2 needs an Alpaca account and API keys in `.env`. V1.3 needs a decision on
the history source: Norgate's data updater is Windows-only (Mac and Linux need
a Windows virtual machine), so a Mac or Linux setup may want an alternative
with point-in-time index membership.
