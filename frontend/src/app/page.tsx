/* Dashboard. Panels come online as their phases land (docs/PHASES.md).
 *
 * Every panel below renders its real empty state rather than placeholder
 * data. A dashboard that shows invented numbers during development is how
 * invented numbers reach production.
 */
import { Panel } from "@/components/Panel";
import { Score } from "@/components/Score";

export default function DashboardPage() {
  return (
    <div className="space-y-3">
      <div className="grid gap-3" style={{ gridTemplateColumns: "repeat(3, minmax(0, 1fr))" }}>
        <Panel
          title="Today's Top Signals"
          state={{
            kind: "empty",
            message: "No companies scored yet.",
            action: "imt score run --date today",
          }}
        >
          {() => null}
        </Panel>

        <Panel
          title="Signal Convergence"
          caption="Category count, not just score — one loud source is not convergence."
          state={{ kind: "empty", message: "Scoring lands in Phase 3." }}
        >
          {() => null}
        </Panel>

        <Panel
          title="Activity Feed"
          state={{ kind: "empty", message: "No events ingested yet.", action: "imt ingest form4 --since 7d" }}
        >
          {() => null}
        </Panel>
      </div>

      <Panel
        title="Score provenance"
        caption="Every 0–100 value carries its normalization method, weights version, and as-of date. Hover any badge."
        state={{
          kind: "ready",
          data: [72, 88, 41],
        }}
        skeletonHeight={60}
      >
        {(values: number[]) => (
          <div className="flex items-center gap-6">
            {values.map((v) => (
              <Score
                key={v}
                value={v}
                size="lg"
                provenance={{
                  normalization: "fallback_threshold",
                  weightsVersion: "0.1.0",
                  asOf: "—",
                }}
              />
            ))}
            <span className="text-caption" style={{ color: "var(--text-muted)" }}>
              Dotted underline means unvalidated — weights not yet backtested (Phase 8).
            </span>
          </div>
        )}
      </Panel>
    </div>
  );
}
