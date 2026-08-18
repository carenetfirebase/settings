# invest

Zero-cost, institutional-style investment research platform. Plain Python,
free data sources only, deterministic math, point-in-time correctness.

**It is a command-line tool that runs on your own machine**, backed by a local
PostgreSQL database. No web app, no phone app, no paid services, no LLM
anywhere in the calculation path.

## Status

Steps 1-8 of the build order are complete: schema, security master, price and
fundamentals ingestion, validation gate, quant engine, fundamental models,
valuation, scoring, and the rendered research report.

Not yet built (steps 9-12): filings watcher and Form 4 parsing, political trade
ingestion, FRED macro and regime classification, and the backtesting engine.

## Setup

```bash
cp .env.example .env        # set EDGAR_USER_AGENT to "yourapp your@email" — SEC requires it
pip install -e ".[dev]"
docker compose up -d        # PostgreSQL 16 on localhost:5432
alembic upgrade head        # create the schema
invest db check
```

## Using it

```bash
invest universe seed        # load ~21 large-cap tickers
invest universe verify      # confirm CIKs against SEC EDGAR (do this before trusting data)
invest ingest prices        # daily OHLCV from Stooq, through the validation gate
invest ingest fundamentals  # XBRL companyfacts from SEC EDGAR
invest analyze AAPL         # score + render the research report, save a snapshot

invest analyze AAPL --as-of 2023-06-30   # point-in-time: only data public by that date
invest conflicts            # what the validation gate flagged
invest snapshots            # stored research runs
```

## Testing

```bash
pytest                      # 337 tests
```

Tests that need a database use `TEST_DATABASE_URL` (default
`postgresql+psycopg://invest@127.0.0.1:5432/invest_test`) and skip with a
visible reason if no server is reachable. They run the real Alembic migrations
rather than `create_all`, so the triggers are exercised too.

## How it is put together

```
src/invest/
  config.py           env-driven settings, no hardcoded secrets
  universe.py         the seed research universe
  security_master.py  ticker -> CIK -> entity_id resolution
  repository.py       THE read layer: point-in-time + quarantine filtering
  analysis.py         orchestration: read -> engines -> snapshot -> report
  db/                 models, enums, session
  providers/          one adapter per source, all behind Protocols
  validation/         the single mandatory gate + its rules
  ingest/             provider -> gate -> database, per domain
  engines/            quant, fundamentals, valuation, scoring
  reports/            the rendered research report
```

Data flows one way: **provider -> validation gate -> database -> repository ->
engines -> report**. The engines never import a vendor module; the providers
never touch the database.

## The rules this codebase enforces

These are enforced by code and tests, not by convention:

- **Nothing is fabricated.** A value that cannot be retrieved is `NULL` with a
  quality flag, and surfaces as `INSUFFICIENT DATA`. Nothing is interpolated,
  zero-filled, or carried forward.
- **Point-in-time.** Every fundamental carries a mandatory `filed_date`.
  Queries filter `filed_date <= as_of`, so a restatement filed later is
  invisible to a simulation dated earlier.
- **Append-only.** Database triggers reject `UPDATE` and `DELETE` on
  `price_observations`, `fundamentals`, and `research_snapshots`. Corrections
  are new rows.
- **No LLM in the math.** Every ratio, score, and valuation is deterministic
  Python with unit tests.
- **Scores are decomposable.** A total is never stored or displayed without its
  components and their weights.
- **The political-trade firewall.** `political_trades` cannot contribute to any
  score — enforced by a static AST check on the scoring module, a runtime SQL
  guard, and an end-to-end test.
- **Honest confidence.** The Confidence score carries a permanent 25% haircut
  for premium data this platform does not have (analyst estimates, options,
  real-time quotes, executability). It is stated in every report.

## Known limitations

- Stooq prices are split-adjusted but **not** dividend-adjusted, and this is
  recorded per row. Do not compute total returns from them without accounting
  for it.
- WACC is modelled from CAPM assumptions and always labelled `estimated`.
- Comparables need a peer group supplied; peer selection is not automated.
- Live ingestion has not been exercised against the real Stooq and SEC
  endpoints from the development sandbox, whose egress policy blocks them. The
  parsers are tested against fixtures; run `invest ingest prices AAPL` on your
  own machine to confirm the live path.
