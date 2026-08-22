/* docs/UI_SPEC.md §4.1.
 *
 * A nav item whose phase has not shipped renders disabled with "Available in
 * Phase N" -- never a dead link, never a blank page. The phase number comes
 * from docs/PHASES.md, so the sidebar is an honest map of what exists.
 */
"use client";

import { usePathname } from "next/navigation";
import Link from "next/link";

interface NavItem {
  label: string;
  href: string;
  /** Undefined means shipped. A number means "Available in Phase N". */
  phase?: number;
}

interface NavGroup {
  heading?: string;
  items: NavItem[];
}

export const NAV: NavGroup[] = [
  { items: [{ label: "Dashboard", href: "/" }] },
  {
    heading: "Intelligence",
    items: [
      { label: "High Priority Signals", href: "/signals", phase: 3 },
      { label: "Insider Activity", href: "/insiders", phase: 2 },
      { label: "Congress Trades", href: "/congress", phase: 4 },
      { label: "Institutional Activity", href: "/institutional", phase: 2 },
      { label: "Activist & 13D/13G", href: "/activist", phase: 2 },
      { label: "Government Contracts", href: "/government", phase: 6 },
      { label: "Corporate Events", href: "/events", phase: 2 },
      { label: "Short Interest", href: "/short-interest", phase: 7 },
      { label: "Macro & Markets", href: "/macro", phase: 7 },
      { label: "Sector Intelligence", href: "/sectors", phase: 7 },
      { label: "Contradictions", href: "/contradictions", phase: 3 },
    ],
  },
  {
    heading: "Research",
    items: [
      { label: "Company Research", href: "/company", phase: 5 },
      { label: "Watchlists", href: "/watchlists", phase: 10 },
      { label: "Screeners", href: "/screeners", phase: 10 },
      { label: "Backtesting", href: "/backtesting", phase: 8 },
      { label: "AI Analyst", href: "/analyst", phase: 9 },
    ],
  },
  {
    heading: "Resources",
    items: [
      { label: "Data Sources", href: "/sources" },
      { label: "Alerts", href: "/alerts", phase: 10 },
      { label: "Settings", href: "/settings", phase: 10 },
    ],
  },
];

function Item({ item, active }: { item: NavItem; active: boolean }) {
  const base = "block rounded-control px-3 py-2 text-body";

  if (item.phase !== undefined) {
    return (
      <span
        className={`${base} cursor-not-allowed`}
        style={{ color: "var(--text-muted)" }}
        title={`Available in Phase ${item.phase}`}
        aria-disabled="true"
      >
        {item.label}
      </span>
    );
  }

  return (
    <Link
      href={item.href}
      className={base}
      style={{
        background: active ? "var(--bg-raised)" : "transparent",
        borderLeft: active ? "2px solid var(--positive)" : "2px solid transparent",
        color: active ? "var(--text-primary)" : "var(--text-secondary)",
      }}
      aria-current={active ? "page" : undefined}
    >
      {item.label}
    </Link>
  );
}

export function Sidebar({ sourcesOnline, sourcesTotal }: {
  sourcesOnline: number;
  sourcesTotal: number;
}) {
  const pathname = usePathname();
  // UI_SPEC §4.1: ring is positive >=90, warning 70-89, negative below.
  const pct = sourcesTotal === 0 ? 0 : Math.round((sourcesOnline / sourcesTotal) * 100);
  const ringColour =
    pct >= 90 ? "var(--positive)" : pct >= 70 ? "var(--warning)" : "var(--negative)";

  return (
    <nav
      className="sticky top-0 flex h-screen flex-col overflow-y-auto p-4"
      style={{
        width: "var(--sidebar-width)",
        background: "var(--bg-app)",
        borderRight: "var(--border-width) solid var(--border)",
      }}
      aria-label="Main"
    >
      <div className="mb-6 flex items-center gap-3">
        <span
          className="mono flex items-center justify-center rounded-control text-caption"
          style={{
            width: 32,
            height: 32,
            border: "var(--border-width) solid var(--border-strong)",
          }}
        >
          IMT
        </span>
        <div className="min-w-0">
          <div className="text-caption leading-tight">Informed Money Terminal</div>
          {/* A real constraint of the product, and a useful reminder. */}
          <div className="mono text-label" style={{ color: "var(--text-muted)" }}>
            $0 / month
          </div>
        </div>
      </div>

      <div className="flex-1 space-y-5">
        {NAV.map((group, i) => (
          <div key={group.heading ?? `group-${i}`}>
            {group.heading ? (
              <div className="panel-label mb-2 px-3" style={{ color: "var(--text-muted)" }}>
                {group.heading}
              </div>
            ) : null}
            <div className="space-y-px">
              {group.items.map((item) => (
                <Item key={item.href} item={item} active={pathname === item.href} />
              ))}
            </div>
          </div>
        ))}
      </div>

      <Link
        href="/sources"
        className="mt-6 block rounded-panel p-3"
        style={{
          background: "var(--bg-panel)",
          border: "var(--border-width) solid var(--border)",
        }}
      >
        <div className="panel-label">Data Coverage</div>
        <div className="mono text-value mt-1" style={{ color: ringColour }}>
          {pct}%
        </div>
        <div className="text-caption" style={{ color: "var(--text-muted)" }}>
          {sourcesOnline} of {sourcesTotal} sources operational
        </div>
      </Link>
    </nav>
  );
}
