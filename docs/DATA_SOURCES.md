# Data sources

This file is the authoritative source list. Mirror it into `config/sources.yaml` — that
file is what the code reads; this one is what a human reads.

**Verify every endpoint, quota, and auth requirement before building against it.** These
change. If reality differs from this table, correct this file in the same commit that
handles the difference.

Legend — **Auth:** `none` / `free-key` (registration, no payment) / `session` (cookie or
agreement acceptance). **Automation:** `full` / `semi` (needs periodic human step) /
`manual`.

---

## Tier 1 — Core, V1, fully automated

| Source | Provides | Endpoint | Auth | Rate limit | Cadence | Format | Notes |
|---|---|---|---|---|---|---|---|
| SEC EDGAR submissions | Filing index per CIK | `data.sec.gov/submissions/CIK{10-digit}.json` | none | **10 req/s hard**, UA required | intraday | JSON | Blocked IP if exceeded. UA: `Informed Money Terminal <email>`. |
| SEC EDGAR full-text/daily index | New filings by day | `www.sec.gov/Archives/edgar/daily-index/` | none | as above | daily | idx/JSON | Primary discovery loop. |
| SEC Form 4/144 | Insider transactions | EDGAR document XML | none | as above | daily | XML | Form 4 XML is well-structured. ~350k/yr. |
| SEC 8-K / 10-Q / 10-K | Events, financials | EDGAR documents | none | as above | daily | HTML/XBRL | HTML parsing for sections is messy; see SPEC §9. |
| SEC 13D / 13G / 13F | Ownership | EDGAR documents | none | as above | as filed | XML/HTML | 13F is quarterly, up to 45d stale. |
| SEC Company Facts (XBRL) | Fundamentals | `data.sec.gov/api/xbrl/companyfacts/CIK{...}.json` | none | as above | as filed | JSON | Tag coverage varies by filer. Store `filed_date` per fact. |
| SEC company_tickers | CIK↔ticker map | `www.sec.gov/files/company_tickers.json` | none | as above | daily | JSON | **Snapshot daily, retain history** (SPEC §2). |
| FRED | Macro series | `api.stlouisfed.org/fred/` | **free-key** | 120 req/min | daily | JSON | Key is free, instant, no payment method. |
| CFTC COT | Futures positioning | `publicreporting.cftc.gov` (Socrata) | none (higher limits with free token) | throttled anon | weekly Fri | JSON/CSV | Legacy + disaggregated reports. |
| USAspending | Federal awards | `api.usaspending.gov/api/v2/` | none | courteous use | daily | JSON | No ticker. Entity resolution required (SPEC §5). |
| Stooq | **EOD prices, benchmarks** | `stooq.com/q/d/l/?s={sym}&i=d` | none | courteous, throttle hard | daily | CSV | Split/dividend adjusted. Primary price source. Cache aggressively; do not hammer. |
| EIA | Energy data | `api.eia.gov/v2/` | **free-key** | generous | daily/weekly | JSON | Free registration. |
| openFDA | Approvals, recalls, 510(k), PMA | `api.fda.gov/` | none (key raises limit) | 240/min, 1000/day anon | daily | JSON | Free key raises to 240/min, 120k/day. Sponsor-name resolution is weak. |

---

## Tier 2 — V1, requires registration or partial automation

| Source | Provides | Auth | Automation | Notes |
|---|---|---|---|---|
| **SAM.gov** | Contract opportunities | **free-key** (account + API key request, can take days) | full once keyed | Opportunities API. Key request is a manual one-time step — flag it in setup docs. |
| **FINRA** | Short interest, short-sale volume, OTC/ATS transparency | **free-key** (FINRA API Platform account) | full once keyed | Short interest is bi-monthly with ~8 day publication lag. Daily short-sale volume files are separate and are **not** short interest. |
| **OCC** | Options volume, put/call | none | full | Largely **aggregate and product-level**, not clean per-symbol open interest. Label "EOD public options positioning". Per-symbol OI at scale is `Premium-Dependent`. |

---

## Tier 3 — V1 but hard; scope defensively

### House of Representatives PTRs

- Source: `disclosures-clerk.house.gov` — annual ZIP containing an index (`.txt`/XML) plus
  individual **PDFs**.
- Auth: none. Automation: **semi**.
- **The problem:** a substantial share of PTR PDFs are scanned images, and some are
  handwritten. Text extraction fails on these. OCR (Tesseract) is required and still
  produces errors on handwriting.
- **Required design:**
  1. Ingest the index automatically; download PDFs automatically.
  2. Try text extraction (`pdfplumber`). If character yield is below threshold, route to OCR.
  3. If OCR confidence is low, route to a **review queue**, do not guess.
  4. Provide `imt ingest congress --from-csv <path>` as a manual fallback so a stalled
     parser never blocks the rest of the system.
- Budget this as a full phase. It is the most likely place to lose two weeks.

### Senate eFD

- Source: `efdsearch.senate.gov`.
- Auth: **session** — requires accepting an agreement to obtain a cookie, and has bot
  protection. Automation: **semi at best**.
- Many filings are paper/scanned.
- **V1 decision: Senate is `manual` only.** The House pipeline is automated; Senate
  filings enter through `imt ingest congress --from-csv`. The UI states Senate coverage is
  manual-import and shows the date of the last import. Revisit in V2 only if the terms of
  use are confirmed to permit automated retrieval.

**Legal note for both:** these are public records, but check current terms of use before
automating. If terms prohibit automated retrieval, the manual import path becomes the
only path. That is an acceptable V1 outcome.

---

## Deferred to V2 / Premium-Dependent

| Capability | Why not V1 |
|---|---|
| **TRACE corporate bonds / credit engine** | Free TRACE is delayed and incomplete; bond→issuer mapping requires **CUSIP, which is licensed by CGS**. Real licensing exposure for no proportionate V1 benefit. Build the schema and the Equity/Credit Divergence interface; leave the feed disabled. |
| Public float | Not available free. Short interest reported vs shares outstanding instead. |
| GICS sector classification | Licensed. SIC-based internal taxonomy used instead. |
| Real-time options flow, Greeks, IV surface, dealer gamma | No free source. Interfaces only. |
| Intraday prices | Not needed for V1 horizons. |
| Earnings call transcripts | No reliable free, licence-clean source at scale. |
| Analyst estimates | No free source. |
| N-PORT | Low marginal value vs parsing cost. |
| Unadjusted price history + corporate actions table | No free clean source. |
| ADRs, OTC, non-US listings | Universe scope decision (SPEC §2). |

---

## Explicitly not automated

These may be used for **manual** verification during development. They must not become
code dependencies, and nothing in `src/` may make an HTTP request to them:

OpenInsider · Capitol Trades · TradingView · Finviz · TIKR · Koyfin · StockAnalysis.com ·
Forex Factory · ROIC.ai · Fiscal.ai

A test asserts that no hostname in this list appears in `config/sources.yaml` or anywhere
under `src/`.

If one of these becomes genuinely necessary, raise it as a decision with its terms of
service attached. Do not add it quietly.

---

## Setup checklist (one-time, human)

Before Phase 1 can complete:

- [ ] FRED API key — `fred.stlouisfed.org/docs/api/api_key.html`
- [ ] EIA API key — `eia.gov/opendata/`
- [ ] SAM.gov account + API key request (**start early, can take days**)
- [ ] FINRA API Platform account + credentials
- [ ] openFDA key (optional, raises rate limit)
- [ ] Email address for the SEC User-Agent header
- [ ] All of the above into `.env`, mirrored as blank keys in `.env.example`

None of these require a payment method. If any registration flow asks for one, stop and
flag it — that violates the $0 constraint.
