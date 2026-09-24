/**
 * The site map: every page, the category it lives in, what it is for, what
 * data backs it, and whether it exists yet.
 *
 * This is the single source of truth for navigation, for the "planned" pages,
 * and for docs/SITE_MAP.md (a test fails if the two drift apart). A page's
 * status is a claim about the product, so it is stated here once rather than
 * re-asserted in each component.
 */

export type Status = "live" | "v1" | "v2";

export interface Page {
  /** Stable id, used as the React key and in tests. */
  id: string;
  title: string;
  /** Route under the /app basename. `:ticker` pages take a symbol. */
  path: string;
  status: Status;
  /** One line: what a person uses this page for. */
  purpose: string;
  /** Where its numbers come from. */
  data: string;
  /** What exists today, when status is live but the page is not complete. */
  today?: string;
}

export interface Category {
  id: string;
  title: string;
  pages: Page[];
}

export const STATUS_LABEL: Record<Status, string> = {
  live: "Live",
  v1: "V1",
  v2: "V2",
};

export const STATUS_MEANING: Record<Status, string> = {
  live: "Built and served by the research API today.",
  v1: "Next build phase: paid data, signals, validation and paper trading.",
  v2: "After V1 has proven itself in paper trading.",
};

export const SITE_MAP: Category[] = [
  {
    id: "command",
    title: "Command Center",
    pages: [
      {
        id: "command-center",
        title: "Command Center",
        path: "/",
        status: "live",
        purpose:
          "One screen for the day: trend gate, portfolio heat, the best trade cards and open positions, with breadth and event odds as context.",
        data: "Every other page, summarised.",
        today: "Regime, universe coverage, data quality and research history. The other panels fill in as V1 lands.",
      },
    ],
  },
  {
    id: "markets",
    title: "Markets",
    pages: [
      {
        id: "markets-overview",
        title: "Overview",
        path: "/markets",
        status: "live",
        purpose: "The research universe: every tracked symbol, its sector and its data-quality status.",
        data: "Security master, verified against SEC EDGAR.",
        today: "Universe table. Relative-strength columns arrive with V1 data.",
      },
      {
        id: "markets-sectors",
        title: "Sectors & Rotation",
        path: "/markets/sectors",
        status: "v1",
        purpose: "Relative strength (12-month return, skipping the latest month) for every sector: which lead the S&P 500. Scored.",
        data: "Survivorship-free daily bars (Norgate).",
      },
      {
        id: "markets-breadth",
        title: "Breadth",
        path: "/markets/breadth",
        status: "v1",
        purpose: "Context, not scored: % of members above the 50- and 200-day averages, advance/decline, new highs vs lows.",
        data: "Survivorship-free index constituents and history (Norgate).",
      },
      {
        id: "markets-macro",
        title: "Macro & Rates",
        path: "/markets/macro",
        status: "live",
        purpose: "Context, not scored: yield curve, credit spreads, VIX, unemployment and inflation, each with its threshold.",
        data: "FRED / ALFRED, stored with vintages so history is point-in-time.",
      },
      {
        id: "markets-events",
        title: "Prediction Markets",
        path: "/markets/events",
        status: "v2",
        purpose: "Context, not scored: market-implied odds for FOMC, CPI, PCE and recession, with 24-hour changes.",
        data: "Kalshi and Polymarket public APIs.",
      },
      {
        id: "markets-cross-asset",
        title: "Cross-Asset",
        path: "/markets/cross-asset",
        status: "v2",
        purpose: "Context, not scored: the dollar, oil, gold, Treasuries and crypto.",
        data: "FRED dollar index, ETF proxies, CCXT for crypto.",
      },
    ],
  },
  {
    id: "signals",
    title: "Signals",
    pages: [
      {
        id: "signals-scanner",
        title: "Scanner",
        path: "/signals/scanner",
        status: "v1",
        purpose: "Every symbol run through the trend gate, relative strength and pullback entry, plus the quality and event vetoes, showing exactly why each passes or fails.",
        data: "Only the 10/10 inputs in docs/ENGINE_INPUTS.md.",
      },
      {
        id: "signals-cards",
        title: "Trade Cards",
        path: "/signals/cards",
        status: "v1",
        purpose: "Entry, stop, target, size, evidence, contradictions and the level that breaks the thesis.",
        data: "Signal engine plus risk model.",
      },
      {
        id: "signals-ledger",
        title: "Signal Ledger",
        path: "/signals/ledger",
        status: "v1",
        purpose: "Every signal ever fired, taken or not, with its outcome in R and its best and worst excursion (MFE/MAE).",
        data: "Append-only signal log.",
      },
    ],
  },
  {
    id: "research",
    title: "Research",
    pages: [
      {
        id: "research-symbol",
        title: "Symbol Research",
        path: "/research/:ticker",
        status: "live",
        purpose: "One symbol in depth: chart, the three scores with every component, fundamentals, insiders, the full report and its history.",
        data: "Prices, SEC XBRL fundamentals, Form 4 filings, stored research snapshots.",
      },
      {
        id: "research-filings",
        title: "Filings & Insiders",
        path: "/research/filings",
        status: "v1",
        purpose: "A feed across the whole universe: new 8-Ks and insider open-market buys, opportunistic insiders first.",
        data: "SEC EDGAR filing index and Form 4.",
      },
      {
        id: "research-ecosystem",
        title: "Ecosystem Map",
        path: "/research/ecosystem",
        status: "v2",
        purpose: "Customer and supplier links, dated, used to find stocks that have not yet reacted to news about a linked company.",
        data: "10-K major-customer disclosures (≥10% of revenue).",
      },
      {
        id: "research-options",
        title: "Options",
        path: "/research/options",
        status: "v2",
        purpose: "Chain, IV rank and expected move. IV rank decides shares or a spread; it never sets direction.",
        data: "OPRA via Alpaca; deeper history from Massive if needed.",
      },
    ],
  },
  {
    id: "trading",
    title: "Trading",
    pages: [
      {
        id: "trading-ticket",
        title: "Order Ticket",
        path: "/trading/ticket",
        status: "v1",
        purpose: "Turn a trade card into a bracket order (entry + stop + target) in one step. Paper first.",
        data: "Alpaca trading API.",
      },
      {
        id: "trading-positions",
        title: "Positions",
        path: "/trading/positions",
        status: "v1",
        purpose: "Open positions with P&L in dollars and in R, and whether each stop is live at the broker.",
        data: "Alpaca account and positions.",
      },
      {
        id: "trading-risk",
        title: "Risk",
        path: "/trading/risk",
        status: "v1",
        purpose: "Portfolio heat against its cap, correlated clusters, the drawdown breaker and the halt switch.",
        data: "Positions plus the risk model.",
      },
      {
        id: "trading-journal",
        title: "Journal",
        path: "/trading/journal",
        status: "v2",
        purpose: "Notes and a data snapshot for every trade, reviewed weekly against the ledger.",
        data: "Your notes plus the signal ledger.",
      },
    ],
  },
  {
    id: "lab",
    title: "Lab",
    pages: [
      {
        id: "lab-backtests",
        title: "Backtests",
        path: "/lab/backtests",
        status: "v1",
        purpose: "Point-in-time backtests with costs and next-bar fills, walk-forward splits, and honest refusals when data cannot support a test.",
        data: "The existing backtest engine, exposed through the API.",
      },
      {
        id: "lab-calibration",
        title: "Calibration",
        path: "/lab/calibration",
        status: "v1",
        purpose: "Does a score of 80 mean anything? Hit rate and expectancy by score bucket.",
        data: "Signal ledger outcomes.",
      },
      {
        id: "lab-attribution",
        title: "Layer Attribution",
        path: "/lab/attribution",
        status: "v1",
        purpose: "What each layer adds out of sample, adjusted for how many rules were tried. Layers that add nothing get cut.",
        data: "Signal ledger plus walk-forward results.",
      },
    ],
  },
  {
    id: "system",
    title: "System",
    pages: [
      {
        id: "system-feeds",
        title: "Data Feeds",
        path: "/system/feeds",
        status: "live",
        purpose: "Every source: what is stored, when it last updated, how delayed it is, and whether it failed over.",
        data: "Database row counts; feed health checks arrive in V1.",
        today: "Stored row counts per table.",
      },
      {
        id: "system-quality",
        title: "Data Quality",
        path: "/system/quality",
        status: "live",
        purpose: "Everything the validation gate flagged, so bad data is visible rather than silently dropped.",
        data: "Validation gate conflicts.",
      },
      {
        id: "system-settings",
        title: "Settings",
        path: "/system/settings",
        status: "v1",
        purpose: "Which keys are configured (never their values), risk limits, paper/live mode and sign-in.",
        data: "Server-side configuration.",
      },
    ],
  },
];

export const ALL_PAGES: Page[] = SITE_MAP.flatMap((c) => c.pages);

export function pageById(id: string): Page {
  const page = ALL_PAGES.find((p) => p.id === id);
  if (!page) throw new Error(`No page ${id} in the site map`);
  return page;
}
