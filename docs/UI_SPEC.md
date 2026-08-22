# UI specification

Design reference: `docs/design/dashboard-mockup.png` (1536×1024). **The mockup is the visual
authority.** Match its layout, density, and palette.

It is not the *behavioural* authority. Section 2 below lists twelve places where the mockup
contradicts the integrity rules in `SPEC.md`. Where they conflict, **SPEC wins** and the
mockup is corrected. Build the corrected version.

> **Mockup status.** The PNG is not yet in the repo. Everything in §1 and §3–§6 is
> self-sufficient and was built from the token values and measurements below. The two
> acceptance criteria that require the image itself — Phase 1 #7 and Phase 10 #7 — are
> **blocked** until it lands, and are marked as such rather than silently passed.

---

## 1. Design tokens

Defined once in `frontend/src/styles/tokens.css` as CSS custom properties and mirrored into
`tailwind.config.ts`. No hex value appears anywhere else in the codebase — a lint rule
enforces this.

### Colour

```css
/* surfaces */
--bg-app:            #010C15;  /* page + sidebar */
--bg-panel:          #09141C;  /* every card and panel */
--bg-raised:         #111923;  /* search field, hover, table row hover */
--bg-inset:          #060F17;  /* inset wells, sub-boxes inside panels */

/* lines */
--border:            #16232E;  /* default 1px panel border */
--border-strong:     #1F303D;  /* table header rules, active tab underline */

/* text */
--text-primary:      #E8EEF2;
--text-secondary:    #8A9BA8;  /* labels, column headers, captions */
--text-muted:        #5A6B78;  /* timestamps, disabled */

/* semantic — meaning is fixed, never decorative */
--positive:          #2DD4A7;  /* teal-green: confirming evidence, up, healthy */
--positive-deep:     #0F5D41;  /* filled primary button */
--warning:           #F0B429;  /* amber: stale, degraded, needs attention */
--negative:          #E5484D;  /* red: contradictions, down, failure */
--info:              #4A9FD8;  /* blue: tickers, links, filings */
--political:         #8B7BD8;  /* purple: congressional category only */

/* heat map ramp */
--heat-pos-max:      #144831;
--heat-neg-max:      #4A1F21;
```

**Semantic discipline.** Green means confirming evidence or a positive change — never "buy".
Red means contradiction or a negative change — never "sell". Amber means the data is stale
or degraded — never "caution, consider trading". This mapping is stated in the UI legend and
must be honoured in every component.

### Type

```css
--font-sans:  "Inter", ui-sans-serif, system-ui;         /* all UI text */
--font-mono:  "JetBrains Mono", ui-monospace, monospace; /* all numbers, tickers, dates */
```

**Every number, ticker, and date is monospaced and tabular** (`font-variant-numeric:
tabular-nums`). Columns of figures must align on the decimal. This is the single most
important typographic rule in a terminal — a proportional-figure table reads as amateur.

Scale: `10px/0.08em uppercase` panel labels · `11px` captions and timestamps · `13px` body
and table cells · `15px` panel headings · `20px` section values · `32px` KPI figures.

### Space and shape

4px base unit. Panel padding 16px. Panel gap 12px. Radius: 6px panels, 4px buttons and
chips, full for score badges. Border 1px `--border`. **No shadows.** Depth comes from
surface value, not blur — shadows read as consumer-app on a dark terminal.

---

## 2. Mandatory corrections to the mockup

Build these differently from what the image shows. Each one exists because the mockup, as
drawn, would mislead the person using it.

| # | Mockup shows | Build instead | Rule |
|---|---|---|---|
| 1 | Events timeline: "CEO Buy · May 16, 2025" — one date | **Two dates on every event**: `Txn May 16 · Filed May 18 · 2d lag`. Lag rendered in `--warning` above 7 days, `--negative` above 30. | SPEC §6.5, §7 |
| 2 | Live feed: "6m ago — Rep. Smith purchased shares" | Time-ago describes **detection**, and must sit next to the transaction date: `Detected 6m ago · Txn Apr 2 · 44d lag`. A congressional row without its transaction date is a bug. | SPEC §5, §11 |
| 3 | "SHORT INTEREST %" | "SHORT INTEREST (% OF SHARES OUTSTANDING)". Never "% of float" — free float is not available (SPEC §4). | SPEC §4, §8 |
| 4 | "Data Updates: Live ●" | `Last ingest 09:42 ET · Prices as of Aug 21 close`. **Nothing in this system is live.** Filings arrive on EDGAR's cadence; prices are EOD. | SPEC §10 |
| 5 | "Market Open · 09:54 AM ET" | Keep the market clock — it is honest. But it must not sit adjacent to the data-status indicator, because proximity implies the data is intraday. Move it left of the divider. | — |
| 6 | Score badge `94` with no provenance | Every score is hover/tap-revealing: normalization method (`percentile` or `threshold-fallback`), `weights_version`, and the as-of date. A threshold-normalized score renders with a dotted underline meaning "unvalidated". | SPEC §6.2, §6.8 |
| 7 | Convergence radar shows six axes and a `94` centre | Radar must make **category count** visually obvious — a 94 from one category and a 94 from five must not look alike. Add a category-count ring: n filled segments out of 10. Contradiction axis renders in `--negative` and is never averaged into the shape. | SPEC §6.4, §6.6 |
| 8 | No contradiction figure on the dashboard | Contradiction Score appears in Today's Top Signals as its own column, always, even when zero. It is never netted into the score. | SPEC §6.6 |
| 9 | AI Analyst bullets, uncited | Every AI line carries a source chip linking to the filing or database row. Uncited lines render in `--text-secondary` under an "Interpretation" subhead, visually separated from "Facts". | SPEC §9 |
| 10 | Government Contracts panel, no caveat | Persistent caveat line: "Covers awards resolved to a listed parent at ≥85% confidence. Subsidiary awards are undercounted." | SPEC §5 |
| 11 | "Alex Morgan · Personal Plan", account chevron | Single-user local application. No accounts, no plans, no auth. Replace with the data-freshness cluster. Remove the chevron menu. | — |
| 12 | Sun icon / theme toggle | Dark only in V1. Remove the control rather than shipping a toggle that does nothing. | Scope |

Two further notes: the mockup's sample dates are 2025 while its cards say "24H" — sample
data only, ignore. And "Data Sources 15/15" must be computed from `config/sources.yaml`,
never hardcoded.

---

## 3. Layout

```
┌──────────┬──────────────────────────────────────────────────────────┐
│          │  top bar                                          56px   │
│ sidebar  ├──────────────────────────────────────────────────────────┤
│  208px   │  KPI strip — 6 cards                             ~92px   │
│  fixed   ├──────────────────────────────────────────────────────────┤
│          │  row A: top signals (5fr) │ convergence (5fr) │ feed (5fr)│
│          ├──────────────────────────────────────────────────────────┤
│          │  row B: 5 equal panels                                    │
│          ├──────────────────────────────────────────────────────────┤
│          │  row C: 4 equal panels                                    │
│          ├──────────────────────────────────────────────────────────┤
│          │  footer                                                   │
└──────────┴──────────────────────────────────────────────────────────┘
```

CSS Grid, 12px gaps, `--bg-app` showing through as the gutter. Content max-width 1920px,
centred. Sidebar is `position: sticky`, independently scrollable.

Breakpoints: ≥1600px as drawn · 1280–1599px row A becomes 2+1 wrap, rows B and C become 3
and 2 across · <1280px single column, sidebar collapses to a 56px icon rail · <768px is out
of scope for V1 (this is a desktop terminal; say so on a mobile visit rather than shipping a
broken layout).

---

## 4. Components

### 4.1 Sidebar

`IMT` mark in a 1px-bordered square, wordmark "Informed Money Terminal", subtitle
`$0 / month` in `--text-muted` — keep it, it is a real constraint of the product and a
useful reminder.

Groups, in order, with `10px` uppercase `--text-muted` headers:

- **(ungrouped)** Dashboard
- **INTELLIGENCE** — High Priority Signals · Insider Activity · Congress Trades ·
  Institutional Activity · Activist & 13D/13G · Government Contracts · Corporate Events ·
  Short Interest · Macro & Markets · Sector Intelligence · Contradictions
- **RESEARCH** — Company Research · Watchlists · Screeners · Backtesting · AI Analyst
- **RESOURCES** — Data Sources · Alerts · Settings

Active item: `--bg-raised` fill plus a 2px `--positive` left rule. Icons 16px, stroked, from
one set only (lucide-react).

Footer block: **Data Coverage** ring with percentage, caption "N of M sources operational".
Ring is `--positive` ≥90, `--warning` 70–89, `--negative` below. Links to Data Sources.

A nav item whose phase has not shipped renders disabled with tooltip "Available in Phase N" —
never a dead link, never a blank page.

### 4.2 Top bar

Left: global search, 480px, `--bg-raised`, magnifier icon, placeholder "Search ticker,
company, person, filing…", `/` keyboard hint chip on the right edge. Focus opens a command
palette (§4.12).

Right, in order: market clock (`Market Open · 09:54 ET`, `--positive` when open, `--text-muted`
when closed) · divider · **data freshness cluster** (`Last ingest 09:42 ET · Prices Aug 21
close`, with a status dot; amber if any source is stale, red if a core source has failed;
click opens Data Sources) · alerts bell with unread count badge.

### 4.3 KPI strip — six cards

Each: `10px` uppercase label · `32px` mono figure · delta line (`↑ 8 vs yesterday`, coloured
by direction) · 14-day sparkline bleeding to the card's right edge at 40% opacity.

1. **High Priority Signals** — count of Research Priority ≥85 · `--positive`
2. **Form 4 Filings (24h)** — accepted in the last 24h · `--info`
3. **Congress Trades (24h)** — **disclosed** in the last 24h, not transacted · `--political`
4. **13D/13G Alerts** — new filings · `--warning`
5. **Market Regime** — label ("Moderate Risk-On"), trend line, 0–100 gauge ring
6. **Data Sources** — `15 / 15 Active`, uptime, layers icon

Cards 1–4 are clickable filters into their respective pages. Card 3's tooltip states the
disclosure-vs-transaction distinction explicitly.

### 4.4 Today's Top Signals

Columns: `#` · Ticker (mono, `--info`, links to deep dive) · Company · **Score** (36px ring
badge, ring arc = value, colour banded ≥85 positive / 65–84 warning / <65 muted) ·
**Contra** (new — contradiction score, `--negative` when >40) · Top Drivers (up to 4 category
icons, tooltip names the category and its score) · Action.

Actions are research labels, styled by intent, not by trading direction:
`Deep Dive` filled `--positive-deep` · `Investigate` outlined `--warning` ·
`Watch` outlined `--info`.

Row hover `--bg-raised`. Five rows, then "View full queue →".

Empty state: "No companies scored yet. Run `imt score run` or wait for the next scheduled
ingest." Not a shrug — an instruction.

### 4.5 Signal Convergence panel

Header: company name + ticker + external-link to deep dive. A company selector, since the
mockup's pinned single company is only its default (top-ranked name).

**Left — radar**, six axes: Insider Conviction · Political Activity · Institutional Activity
· Catalyst Strength · Fundamental Quality · Macro Alignment. Polygon fill `--positive` at
12% opacity, 1.5px stroke. Axis labels outside with values in mono.

Centre: Research Priority, 40px mono, caption "Research Priority".

**Category-count ring** (correction #7) circles the radar: 10 segments, one per evidence
category, filled when that category cleared τ. This is what distinguishes real convergence
from one loud source, and it is the most important pixel on the dashboard.

Contradiction is drawn as a separate `--negative` marker outside the polygon — never folded
into the shape.

**Right — Recent Events Timeline.** Vertical rail, one dot per event coloured by category.
Each entry: event title · **transaction date** · **filed date** · lag · value · source chip.
Newest first, 4 visible, "View timeline →".

### 4.6 Live Activity Feed

Tabs: All · Insiders · Congress · Institutions · Activists · Filings · Government · Macro.
Active tab underlined 2px `--positive`. Filters button opens category/ticker/value filters.

Row: category icon · detection time · description · ticker chip · value or range ·
category tag chip. Beneath the description, in `11px --text-muted`: transaction date, filed
date, and lag. Congressional and 13F rows **must** show lag; a Form 4 filed within 2 days
may show it compactly.

New rows fade in over 200ms. Feed pauses on hover. Respect `prefers-reduced-motion`.

### 4.7 Row B — five summary panels

**Insider Activity Summary (30D)** — Open Market Buys · Open Market Sales · Total Value
Bought · Total Value Sold · Buy/Sell Ratio, each with a period delta. Area sparkline below.
Period toggle 7D/30D/90D/1Y. Counts are **code `P` and `S` only** — grants, exercises, and
tax withholding are excluded and the panel says so in its caption.

**Congressional Trading (30D)** — donut, centre = total trades. Legend: Buys / Sells / Other
with counts and percentages. Caption: "By disclosure date. Underlying transactions average
Nd older." Compute that average; do not hardcode it.

**Government Contracts (90D)** — Total Awards · Unique Companies · Top Sector with leading
recipient. Plus the coverage caveat from correction #10.

**Short Interest & Price** — three figures (SI % of shares outstanding · 30D change in pp ·
days to cover) over a dual-axis chart: price line `--positive`, short interest `--info`.
Range toggle 1M/3M/6M/1Y/2Y. Caption states the bi-monthly settlement cadence and
publication lag.

**Macro Regime Overview** — six labelled rows (Growth · Inflation · Liquidity · Rates · Risk
Appetite · USD Trend) with categorical values, coloured by direction. Each row's tooltip
names the FRED series behind it.

### 4.8 Row C — four panels

**Sector Heat Map (1D)** — 10 tiles, internal SIC-derived taxonomy (SPEC §4). Background
interpolates `--heat-neg-max` → `--bg-panel` → `--heat-pos-max` by percentage. Label "1D",
caption "As of last close, Aug 21" — never implied intraday.

**AI Analyst Summary** — company name, "Key Takeaway" paragraph, then two columns: Bull Case
(`--positive` bullets) and Risks (`--negative` bullets). Per correction #9, each bullet
carries a source chip; uncited content is grouped under "Interpretation". Panel footer:
model name and prompt version, in `--text-muted`.

**Watchlist Summary** — High Conviction (>85) · Watchlist (65–85) · Monitor (<65) · Total,
each with a delta, plus a donut of the split.

**Data Quality Score** — 0–100 ring, qualitative label, and a per-source checklist with
Online / Delayed / Stale / Failed states. Any non-Online source promotes the top-bar status
dot to amber or red.

### 4.9 Footer

"All data sourced from public domain and government APIs · Last full ingest {timestamp} ·
Research tool, not financial advice." Right: "Built with open source". Keep it quiet —
`11px --text-muted`.

### 4.10 Universal panel states

Every panel implements four states. This is a checklist item at review, not optional.

- **Loading** — skeleton at the panel's real dimensions. No spinners; layout must not jump.
- **Empty** — plain statement of why plus the action that fills it. "No 13D filings in the
  last 30 days." is complete; "No data" is not.
- **Stale** — renders the data it has, with an amber header strip: "SEC EDGAR last succeeded
  4 days ago. Figures below are from Aug 18." Never blank a panel for staleness, and never
  show it silently.
- **Failed** — what broke and what to do: "USAspending ingest failed 3× (rate limit).
  Retrying at 14:00. Contract figures excluded from scores."

### 4.11 Score provenance (correction #6)

A shared `<Score>` component used everywhere a 0–100 value appears. Hover or tap reveals:
value · normalization method · `weights_version` · as-of date · the top three contributing
features with their raw values and units. Threshold-normalized scores render with a dotted
underline; the legend defines it as "unvalidated — weights not yet backtested".

### 4.12 Command palette

`/` or `Ctrl+K`. Searches tickers, companies, politicians, insiders, institutions, agencies,
filings, sectors. Grouped results, arrow-key navigation, Enter opens. Recent searches
persist locally.

---

## 5. Copy rules

Enforced by a grep test in CI over `frontend/src`:

- **Banned:** "buy", "sell", "recommendation", "signal to buy", "target price", "conviction
  to trade", "opportunity to enter", "live" (as a data descriptor), "% of float".
- "Deep Dive", "Investigate", "Watch" are the only three action verbs on a company row.
- An action keeps its name throughout: the "Watch" button produces a "Watching" state and a
  "Removed from watchlist" toast.
- Sentence case everywhere except the `10px` uppercase panel labels.
- Errors state what happened and what happens next. They do not apologize and are never
  vague.
- Every figure derived from a filing links to that filing on EDGAR. Provenance is one click
  away from every number on screen, without exception.

---

## 6. Accessibility and performance

Keyboard reachable throughout, visible focus ring (`--info`, 2px offset). Colour is never
the sole carrier of meaning — pair with an icon or label, because red/green sits directly on
the most common colour-vision deficiency. Contrast ≥4.5:1 for body text against
`--bg-panel`; `--text-muted` is reserved for non-essential text only. `prefers-reduced-motion`
disables sparkline animation and feed transitions.

Budgets: dashboard interactive under 2s against a populated database; no panel blocks another
(each fetches independently and renders as it resolves); charts virtualize above 2,000
points; the feed windows above 200 rows.
