# Build phases

A phase is **not done** until every acceptance criterion below produces the stated output,
plus the four quality gates in `CLAUDE.md` (ruff format, ruff check, mypy, pytest) pass.
State explicitly which criteria you ran and paste the output. Do not begin the next phase
before then.

Within a phase, build **one vertical slice at a time** — adapter → ingest → table →
feature → endpoint → UI → tests — not all adapters then all features.

---

## Phase 0 — Architecture (no code)

**Deliverable:** `docs/ARCHITECTURE.md`, in nine sections:

- **A. System architecture** — components, data flow ingestion → entity resolution →
  features → scoring → API → UI, and where the process boundaries sit.
- **B. Repository tree** — every folder and significant file with a one-line purpose.
- **C. Data-source matrix** — reconcile `docs/DATA_SOURCES.md` against current reality.
  Confirm or correct each endpoint, auth requirement, rate limit, cadence, format,
  licensing constraint, and fallback. Flag anything believed wrong or changed.
- **D. Database ERD** — tables, columns with types, keys, indexes, raw-payload retention.
  Must satisfy the point-in-time requirements in SPEC §7 and the field names in
  `docs/API_CONTRACT.md`.
- **E. Scoring implementation plan** — how the formulas in SPEC §6 become deterministic
  code, where `weights.yaml` is read, how `weights_version` is stamped on every score row,
  and how the reproducibility test in Phase 3 will be satisfied.
- **F. Frontend architecture** — component hierarchy, how the four panel states in UI_SPEC
  §4.10 are implemented once and reused, how generated OpenAPI types reach components, how
  the token lint rule works.
- **G. Build order** — confirm or amend this file, with inter-phase dependencies explicit.
- **H. $0 cost audit and feature matrix** — every V1 component confirmed free; separately,
  anything that could unexpectedly incur cost or hit a hard quota. Then every feature
  marked `V1-Free`, `V2`, or `Premium-Dependent`.
- **I. Risks and open questions** — data quality, look-ahead, survivorship, expected
  entity-resolution error rates by source, licensing, false positives, LLM hallucination.

Ends with a numbered list of decisions needed before Phase 1.

**Done when:** the document exists, covers sections A–I, and ends with that list. No other
file has been created.

---

## Phase 1 — Foundation

Reads: SPEC §2, §3, §5, §13; UI_SPEC §1, §3, §4.1, §4.2, §4.10; API_CONTRACT (envelope); all of `CLAUDE.md`.

Repo skeleton · `uv` project · Docker Compose Postgres 16 · Alembic · structlog ·
`core/http.py` (rate limiter, retry, disk cache, UA injection) · `config/sources.yaml`,
`weights.yaml`, `universe.yaml` · FastAPI app with `/health` · Next.js shell with dark
theme tokens · **`entities/` module with name normalization, match confidence, override
CSV, review queue table** · pytest with `respx` fixtures · CI-equivalent local script.

**UI slice:** `tokens.css` from UI_SPEC §1 · app shell, sidebar with all three nav groups
(unshipped items disabled with "Available in Phase N") · top bar with search field and the
data-freshness cluster · `<Panel>` primitive implementing all four states from UI_SPEC §4.10
· `<Score>` provenance component (UI_SPEC §4.11) · generated API types.

**Acceptance:**
1. `docker compose up -d db; uv run alembic upgrade head` → migrations apply clean on an empty DB.
2. `curl http://localhost:8000/health` → `{"status":"ok","db":"ok"}`.
3. `npm run dev` → dark shell renders at `:3000`, hits `/api/health` through the proxy.
4. `uv run pytest` → ≥15 tests pass, **zero network calls** (verify by running with the network disabled).
5. `uv run python -c "from imt.entities import normalize_name; print(normalize_name('THE ACME HOLDINGS CORP.'))"` → `ACME`.
6. Rate limiter test: 20 queued requests to a mocked host complete in ≥2.4s at 8 req/s.
7. Shell renders against the mockup at 1536px width; sidebar groups, ordering, and labels match `docs/design/dashboard-mockup.png`.
8. Token lint fails the build on an added raw hex value in `frontend/src` (prove it by adding one, then removing it).
9. `<Panel>` storybook-equivalent page renders all four states.
10. Copy grep test runs and passes as part of `npm test`.

---

## Phase 2 — SEC engine

Reads: SPEC §2, §4, §7, §8 (insider, catalyst, activist), DATA_SOURCES Tier 1, UI_SPEC §4.3/§4.6, API_CONTRACT (`/feed`, `/dashboard/kpis`).

Universe build + monthly snapshots · daily CIK↔ticker snapshot · EDGAR daily-index
discovery · Form 4 ingest + XML parser (all transaction codes) · 8-K ingest + item
classification · 13D/13G ingest + Item 4 keyword classification · raw payload retention.

**UI slice:** Live Activity Feed (UI_SPEC §4.6) with tabs, and KPI cards 2 and 4. Every feed
row shows detection time, transaction date, filed date, and lag.

**Acceptance:**
1. `uv run imt universe build` → ≥3,500 securities, each with a CIK.
2. `uv run imt ingest form4 --since 7d` → ≥2,000 transactions; `SELECT count(*) FROM insider_transactions WHERE transaction_code='P'` > 0.
3. Every row in `insider_transactions` has non-null `source_id`, `retrieved_at`, `effective_date`, `source_document_url`. Enforced by a test that asserts zero violating rows.
4. Re-running the same ingest twice adds **zero** duplicate rows (idempotency test).
5. `uv run imt ingest eightk --since 7d` → ≥200 filings, ≥80% with at least one classified item.
6. `GET /api/filings?form=4&days=7` returns ≥50 rows with both `transaction_date` and `acceptance_datetime` populated and distinct.
7. UI feed renders those rows with both dates visible without scrolling horizontally.
8. Parser unit tests cover a Form 4 with multiple transactions, a footnoted 10b5-1, and an amendment.
9. Feed matches the mockup's row layout, and a component test asserts a row cannot render without both dates.

---

## Phase 3 — Scoring core

Reads: SPEC §6, §7, §10; UI_SPEC §4.4/§4.5/§4.11; API_CONTRACT (`/signals/top`, `/convergence`).

`signal_features` table · percentile + fallback-threshold normalization · category scores
with diminishing-returns combination · insider cluster detection · per-source freshness ·
contradiction checks · convergence · Research Priority · Confidence · DataQuality ·
`weights_version` stamping.

**UI slice:** Today's Top Signals table including the Contradiction column (UI_SPEC
correction #8) · Signal Convergence radar with the category-count ring (correction #7) ·
Recent Events Timeline · KPI card 1 · `<Score>` wired to real provenance.

**Acceptance:**
1. `uv run imt score run --date 2026-06-01` twice → byte-identical output (`Compare-Object` on the exported CSV returns nothing).
2. Test: a synthetic company with five signals **all from Form 4**, each sub-signal at
   strength 100, scores Convergence < 45. The same company with one signal each at
   strength 100 from five distinct categories scores > 80. Sub-signal strengths are pinned
   in the test, because the threshold depends on them. This is the core correctness test of
   the whole system.
3. Test: no module under `src/imt/scoring/` references `datetime.now`, `date.today`, or `time.time` (AST-level test).
4. Test: cluster detector fires on 3 independent `P` filers within 7 days including a CEO; does not fire on one filer with 3 amendments.
5. Every row in `scores` has a non-null `weights_version` and `normalization` method.
6. **With Convergence and DataQuality both pinned at 100**, a Contradiction of 100 reduces
   Research Priority to exactly 40% of base. The test injects Contradiction directly:
   `100·(1−Π(1−c/100))` only reaches 100 if some single check returns exactly 100, so it
   cannot be produced from check inputs.
7. Visual test: a one-category 90 and a five-category 90 render with visibly different count rings — screenshot both and confirm.
8. Every score on screen exposes normalization method and `weights_version` on hover.
9. Contradiction column renders even when the value is 0.
10. Weights loader rejects a `weights.yaml` whose category weights sum to ≈1.0 (the
    normalization trap in SPEC §6.4) and rejects any single category weight > 1.05.

---

## Phase 4 — Congressional

Reads: SPEC §5, §6.5, §8; DATA_SOURCES Tier 3. **Budget generously.**

> **Status: manual-CSV path built; PDF/OCR pipeline not built.**
> The CSV import, bracket parsing, disclosure-lag computation, entity
> resolution with the 0.85 gate and review queue, the summary endpoint with a
> computed average lag, and the donut panel are all done and tested
> (criteria 3, 4, 5, 6, 7, 8). The House ZIP → PDF → OCR pipeline needs
> Tesseract and network access and remains outstanding, so **criteria 1 and 2
> are not met**.

House index + PDF ingest · text extraction with OCR fallback · low-confidence review queue
· Senate manual-CSV import · PTR normalization · disclosure-lag computation · entity
resolution to CIK · politician profiles.

**UI slice:** Congressional Trading donut (UI_SPEC §4.7) with the computed average-lag
caption · KPI card 3 with its disclosure-vs-transaction tooltip.

**Acceptance:**
1. `uv run imt ingest congress-house --year 2026` → ≥500 transactions parsed.
2. Parse-outcome report prints counts for: text-extracted, OCR'd, review-queued, failed. Review-queued + failed < 30% of documents.
3. Every congressional transaction has both `transaction_date` and `disclosure_date`, and `disclosure_lag_days = disclosure_date - transaction_date` ≥ 0 for 100% of rows.
4. Entity resolution report: % resolved at confidence ≥0.85, and unresolved rows are in the review queue rather than dropped or force-matched.
5. `uv run imt ingest congress --from-csv tests/fixtures/manual_ptr.csv` works independently of the PDF pipeline.
6. Test: a PTR with a 45-day lag scores lower freshness than a Form 4 filed 2 days after its transaction, at equal dollar value.
7. UI never displays a PTR without its transaction date adjacent to its disclosure date.
8. No column stores a single congressional "amount" — only `value_low` / `value_high`. A
   schema test asserts this; midpoints appear only as derived features.

---

## Phase 5 — Fundamentals

Reads: SPEC §4, §7, §8.

XBRL Company Facts ingest with `filed_date` per fact and append-only restatement handling ·
all fundamental metrics · Piotroski / Altman / Beneish · valuation and owner-earnings
metrics · Business Quality / Valuation / Capital Allocation scores.

**UI slice:** Company deep-dive page, all sections from SPEC §11 / UI_SPEC.

**Acceptance:**
1. ≥3,000 companies with ≥4 quarters of revenue and net income.
2. Every metric row records which XBRL tags it resolved; unresolvable metrics are `NULL` with a reason code, never 0 and never estimated.
3. Point-in-time test: query fundamentals as-of a date before a known restatement returns the **original** figure.
4. Spot-check 3 large-cap companies' ROIC and FCF against their 10-K by hand; document the comparison in `docs/validation/`.
5. Deep-dive page renders all fundamental sections with source filing links.

---

## Phase 6 — Government

Reads: SPEC §5, §8; DATA_SOURCES Tier 1/2.

USAspending ingest · SAM.gov opportunities · UEI/name → CIK resolution with confidence ·
contract momentum (30d/90d/12m/YoY) · opportunity → award → 8-K timeline.

**UI slice:** Government Contracts panel with the permanent coverage caveat (UI_SPEC
correction #10).

**Acceptance:**
1. ≥50,000 award records ingested for the backfill window.
2. Resolution report published: total recipients, % resolved ≥0.85, % unresolved. **Number is stated honestly, not optimized by lowering the threshold.**
3. Only ≥0.85 matches feed contract-momentum features (test asserts this).
4. UI displays the government-contract coverage caveat (SPEC §5.5) on every contract panel.
5. At least one end-to-end timeline renders for a known defence contractor.

---

## Phase 7 — Macro and positioning

Reads: SPEC §8; DATA_SOURCES Tier 1/2.

FRED series · CFTC COT with percentiles · FINRA short interest and short volume as
**separate** tables · OCC options summary · macro regime classifier.

**UI slice:** Short Interest & Price dual-axis panel · Macro Regime Overview · Sector Heat
Map · KPI card 5.

**Acceptance:**
1. ≥20 FRED series with ≥10 years of history.
2. COT percentiles computed over ≥5 years for ≥10 markets.
3. Schema test: `short_interest` and `short_volume` are distinct tables; no view or query joins them into a single "short" figure.
4. Short interest is labelled "% of shares outstanding" everywhere in the UI — grep test over frontend source finds zero instances of "% of float".
5. Macro regime classifier outputs one of the five labels with the contributing factors listed.

---

## Phase 8 — Backtesting

Reads: SPEC §6.8, §7. **This is the phase that determines whether any of the above is real.**

> **Status: engine built; baseline report not produced.**
> The entry clock, forward returns, universe reconstruction, terminal outcome
> handling, the look-ahead assertion, confidence intervals, and walk-forward
> chronology are built and tested (criteria 1, 2, 3, 4, 6). **Criterion 5 — the
> baseline report on real insider clusters — is not met**: it needs live price
> history, which the development environment cannot reach. Run it on the target
> machine once Stooq ingest has populated `prices_daily`.

Point-in-time event study engine · universe reconstruction from snapshots · forward
returns at 1/5/20/60/120/250 days · absolute, benchmark-adjusted, sector-adjusted · hit
rate, median, mean, MAE, MFE, drawdown, volatility · delisting outcome handling · walk-
forward framework with train/validation/out-of-sample splits · actor historical scores.

**Acceptance:**
1. Look-ahead test: for every backtest entry, `entry_timestamp >= public_availability_timestamp`. Zero violations, asserted over the full result set.
2. Congressional backtest entries use disclosure date; a test proves that using transaction date produces different (and inadmissible) results.
3. Universe reconstruction test: a company delisted in 2025 appears in the 2024 universe and not the 2026 one.
4. Delisted names appear in results with terminal outcome codes; survivorship-bias check documented.
5. Baseline report produced for insider cluster buying: n, hit rate, median excess return at each horizon, **with confidence intervals** — the 24-month backfill gives roughly 12 months of signals at the 250-day horizon, so point estimates alone would overstate what is known. **Publish it even if the result is null or negative.**
6. Walk-forward split respects chronology — no validation date precedes any training date.

---

## Phase 9 — AI analyst

Reads: SPEC §9.

LM Studio client · section extraction for 10-K/10-Q · hierarchical summarization ·
QoQ management-language comparison · convergence explanation · bull/bear generation ·
citation enforcement.

**UI slice:** AI Analyst Summary panel with fact/interpretation separation and per-line
source chips (UI_SPEC correction #9).

**Acceptance:**
1. Test: no module under `src/imt/llm/` writes to any numeric column.
2. Every stored LLM output records model, prompt version, temperature, and input fact-set hash.
3. Citation test: any LLM claim rendered as "fact" resolves to a source passage or database row; uncited claims render as "interpretation".
4. Section extractor is tested against 10 varied 10-Ks; extraction success rate documented, not assumed.
5. Adversarial test: given a fact set with a missing revenue figure, the model does not invent one — it reports the gap.

---

## Phase 10 — UI refinement

Reads: SPEC §11.

Remaining panels (Watchlist Summary, Data Quality Score) · person profiles · command
palette · watchlists · alert rules · screeners · responsive breakpoints (UI_SPEC §3) ·
accessibility pass (UI_SPEC §6) · side-by-side comparison against the mockup.

**Acceptance:**
1. Every panel displaying scored data shows its data-quality state.
2. Every score displayed shows its normalization method and `weights_version`.
3. Grep test: zero occurrences of "BUY", "SELL", "recommendation", or "signal to buy" in frontend copy.
4. Global search returns results across all six entity types.
5. Alert rules from SPEC §11 evaluate correctly against a seeded fixture dataset.
6. Cold-start dashboard load < 2s against a fully populated database.
7. Side-by-side screenshot against `docs/design/dashboard-mockup.png` at 1536px: layout, density, and palette match, and all twelve UI_SPEC §2 corrections are visibly applied.
8. Keyboard-only traversal of the full dashboard succeeds with a visible focus ring throughout.
9. No panel anywhere is missing its stale or failed state — audited panel by panel.

---

## Standing rule

If a phase's acceptance criteria cannot be met on free data, **stop and say so**. Mark the
capability `Premium-Dependent`, build the interface, disable the feature, and move on. Do
not approximate a blocked feature and present the approximation as the real thing.
