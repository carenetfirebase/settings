/* Congressional Trading. docs/UI_SPEC.md §4.7, correction #2.
 *
 * The caption states how much older the underlying transactions are than the
 * disclosures, computed from the data rather than hardcoded. This is the panel
 * where the disclosure lag matters most: everything shown here is grouped BY
 * DISCLOSURE DATE, and without the caption a "30 day" window reads as thirty
 * days of trading activity when it is really thirty days of paperwork about
 * trades that happened weeks earlier.
 */
"use client";

import { useEffect, useState } from "react";
import { Panel, type PanelState } from "@/components/Panel";
import { fetchEnvelope, toPanelState } from "@/lib/api";

interface Slice {
  label: string;
  count: number;
  pct: number;
}

interface CongressSummary {
  total_trades: number;
  slices: Slice[];
  average_disclosure_lag_days: number | null;
  max_disclosure_lag_days: number | null;
  resolved_to_company: number;
  unresolved: number;
  period: string;
}

/* Keys match the vocabulary the API returns: purchase / sale / exchange /
 * other. Not buy / sell -- those are banned copy (UI_SPEC §5) and would be
 * rendered verbatim in this legend.
 *
 * Green and red here mean direction of the disclosed transaction, which is
 * the one place UI_SPEC's semantic rule permits it: a purchase is not a
 * recommendation, it is what the filing says happened. */
const SLICE_COLOUR: Record<string, string> = {
  purchase: "var(--positive)",
  sale: "var(--negative)",
  exchange: "var(--info)",
  other: "var(--text-muted)",
};

function Donut({ slices, total }: { slices: Slice[]; total: number }) {
  const size = 132;
  const radius = size / 2 - 10;
  const circumference = 2 * Math.PI * radius;
  let offset = 0;

  return (
    <div className="relative" style={{ width: size, height: size }}>
      <svg width={size} height={size} role="img" aria-label={`${total} disclosed trades`}>
        <g transform={`rotate(-90 ${size / 2} ${size / 2})`}>
          {slices.map((slice) => {
            const length = (slice.pct / 100) * circumference;
            const dash = `${length} ${circumference - length}`;
            const element = (
              <circle
                key={slice.label}
                cx={size / 2}
                cy={size / 2}
                r={radius}
                fill="none"
                strokeWidth={12}
                stroke={SLICE_COLOUR[slice.label] ?? "var(--text-muted)"}
                strokeDasharray={dash}
                strokeDashoffset={-offset}
              />
            );
            offset += length;
            return element;
          })}
        </g>
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="mono" style={{ fontSize: "var(--text-value)" }}>
          {total}
        </span>
        <span className="text-caption" style={{ color: "var(--text-muted)" }}>
          disclosed
        </span>
      </div>
    </div>
  );
}

export function CongressPanel({ period = "30d" }: { period?: string }) {
  const [state, setState] = useState<PanelState<CongressSummary>>({ kind: "loading" });

  useEffect(() => {
    fetchEnvelope<CongressSummary>(`/congress/summary?period=${period}`)
      .then((body) =>
        setState(
          toPanelState(body, {
            emptyMessage: "No congressional disclosures in this window.",
            emptyAction: "imt ingest congress --from-csv <path>",
            isEmpty: (data) => data.total_trades === 0,
          }),
        ),
      )
      .catch((error: Error) => setState({ kind: "failed", message: error.message }));
  }, [period]);

  return (
    <Panel
      title={`Congressional Trading (${period.toUpperCase()})`}
      state={state}
      skeletonHeight={200}
    >
      {(data) => (
        <>
          <div className="flex items-center gap-4">
            <Donut slices={data.slices} total={data.total_trades} />
            <ul className="m-0 flex-1 list-none p-0">
              {data.slices.map((slice) => (
                <li key={slice.label} className="flex items-center justify-between py-1">
                  <span className="flex items-center gap-2 text-caption">
                    <span
                      aria-hidden
                      className="rounded-full"
                      style={{
                        width: 8,
                        height: 8,
                        background: SLICE_COLOUR[slice.label] ?? "var(--text-muted)",
                      }}
                    />
                    <span style={{ color: "var(--text-secondary)" }}>{slice.label}</span>
                  </span>
                  <span className="mono text-caption">
                    {slice.count} · {slice.pct.toFixed(0)}%
                  </span>
                </li>
              ))}
            </ul>
          </div>

          {/* Computed, never hardcoded (UI_SPEC §4.7). */}
          <p className="mt-3 mb-0 text-caption" style={{ color: "var(--text-muted)" }}>
            By disclosure date.{" "}
            {data.average_disclosure_lag_days === null
              ? "No lag figure yet."
              : `Underlying transactions average ${data.average_disclosure_lag_days.toFixed(
                  0,
                )}d older` +
                (data.max_disclosure_lag_days
                  ? `, up to ${data.max_disclosure_lag_days}d.`
                  : ".")}{" "}
            {data.unresolved > 0
              ? `${data.unresolved} of ${data.total_trades} could not be matched to a listed company and are excluded from scores.`
              : ""}
          </p>
        </>
      )}
    </Panel>
  );
}
