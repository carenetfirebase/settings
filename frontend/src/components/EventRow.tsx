/* One row in the activity feed and the events timeline.
 * docs/UI_SPEC.md §4.6, corrections #1 and #2.
 *
 * CLAUDE.md non-negotiable #5: "Transaction date and disclosure date are
 * different fields and both are always shown. Any UI element implying a
 * congressional trade happened today when the PTR covers a six-week-old
 * transaction is a bug."
 *
 * That is enforced here by the type, not by discipline. For the three dated
 * categories the props are a discriminated union requiring both dates and the
 * lag; there is no way to construct a congressional row without them, so the
 * bug is a compile error.
 *
 * Time-ago always describes DETECTION -- when we saw it -- and never stands
 * alone. "6m ago" next to a 44-day-old transaction is the single failure this
 * whole system exists to avoid.
 */

export type DatedCategory = "political" | "corporate_insider" | "institutional";
export type UndatedCategory =
  | "government"
  | "corporate_event"
  | "fundamental"
  | "valuation"
  | "positioning"
  | "macro_sector"
  | "credit";

interface Common {
  eventId: string;
  headline: string;
  ticker?: string;
  detectedAgo: string;
  value?: string;
  sourceUrl: string;
  sourceLabel: string;
}

/* Both dates and the lag are required. Making any of them optional here is
 * how the rule quietly stops holding. */
export type EventRowProps =
  | (Common & {
      category: DatedCategory;
      transactionDate: string;
      disclosureDate: string;
      disclosureLagDays: number;
    })
  | (Common & { category: UndatedCategory; filedDate: string });

const CATEGORY_COLOUR: Record<DatedCategory | UndatedCategory, string> = {
  political: "var(--political)",
  corporate_insider: "var(--info)",
  institutional: "var(--info)",
  government: "var(--positive)",
  corporate_event: "var(--warning)",
  fundamental: "var(--text-secondary)",
  valuation: "var(--text-secondary)",
  positioning: "var(--text-secondary)",
  macro_sector: "var(--text-secondary)",
  credit: "var(--text-secondary)",
};

/** UI_SPEC correction #1: amber above 7 days, red above 30. */
function lagColour(days: number): string {
  if (days > 30) return "var(--negative)";
  if (days > 7) return "var(--warning)";
  return "var(--text-muted)";
}

export function EventRow(props: EventRowProps) {
  const { category, headline, ticker, detectedAgo, value, sourceUrl, sourceLabel } = props;

  return (
    <li
      className="flex gap-3 py-2"
      style={{ borderBottom: "var(--border-width) solid var(--border)" }}
    >
      <span
        aria-hidden
        className="mt-2 shrink-0 rounded-full"
        style={{ width: 6, height: 6, background: CATEGORY_COLOUR[category] }}
      />
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2">
          {ticker ? (
            <span className="mono text-body" style={{ color: "var(--info)" }}>
              {ticker}
            </span>
          ) : null}
          <span className="text-body truncate">{headline}</span>
          {value ? <span className="mono text-caption text-secondary">{value}</span> : null}
        </div>

        {/* The dates line. For dated categories this is mandatory. */}
        <div className="mt-1 flex flex-wrap gap-x-3 text-caption text-muted">
          <span className="mono">Detected {detectedAgo}</span>
          {"transactionDate" in props ? (
            <>
              <span className="mono">Txn {props.transactionDate}</span>
              <span className="mono">Disclosed {props.disclosureDate}</span>
              <span className="mono" style={{ color: lagColour(props.disclosureLagDays) }}>
                {props.disclosureLagDays}d lag
              </span>
            </>
          ) : (
            <span className="mono">Filed {props.filedDate}</span>
          )}
          <a
            href={sourceUrl}
            target="_blank"
            rel="noreferrer"
            className="underline"
            style={{ color: "var(--info)" }}
          >
            {sourceLabel}
          </a>
        </div>
      </div>
    </li>
  );
}
