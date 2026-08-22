/* docs/UI_SPEC.md §4.2, corrections #4, #5, #11, #12.
 *
 * Three things this deliberately does NOT have:
 *
 *  - a "Live" indicator. Nothing in this system is live. Filings arrive on
 *    EDGAR's cadence and prices are end-of-day, so the freshness cluster names
 *    the last ingest and the price as-of date instead (correction #4).
 *  - an account menu. Single-user local application, no accounts, no plans,
 *    no auth (correction #11).
 *  - a theme toggle. Dark only in V1; shipping a control that does nothing is
 *    worse than not shipping it (correction #12).
 *
 * The market clock stays, because it is honest -- but it sits LEFT of the
 * divider, away from the data-status cluster. Adjacency would imply the data
 * is intraday (correction #5).
 */
"use client";

export interface FreshnessState {
  lastIngest: string | null;
  pricesAsOf: string | null;
  /** Worst status across all sources; drives the dot colour. */
  worst: "current" | "delayed" | "stale" | "unavailable" | "failed";
}

export interface TopBarProps {
  marketOpen: boolean;
  marketTime: string;
  freshness: FreshnessState;
}

function dotColour(worst: FreshnessState["worst"]): string {
  if (worst === "current") return "var(--positive)";
  if (worst === "failed" || worst === "unavailable") return "var(--negative)";
  return "var(--warning)";
}

export function TopBar({ marketOpen, marketTime, freshness }: TopBarProps) {
  return (
    <header
      className="flex items-center gap-4 px-4"
      style={{
        height: "var(--topbar-height)",
        background: "var(--bg-app)",
        borderBottom: "var(--border-width) solid var(--border)",
      }}
    >
      <label className="sr-only" htmlFor="global-search">
        Search
      </label>
      <div className="relative" style={{ width: 480, maxWidth: "40vw" }}>
        <input
          id="global-search"
          type="search"
          placeholder="Search ticker, company, person, filing…"
          className="w-full rounded-control px-3 py-2 text-body"
          style={{
            background: "var(--bg-raised)",
            border: "var(--border-width) solid var(--border)",
            color: "var(--text-primary)",
          }}
        />
        <kbd
          className="mono absolute right-2 top-1/2 -translate-y-1/2 rounded-control px-1.5 text-label"
          style={{ background: "var(--bg-inset)", color: "var(--text-muted)" }}
        >
          /
        </kbd>
      </div>

      <div className="flex-1" />

      {/* Market clock -- honest, and kept away from the data status. */}
      <span
        className="mono text-caption"
        style={{ color: marketOpen ? "var(--positive)" : "var(--text-muted)" }}
      >
        {marketOpen ? "Market open" : "Market closed"} · {marketTime}
      </span>

      <span aria-hidden style={{ width: 1, height: 20, background: "var(--border-strong)" }} />

      {/* Data freshness cluster. Never the word "live". */}
      <a
        href="/sources"
        className="flex items-center gap-2 text-caption"
        style={{ color: "var(--text-secondary)" }}
      >
        <span
          aria-hidden
          className="rounded-full"
          style={{ width: 8, height: 8, background: dotColour(freshness.worst) }}
        />
        <span className="mono">
          {freshness.lastIngest ? `Last ingest ${freshness.lastIngest}` : "No ingest yet"}
          {freshness.pricesAsOf ? ` · Prices ${freshness.pricesAsOf}` : ""}
        </span>
      </a>
    </header>
  );
}
