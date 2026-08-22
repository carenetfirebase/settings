/* App shell: sidebar + top bar + content. docs/UI_SPEC.md §3.
 *
 * Source counts come from GET /api/v1/system/sources, which computes them
 * from config/sources.yaml. UI_SPEC §2 is explicit that "15/15" must never be
 * hardcoded -- a hardcoded count keeps saying everything is fine after a feed
 * dies.
 */
"use client";

import { useEffect, useState } from "react";
import { Sidebar } from "@/components/Sidebar";
import { TopBar, type FreshnessState } from "@/components/TopBar";
import { fetchEnvelope, worstStatus, type SourceState } from "@/lib/api";

export function Shell({ children }: { children: React.ReactNode }) {
  const [sources, setSources] = useState<SourceState[] | null>(null);
  const [marketTime, setMarketTime] = useState("--:--");

  useEffect(() => {
    fetchEnvelope<SourceState[]>("/system/sources")
      .then((body) => {
        if ("data" in body) setSources(body.data);
      })
      .catch(() => setSources([]));
  }, []);

  useEffect(() => {
    const tick = () =>
      setMarketTime(
        new Intl.DateTimeFormat("en-US", {
          hour: "2-digit",
          minute: "2-digit",
          timeZone: "America/New_York",
        }).format(new Date()) + " ET",
      );
    tick();
    const id = setInterval(tick, 30_000);
    return () => clearInterval(id);
  }, []);

  const online = (sources ?? []).filter((s) => s.status === "current").length;
  const total = sources?.length ?? 0;

  const freshness: FreshnessState = {
    // Honest empty state: until an ingest has run there is nothing to claim.
    lastIngest: null,
    pricesAsOf: null,
    worst: sources ? worstStatus(sources) : "unavailable",
  };

  return (
    <div className="flex">
      <Sidebar sourcesOnline={online} sourcesTotal={total} />
      <div className="flex min-w-0 flex-1 flex-col">
        <TopBar marketOpen={false} marketTime={marketTime} freshness={freshness} />
        <main
          className="flex-1 p-3"
          style={{ maxWidth: "var(--content-max)", width: "100%" }}
        >
          {children}
        </main>
        <footer className="px-4 py-3 text-caption" style={{ color: "var(--text-muted)" }}>
          All data sourced from public domain and government APIs · Research tool, not
          financial advice.
        </footer>
      </div>
    </div>
  );
}
