# Inherited code — what to salvage from `src/invest/`

This repository previously contained a complete 12-step build under `src/invest/`
(~12,700 LOC, ~450 tests). It targets a different product: a CLI-only research tool with no
frontend, pandas instead of Polars, pip instead of `uv`, and — critically — a **firewall
that keeps congressional data out of every score**.

Informed Money Terminal makes political disclosure evidence category #2. That is an
inversion, not a refactor, so `src/imt/` is a fresh package. The old tree stays in git
history and is deleted from the working tree once each item below is either ported or
explicitly rejected.

## Port

| From | To | Why |
|---|---|---|
| `providers/ratelimit.py` | `core/http.py` | Token-bucket limiter with tests. Sound. |
| `providers/edgar.py` | `adapters/sec_edgar.py` | Handles UA, 10 req/s, retry semantics. |
| `providers/form4.py` | `adapters/sec_form4.py` | Form 4 XML parsing incl. footnotes, amendments. The single most valuable inherited file. |
| `providers/stooq.py` | `adapters/stooq.py` | CSV shape and quirks already handled. |
| `repository.py` (point-in-time queries) | `db/pit.py` | `as_of` query patterns are correct. |
| `engines/backtest.py` | `backtest/engine.py` | Forward returns, horizon handling. |
| `engines/regime.py` | `features/macro.py` | FRED regime classifier and thresholds. |
| `security_master.py` (`normalize_cik`, `normalize_ticker`) | `entities/identifiers.py` | Small, correct. |

## Reject

| Item | Why |
|---|---|
| Political firewall (`FIREWALLED_TABLES`) | Inverted by design. **But its four objections are real and are answered, not ignored** — see below. |
| `providers/alphavantage.py`, `ingest/intraday.py` | Intraday is out of V1 scope (SPEC §4, DATA_SOURCES deferred list). |
| `engines/scoring.py` | Different model entirely — no convergence, no contradiction, no independence buckets. |
| pandas / pip / `invest` package naming | Superseded by CLAUDE.md's stack. |
| `AnalystEstimate`, `OptionsChainObservation` tables | No free source (DATA_SOURCES deferred). |

## The firewall objections, and how IMT answers them

The old `providers/congress.py` argued congressional data should never reach a score. Those
arguments are good and each one is answered by a specific mechanism rather than dismissed:

1. **"Disclosure lag destroys most of the edge."** → Answered by SPEC §6.5: a 10-day
   half-life, the most aggressive in the table, measured from **transaction date** not
   disclosure date. A 45-day-old PTR retains 4% of its freshness weight. Phase 4 criterion 6
   tests exactly this.
2. **"Bracket midpoints are an invention."** → Answered by SPEC §8: the database stores
   `value_low` and `value_high` only. The midpoint exists solely as a derived feature
   carrying the reason code `derived_bracket_midpoint`. Phase 4 criterion 8 asserts no
   single-amount column exists.
3. **"The dataset is survivorship-biased in how it reaches you."** → Answered by ingesting
   the **complete** House index rather than curated coverage, and by Phase 8 requiring the
   backtest result to be published even when null or negative.
4. **"Attribution is ambiguous — spouses, dependents, blind trusts."** → Answered by
   SPEC §8 carrying `owner_type` (self / spouse / dependent) as a distinct feature rather
   than collapsing filers into one actor.

If Phase 8's backtest shows congressional signals carry no excess return, the honest
outcome is to publish that and set `w_political` toward zero — not to quietly retune.
