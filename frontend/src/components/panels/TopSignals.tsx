/* Today's Top Signals. docs/UI_SPEC.md §4.4, correction #8.
 *
 * Contradiction has its own column and renders even at zero. It is never
 * netted into the score — a company with a strong thesis and a CFO selling
 * shows both numbers, because collapsing them into one would hide the fact
 * that matters most.
 *
 * The rank leads and the score follows, because V1 Research Priority is a
 * ranking key rather than a percentage: DataQuality multiplies it, and with 3
 * of 13 contradiction checks available the absolute value sits in the low
 * single digits (SPEC §6.7). Presenting it as though 0-100 were a meaningful
 * scale would be its own kind of lie.
 *
 * Actions are research verbs. There is no buy or sell anywhere on this row.
 */
"use client";

import { useEffect, useState } from "react";
import { Panel, type PanelState } from "@/components/Panel";
import { Score } from "@/components/Score";
import { fetchEnvelope, toPanelState } from "@/lib/api";

interface Driver {
  category: string;
  score: number;
  label: string;
}

interface TopSignal {
  rank: number;
  cik: string;
  ticker: string | null;
  company_name: string;
  research_priority: number;
  confidence: number;
  contradiction: number;
  convergence: number;
  categories_cleared: number;
  categories_total: number;
  top_drivers: Driver[];
  score_provenance: {
    normalization: string;
    weights_version: string;
    as_of: string;
    validated: boolean;
    contradiction_checks_available: number;
    contradiction_checks_total: number;
  };
}

/** UI_SPEC §4.4: research labels, styled by intent, never by direction. */
function action(signal: TopSignal): { label: string; style: React.CSSProperties } {
  if (signal.categories_cleared >= 4) {
    return {
      label: "Deep Dive",
      style: { background: "var(--positive-deep)", color: "var(--text-primary)" },
    };
  }
  if (signal.contradiction > 40) {
    return {
      label: "Investigate",
      style: { border: "1px solid var(--warning)", color: "var(--warning)" },
    };
  }
  return { label: "Watch", style: { border: "1px solid var(--info)", color: "var(--info)" } };
}

export function TopSignals() {
  const [state, setState] = useState<PanelState<TopSignal[]>>({ kind: "loading" });

  useEffect(() => {
    fetchEnvelope<TopSignal[]>("/signals/top?limit=5")
      .then((body) =>
        setState(
          toPanelState(body, {
            emptyMessage: "No companies scored yet.",
            emptyAction: "imt score run --date today",
          }),
        ),
      )
      .catch((error: Error) => setState({ kind: "failed", message: error.message }));
  }, []);

  return (
    <Panel
      title="Today's Top Signals"
      caption="Contradiction is shown separately and never netted into the score."
      state={state}
      skeletonHeight={260}
    >
      {(rows) => (
        <div className="overflow-x-auto">
          <table className="w-full" style={{ borderCollapse: "collapse" }}>
            <thead>
              <tr style={{ borderBottom: "1px solid var(--border-strong)" }}>
                {["#", "Ticker", "Company", "Score", "Contra", "Drivers", ""].map((h) => (
                  <th
                    key={h}
                    className="panel-label pb-2 text-left"
                    style={{ fontWeight: 400 }}
                  >
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => {
                const act = action(row);
                return (
                  <tr key={row.cik} style={{ borderBottom: "1px solid var(--border)" }}>
                    <td className="mono py-2 text-caption" style={{ color: "var(--text-muted)" }}>
                      {row.rank}
                    </td>
                    <td className="mono py-2 text-body" style={{ color: "var(--info)" }}>
                      {row.ticker ?? "—"}
                    </td>
                    <td className="py-2 text-body">{row.company_name}</td>
                    <td className="py-2">
                      <Score
                        value={row.research_priority}
                        provenance={{
                          normalization:
                            row.score_provenance.normalization === "percentile"
                              ? "percentile"
                              : "fallback_threshold",
                          weightsVersion: row.score_provenance.weights_version,
                          asOf: row.score_provenance.as_of,
                          drivers: [
                            { label: "Convergence", value: row.convergence.toFixed(1) },
                            {
                              label: "Categories cleared",
                              value: `${row.categories_cleared} of ${row.categories_total}`,
                            },
                            {
                              label: "Contradiction checks run",
                              value: `${row.score_provenance.contradiction_checks_available} of ${row.score_provenance.contradiction_checks_total}`,
                            },
                          ],
                        }}
                      />
                    </td>
                    {/* Always rendered, even at zero (correction #8). */}
                    <td
                      className="mono py-2 text-body"
                      style={{
                        color:
                          row.contradiction > 40 ? "var(--negative)" : "var(--text-secondary)",
                      }}
                    >
                      {row.contradiction.toFixed(0)}
                    </td>
                    <td className="py-2 text-caption" style={{ color: "var(--text-secondary)" }}>
                      {row.top_drivers.map((d) => d.label).join(" · ") || "—"}
                    </td>
                    <td className="py-2">
                      <span
                        className="rounded-control px-2 py-1 text-caption"
                        style={act.style}
                      >
                        {act.label}
                      </span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          <p className="mt-2 mb-0 text-caption" style={{ color: "var(--text-muted)" }}>
            Score is a ranking key, not a percentage — DataQuality multiplies it, and only{" "}
            {rows[0]?.score_provenance.contradiction_checks_available ?? 0} of{" "}
            {rows[0]?.score_provenance.contradiction_checks_total ?? 13} contradiction checks
            can run until later phases land.
          </p>
        </div>
      )}
    </Panel>
  );
}
