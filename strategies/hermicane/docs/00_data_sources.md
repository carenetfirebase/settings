# Phase 0 data sources: what is needed, what was reachable, what it costs

This is the §3.1 table with the acquisition problem solved explicitly rather
than assumed away. The executable version is `phase0/sources.py`; this document
is the prose that goes with it, and the two are meant to be kept in step.

## Probe result

Run `python -m phase0.cli check` to reproduce. At the time of writing, from
this environment, every host was refused at the network layer:

| Series | Host | Result |
| --- | --- | --- |
| `xau_1m` | datafeed.dukascopy.com | `blocked_by_policy` — 403 to CONNECT |
| `dxy_1m` | datafeed.dukascopy.com | `blocked_by_policy` — 403 to CONNECT |
| `us2y_intraday` | databento.com | `blocked_by_policy` — 403 to CONNECT |
| `dgs2_daily` | fred.stlouisfed.org | `blocked_by_policy` — 403 to CONNECT |
| `gold_daily` | fred.stlouisfed.org | `blocked_by_policy` — 403 to CONNECT |
| `actuals_first_print` | alfred.stlouisfed.org | `blocked_by_policy` — 403 to CONNECT |
| `consensus` | api.tradingeconomics.com | `blocked_by_policy` — 403 to CONNECT |

`blocked_by_policy` means the egress proxy answered 403 to the CONNECT, i.e.
the destination is not on this environment's allowlist. It is not a bad URL, a
missing key, or a rate limit, and retrying or rewriting the request will not
change it.

## The series, and what each one costs

### `xau_1m` — XAUUSD 1-minute OHLC, five years or more

The hardest piece and the one everything else hangs off. Dukascopy's historical
tick export is free and scriptable; FirstRate Data and Databento sell cleaner
1-minute bars.

*Needed for*: impulse, pullback, micro-structure, and every outcome column.

*Degradation*: run the event studies on 5-minute bars. The T+1 and T+3
reaction columns become T+5, the control's entry moves with them, and the
micro-structure breakout filter cannot be evaluated at all — three bars of
5-minute data is a quarter of an hour, which is not micro-structure.

### `dxy_1m` — the dollar index, or EURUSD and USDJPY to synthesise it

*Needed for*: the macro-alignment filter, and nothing else.

*Degradation*: drop the filter from the ablation and report it as **untested
rather than failed**. §1 argues it is not independent confirmation in the first
place, so its absence costs less than the row count suggests. `run` records
this in provenance automatically when `--dxy` is omitted.

### `us2y_intraday` — 2Y yield or a ZT/ZF front-future proxy, 1-minute

*Needed for*: Δ2Y over T+0→T+3, which **is** the v2 direction signal.

*Degradation*: **none.** Direction in v2 is `-sign(Δ2Y) × sign(beta)`. Without
an intraday 2Y there is no direction, no control rule, and no Phase 0. A daily
2Y change cannot stand in: it spans the whole session and carries everything
else that happened that day.

If a futures proxy is used instead of the cash yield, that is a legitimate
substitution and `Source.proxy_for` exists to record it — but note the sign
convention flips (a note future rallies as yields fall) and the loader is given
the series as-is, so invert it before ingest rather than after.

### `dgs2_daily` and `gold_daily` — the beta estimator's two legs

FRED `DGS2` is free and keyless. Gold's daily close can come from FRED
(`GOLDPMGBD228NLBM`) or, acceptably, from resampling the 1-minute series to
daily closes on the same clock — the estimator only needs a consistent daily
sampling of the same asset. `BarSeries.daily_closes` does this; the
substitution must be recorded in provenance by the caller.

*Degradation if both are missing*: the beta estimator cannot run, and with it
the central thesis of v2 is untestable. There is no version of Phase 0 worth
having without this pair.

### `actuals_first_print` — ALFRED vintages

*Needed for*: the surprise column.

*Degradation*: **none, and this is the one shortcut that must not be taken.**
The market traded the number that printed. A panel built from revised FRED
values is lookahead bias dressed as tidiness and it inflates every result
downstream. `loaders.require_first_print` refuses any source marked
`first_print=False` for the actual column, so the rule is enforced in code and
not only in prose.

### `consensus` — analyst consensus, and its dispersion where published

The genuinely hard one. Trading Economics sells an API; Econoday sells the
calendar; a scraped Investing.com historical calendar is the free route and the
least reliable.

*Needed for*: `surprise = actual − consensus`, and the z-scored surprise built
from it.

*Degradation*: without consensus there is no surprise, and the event-study
framing collapses to an unconditional post-release drift study. **That study is
still worth running** — the §3.3 control needs only Δ2Y and prices — but no
surprise-conditioned filter can be evaluated. Events without consensus are
flagged rather than dropped: they still count in the control, and every
surprise filter rejects them, which is visible in the ablation's retained-share
column.

## Ingest formats

All CSV with a header row. Timestamps without a zone are **assumed UTC**;
getting that wrong shifts every event window by hours and would not announce
itself in the results.

| File | Columns |
| --- | --- |
| bars | `timestamp,open,high,low,close[,volume]` |
| daily | `date,value` — FRED's own `observation_date,SERIES` layout is accepted |
| calendar | `timestamp_utc,event_type,actual,consensus[,consensus_sd]` |

Missing values may be empty or `.` (FRED's marker). They become NaN, and NaN
propagates to a flag on the panel row — never to a zero, and never to a
forward fill. A forward-filled daily yield manufactures a zero change on every
holiday, which biases the beta regression toward zero by padding it with
non-observations.
