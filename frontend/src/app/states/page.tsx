/* Phase 1 criterion 9: every panel state, rendered side by side.
 *
 * This is the storybook-equivalent. It exists so "does this panel handle
 * staleness" is answerable by looking rather than by reading code, and so a
 * regression in any of the four states is visible immediately.
 */
import { Panel } from "@/components/Panel";
import { EventRow } from "@/components/EventRow";

export default function PanelStatesPage() {
  return (
    <div className="space-y-3">
      <h1 className="text-heading">Panel states</h1>
      <p className="text-caption" style={{ color: "var(--text-muted)" }}>
        UI_SPEC §4.10. Every panel implements all four. A panel with only a happy path is not
        done.
      </p>

      <div className="grid gap-3" style={{ gridTemplateColumns: "repeat(2, minmax(0, 1fr))" }}>
        <Panel title="Loading" state={{ kind: "loading" }} skeletonHeight={120}>
          {() => null}
        </Panel>

        <Panel
          title="Empty"
          state={{
            kind: "empty",
            message: "No 13D filings in the last 30 days.",
            action: "imt ingest thirteen-d --since 30d",
          }}
        >
          {() => null}
        </Panel>

        <Panel
          title="Stale"
          state={{
            kind: "stale",
            data: "Figures rendered from the last successful ingest.",
            sourceId: "SEC EDGAR",
            lastSuccess: "4 days ago",
            asOf: "Aug 18",
          }}
        >
          {(data: string) => <p className="text-body m-0">{data}</p>}
        </Panel>

        <Panel
          title="Failed"
          state={{
            kind: "failed",
            message: "USAspending ingest failed 3× (rate limit).",
            retryAt: "14:00",
            affected: ["government_contracts"],
          }}
        >
          {() => null}
        </Panel>
      </div>

      <Panel
        title="Event rows"
        caption="Both dates on every dated event — the type will not compile without them."
        state={{ kind: "ready", data: null }}
      >
        {() => (
          <ul className="m-0 list-none p-0">
            <EventRow
              eventId="1"
              category="political"
              headline="Disclosed a purchase"
              ticker="ABC"
              detectedAgo="6m ago"
              transactionDate="2026-07-09"
              disclosureDate="2026-08-22"
              disclosureLagDays={44}
              value="$1.5M–$5M"
              sourceUrl="#"
              sourceLabel="House PTR"
            />
            <EventRow
              eventId="2"
              category="corporate_insider"
              headline="CEO open-market purchase"
              ticker="XYZ"
              detectedAgo="2h ago"
              transactionDate="2026-08-20"
              disclosureDate="2026-08-22"
              disclosureLagDays={2}
              value="$2.4M"
              sourceUrl="#"
              sourceLabel="Form 4"
            />
            <EventRow
              eventId="3"
              category="corporate_event"
              headline="Material definitive agreement"
              ticker="DEF"
              detectedAgo="1d ago"
              filedDate="2026-08-21"
              sourceUrl="#"
              sourceLabel="8-K"
            />
          </ul>
        )}
      </Panel>
    </div>
  );
}
