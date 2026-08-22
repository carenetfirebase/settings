/* KPI strip. docs/UI_SPEC.md §4.3.
 *
 * A card whose data has not been ingested yet shows the reason, not a zero.
 * "0 congressional trades in 24h" and "congressional ingest lands in Phase 4"
 * look identical as a number and mean completely different things — the first
 * is a finding, the second is an absence of data.
 *
 * Card 3 counts trades DISCLOSED in the last 24 hours, not transacted. The
 * underlying transactions average weeks older and the tooltip says so
 * (UI_SPEC correction #2).
 */
"use client";

import { useEffect, useState } from "react";
import { fetchEnvelope } from "@/lib/api";

interface KpiCard {
  key: string;
  label: string;
  value: number | null;
  delta: number | null;
  unit: string;
  reason_code: string | null;
}

const ACCENT: Record<string, string> = {
  high_priority_signals: "var(--positive)",
  form4_filings_24h: "var(--info)",
  congress_trades_24h: "var(--political)",
  activist_alerts: "var(--warning)",
  market_regime: "var(--text-secondary)",
  data_sources: "var(--text-secondary)",
};

const TOOLTIP: Record<string, string> = {
  congress_trades_24h:
    "Counts trades DISCLOSED in the last 24 hours. The underlying transactions are typically weeks older — see each row's transaction date and lag.",
  form4_filings_24h: "Form 4 filings accepted by EDGAR in the last 24 hours.",
  high_priority_signals: "Companies with Research Priority at or above 85.",
};

/** Turns a reason_code into something a person can act on. */
function explain(code: string): string {
  const phase = code.match(/phase_(\d+)/)?.[1];
  if (code.startsWith("scoring")) return `Scoring lands in Phase ${phase}`;
  if (code.startsWith("congressional")) return `Congress ingest lands in Phase ${phase}`;
  if (code.startsWith("macro")) return `Macro ingest lands in Phase ${phase}`;
  return code.replace(/_/g, " ");
}

export function KpiStrip() {
  const [cards, setCards] = useState<KpiCard[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    fetchEnvelope<KpiCard[]>("/dashboard/kpis")
      .then((body) => ("data" in body ? setCards(body.data) : setFailed(true)))
      .catch(() => setFailed(true));
  }, []);

  if (failed) {
    return (
      <div
        className="rounded-panel p-4 text-body"
        style={{
          background: "var(--bg-panel)",
          border: "var(--border-width) solid var(--border)",
          color: "var(--negative)",
        }}
      >
        Could not reach the local API. Start it with{" "}
        <span className="mono">uv run uvicorn imt.api.main:app --port 8000</span>.
      </div>
    );
  }

  const items = cards ?? new Array(6).fill(null);

  return (
    <div className="grid gap-3" style={{ gridTemplateColumns: "repeat(6, minmax(0, 1fr))" }}>
      {items.map((card: KpiCard | null, i: number) => (
        <div
          key={card?.key ?? i}
          className="rounded-panel p-4"
          style={{
            background: "var(--bg-panel)",
            border: "var(--border-width) solid var(--border)",
            minHeight: 92,
          }}
          title={card ? TOOLTIP[card.key] : undefined}
        >
          {card === null ? (
            <div
              aria-hidden
              className="animate-pulse rounded-control"
              style={{ height: 52, background: "var(--bg-inset)" }}
            />
          ) : (
            <>
              <div className="panel-label">{card.label}</div>
              {card.value === null ? (
                <div className="mt-2 text-caption" style={{ color: "var(--text-muted)" }}>
                  {card.reason_code ? explain(card.reason_code) : "Not available"}
                </div>
              ) : (
                <div
                  className="mono mt-1"
                  style={{ fontSize: "var(--text-kpi)", color: ACCENT[card.key] }}
                >
                  {card.value}
                </div>
              )}
            </>
          )}
        </div>
      ))}
    </div>
  );
}
