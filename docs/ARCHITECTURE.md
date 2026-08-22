# Architecture

Phase 0 deliverable. Resolves `docs/SPEC.md` into buildable structure. Where the spec is
wrong or unbuildable, this document says so rather than working around it silently.

---

## A. System architecture

Four processes. Postgres is the only shared state. There is no message broker, no worker
pool, and no service mesh, because the workload is one user, one machine, and a daily
cadence — a broker would add failure modes without removing any.

```
┌─ imt CLI (Task Scheduler / cron) ─────────────────────────────┐
│  ingest → normalize → resolve → featurize → score             │
│  each subcommand independently runnable and idempotent        │
└────────────────────────────┬──────────────────────────────────┘
                             ▼
                    ┌─────────────────┐
                    │  PostgreSQL 16  │◄──── read-only ──── FastAPI :8000 (loopback)
                    └─────────────────┘                          ▲
                             ▲                                   │ JSON
                   LM Studio :1234 ──── writes llm_outputs        │
                   (qualitative only)                    Next.js :3000
```

**The API never writes.** It holds a read-only database role. Every mutation happens in a
CLI job. This is what makes "refresh the dashboard" incapable of corrupting a backtest, and
it means the API can be restarted mid-ingest without consequence.

### Pipeline stages

```
adapter          HTTP → bytes.        Rate-limited, cached, UA-stamped. No parsing.
raw_documents    bytes → append-only row, keyed by content hash.
normalizer       raw → typed rows (insider_transactions, congressional_transactions, …)
entity resolution  source key → CIK + confidence. Below 0.85 → review queue, not scoring.
signal_events    every evidence-bearing fact → one unified row.
features         signal_events + typed tables → signal_features (raw quantities, units)
scoring          signal_features + weights.yaml → scores
API              scores + events → JSON envelope
UI               envelope → pixels. Formats only; never calculates.
```

**Two boundaries carry the design.**

**`raw_documents` is the bedrock.** Append-only, keyed by `(source_id, source_record_id,
content_hash)`. Everything downstream is derivable from it. When a Form 4 parser turns out
to mishandle footnoted 10b5-1 disclosures — and it will — the fix is a reparse, not a
refetch of 350,000 documents from an API that rate-limits at 10/s. This is also what makes
non-negotiable #3 enforceable rather than aspirational: nothing overwrites a raw record
because the primary key includes the hash of its content.

**`signal_events` is the unification point.** Every fact that could be evidence — a Form 4
purchase, a PTR, a 13D, a contract award — writes one row with the same shape: category,
`detected_at`, `transaction_date`, `disclosure_date`, `disclosure_lag_days`,
`public_available_at`, CIK, value, entity-match confidence, source. Without it, `GET /feed`
is an eight-way `UNION ALL` that must be edited every time a source is added, and the
two-dates rule (non-negotiable #5) has to be re-enforced in eight places. With it, the rule
is a `NOT NULL` constraint in one table.

Process boundary rationale: ingestion is I/O-bound and slow (rate limits dominate); scoring
is CPU-bound and fast; the API must stay responsive. Separating them means a stalled EDGAR
fetch cannot make the dashboard hang, which is the failure the four panel states in UI_SPEC
§4.10 exist to communicate.

---

## B. Repository tree

```
CLAUDE.md                     operating manual, read every session
docker-compose.yml            Postgres 16 (Windows); dev container uses a native cluster
pyproject.toml                uv project, ruff + mypy strict config
scripts/
  dev.ps1 / dev.sh            start db, export IMT_DATABASE_URL
  run_job.ps1                 Task Scheduler entrypoint; wraps `uv run imt …`
  gates.ps1 / gates.sh        the four quality gates in order
config/
  sources.yaml                per-source auth, rate limit, staleness threshold, terms URL
  weights.yaml                every scoring constant + weights_version. Validated at load.
  universe.yaml               exchanges, exclusions, backfill months
  sector_map.yaml             SIC range → internal 11-bucket sector
  overrides/entity_map.csv    manual CIK overrides; always wins; committed
src/imt/
  core/
    config.py                 pydantic-settings; .env; no secret ever logged
    http.py                   THE only outbound HTTP path: limiter, retry, cache, UA
    ratelimit.py              per-host token bucket
    cache.py                  on-disk response cache keyed by URL + UA
    logging.py                structlog: JSON to file, human to console
    clock.py                  the only place `datetime.now` is legal outside adapters
  adapters/
    base.py                   the five Protocols
    sec_edgar.py sec_form4.py sec_xbrl.py stooq.py fred.py cftc.py
    usaspending.py sam.py finra.py openfda.py occ.py house_ptr.py senate_efd.py
    yfinance_adapter.py       second MarketDataProvider, disabled in sources.yaml
  entities/
    normalize.py              normalize_name — one function, every source
    identifiers.py            normalize_cik, normalize_ticker
    resolver.py               per-source strategies → EntityMatch(cik, confidence, method)
    review.py                 the sub-0.85 queue
  ingest/                     one module per job; fetch → raw → normalize → events
  features/                   insider.py political.py activist.py catalyst.py
                              fundamentals.py valuation.py government.py positioning.py
                              macro.py  — each emits signal_features rows, never scores
  scoring/
    weights.py                loads + validates weights.yaml, exposes frozen Weights
    normalize.py              percentile ‖ threshold fallback, stamps method
    categories.py             within-category diminishing returns
    convergence.py contradiction.py freshness.py composite.py
    runner.py                 score_company(cik, as_of, weights, session)
  backtest/                   engine.py universe.py returns.py report.py
  llm/                        client.py sections.py prompts/ citations.py
  api/                        main.py deps.py envelope.py routers/*.py
  db/
    base.py                   DeclarativeBase + SourcedMixin (the six provenance columns)
    models.py  enums.py  pit.py (as-of query helpers)
  cli.py                      typer app: ingest / score / backtest / universe / entities
alembic/versions/             every schema change
frontend/
  src/styles/tokens.css       single source of every colour, size, radius, space
  src/components/
    Panel.tsx                 the four states, implemented once
    Score.tsx                 provenance on hover (UI_SPEC §4.11)
    EventRow.tsx              cannot render without both dates — enforced by types
    Sidebar.tsx TopBar.tsx KpiCard.tsx
    panels/*.tsx              one per dashboard panel
  src/lib/api.generated.ts    from OpenAPI; hand-written response types are forbidden
  src/lib/api.ts              typed fetch wrappers + envelope → PanelState mapping
  tests/tokens.test.ts        no raw hex / arbitrary px outside tokens.css
  tests/copy.test.ts          banned-words gate (UI_SPEC §5)
tests/
  fixtures/                   recorded HTTP responses, committed
docs/
```

---

## C. Data-source matrix — reconciliation

**I could not verify any endpoint from this environment.** The development container's
network policy rejects CONNECT to every data host — `www.sec.gov`, `data.sec.gov`,
`stooq.com`, `publicreporting.cftc.gov`, `disclosures-clerk.house.gov` all return 403 at
the gateway. Only package registries resolve.

This is not a blocker for building (CLAUDE.md already requires zero-network tests against
recorded fixtures), but it has a consequence you need to accept explicitly: **I cannot run
any acceptance criterion that requires live ingestion, and I will not report one as passing.**
Phase 2 criteria 1/2/5/6, Phase 4 criterion 1, Phase 5 criterion 1, Phase 6 criterion 1 and
Phase 7 criteria 1/2 are yours to run. Everything else — parsers, scoring, entity
resolution, API shape, UI, migrations — runs here against fixtures and I will paste real
output for those.

Corrections and warnings against the table in `docs/DATA_SOURCES.md`, from knowledge rather
than probing, all of which need confirming on first live run:

1. **`company_tickers.json` does not carry exchange.** It is `{cik_str, ticker, title}`
   only. Exchange comes from `company_tickers_exchange.json`, a separate file with a
   different shape (`fields` + `data` arrays). The universe builder needs both. DATA_SOURCES
   lists only the first.

2. **Nothing free identifies "common equity".** SPEC §2 excludes ETFs, closed-end funds,
   ADRs, SPACs, units, warrants and preferreds, but no SEC file has a security-type field.
   Proposed deterministic rule, to be recorded in `universe.yaml`: **require a 10-K or 10-Q
   in the trailing 24 months.** Foreign private issuers file 20-F and drop out; funds file
   N-CSR/N-PORT and drop out; most trust/unit structures never file 10-Q. Ticker-suffix
   heuristics (`-WT`, `-U`, `.PR`) catch the residue. This will not be exact, and the
   universe table should carry `inclusion_reason` so the errors are auditable rather than
   invisible.

3. **Stooq per-symbol fetching does not scale to this universe.** 4,000 symbols × one
   request each, daily, against a site with undocumented limits that blocks aggressively, is
   the fastest way to lose the primary price source. The adapter must prefer the bulk daily
   archive and fall back to per-symbol only for gaps. Budget one request per symbol per
   *backfill*, not per day. DATA_SOURCES says "cache aggressively; do not hammer" — this is
   the specific mechanism.

4. **FINRA short interest is not one thing.** Bi-monthly *short interest* and daily
   *short-sale volume* come from different products with different auth and cadence. SPEC §8
   and Phase 7 criterion 3 already forbid conflating them; the adapter layer must reflect it
   as two adapters, not one with a mode flag.

5. **CFTC Socrata dataset identifiers change** when the commission republishes. Pin the
   dataset ID in `sources.yaml`, and have ingestion fail loudly on an unexpected schema
   rather than silently writing nulls.

6. **House PTR ZIP naming is positional, not stable.** `{YEAR}FD.ZIP` has held recently but
   the index format inside has changed between years. Parse defensively and assert row
   counts.

7. **`openFDA` anonymous limits are the binding constraint** at 1,000/day, not the 240/min.
   A universe-wide sponsor sweep exceeds it. Restrict openFDA to the biotech sector module's
   candidate list, not the universe.

---

## D. Database ERD

Every table storing an external fact inherits `SourcedMixin`: `source_id`, `retrieved_at`,
`effective_date`, `source_document_url`, `source_record_id`, `data_quality` (enum). This is
a mixin so it cannot be forgotten, plus a test that reflects the metadata and fails on any
table missing a column.

**Identity and time**

| Table | Key | Notes |
|---|---|---|
| `companies` | `cik` char(10) PK | `name`, `sic`, `sector_code`, `status`, `first_seen`, `last_seen`, `delisted_date`, `inclusion_reason` |
| `ticker_map` | `(cik, ticker, valid_from)` | `valid_to` nullable. **Every ticker→CIK lookup goes through here with a date.** GiST index on the range. |
| `universe_snapshots` | `(snapshot_month, cik)` | one row per security per month; backtest universe reconstruction |

**Raw and operational**

| Table | Key | Notes |
|---|---|---|
| `raw_documents` | `id` bigserial; UNIQUE `(source_id, source_record_id, content_hash)` | `payload` bytea, `content_type`, `retrieved_at`. Append-only, enforced by a `BEFORE UPDATE OR DELETE` trigger that raises. |
| `data_sources` | `id` text PK | mirrors `sources.yaml`; `status`, `staleness_threshold_hours` |
| `ingestion_runs` | `id` | `source_id`, `started_at`, `finished_at`, `status`, `records_written`, `error` — drives every `meta.sources` block |

**Evidence**

| Table | Notes |
|---|---|
| `filings` | `accession` PK, `cik`, `form_type`, `filed_date`, **`acceptance_datetime`**, **`public_available_at`**, `primary_doc_url` |
| `insider_transactions` | `filing_accession` FK, `insider_id`, `transaction_code` char(1), `transaction_date`, `shares`, `price_minor` bigint, `value_minor` bigint, `currency`, `is_10b5_1`, `role`, `shares_owned_after` |
| `congressional_transactions` | `filer_id`, `owner_type` enum(self/spouse/dependent), `transaction_date`, `disclosure_date`, `disclosure_lag_days` generated, **`value_low_minor`, `value_high_minor`** — and **no single-amount column, ever** |
| `activist_positions` | `is_activist` bool (13D true / 13G false — never inferred), `pct_of_class`, `item4_categories` text[] |
| `institutional_holdings` | 13F; `report_period`, `filed_date` |
| `government_contracts` | `recipient_uei`, `recipient_name`, `award_amount_minor`, `action_date`, `agency`, `naics` |
| `xbrl_facts` | `(cik, tag, unit, period_start, period_end, filed_date)` — **append-only; restatements insert** |
| `prices_daily` | `(cik, date)`, adjusted OHLCV, `is_adjusted` always true in V1 |
| `short_interest` | bi-monthly; `settlement_date`, `publication_date`, `shares_short`, `pct_shares_outstanding` |
| `short_volume` | daily; **separate table by design** (Phase 7 criterion 3) |
| `macro_observations` | `series_id`, `reference_period`, `release_timestamp`, `value` |

**Resolution, signals, scores**

| Table | Notes |
|---|---|
| `entity_matches` | `(source, source_key)` PK, `resolved_cik`, `method`, `confidence` numeric(4,3), `resolved_at`, `reviewed` |
| `entity_review_queue` | everything below 0.85, with candidates and scores |
| `signal_events` | `event_id`, `category`, `cik`, `detected_at`, `transaction_date`, `disclosure_date`, `disclosure_lag_days`, **`public_available_at NOT NULL`**, `value_low_minor`/`value_high_minor`/`value_exact_minor`, `entity_match_confidence`, `source_id`, `source_document_url`. CHECK: for `political`/`corporate_insider`/`institutional`, `transaction_date` and `disclosure_date` are both NOT NULL. CHECK: exactly one of range/exact populated. |
| `signal_features` | `(cik, as_of, feature_key)`, `value` numeric, `unit`, `reason_code` nullable — **NULL value + reason code is the only way to express missing** |
| `scores` | `(cik, as_of)`, all composites, **`weights_version` NOT NULL**, **`normalization` NOT NULL**, `categories_cleared`, `categories_total` |
| `contradiction_items` | `(cik, as_of, check_id)`, `severity`, `detail`, `source_url`, `status` enum(fired/clear/**unavailable**) |
| `llm_outputs` | `model`, `prompt_version`, `temperature`, `fact_set_hash`, `payload` JSONB |

Indexes that matter: `signal_events (cik, public_available_at DESC)` for the feed and every
point-in-time query; `signal_events (category, detected_at DESC)` for feed tabs;
`xbrl_facts (cik, tag, filed_date)` for as-of fundamentals; partial index
`entity_matches (source) WHERE confidence < 0.85` for the review queue.

**Point-in-time is enforced by column, not convention.** `public_available_at` is NOT NULL
on `signal_events` and `filings`. Every backtest query filters on it. There is no code path
that can select an event by `transaction_date` for entry timing, because the backtest engine
takes only `public_available_at` as its clock.

**Money is `bigint` minor units + `currency`** everywhere, per API_CONTRACT. No `float`,
no `numeric` for money. `numeric` is reserved for ratios and scores.

---

## E. Scoring implementation

`config/weights.yaml` → `scoring/weights.py` → frozen `Weights` dataclass, loaded once per
process. **Validation at load, not at use:**

- category weights must **not** sum to ≈1.0 (±0.15) — the SPEC §6.4 normalization trap
- no single category weight > 1.05 — beyond that, one category clears Convergence 45 and
  Phase 3 criterion 2 fails
- τ ∈ [0,100], λ > 0
- `weights_version` present and semver

The file's SHA-256 is recorded alongside `weights_version`; a mismatch between a committed
version string and the file's hash fails the load, so weights cannot drift from their label.

**The scoring entry point is a pure function:**

```python
def score_company(cik: str, as_of: date, weights: Weights, facts: FactSet) -> ScoreRow: ...
```

`FactSet` is materialized *before* scoring by a query filtered on `public_available_at <=
as_of`. Scoring itself touches no session, no clock, no filesystem. That is what makes
criterion 1 (byte-identical reruns) and criterion 3 (no `datetime.now` under `scoring/`)
structurally true rather than hopefully true.

**Determinism has one real threat: float non-associativity.** `Π(1 - s/100)` over
sub-signals gives different last-bit results depending on iteration order, and set/dict
iteration order is not guaranteed across the values involved. Mitigation: every reduction
sorts its inputs by a stable key (`actor_id`, then `feature_key`) before folding, and every
persisted score is `round(x, 6)`. The reproducibility test compares exported CSV bytes.

**Stamping.** `weights_version` and `normalization` are non-nullable columns on `scores`,
written by `runner.py` from the loaded `Weights` — not passed in by callers, so they cannot
be omitted or falsified.

**Normalization** tries percentile against the trailing 36-month distribution, requires
≥500 observations, and otherwise falls back to the piecewise-linear thresholds in
`weights.yaml`, stamping `fallback_threshold`. In V1 this is effectively always the
fallback, which is why Confidence carries the ×0.7 penalty and is capped at 70.

**A finding that changes Phase 3.** SPEC §6.6 lists thirteen contradiction checks. Only
three of them — CEO/CFO selling, executive departure, immaterial insider purchase — can be
computed from Phase 2 data. The rest need fundamentals (Phase 5), short interest and prices
(Phase 7), or government awards (Phase 6). Building Phase 3's contradiction engine as
though all thirteen exist would produce a system that reports Contradiction 0 for companies
it has simply not checked, which is worse than reporting nothing.

Resolution: contradiction is a **registry**. Each check declares the data it needs. At
scoring time a check is `fired`, `clear`, or `unavailable`, and `unavailable` is persisted
distinctly. The UI renders "3 of 13 checks available" beside the score, and `DataQuality`
is reduced in proportion — so a company with most checks unavailable cannot rank highly,
which is exactly the mechanism SPEC §10 already specifies. Checks light up as their phases
land, with no change to the scoring core.

---

## F. Frontend architecture

Next.js 15 App Router. Server components fetch; client components handle interaction. Each
panel fetches independently — UI_SPEC §6 requires no panel to block another, so there is no
single dashboard query.

**The four states are one component.** `Panel` takes a discriminated union:

```ts
type PanelState<T> =
  | { kind: 'loading' }
  | { kind: 'empty';  message: string; action?: string }
  | { kind: 'stale';  data: T; sourceId: string; lastSuccess: string; asOf: string }
  | { kind: 'failed'; message: string; retryAt?: string; affected: string[] }
  | { kind: 'ready';  data: T };
```

`src/lib/api.ts` maps the response envelope to that union — `meta.sources[].status` decides
stale vs ready, an `error` body decides failed, an empty `data` array decides empty. Panels
never construct the union themselves, so "panel with only a happy path" becomes impossible
rather than merely discouraged: the type has no ready-only form.

**Types.** `openapi-typescript` generates `src/lib/api.generated.ts` from FastAPI's schema.
It is committed, and `npm run types:check` regenerates and diffs — CI fails on drift. Hand
authoring a response interface is what lets a `% of float` label reappear after being
removed, so the lint config bans importing response types from anywhere else.

**Token lint.** Two layers. A vitest test scans `frontend/src/**` for `#[0-9a-f]{3,8}` and
bare `px` values outside `tokens.css` and fails with the offending file and line. An ESLint
rule bans arbitrary Tailwind values (`bg-[#...]`). Both run in `npm test`, so criterion 8 is
provable by adding a hex and watching the suite go red.

**`EventRow` cannot render without both dates.** Its props type requires
`transactionDate` and `disclosureDate` as non-optional for political/insider/institutional
categories via a discriminated union on `category`. The two-dates rule is a compile error,
not a code review.

---

## G. Build order

`docs/PHASES.md` is sound and I would keep its shape. Two amendments, both dependency
corrections rather than preference:

**1. Pull Stooq EOD prices forward into Phase 2.** Phase 3's contradiction check "stock
already up >50% in 90 days" needs a price series, and Phase 8 needs one for every forward
return. Prices are currently first mentioned in Phase 7. The Stooq adapter is small and has
no auth, so it costs little to add as a Phase 2 slice, and it unblocks a contradiction check
and de-risks the phase everything depends on. Without this, Phase 3 ships with 3 of 13
contradiction checks instead of 4, and Phase 8 begins with an unproven price path.

**2. Phase 3's contradiction engine is explicitly partial**, per section E. This should be
written into the phase description so it is not discovered as a shortfall later. Add an
acceptance criterion: *unavailable checks are persisted as `unavailable`, never as clear,
and the UI shows the available-check count.*

Otherwise the dependency chain holds: 1 → 2 → 3, with 4/5/6/7 independently parallel after
3, 8 requiring 2+3 plus whichever of 4–7 the signal under test needs, 9 requiring 5, and 10
requiring everything. The riskiest ordering choice in the existing plan is correct: Phase 4
(congressional PDFs) sits after the scoring core, so a two-week OCR sink does not block the
system's core value.

---

## H. $0 audit and feature matrix

**Confirmed free, no payment method, V1:** SEC EDGAR (all forms, submissions, XBRL, ticker
map), FRED, CFTC, USAspending, Stooq, EIA, openFDA, FINRA, SAM.gov, OCC, House PTRs,
PostgreSQL, Python/Node toolchain, LM Studio and any local model.

**Could unexpectedly cost or hard-stop:**

| Risk | Mechanism | Mitigation |
|---|---|---|
| SEC IP block | >10 req/s or missing UA | Limiter defaults 8/s; UA mandatory in `core/http.py`; block is the loudest failure in the system and must page the operator, not retry silently |
| Stooq soft-ban | per-symbol sweeps | bulk archive; per-symbol only for gaps |
| openFDA 1,000/day anon | universe-wide sweep | sector-module scope only |
| SAM.gov key latency | days to issue | start before Phase 1; Phase 6 is otherwise blocked |
| LM Studio wall-clock | 8k context × top-10 companies | funnel (SPEC §12) restricts LLM to final tier; nothing in the critical path waits on it |
| Disk | raw payload retention, append-only | 24-month backfill ≈ tens of GB; `raw_documents` payloads compressed, retention policy configurable |

**Feature matrix**

| Feature | Tier |
|---|---|
| Insider, congressional (House), activist, 8-K, fundamentals, valuation, government contracts, macro regime, short interest, sector heat, convergence/contradiction scoring, backtesting, AI analyst | `V1-Free` |
| Senate eFD automated retrieval | `V2` — manual CSV in V1 |
| TRACE / credit divergence | `V2` — CUSIP licensed by CGS; schema + interface only, feed disabled |
| Public float, float-based short % | `Premium-Dependent` |
| GICS sectors | `Premium-Dependent` — SIC taxonomy instead |
| Real-time options flow, Greeks, IV surface, dealer gamma | `Premium-Dependent` — interfaces only |
| Intraday prices, analyst estimates, transcripts, unadjusted price history | `Premium-Dependent` |

---

## I. Risks and open questions

**Entity resolution is the system's central risk**, and its error rate is not symmetric. A
false negative loses a signal; a false positive **manufactures convergence that does not
exist**, which is the one failure that makes the whole product actively misleading. Expected
accuracy from SPEC §5: SEC 100%, FINRA ~98%, congressional ~85% with ticker and ~60%
without, USAspending/SAM ~50–70%, openFDA ~50%. At the 0.85 gate, government-contract
coverage will be visibly partial and must stay labelled that way.

**Convergence is measured across categories that are not actually independent.** An 8-K
announcing a contract award and the USAspending record of that same award are two categories
by SPEC §6.3's definition, but one event. Category 5 (corporate event) and category 4
(government business) will co-fire on the same underlying fact and inflate convergence.
Phase 3 needs a de-duplication pass keyed on `(cik, underlying_event_date, value)` across
categories, and I do not think the current spec accounts for it.

**Statistical power at long horizons is marginal.** A 24-month backfill supports roughly 12
months of signals at the 250-day horizon. Insider clusters (≥3 independent `P` filers in 7
days) are not common; the sample at 250 days may be small enough that a point estimate is
meaningless. Phase 8 must report confidence intervals, and a null result there is the most
likely single outcome of this project.

**Look-ahead will re-enter through repair work, not through the original code.** The
backtest engine takes `public_available_at` as its only clock, but a later "fix" that joins
`transaction_date` for convenience reintroduces the bug invisibly. Criterion 1 must run over
the full result set on every backtest, not once.

**Survivorship depends on `universe_snapshots` actually being written monthly** from the
first month. There is no way to reconstruct a snapshot retroactively — a month not captured
is gone. This should start in Phase 2, not Phase 8.

**LLM hallucination is contained structurally**, not by prompting: the LLM writes only to
`llm_outputs`, a test asserts no module under `llm/` writes a numeric column, and uncited
claims are moved server-side from `facts` to `interpretation`. The residual risk is a
plausible-but-wrong *summary* of a real filing section, which citation display mitigates but
does not eliminate.

**Threshold-normalized scores are hypotheses shown as numbers.** Everything in V1 carries
the dotted underline and the ×0.7 confidence penalty, but a 94 still looks authoritative on
a dark background. This is a real product risk and the strongest argument for reaching Phase
8 quickly rather than polishing Phases 4–7.

---

## Decisions needed before Phase 1

1. **Mockup.** `docs/design/dashboard-mockup.png` is not in the repo. Phase 1 criterion 7
   and Phase 10 criterion 7 cannot be met without it. Send it, or accept that both are
   waived and UI_SPEC §1/§3/§4 alone are the visual authority.

2. **Live-ingestion criteria.** This environment cannot reach any data host. Confirm you
   will run the live criteria on your Windows machine and paste output back, and that I
   should mark them `blocked-external` rather than skipping or simulating them.

3. **Prices into Phase 2?** Section G amendment 1. My recommendation is yes.

4. **Partial contradiction engine.** Confirm the registry approach in section E — checks
   report `unavailable` and reduce DataQuality — rather than Phase 3 shipping a
   contradiction score that silently means "3 of 13 checks ran".

5. **Cross-category double counting.** Do you want the de-duplication pass in Phase 3, or
   accept inflated convergence on contract-announcement events until later? I recommend
   Phase 3, because every score produced before the fix is wrong in a way that flatters the
   system.

6. **Universe rule.** Confirm "10-K or 10-Q in trailing 24 months" as the common-equity
   proxy, with `inclusion_reason` recorded per company. It will admit some non-common
   equity and exclude some genuine names.

7. **The old `src/invest/` tree.** Delete from the working tree once ports are done (history
   retains it), or keep it side by side during the build? I recommend deleting after Phase 3
   — by then everything worth porting has been.

8. **Python version.** Spec says 3.12; the dev container has 3.12.3 available and Windows
   should install 3.12. Confirm no 3.13 features.

9. **`imt` on PATH.** Task Scheduler needs an absolute path to `uv`. Confirm you want
   `scripts/run_job.ps1` to resolve it rather than assuming a PATH entry.
