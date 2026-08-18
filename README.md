# invest

Zero-cost, institutional-style investment research platform. Plain Python,
free data sources only, deterministic math, point-in-time correctness.

**It is a command-line tool that runs on your own machine**, backed by a local
PostgreSQL database. No web app, no phone app, no paid services, no LLM
anywhere in the calculation path.

## Status

**All 12 steps of the build order are complete.** Schema, security master,
price and fundamentals ingestion, validation gate, quant engine, fundamental
models, valuation, scoring and reporting, Form 4 insider parsing, firewalled
political disclosures, FRED macro with a regime classifier, and a
point-in-time backtesting engine.

The read-only FastAPI local API from the spec's tech stack is also built.

## Setup

```bash
cp .env.example .env        # set EDGAR_USER_AGENT to "yourapp your@email" — SEC requires it
pip install -e ".[dev]"
docker compose up -d        # PostgreSQL 16 on localhost:5432
alembic upgrade head        # create the schema
invest db check

invest bootstrap            # seed, verify CIKs, ingest prices + fundamentals
```

`bootstrap` runs CIK verification *before* fetching any fundamentals — an
unverified CIK would attach one company's financials to another company's
price history, and that is tedious to unpick once written.

## About "real-time"

There isn't any, and there can't be at zero cost. Exchanges license the
real-time consolidated feed, so no free source carries it. What this platform
gets is:

| Tier | Available | Source |
|---|---|---|
| End-of-day daily bars | Yes | Stooq, Alpha Vantage |
| ~15-minute delayed intraday | Yes | Alpha Vantage |
| Real-time consolidated quotes | **No** | exchange-licensed |

Every intraday row carries `delay_seconds` in a NOT NULL column, and a CHECK
constraint forces `is_delayed` to agree with it. You cannot store an
unlabelled quote, and `invest quote` always prints the basis and the age:

```
AAPL  125.60
  basis      DELAYED by 15 min
  age now    17 min
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

More:

```bash
invest ingest filings       # SEC filing index + Form 4 insider transactions
invest insider AAPL         # insider activity, conviction trades separated from grants
invest ingest macro         # FRED series (needs FRED_API_KEY)
invest regime               # market regime from macro data
invest backtest AAPL --fast 50 --slow 200   # point-in-time backtest with costs
invest ingest intraday      # delayed intraday bars (needs ALPHAVANTAGE_API_KEY)
invest quote AAPL           # latest price, with its true age stated

invest ingest political --file disclosures.csv   # firewalled, never a score input
invest disclosures AAPL     # congressional disclosures, research context only
```

### The local API

```bash
invest serve                # http://127.0.0.1:8000, interactive docs at /docs
```

Read-only and unauthenticated, which is only safe because it is also local.
Two things enforce that rather than assuming it: every route is a GET (a test
enumerates the route table and fails on anything else), and every request runs
inside a `SET TRANSACTION READ ONLY` transaction, so a bug in a handler cannot
write. Binding a non-loopback address requires `--allow-public-bind`, because
exposing it publishes your research database to whoever can reach the port.

Every data endpoint takes `as_of`, so point-in-time is the default posture
rather than something a caller must remember to ask for.

## Testing

```bash
pytest                      # 597 tests
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
  engines/            quant, fundamentals, valuation, scoring, regime, backtest
  reports/            the rendered research report
  api/                read-only local FastAPI app
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
- **Most signals cannot be honestly backtested here, and the engine refuses
  rather than pretending.** There is no survivorship-bias-free universe
  history on free sources, so any cross-sectional or multi-name backtest is
  refused outright with `THIS SIGNAL CANNOT YET BE RELIABLY BACKTESTED WITH
  THE AVAILABLE FREE DATA.` Single-name price and fundamental signals do run,
  and still carry a survivorship caveat in every report.
- Backtest spread and slippage are assumptions, not measurements. V1 has no
  quote or fill data, so the defaults are deliberately pessimistic.
- Political disclosures require a structured CSV export. The official sources
  publish PDFs and a search UI, and parsing transaction tables out of
  variable-layout PDFs would risk writing a plausible-looking wrong number.
- Live ingestion has not been exercised against the real Stooq and SEC
  endpoints from the development sandbox, whose egress policy blocks them. The
  parsers are tested against fixtures; run `invest ingest prices AAPL` on your
  own machine to confirm the live path.
