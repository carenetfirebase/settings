/* Dashboard. Panels come online as their phases land (docs/PHASES.md).
 *
 * Panels whose data does not exist yet render their real empty state rather
 * than placeholder numbers. A dashboard that shows invented figures during
 * development is how invented figures reach production.
 */
import { Panel } from "@/components/Panel";
import { ActivityFeed } from "@/components/panels/ActivityFeed";
import { KpiStrip } from "@/components/panels/KpiStrip";

export default function DashboardPage() {
  return (
    <div className="space-y-3">
      <KpiStrip />

      <div className="grid gap-3" style={{ gridTemplateColumns: "repeat(3, minmax(0, 1fr))" }}>
        <Panel
          title="Today's Top Signals"
          caption="Research priority, with contradiction shown separately and never netted."
          state={{
            kind: "empty",
            message: "No companies scored yet. Scoring lands in Phase 3.",
            action: "imt score run --date today",
          }}
          skeletonHeight={260}
        >
          {() => null}
        </Panel>

        <Panel
          title="Signal Convergence"
          caption="Category count, not just score — one loud source is not convergence."
          state={{ kind: "empty", message: "Scoring lands in Phase 3." }}
          skeletonHeight={260}
        >
          {() => null}
        </Panel>

        <ActivityFeed />
      </div>
    </div>
  );
}
