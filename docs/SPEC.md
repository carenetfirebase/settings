# Informed Money Terminal — Specification

Conventions and commands live in `CLAUDE.md`. Data sources live in `docs/DATA_SOURCES.md`.
Build order and acceptance criteria live in `docs/PHASES.md`. This file is requirements.

---

## 1. The question the system answers

> Out of thousands of publicly traded companies, where are informed money, corporate
> developments, fundamentals, government activity, positioning, and market conditions
> unusually converging — and what evidence might prove the thesis wrong?

Output: a short, ranked, explainable list of companies worth a human's research time.
Not a buy list. Every ranking is decomposable into the evidence that produced it.

Success metric: reduce ~4,000 securities and thousands of daily public events to ≤25
research candidates, each of which the system can justify and argue against.

---

## 2. Universe

Defined in `config/universe.yaml`. V1 default:

- US-listed **common equity** on NYSE, Nasdaq, NYSE American.
- Must map to an SEC CIK with filings in the last 24 months.
- **Excluded:** OTC/pink sheets, closed-end funds, ETFs, ADRs (V2), pre-merger SPACs,
  units, warrants, preferred shares.
- Expected size: ~4,000 securities.

**Survivorship.** The universe table is append-only with `first_seen`, `last_seen`,
`delisted_date`, `status`. A ticker leaving the exchange is marked delisted, never
deleted. Backtests over a historical window use the universe **as it was on that date**,
reconstructed from `universe_snapshots` (one row per security per month). Tickers are
reused by different companies over time — **CIK is the identity key, ticker is an
attribute with a validity range.** Never join on ticker across time.

**Backfill bounds.** Initial backfill is **24 months**. Enough for Form 4 cluster
detection, 8 quarters of fundamentals, and 250-day forward windows on the first 12 months
of signals. Full EDGAR history is hundreds of GB and is out of scope. Backfill depth is a
config value, not a hardcoded constant.

---

## 3. Data philosophy

Source preference: government/regulatory API → government structured download → exchange
or SRO dataset → official company filing → explicitly permitted free API → secondary site
for **manual** verification only.

- Scraping a third-party site is never a critical dependency unless its terms explicitly
  permit automated access.
- Never fabricate a missing value. Missing is `NULL` plus a reason code.
- Every stored external fact carries `source_id`, `retrieved_at`, `effective_date`,
  `source_document_url`, `source_record_id`, `data_quality`.
- Free-but-requires-registration is acceptable and must be declared per source in
  `config/sources.yaml`.

---

## 4. Reference data — resolved

These were unspecified in the original brief and block downstream work. Decisions:

| Need | V1 decision | Consequence to declare in UI |
|---|---|---|
| **EOD prices** (all backtests, event studies, price behaviour) | Stooq bulk daily CSV, split/dividend-adjusted, per `docs/DATA_SOURCES.md`. `yfinance` implemented as a second adapter behind the same Protocol, disabled by default. | Adjusted-only series. Vintage-adjusted, so a split restates history. Acceptable for return-based event studies; **not** acceptable for anything needing raw historical price levels. |
| **Benchmarks** | S&P 500 via `^SPX` on Stooq; sector benchmarks via SPDR sector ETFs (XLE, XLF, XLK, XLV, XLI, XLY, XLP, XLU, XLB, XLRE, XLC). | Sector-adjusted returns are ETF-relative, not index-relative. |
| **Shares outstanding** | SEC XBRL `dei:EntityCommonStockSharesOutstanding`, point-in-time by filing date. | Authoritative and free. Quarterly granularity. |
| **Public float** | **Not available free.** `Premium-Dependent`. | Short interest is expressed as **% of shares outstanding**, labelled as such. Never call it "% of float". |
| **Sector / industry** | SEC SIC code from EDGAR submissions, mapped to an 11-bucket internal taxonomy in `config/sector_map.yaml`. | GICS is licensed and out of scope. Internal taxonomy is coarse; say so on screen. |
| **Corporate actions** | Implicit in Stooq's adjusted series. No separate splits/dividends table in V1. | Cannot compute unadjusted levels or precise dividend yield. `Premium-Dependent`. |
| **CIK ↔ ticker map** | SEC `company_tickers.json`, snapshotted daily, history retained. | Enables point-in-time ticker resolution. |

---

## 5. Entity resolution — the crux

Cross-source convergence is only as good as the joins. This gets a dedicated module
(`src/imt/entities/`) and is a Phase 1 deliverable, not an afterthought.

**Canonical identity is the SEC CIK.** Everything resolves to a CIK or is quarantined.

Per-source resolution:

| Source | Given | Method | Realistic accuracy |
|---|---|---|---|
| SEC filings | CIK | Direct. | 100% |
| Congressional PTR | Free-text asset description, sometimes a ticker | Ticker extraction regex → validate against point-in-time ticker map. If no ticker: normalized-name fuzzy match (RapidFuzz token-set) against issuer names. | ~85% with ticker, ~60% without |
| USAspending | UEI, legacy DUNS, recipient name, parent name | UEI→name→normalized-name match against SEC company names + former names from EDGAR. | ~50–70%. Most federal recipients are private or subsidiaries. |
| SAM.gov | Same as USAspending | Same | Same |
| FINRA short interest | Ticker + exchange | Point-in-time ticker map | ~98% |
| openFDA | Applicant/sponsor name | Normalized-name match | ~50%, heavy subsidiary problem |

**Requirements:**

1. `entity_matches` table: `source`, `source_key`, `resolved_cik`, `method`,
   `confidence` (0–1), `resolved_at`, `reviewed` bool.
2. **Confidence threshold.** Matches below `0.85` do not feed scoring. They go to a
   review queue surfaced in the UI. This is a hard gate — a wrong join silently
   manufactures fake convergence, which is the single worst failure mode of this system.
3. **Manual override** file `config/overrides/entity_map.csv`, always wins, committed.
4. **Name normalization** is a single shared function: uppercase, strip punctuation, strip
   corporate suffixes (INC, CORP, CO, LLC, LP, PLC, HOLDINGS, GROUP, THE), collapse
   whitespace. Used identically by every source.
   **Suffix stripping is positional**: `THE` is stripped only as a leading token; every
   other suffix is stripped only as a trailing token, repeatedly. Unanchored stripping
   turns `GROUP 1 AUTOMOTIVE` into `1 AUTOMOTIVE`, which is a defect.
5. **Subsidiary problem is unsolved and must be visible.** A contract awarded to a
   subsidiary will usually not resolve to the listed parent. The UI states government
   contract coverage is incomplete. Do not present contract momentum as comprehensive.

---

## 6. Scoring — resolved

The original brief specified "0–100" everywhere without defining what that means. Left
open, this produces arbitrary magic constants. Resolved as follows.

### 6.1 Layers

Keep three layers separate in code and in the database:

1. **Features** — raw computed quantities with units (dollars, %, days, counts). Table
   `signal_features`. Never displayed as a score.
2. **Category scores** — features normalized to 0–100 and combined per evidence category.
3. **Composites** — Convergence, Contradiction, Freshness, Research Priority, Confidence.

### 6.2 Normalization to 0–100

Default method: **percentile rank of the feature against its own trailing 36-month
cross-sectional distribution**, ×100.

- Requires ≥500 historical observations of that feature. If unavailable (early in the
  project's life, which is most of V1), fall back to **piecewise-linear thresholds**
  defined per feature in `config/weights.yaml`, and stamp the row
  `normalization = 'fallback_threshold'`.
- The UI must show which method produced a score. A threshold-normalized score is a
  hypothesis; a percentile score is an observation.

### 6.3 Evidence categories (independence buckets)

Convergence means agreement across **independent** categories. These are the buckets:

| # | Category | Sources |
|---|---|---|
| 1 | Corporate insider | Form 4, Form 144 |
| 2 | Political | House PTR, Senate eFD |
| 3 | Institutional / activist | 13D, 13G, 13F |
| 4 | Government business | USAspending, SAM.gov |
| 5 | Corporate event | 8-K |
| 6 | Fundamental quality | XBRL |
| 7 | Valuation | XBRL + price |
| 8 | Positioning | Short interest, short volume, OCC options |
| 9 | Macro / sector | FRED, CFTC, EIA |
| 10 | Credit | TRACE — **V2, see DATA_SOURCES** |

Within a category, sub-signals combine with **diminishing returns**, counting only
independent actors:

```
C_i = 100 * (1 - Π_j (1 - s_ij/100))     # s_ij = each independent sub-signal, 0-100
```

So three separate insiders buying compounds; the same insider filing three amended forms
does not. Deduplicate by actor identity before combining.

### 6.4 Convergence

```
raw   = Σ_i  w_i * (C_i / 100) * 1[C_i ≥ τ]        # τ default 60
Convergence = 100 * (1 - exp(-λ * raw))            # λ default 0.55
```

`w_i`, `τ`, `λ` in `config/weights.yaml`. λ is calibrated so three strong independent
categories ≈ 75 and five ≈ 92.

> **The convergence weights are deliberately NOT normalized to sum to 1.**
> With λ = 0.55, the stated calibration requires `w_i ≈ 0.88` per category, summing to
> ≈ 8.8 across ten categories. If someone "tidies" them to sum to 1 (w = 0.1 each), three
> strong categories score **15** and five score **24**, and the scoring system silently
> stops working. `config/weights.yaml` carries this warning inline and
> `imt.scoring.weights` validates it at load.
>
> **Upper bound on any single weight.** Phase 3's core correctness test requires that five
> signals from one category score Convergence < 45. That bound is breached at
> `w_i ≥ 1.087`. No single category weight may exceed **1.05**. The loader enforces it.

**One category can never produce high convergence**, which is the entire point.

### 6.5 Freshness

Per-source decay, never a single shared function. `config/weights.yaml` holds a half-life
per event type:

| Event | Half-life (days) | Rationale |
|---|---|---|
| Form 4 open-market purchase | 21 | Filed within 2 business days; genuinely fresh |
| Form 144 | 14 | |
| 8-K | 10 | Event-driven |
| 13D | 30 | Filed within 10 days, positions persist |
| 13G | 90 | Passive |
| Congressional PTR | 10 | **Aggressive.** Transaction may be 45 days old at disclosure |
| 13F | 120 | Up to 45 days stale on arrival; never treat as a fresh signal |
| Short interest | 21 | Bi-monthly settlement, ~8-day publication lag |
| Government contract | 60 | |
| Macro | 30 | |

```
freshness_ij = 0.5 ^ (age_days / half_life)
```

For congressional trades, `age_days` is measured from the **transaction date**, not the
disclosure date. Disclosure lag is a penalty, not a reset.

### 6.6 Contradiction

Mandatory. Every thesis searches for its own disconfirmation. Checks include: CFO or CEO
selling, CEO/CFO departure, share dilution, rising debt or falling interest coverage,
rising short interest, deteriorating gross margin, inventory growth outpacing revenue,
negative FCF trend, declining government awards, adverse regulatory filing, stock already
up >50% in 90 days, stale congressional disclosure, insider purchase immaterial relative
to existing holdings or compensation.

```
Contradiction = 100 * (1 - Π_k (1 - c_k/100))
```

Contradiction **reduces** Research Priority multiplicatively — it never simply subtracts,
and it is never netted against bullish evidence into a single number. It is displayed
separately, always.

### 6.7 Composites

```
InformedMoney = weighted(C_1 insider, C_2 political, C_3 institutional)
Catalyst      = weighted(C_4 government, C_5 corporate event)
Fundamental   = weighted(C_6 quality, C_7 valuation)
Context       = weighted(C_8 positioning, C_9 macro/sector)

base = w_im*InformedMoney + w_cat*Catalyst + w_fun*Fundamental + w_ctx*Context

ResearchPriority = base
                 * (0.5 + 0.5 * Convergence/100)
                 * (1 - 0.6 * Contradiction/100)
                 * DataQuality/100
```

```
Confidence = 100 * (DataQuality/100)
                 * (CategoryCoverage)          # share of categories with usable data
                 * (1 - 0.5*Contradiction/100)
                 * (percentile_normalized ? 1.0 : 0.7)
```

> **Confidence is capped at 70 for the whole of V1**, because every score is
> threshold-normalized until Phase 8 supplies 500+ observations per feature and the
> ×0.7 penalty applies universally. Any mockup, example payload, or fixture showing a V1
> confidence above 70 is wrong. A test asserts the cap.

Risk is reported separately (volatility, drawdown, leverage, contradiction), never folded
into priority.

### 6.8 Weights are hypotheses

Every number above is a starting hypothesis, **not** a proven parameter. All live in
`config/weights.yaml` with a semantic `weights_version`. Every row in `scores` stores the
`weights_version` that produced it. The UI labels V1 scores "unvalidated — weights not yet
backtested" until Phase 8 produces evidence. Weight changes are commits.

---

## 7. Point-in-time and look-ahead — hard rules

The most likely way this system lies to you.

1. **Entry timestamp is the public-availability timestamp**, always:
   - SEC filings → EDGAR `acceptance_datetime`. If accepted after 16:00 ET, the first
     tradable moment is the next session's open.
   - Congressional PTRs → the date the PDF appeared in the House/Senate index, which the
     ingestion job records at fetch time. **Not** the filing date printed on the document,
     and emphatically not the transaction date.
   - Short interest → FINRA publication date, not settlement date.
   - Macro → release timestamp, not reference period.
2. **Fundamentals are as-filed.** Store every XBRL fact with its `filed_date` and `frame`.
   Restatements create new rows; they never update old ones. A backtest asks "what was
   known on date D", which is a query over `filed_date <= D`.
3. **Universe is reconstructed** from `universe_snapshots` for the backtest date.
4. **Ticker resolution is point-in-time** via the dated CIK↔ticker map.
5. **No scoring function may call `datetime.now()`.** As-of date is an argument. This is
   enforced by a lint rule and a test.
6. **Delisted and acquired names are included** in backtests, with terminal returns handled
   explicitly (`delisted`, `acquired`, `merged` outcome codes).

---

## 8. Engines

Each engine is a package under `src/imt/features/` producing features, plus a scorer under
`src/imt/scoring/`. Details of what each computes:

**Insider (Form 4).** Distinguish transaction codes: `P` open-market purchase (very high
relevance), `S` open-market sale (context-dependent), `A` grant/award (low), `M` option
exercise (contextual), `G` gift (low), `F` tax withholding (low). Features: role weight
(CEO/CFO > officer > director > 10% holder), dollar value, % change in holdings,
transaction freshness, cluster size, count of independent insiders, 10b5-1 flag where
disclosed. **Cluster detection:** ≥3 independent insiders with code `P` within a rolling
7-day window, with CEO or CFO participation scoring materially higher than any isolated
transaction.

**Political.** Features: dollar range midpoint, transaction freshness, disclosure lag,
chamber, leadership position, committee-to-industry overlap, repeated same-sector
transactions, filer historical signal quality, self vs spouse vs dependent, multi-lawmaker
clustering. Committee overlap is a **research-context signal only** — the UI must never
imply misconduct, and copy should be reviewed with that in mind.

> **Bracket midpoints are derived, never stored as facts.** Congressional disclosures
> report amount brackets ($1,001–$15,000, and so on). The database stores
> `value_low` and `value_high`; the midpoint is computed at feature time and carries the
> reason code `derived_bracket_midpoint`. No column anywhere holds a single "amount" for a
> congressional trade. This preserves the honest objection that a bracket midpoint is an
> estimate while still allowing it as a feature input.

**Actor histories (politicians and insiders).** Forward returns at +5/+20/+60/+120/+250
trading days from **public disclosure**: raw, S&P-excess, sector-excess, win rate, median,
max drawdown, mean disclosure lag, sector specialization. Produces `HistoricalSignalQuality
0–100`. Requires ≥20 disclosed trades to report; below that, show "insufficient history"
rather than a noisy number. Actors are not treated as equivalent.

**Activist / ownership.** 13D vs 13G is a hard distinction — 13D is active intent, 13G is
passive, and conflating them is a correctness bug. 13D Item 4 parsed by deterministic
keyword matching first (strategic alternatives, board representation, capital allocation,
management change, merger, sale, restructuring, repurchase), with optional local-LLM
classification layered on top and labelled as interpretation. 13F is included for
ownership context with a 120-day half-life; it is never a fresh signal.

**Corporate catalyst (8-K).** Classify by item number, then by content: acquisition,
merger, material agreement, contract, financing, debt, bankruptcy, executive departure,
director appointment, earnings, guidance, restructuring, cybersecurity incident (Item
1.05), share issuance, asset disposition. Link each 8-K backwards in time to preceding
insider, political, institutional, and government-contract activity for the same CIK — the
timeline is the product.

**Fundamentals (XBRL).** Deterministic code only: revenue growth, EPS growth, FCF, FCF
margin, gross/operating margin, ROIC, ROE, ROA, debt/equity, debt/EBITDA, interest
coverage, FCF conversion, working-capital trend, share dilution, SBC/revenue, accrual
quality, Piotroski F, Altman Z, Beneish M. XBRL tag coverage is inconsistent across
filers; every metric records which tags it resolved and marks itself unavailable rather
than guessing.

**Value / owner earnings.** Owner earnings, FCF yield, earnings yield, EV/EBIT, EV/EBITDA,
P/FCF, normalized margins, ROIC, reinvestment rate, incremental ROIC, net debt, share-count
change, buybacks, dividends, acquisitions. Produces Business Quality, Valuation, and
Capital Allocation scores separately. **Cheap is not good** — the target is quality
business + sensible valuation + rational capital allocation.

**Government.** Award momentum over trailing 30d / 90d / 12m and YoY. Opportunity → award
→ 8-K announcement → revenue-line timeline. Coverage caveat from §5 displayed alongside.

**Positioning.** Short interest, short % of shares outstanding (**not** float), days to
cover, change, historical percentile. Short-sale **volume** and short **interest** are
different quantities and must never be conflated in code, schema, or UI copy. OCC options
data is labelled "EOD public options positioning" — not institutional flow. Real-time
Greeks, IV surface, and dealer gamma are `Premium-Dependent`, interfaces only.

**Macro regime.** FRED + CFTC. Fed funds, 2y, 10y, curve, CPI, PCE, unemployment, GDP,
credit spreads, financial conditions, oil, volatility proxies, liquidity. CFTC COT: net
positioning, 1/4/12-week change, historical percentile, extremes. Output label: Strong
Risk-On / Moderate Risk-On / Neutral / Moderate Risk-Off / Strong Risk-Off. Thresholds
configurable and backtestable.

**Sector modules.** Pluggable, registered by internal sector code. V1 ships Energy
(EIA + COT), Defence (USAspending + SAM), Biotech (openFDA). Others fall back to the
generic model. Architecture must accept new modules without touching the scoring core.

---

## 9. Local LLM — scope and limits

Endpoint: OpenAI-compatible, `http://localhost:1234/v1`. Assume 8k usable context.

**Permitted:** summarize a filing section; compare MD&A language quarter over quarter;
explain why a company ranked highly, given structured facts; draft bull case; draft bear
case; list unanswered questions; summarize risks; classify 13D Item 4 intent.

**Forbidden:** computing any number; filling a missing value; replacing a database query;
producing a buy/sell view; asserting anything not present in its supplied context.

**Required engineering:**
- The LLM receives **structured facts assembled by the application**, never raw dumps.
- 10-K/10-Q are far larger than context. Extract target sections first (Item 1A Risk
  Factors, Item 7 MD&A) by deterministic HTML heading parsing, chunk, then summarize
  hierarchically. Section extraction is its own tested component with a known failure rate.
- Every LLM output is stored with model name, prompt version, temperature, and input
  fact-set hash.
- Output must separate **fact** (with a citation back to the source passage or database
  row) from **interpretation**. Any claim without a citation renders in the UI as
  interpretation.
- Temperature 0 for classification tasks.

---

## 10. Data quality system

Every panel knows the state of its feed: `current`, `delayed`, `stale`, `unavailable`,
`estimated`, `manually_imported`. Per-source staleness thresholds in `config/sources.yaml`.

`DataQualityScore 0–100` is computed per company as coverage-weighted feed health, and it
**multiplies Research Priority** (§6.7). A confident score is never displayed on top of
stale critical feeds — a company with no fundamentals in 9 months cannot rank highly, by
construction.

---

## 11. Interface

The visual design is specified component by component in **`docs/UI_SPEC.md`**. The
panel-to-endpoint-to-table chain is in **`docs/API_CONTRACT.md`**. Read those; do not
design from this section.

Only the non-negotiables live here, because they are product rules rather than design ones:

1. Nothing in this system is live. The UI never implies real-time data.
2. Every event shows its transaction date, its disclosure date, and the lag between them.
3. Contradiction is displayed separately, always, never netted into a score.
4. Convergence must visually distinguish one loud category from five agreeing ones.
5. Every score exposes its normalization method and `weights_version`.
6. Every figure derived from a filing is one click from that filing.
7. Short interest is expressed as a percentage of shares outstanding, never of float.
8. No buy/sell language anywhere. The only company actions are Deep Dive, Investigate, Watch.
9. Stale data is shown as stale, not hidden and not silently rendered as current.
10. AI output separates cited fact from uncited interpretation.

`docs/UI_SPEC.md` §2 lists the twelve places where the mockup as drawn violates these rules,
and what to build instead.

## 12. Performance funnel

Do not score the full universe from scratch daily. Event-driven funnel:

```
~4,000 securities
  → filter to names with a new qualifying public event in the window   (~300–600)
  → full scoring                                                        (~500)
  → monitored set                                                       (~100)
  → research candidates                                                 (~25)
  → deep analysis + LLM                                                 (top 10)
```

LLM calls are the expensive step (wall-clock, locally) and run only on the final tier.
Full-universe rescoring is a separate weekly job.

---

## 13. Security

Public data, but engineer properly: secrets in `.env` only, nothing committed, input
validation on every API boundary, pinned dependencies (`uv.lock` committed), safe path
handling, no secrets in logs, API bound to `127.0.0.1` only, least privilege on the
database role.

---

## 14. Legal

V1 is **personal research use**. `config/sources.yaml` stores per source: terms URL,
attribution requirement, automated-access rules, redistribution rules, rate limit. Do not
design on the assumption that any third-party data may be redistributed or commercialized.
Where a source's terms are ambiguous about automated access, treat it as manual-only and
say so in the UI.

---

## 15. What this system is not

Not a signal service. Not a trading bot. Not a source of buy/sell recommendations. Not a
claim that insiders, politicians, or activists are right. Not evidence of misconduct by
anyone. It is a filter that ranks where public evidence unusually converges, tells you how
stale that evidence is, and argues against itself.
