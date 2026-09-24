# invest

A personal research and trading terminal. Plain Python engines, deterministic
math, point-in-time correctness, and a web front end over the same read-only
API.

**It runs on your own machine**, backed by a local PostgreSQL database: a
command-line tool plus a web terminal at `http://127.0.0.1:8000/app/`. There is
no LLM anywhere in the calculation path.

![Command Center, end-state design mockup](docs/design/command-center.png)

*The end-state design (illustrative data). What is built today and what comes
next is in [docs/SITE_MAP.md](docs/SITE_MAP.md); which data may move a score,
and why, is in [docs/ENGINE_INPUTS.md](docs/ENGINE_INPUTS.md).*

## Direction

The platform is growing from a zero-cost research tool into a trading
terminal for one person (friends possibly later), on a **$150–300/month** data
budget. Two documents govern that growth:

- **[Engine inputs](docs/ENGINE_INPUTS.md).** Only data points that meet all
  eight criteria (evidence, point-in-time, quality, timeliness, cost,
  testability, correct role, licensing) can move a score. Everything else is
  labelled context or cut. V1 adds Alpaca (real-time SIP data, paper and live
  trading, $99/mo) and Norgate (survivorship-free history, ~$53/mo).
- **[Site map](docs/SITE_MAP.md).** Every page, its purpose, its data, and
  whether it is Live, V1 or V2. The site's navigation is built from the same
  list, and a test keeps the two in step.

## Status

**All 12 steps of the build order are complete.** Schema, security master,
price and fundamentals ingestion, validation gate, quant engine, fundamental
models, valuation, scoring and reporting, Form 4 insider parsing, firewalled
political disclosures, FRED macro with a regime classifier, and a
point-in-time backtesting engine.

The read-only FastAPI local API from the spec's tech stack is also built,
and the web terminal (`web/`) is served from it.

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
| Real-time consolidated quotes | **No** (V1: Yes) | exchange-licensed; V1 adds Alpaca's SIP feed |

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

### The web terminal

```bash
npm --prefix web install
npm --prefix web run build  # outputs web/dist
invest serve                # then open http://127.0.0.1:8000/app/
```

`invest serve` serves the built site under `/app` alongside the API, so there
is one process and one origin. While working on the front end, run
`npm --prefix web run dev` instead of building: it serves the site at
`http://127.0.0.1:5173/app/` with hot reload and forwards API calls to
`invest serve`.

The site reads everything through the same read-only endpoints below. Pages
that are not built yet say so and show no numbers, because a placeholder chart
would look like data. Served pages carry a Content-Security-Policy that
restricts them to this origin, so nothing loads from third parties.

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
pytest                      # Python: engines, API, web serving
npm --prefix web test       # site: formatting, API client, site-map sync
npm --prefix web run typecheck
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
  api/                read-only local FastAPI app, and the /app site route
web/                  the web terminal (React + TypeScript + Vite)
  src/siteMap.ts      every page and its status; navigation is built from it
  src/api/            typed client for the read-only API
  src/pages/          one module per page
docs/
  ENGINE_INPUTS.md    which data may move a score, and the evidence for each
  SITE_MAP.md         table of contents: every page, Live / V1 / V2
  design/             end-state mockup (HTML source + rendered PNG)
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
- **Only 10/10 inputs are scored.** In the trading engine, a data point moves
  a score only if it meets every criterion in
  [docs/ENGINE_INPUTS.md](docs/ENGINE_INPUTS.md). Breadth, macro regime,
  prediction markets and the like are shown as labelled context. A test fails
  the build if the signal engine references anything off the list. The older
  research-page Trade Setup score predates the rule (it uses RSI and MACD), is
  labelled legacy, and never feeds a trade card.
- **The ledger cannot be edited.** Every signal the engine finds, fired or
  blocked, is appended with its full reasoning, and outcomes are appended as
  they resolve. Database triggers reject UPDATE and DELETE, and backfilled
  history is labelled so it can never pass for a live track record.
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
