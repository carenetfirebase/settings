# API contract — panel to endpoint to source

Every pixel on the dashboard traces to a table, and every table traces to a source. If a
panel appears here without a resolved chain, it does not get built — it renders its empty
state until the chain exists.

Base URL `http://127.0.0.1:8000/api/v1`. Bound to loopback only. No auth (single-user local
app). All responses JSON. All timestamps ISO-8601 with explicit offset. All money in
integer minor units with a `currency` field — never floats.

---

## Universal response envelope

Every endpoint that returns scored or sourced data uses this shape. The `meta` block is not
optional decoration — the UI's stale/failed states are driven entirely by it.

```jsonc
{
  "data": [ /* ... */ ],
  "meta": {
    "as_of": "2026-08-21T16:00:00-04:00",
    "generated_at": "2026-08-22T09:42:11-04:00",
    "data_quality": 92,                    // 0-100, SPEC §10
    "sources": [
      { "id": "sec_edgar", "status": "current", "last_success": "2026-08-22T09:40:00-04:00" },
      { "id": "usaspending", "status": "stale", "last_success": "2026-08-18T02:10:00-04:00",
        "reason": "rate_limited_3x" }
    ],
    "weights_version": "0.1.0",            // present on any scored response
    "normalization": "threshold_fallback", // or "percentile"
    "coverage": { "categories_available": 7, "categories_total": 10 }
  }
}
```

Errors:

```jsonc
{ "error": { "code": "SOURCE_UNAVAILABLE", "message": "USAspending ingest failed 3x (rate limit)",
             "retry_at": "2026-08-22T14:00:00-04:00", "affected_panels": ["government_contracts"] } }
```

---

## Dashboard endpoints

| UI element (UI_SPEC §) | Endpoint | Primary tables | Ultimate source |
|---|---|---|---|
| KPI: High Priority Signals (4.3) | `GET /dashboard/kpis` | `scores` | derived |
| KPI: Form 4 Filings 24h | `GET /dashboard/kpis` | `filings`, `insider_transactions` | SEC EDGAR |
| KPI: Congress Trades 24h | `GET /dashboard/kpis` | `congressional_transactions` | House/Senate |
| KPI: 13D/13G Alerts | `GET /dashboard/kpis` | `activist_positions` | SEC EDGAR |
| KPI: Market Regime | `GET /macro/regime` | `macro_observations`, `macro_regime` | FRED, CFTC |
| KPI: Data Sources | `GET /system/sources` | `data_sources`, `ingestion_runs` | internal |
| Today's Top Signals (4.4) | `GET /signals/top?limit=5` | `scores`, `signal_features`, `companies` | derived |
| Signal Convergence radar (4.5) | `GET /companies/{cik}/convergence` | `scores`, `signal_features` | derived |
| Recent Events Timeline (4.5) | `GET /companies/{cik}/timeline?limit=10` | `signal_events` | multi |
| Live Activity Feed (4.6) | `GET /feed?category=&cursor=&limit=50` | `signal_events` | multi |
| Insider Activity Summary (4.7) | `GET /insiders/summary?period=30d` | `insider_transactions` | SEC Form 4 |
| Congressional Trading (4.7) | `GET /congress/summary?period=30d` | `congressional_transactions` | House/Senate |
| Government Contracts (4.7) | `GET /government/summary?period=90d` | `government_contracts`, `entity_matches` | USAspending |
| Short Interest & Price (4.7) | `GET /positioning/short?cik=&range=6m` | `short_interest`, `prices_daily` | FINRA, Stooq |
| Macro Regime Overview (4.7) | `GET /macro/regime` | `macro_observations` | FRED |
| Sector Heat Map (4.8) | `GET /sectors/performance?period=1d` | `prices_daily`, `sector_map` | Stooq |
| AI Analyst Summary (4.8) | `GET /companies/{cik}/analysis` | `llm_outputs` | local LLM over structured facts |
| Watchlist Summary (4.8) | `GET /watchlists/summary` | `watchlists`, `scores` | derived |
| Data Quality Score (4.8) | `GET /system/data-quality` | `data_sources`, `ingestion_runs` | internal |
| Command palette (4.12) | `GET /search?q=&types=` | multi | multi |

**Identity in URLs is always CIK**, zero-padded to 10 digits. Ticker is accepted as a query
convenience (`?ticker=ABC`) and resolved server-side through the point-in-time map, but it
never appears as a path parameter — tickers are reused across companies over time (SPEC §2).

---

## Representative payloads

These pin down field names so the frontend and backend are built against the same contract.
Field names here are normative.

### `GET /signals/top?limit=5`

```jsonc
{
  "data": [{
    "rank": 1,
    "cik": "0000123456",
    "ticker": "ABC",
    "company_name": "Alpha Builders Inc.",
    "research_priority": 94,
    "confidence": 44,                     // V1 is capped at 70 — SPEC §6.7
    "contradiction": 22,                  // always present, even at 0 — correction #8
    "convergence": 88,
    "categories_cleared": 5,              // drives the count ring — correction #7
    "categories_total": 10,
    "top_drivers": [
      { "category": "corporate_insider", "score": 92, "label": "Insider Conviction" },
      { "category": "political",         "score": 78, "label": "Political Activity" }
    ],
    "score_provenance": {                 // correction #6
      "normalization": "threshold_fallback",
      "weights_version": "0.1.0",
      "as_of": "2026-08-21",
      "validated": false
    }
  }],
  "meta": { /* envelope */ }
}
```

> The `confidence` value in this example is computed from the envelope's own numbers:
> `100 × (92/100) × 0.7 coverage × (1 − 0.5×0.22) × 0.7 threshold-penalty ≈ 40`.
> Any example showing V1 confidence above 70 is arithmetically impossible — see SPEC §6.7.

### `GET /feed?limit=50`

```jsonc
{
  "data": [{
    "event_id": "evt_01J...",
    "category": "political",
    "detected_at": "2026-08-22T09:36:00-04:00",   // when WE saw it
    "transaction_date": "2026-07-09",             // when it actually happened
    "disclosure_date": "2026-08-22",              // when it became public
    "disclosure_lag_days": 44,                    // required on political + 13F
    "public_available_at": "2026-08-22T08:15:00-04:00", // backtest entry clock, SPEC §7
    "headline": "Rep. Smith disclosed a purchase",
    "cik": "0000123456",
    "ticker": "ABC",
    "value_range": { "low": 1500000, "high": 5000000, "currency": "USD" },
    "value_exact": null,
    "freshness": 41,
    "entity_match": { "confidence": 0.94, "method": "ticker_exact" },
    "source": { "id": "house_ptr", "document_url": "https://...", "record_id": "20260822-0031" }
  }],
  "meta": { "next_cursor": "..." }
}
```

Rules the frontend can rely on: `transaction_date` and `disclosure_date` are **always both
present** for `political`, `corporate_insider`, and `institutional` events. `value_range`
and `value_exact` are mutually exclusive and one is always populated — congressional
disclosures are ranges, Form 4s are exact. `entity_match.confidence` below 0.85 never
appears in this feed (SPEC §5).

### `GET /companies/{cik}/convergence`

```jsonc
{
  "data": {
    "research_priority": 94,
    "confidence": 44,
    "axes": [
      { "category": "corporate_insider",   "label": "Insider Conviction",     "score": 92, "cleared": true },
      { "category": "political",           "label": "Political Activity",     "score": 78, "cleared": true },
      { "category": "institutional",       "label": "Institutional Activity", "score": 78, "cleared": true },
      { "category": "corporate_event",     "label": "Catalyst Strength",      "score": 88, "cleared": true },
      { "category": "fundamental",         "label": "Fundamental Quality",    "score": 71, "cleared": true },
      { "category": "macro_sector",        "label": "Macro Alignment",        "score": 74, "cleared": true }
    ],
    "categories_cleared": 5,
    "convergence": 88,
    "convergence_tau": 60,
    "contradiction": { "score": 22, "items": [
      { "check": "cfo_selling", "severity": 40, "detail": "CFO sold $1.1M on 2026-08-04",
        "source_url": "https://..." }
    ]},
    "freshness": 66,
    "data_quality": 92
  }
}
```

`axes` shows the six radar dimensions; `categories_cleared` counts across all ten buckets
(SPEC §6.3) and is what the count ring renders. These are deliberately different numbers and
the UI must not conflate them.

### `GET /companies/{cik}/analysis`

```jsonc
{
  "data": {
    "key_takeaway": "…",
    "facts": [
      { "text": "CEO purchased $2.4M on the open market on 2026-08-14.",
        "citation": { "type": "filing", "url": "https://...", "accession": "0001234-26-000123" } }
    ],
    "interpretation": [ { "text": "…", "citation": null } ],
    "bull_case": [ /* same shape */ ],
    "risks": [ /* same shape */ ],
    "unanswered_questions": ["…"],
    "invalidation_conditions": ["…"],
    "model": { "name": "…", "prompt_version": "analyst.v3", "temperature": 0,
               "fact_set_hash": "sha256:…", "generated_at": "…" }
  }
}
```

Any element in `facts` **must** carry a non-null citation — enforced server-side, not
client-side. Uncited content is moved to `interpretation` before the response is returned
(SPEC §9).

### `GET /positioning/short?cik=&range=6m`

```jsonc
{
  "data": {
    "short_interest_pct_shares_outstanding": 6.21,   // field name is deliberate — correction #3
    "change_30d_pp": -1.13,
    "days_to_cover": 3.7,
    "float_available": false,                        // always false in V1, SPEC §4
    "settlement_cadence": "bimonthly",
    "publication_lag_days": 8,
    "series": [ { "date": "2026-08-21", "close": 61.20, "short_interest_pct": 6.21 } ]
  }
}
```

There is no field named `float`, `short_pct_float`, or similar anywhere in the API surface.
A schema test asserts this.

---

## Conventions

- **Pagination** is cursor-based on every list endpoint. No offset pagination — the feed
  changes under the user.
- **Periods** use a fixed vocabulary: `1d`, `7d`, `30d`, `90d`, `1y`, `2y`, `5y`, `max`.
- **Every scored endpoint** returns `weights_version` and `normalization` in `meta`. A
  response without them is a bug, and a test asserts their presence across all routes.
- **No endpoint returns a computed number the UI must re-derive.** Percentages, ratios,
  deltas, and lags are computed server-side in Python. The frontend formats; it never
  calculates. This keeps one source of truth for every figure.
- **OpenAPI is generated** from FastAPI and the frontend's TypeScript types are generated
  from it (`openapi-typescript`). Hand-written response interfaces in the frontend are
  forbidden — a drifted type is how a `% of float` label sneaks back in.
