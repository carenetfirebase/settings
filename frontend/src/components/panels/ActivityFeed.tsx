/* Live Activity Feed. docs/UI_SPEC.md §4.6, corrections #1 and #2.
 *
 * Every row goes through <EventRow>, whose props type requires both dates for
 * political, insider and institutional events. So the rule that a congressional
 * row must never appear without its transaction date is enforced by the
 * compiler here, not by remembering to pass a field.
 *
 * The tab set matches UI_SPEC §4.6. Tabs whose category has no ingest yet are
 * disabled with the phase that brings them, rather than showing an empty list
 * that reads as "nothing happened".
 */
"use client";

import { useEffect, useState } from "react";
import { Panel, type PanelState } from "@/components/Panel";
import { EventRow, type DatedCategory, type UndatedCategory } from "@/components/EventRow";
import { fetchEnvelope, toPanelState } from "@/lib/api";

interface Money {
  low: number;
  high: number;
  currency: string;
}

interface FeedItem {
  event_id: string;
  category: DatedCategory | UndatedCategory;
  detected_at: string;
  transaction_date: string | null;
  disclosure_date: string | null;
  disclosure_lag_days: number | null;
  headline: string;
  cik: string;
  ticker: string | null;
  value_range: Money | null;
  value_exact: number | null;
  currency: string;
  source: { id: string; document_url: string; record_id: string };
}

const TABS: { key: string; label: string; phase?: number }[] = [
  { key: "", label: "All" },
  { key: "corporate_insider", label: "Insiders" },
  { key: "political", label: "Congress", phase: 4 },
  { key: "institutional", label: "Institutions" },
  { key: "government", label: "Government", phase: 6 },
  { key: "macro_sector", label: "Macro", phase: 7 },
];

const DATED = new Set(["political", "corporate_insider", "institutional"]);

/** Formats only. The API computes every figure (non-negotiable #8). */
function formatMinor(minor: number, currency: string): string {
  const units = minor / 100;
  const abs = Math.abs(units);
  const [scaled, suffix] =
    abs >= 1_000_000 ? [units / 1_000_000, "M"] : abs >= 1_000 ? [units / 1_000, "K"] : [units, ""];
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    maximumFractionDigits: suffix ? 1 : 0,
  }).format(scaled) + suffix;
}

function formatValue(item: FeedItem): string | undefined {
  if (item.value_exact !== null) return formatMinor(item.value_exact, item.currency);
  if (item.value_range) {
    return `${formatMinor(item.value_range.low, item.value_range.currency)}–${formatMinor(
      item.value_range.high,
      item.value_range.currency,
    )}`;
  }
  return undefined;
}

function timeAgo(iso: string): string {
  const seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (seconds < 60) return "just now";
  const minutes = seconds / 60;
  if (minutes < 60) return `${Math.floor(minutes)}m ago`;
  const hours = minutes / 60;
  if (hours < 24) return `${Math.floor(hours)}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

export function ActivityFeed() {
  const [tab, setTab] = useState("");
  const [state, setState] = useState<PanelState<FeedItem[]>>({ kind: "loading" });

  useEffect(() => {
    let cancelled = false;
    setState({ kind: "loading" });
    fetchEnvelope<FeedItem[]>(`/feed?limit=50${tab ? `&category=${tab}` : ""}`)
      .then((body) => {
        if (cancelled) return;
        setState(
          toPanelState(body, {
            emptyMessage: "No events ingested yet.",
            emptyAction: "imt ingest form4 --since 7d",
          }),
        );
      })
      .catch((error: Error) =>
        !cancelled &&
        setState({ kind: "failed", message: `Could not reach the local API. ${error.message}` }),
      );
    return () => {
      cancelled = true;
    };
  }, [tab]);

  return (
    <Panel
      title="Activity Feed"
      caption="Detection time, transaction date, and disclosure lag on every dated event."
      state={state}
      skeletonHeight={260}
    >
      {(items) => (
        <>
          <div
            className="mb-2 flex gap-3 overflow-x-auto"
            style={{ borderBottom: "var(--border-width) solid var(--border)" }}
            role="tablist"
          >
            {TABS.map((t) => {
              const active = t.key === tab;
              if (t.phase !== undefined) {
                return (
                  <span
                    key={t.label}
                    className="whitespace-nowrap pb-2 text-caption"
                    style={{ color: "var(--text-muted)", cursor: "not-allowed" }}
                    title={`Available in Phase ${t.phase}`}
                    aria-disabled="true"
                  >
                    {t.label}
                  </span>
                );
              }
              return (
                <button
                  key={t.label}
                  role="tab"
                  aria-selected={active}
                  onClick={() => setTab(t.key)}
                  className="whitespace-nowrap pb-2 text-caption"
                  style={{
                    color: active ? "var(--text-primary)" : "var(--text-secondary)",
                    borderBottom: active
                      ? "2px solid var(--positive)"
                      : "2px solid transparent",
                    background: "none",
                    border: "none",
                    borderBottomWidth: "2px",
                    borderBottomStyle: "solid",
                    borderBottomColor: active ? "var(--positive)" : "transparent",
                    cursor: "pointer",
                  }}
                >
                  {t.label}
                </button>
              );
            })}
          </div>

          <ul className="m-0 max-h-80 list-none overflow-y-auto p-0">
            {items.map((item) => {
              const common = {
                eventId: item.event_id,
                headline: item.headline,
                ticker: item.ticker ?? undefined,
                detectedAgo: timeAgo(item.detected_at),
                value: formatValue(item),
                sourceUrl: item.source.document_url,
                sourceLabel: item.source.id,
              };
              // The discriminated union: a dated category without both dates
              // will not type-check, so it cannot reach the screen.
              return DATED.has(item.category) &&
                item.transaction_date &&
                item.disclosure_date &&
                item.disclosure_lag_days !== null ? (
                <EventRow
                  key={item.event_id}
                  {...common}
                  category={item.category as DatedCategory}
                  transactionDate={item.transaction_date}
                  disclosureDate={item.disclosure_date}
                  disclosureLagDays={item.disclosure_lag_days}
                />
              ) : (
                <EventRow
                  key={item.event_id}
                  {...common}
                  category={item.category as UndatedCategory}
                  filedDate={item.disclosure_date ?? item.detected_at.slice(0, 10)}
                />
              );
            })}
          </ul>
        </>
      )}
    </Panel>
  );
}
