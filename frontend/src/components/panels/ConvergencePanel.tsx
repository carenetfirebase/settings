/* Signal Convergence. docs/UI_SPEC.md §4.5, correction #7.
 *
 * The count ring circles the axes and is the point of the panel: it makes the
 * number of agreeing categories visible before the score is read. Contradiction
 * is drawn as a separate marker, never folded into the shape (correction #8).
 */
"use client";

import { useEffect, useState } from "react";
import { CategoryCountRing } from "@/components/CategoryCountRing";
import { Panel, type PanelState } from "@/components/Panel";
import { fetchEnvelope, toPanelState } from "@/lib/api";

interface Axis {
  category: string;
  label: string;
  score: number;
  cleared: boolean;
}

interface ConvergenceView {
  research_priority: number;
  confidence: number;
  axes: Axis[];
  categories_cleared: number;
  categories_total: number;
  convergence: number;
  convergence_tau: number;
  contradiction: {
    score: number;
    checks_available: number;
    checks_total: number;
    items: { check: string; status: string; detail: string | null }[];
  };
  data_quality: number;
}

export function ConvergencePanel({ cik }: { cik: string }) {
  const [state, setState] = useState<PanelState<ConvergenceView>>({ kind: "loading" });

  useEffect(() => {
    fetchEnvelope<ConvergenceView | null>(`/companies/${cik}/convergence`)
      .then((body) =>
        setState(
          toPanelState(body as never, {
            emptyMessage: "This company has not been scored yet.",
            emptyAction: "imt score run --date today",
            isEmpty: (data) => data === null,
          }),
        ),
      )
      .catch((error: Error) => setState({ kind: "failed", message: error.message }));
  }, [cik]);

  return (
    <Panel
      title="Signal Convergence"
      caption="Category count, not just score — one loud source is not convergence."
      state={state}
      skeletonHeight={260}
    >
      {(data) => (
        <div className="flex flex-wrap items-start gap-4">
          <CategoryCountRing
            cleared={data.categories_cleared}
            total={data.categories_total}
          >
            <span className="mono" style={{ fontSize: "var(--text-kpi)" }}>
              {data.research_priority.toFixed(1)}
            </span>
            <span className="text-caption" style={{ color: "var(--text-muted)" }}>
              Research Priority
            </span>
          </CategoryCountRing>

          <div className="min-w-0 flex-1">
            <ul className="m-0 list-none p-0">
              {data.axes.map((axis) => (
                <li key={axis.category} className="flex items-center justify-between py-1">
                  <span className="text-caption" style={{ color: "var(--text-secondary)" }}>
                    {axis.label}
                  </span>
                  <span
                    className="mono text-caption"
                    style={{
                      color: axis.cleared ? "var(--positive)" : "var(--text-muted)",
                    }}
                  >
                    {axis.score.toFixed(0)}
                  </span>
                </li>
              ))}
            </ul>

            {/* Separate marker. Never averaged into the shape. */}
            <div
              className="mt-2 rounded-control px-2 py-1"
              style={{ background: "var(--bg-inset)" }}
            >
              <div className="flex items-center justify-between">
                <span className="text-caption" style={{ color: "var(--negative)" }}>
                  Contradiction
                </span>
                <span className="mono text-caption" style={{ color: "var(--negative)" }}>
                  {data.contradiction.score.toFixed(0)}
                </span>
              </div>
              <div className="text-caption" style={{ color: "var(--text-muted)" }}>
                {data.contradiction.checks_available} of {data.contradiction.checks_total} checks
                available
              </div>
            </div>
          </div>
        </div>
      )}
    </Panel>
  );
}
