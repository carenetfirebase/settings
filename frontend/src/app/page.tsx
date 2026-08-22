/* Dashboard. Panels come online as their phases land (docs/PHASES.md). */
import { ActivityFeed } from "@/components/panels/ActivityFeed";
import { CongressPanel } from "@/components/panels/CongressPanel";
import { ConvergencePanel } from "@/components/panels/ConvergencePanel";
import { KpiStrip } from "@/components/panels/KpiStrip";
import { TopSignals } from "@/components/panels/TopSignals";

export default function DashboardPage() {
  return (
    <div className="space-y-3">
      <KpiStrip />
      <div className="grid gap-3" style={{ gridTemplateColumns: "repeat(3, minmax(0, 1fr))" }}>
        <TopSignals />
        {/* Defaults to the top-ranked name; a selector lands with Phase 10. */}
        <ConvergencePanel cik="0000320193" />
        <ActivityFeed />
      </div>
      <div className="grid gap-3" style={{ gridTemplateColumns: "repeat(3, minmax(0, 1fr))" }}>
        <CongressPanel period="90d" />
      </div>
    </div>
  );
}
