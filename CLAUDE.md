# CLAUDE.md — Informed Money Terminal

Read this file first, every session. It is the operating manual.

| File | What it is | When to read |
|---|---|---|
| `docs/SPEC.md` | Product and data requirements | When you need a requirement |
| `docs/DATA_SOURCES.md` | Source matrix, auth, licensing, fallbacks | Before touching any adapter |
| `docs/UI_SPEC.md` | Design tokens, every panel, mockup corrections | Before touching any frontend file |
| `docs/API_CONTRACT.md` | Panel → endpoint → table → source, with normative field names | Before adding any route or fetch |
| `docs/PHASES.md` | Build order and acceptance criteria | At the start and end of every phase |
| `docs/ARCHITECTURE.md` | Resolved architecture, Phase 0 output | When you need a decision's rationale |
| `docs/INHERITED.md` | What was salvaged from the prior `src/invest/` build | Before writing an adapter or parser from scratch |

## What this project is

A local, single-user research terminal that ranks publicly traded US companies by how
unusually multiple **independent** public-evidence categories converge — insider buying,
congressional disclosures, activist filings, government contracts, fundamentals,
valuation, positioning, macro — and actively searches for evidence against each thesis.

It outputs a **Research Priority** ranking, never a buy/sell recommendation.

## Non-negotiables

1. **$0/month.** No paid API, no cloud service, no paid tier. Free-but-registration-required
   is acceptable and must be declared. If a feature cannot be built on free data, mark it
   `Premium-Dependent`, build the interface, disable the feature. Never approximate silently.
2. **Never fabricate a financial data point.** If a value is missing, it is `NULL` with a
   reason code. No interpolation, no LLM-generated numbers.
3. **Never overwrite a raw source record.** Raw payloads are append-only. Backtests depend on it.
4. **Deterministic code computes numbers. The LLM never does.** No ratio, score, weight, or
   return is ever produced by a language model.
5. **Transaction date and disclosure date are different fields and both are always shown.**
   Any UI element implying a congressional trade happened today when the PTR covers a
   six-week-old transaction is a bug.
6. **No look-ahead.** See SPEC §7. Every backtest entry uses the public-availability
   timestamp, never the underlying event date.
7. **The mockup is the visual authority; SPEC is the behavioural authority.** Where they
   disagree, build the corrected version in UI_SPEC §2. There are twelve such corrections
   and every one exists because the mockup as drawn would mislead the user.
8. **The frontend formats; it never calculates.** Every percentage, ratio, delta, and lag is
   computed in Python and returned by the API. One source of truth per figure.

## Environment

The spec targets Windows 11. The code is written cross-platform so it also runs on the
Linux container used for development. **Never introduce a platform-specific dependency
without a fallback.**

| Thing | Choice | Notes |
|---|---|---|
| Target OS | Windows 11 | Native, **not** WSL. Use PowerShell 7 (`pwsh`). |
| Dev OS | Linux container | Same commands via `scripts/*.sh` mirrors of `scripts/*.ps1`. |
| Shell | PowerShell 7 on Windows | No `make`, no bash-isms, no `&&` chaining in `.ps1`. Use `;` or separate lines. |
| Python | 3.12 | |
| Python packaging | `uv` | `uv sync`, `uv run`. No pip, no poetry, no conda. |
| Database | PostgreSQL 16 | Docker Desktop on Windows; native cluster in the dev container. **SQLite is not a target.** Use JSONB, window functions, CTEs, partial indexes freely. |
| Migrations | Alembic | Every schema change is a migration. No manual DDL. |
| Backend | FastAPI + SQLAlchemy 2.0 (typed, `Mapped[]` style) | |
| Data processing | Polars | Pandas only where a library forces it. |
| Frontend | Next.js 15 (App Router), TypeScript, Node 20+ LTS | |
| Styling | Tailwind CSS | |
| Charts | Apache ECharts (`echarts-for-react`) | |
| Scheduling | Windows Task Scheduler → `scripts/run_job.ps1` | Each job is a CLI entrypoint, independently runnable. |
| Local LLM | LM Studio, OpenAI-compatible endpoint at `http://localhost:1234/v1` | Model configurable. Assume 8k usable context unless told otherwise. |
| Testing | pytest + `respx` for HTTP mocking | |
| Lint/format | ruff (format + lint), mypy strict on `src/imt/` | |

Paths: always use `pathlib.Path`. Never hardcode `/` or `\`.

## Commands

```powershell
# one-time
docker compose up -d db
uv sync
uv run alembic upgrade head
cd frontend; npm install; cd ..

# daily dev
docker compose up -d db
uv run uvicorn imt.api.main:app --reload --port 8000
cd frontend; npm run dev            # port 3000, proxies /api to :8000

# quality gates — all four must pass before any phase is called done
uv run ruff format --check .
uv run ruff check .
uv run mypy src/imt
uv run pytest

# ingestion jobs (also what Task Scheduler calls)
uv run imt ingest sec-submissions --since 2d
uv run imt ingest form4 --since 2d
uv run imt score run --date today
uv run imt backtest run --signal insider_cluster --horizons 1,5,20,60,120,250
```

On Linux, `scripts/dev.sh` starts the database cluster and exports `IMT_DATABASE_URL`.

## Repo layout

```
src/imt/
  adapters/        one module per data provider, all behind a Protocol
  ingest/          job entrypoints; fetch → validate → persist raw → normalize
  entities/        entity resolution (see SPEC §5) — the crux of the system
  features/        deterministic feature computation from normalized tables
  scoring/         normalization, category scores, convergence, contradiction
  backtest/        point-in-time event studies
  llm/             local LLM client + prompts; qualitative only
  api/             FastAPI routers
  db/              SQLAlchemy models, Alembic env
  core/            config, logging, rate limiting, retries, caching
frontend/
  src/styles/tokens.css   single source of every colour, type, and space value
  src/components/         panel primitives; each implements loading/empty/stale/failed
  src/lib/api.ts          generated types + typed fetch wrappers
config/            weights.yaml, sources.yaml, universe.yaml, sector_map.yaml, overrides/
tests/
  fixtures/        recorded HTTP responses — committed
docs/
```

## Conventions

- **Adapters.** Every external source sits behind a `Protocol` in `adapters/base.py`
  (`MarketDataProvider`, `PoliticalDataProvider`, `FundamentalsProvider`,
  `OptionsDataProvider`, `ContractsProvider`). Swapping a free provider for a paid one
  later must touch only `adapters/` and `config/sources.yaml`.
- **Every persisted fact carries** `source_id`, `retrieved_at`, `effective_date`,
  `source_document_url`, `source_record_id`, `data_quality` enum. This is a schema
  constraint, not a convention. No table storing an external fact omits them.
- **HTTP.** All outbound calls go through `core/http.py`: per-host rate limiter,
  exponential backoff, on-disk response cache, mandatory User-Agent from
  `config/sources.yaml`. Never call `httpx` directly from an adapter.
- **SEC fair access.** Max 10 req/s, `User-Agent: "Informed Money Terminal <your-email>"`.
  Exceeding this gets the IP blocked. The limiter defaults to 8 req/s.
- **Tests never hit the network.** Use recorded fixtures in `tests/fixtures/`. Live smoke
  tests are marked `@pytest.mark.live` and excluded by default
  (`addopts = "-m 'not live'"`).
- **Secrets** in `.env`, never committed. `.env.example` stays current with every new key.
- **Logging** is structured (`structlog`), JSON to file, human-readable to console. Never
  log a secret or a full raw payload.
- **Design tokens.** Every colour, font size, radius, and spacing value comes from
  `frontend/src/styles/tokens.css`. A lint rule fails the build on a raw hex value or
  arbitrary pixel size anywhere in `frontend/src` outside that file.
- **Panel states.** Every data panel implements loading, empty, stale, and failed (UI_SPEC
  §4.10). A panel with only a happy path is not done.
- **Copy gate.** The banned-words grep test in UI_SPEC §5 runs in the standard test suite,
  not just at Phase 10.
- **Scores are reproducible.** Running `imt score run --date 2026-03-01` twice produces
  byte-identical output. No `random`, no `datetime.now()` inside scoring — the as-of date
  is always passed in.

## Working method

- **One vertical slice at a time.** A slice is: adapter → ingest job → normalized table →
  feature → API endpoint → UI element → tests. Do not build all adapters, then all
  features. Build one thing end to end.
- **Do not start the next phase until the current phase's acceptance criteria in
  `docs/PHASES.md` pass.** State explicitly which criteria you ran and their output.
- For each slice: (1) say what you're building and why, (2) list files touched, (3) write
  the code, (4) give the exact PowerShell commands, (5) give a test procedure with expected
  output, (6) name the two or three most likely failure modes.
- **Ask before assuming.** If the spec is ambiguous, ask one specific question rather than
  picking a plausible interpretation and building on it.
- **Push back.** If something in the spec is a bad idea, unbuildable on free data, or will
  produce misleading output, say so before building it. Being agreeable here is expensive.
- I am technically capable but still learning software engineering. Explain architectural
  decisions in plain language. Skip the jargon, keep the substance.

## Context management

`docs/SPEC.md` is long. Read the section you need, not the whole file, once you are past
the architecture phase. `docs/PHASES.md` tells you which SPEC sections a phase depends on.
