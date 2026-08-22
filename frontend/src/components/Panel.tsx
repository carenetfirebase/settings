/* The four panel states, implemented once. docs/UI_SPEC.md §4.10.
 *
 * The state is a discriminated union with no ready-only form, so "a panel with
 * only a happy path" is a type error rather than a code-review note. A panel
 * that has not thought about staleness cannot be constructed.
 *
 * Stale never blanks a panel: it renders the data it has under an amber strip
 * naming the source and the age. Hiding stale figures is worse than showing
 * them labelled, because the user cannot tell the difference between "no
 * events" and "we stopped looking four days ago".
 */
import type { ReactNode } from "react";

export type PanelState<T> =
  | { kind: "loading" }
  | { kind: "empty"; message: string; action?: string }
  | { kind: "stale"; data: T; sourceId: string; lastSuccess: string; asOf: string }
  | { kind: "failed"; message: string; retryAt?: string; affected?: string[] }
  | { kind: "ready"; data: T };

export interface PanelProps<T> {
  title: string;
  caption?: string;
  state: PanelState<T>;
  children: (data: T) => ReactNode;
  /** Height of the loading skeleton. Must match the panel's real height so
   *  the layout does not jump when data arrives (UI_SPEC §4.10). */
  skeletonHeight?: number;
}

function Header({ title, caption }: { title: string; caption?: string }) {
  return (
    <div className="mb-3">
      <h2 className="panel-label m-0">{title}</h2>
      {caption ? <p className="text-caption text-muted mt-1 mb-0">{caption}</p> : null}
    </div>
  );
}

function StaleStrip({
  sourceId,
  lastSuccess,
  asOf,
}: {
  sourceId: string;
  lastSuccess: string;
  asOf: string;
}) {
  return (
    <div
      role="status"
      className="mb-3 rounded-control px-3 py-2 text-caption"
      style={{ background: "color-mix(in srgb, var(--warning) 12%, transparent)" }}
    >
      <span style={{ color: "var(--warning)" }}>
        {sourceId} last succeeded {lastSuccess}. Figures below are from {asOf}.
      </span>
    </div>
  );
}

export function Panel<T>({ title, caption, state, children, skeletonHeight = 160 }: PanelProps<T>) {
  return (
    <section
      className="rounded-panel p-4"
      style={{
        background: "var(--bg-panel)",
        border: "var(--border-width) solid var(--border)",
      }}
      aria-busy={state.kind === "loading"}
    >
      <Header title={title} caption={caption} />

      {state.kind === "loading" && (
        <div
          aria-hidden
          className="animate-pulse rounded-control"
          style={{ height: skeletonHeight, background: "var(--bg-inset)" }}
        />
      )}

      {state.kind === "empty" && (
        <div className="text-body text-secondary">
          <p className="m-0">{state.message}</p>
          {/* An empty state states why it is empty and what fills it.
           *  "No data" is not an acceptable empty state (UI_SPEC §4.10). */}
          {state.action ? (
            <p className="mt-2 mb-0 text-caption text-muted mono">{state.action}</p>
          ) : null}
        </div>
      )}

      {state.kind === "failed" && (
        <div className="text-body" role="alert">
          <p className="m-0" style={{ color: "var(--negative)" }}>
            {state.message}
          </p>
          {state.retryAt ? (
            <p className="mt-2 mb-0 text-caption text-muted">Retrying at {state.retryAt}.</p>
          ) : null}
          {state.affected?.length ? (
            <p className="mt-1 mb-0 text-caption text-muted">
              Excluded from scores: {state.affected.join(", ")}.
            </p>
          ) : null}
        </div>
      )}

      {state.kind === "stale" && (
        <>
          <StaleStrip
            sourceId={state.sourceId}
            lastSuccess={state.lastSuccess}
            asOf={state.asOf}
          />
          {children(state.data)}
        </>
      )}

      {state.kind === "ready" && children(state.data)}
    </section>
  );
}
