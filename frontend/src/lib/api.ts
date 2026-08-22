/* Typed access to the local API. docs/API_CONTRACT.md.
 *
 * The frontend FORMATS; it never CALCULATES (CLAUDE.md non-negotiable #8).
 * Every percentage, ratio, delta, and lag is computed in Python and returned
 * by the API, so there is exactly one source of truth per figure. If you find
 * yourself writing arithmetic in this directory, the endpoint is missing a
 * field.
 *
 * Response types come from src/lib/api.generated.ts, produced by
 * `npm run types:generate` against the FastAPI schema. Hand-written response
 * interfaces are forbidden -- a drifted type is how a "% of float" label
 * sneaks back in after being removed.
 */
import type { PanelState } from "@/components/Panel";

export interface SourceState {
  id: string;
  status: "current" | "delayed" | "stale" | "unavailable" | "failed";
  last_success: string | null;
  reason: string | null;
}

export interface Meta {
  as_of: string | null;
  generated_at: string;
  data_quality: number | null;
  sources: SourceState[];
  weights_version: string | null;
  normalization: string | null;
  coverage: { categories_available: number; categories_total: number } | null;
  next_cursor: string | null;
}

export interface Envelope<T> {
  data: T;
  meta: Meta;
}

export interface ErrorEnvelope {
  error: {
    code: string;
    message: string;
    retry_at: string | null;
    affected_panels: string[];
  };
}

const BASE = "/api/v1";

export async function fetchEnvelope<T>(path: string): Promise<Envelope<T> | ErrorEnvelope> {
  const response = await fetch(`${BASE}${path}`, { cache: "no-store" });
  const body = await response.json();
  return body as Envelope<T> | ErrorEnvelope;
}

function isError(body: unknown): body is ErrorEnvelope {
  return typeof body === "object" && body !== null && "error" in body;
}

/* Maps an envelope onto the panel state union. Panels never construct the
 * union themselves -- that is what makes the four states impossible to skip
 * (UI_SPEC §4.10). */
export function toPanelState<T>(
  body: Envelope<T> | ErrorEnvelope,
  options: { emptyMessage: string; emptyAction?: string; isEmpty?: (data: T) => boolean },
): PanelState<T> {
  if (isError(body)) {
    return {
      kind: "failed",
      message: body.error.message,
      retryAt: body.error.retry_at ?? undefined,
      affected: body.error.affected_panels,
    };
  }

  const empty = options.isEmpty
    ? options.isEmpty(body.data)
    : Array.isArray(body.data) && body.data.length === 0;
  if (empty) {
    return { kind: "empty", message: options.emptyMessage, action: options.emptyAction };
  }

  const stale = body.meta.sources.find((s) => s.status === "stale" || s.status === "delayed");
  if (stale) {
    return {
      kind: "stale",
      data: body.data,
      sourceId: stale.id,
      lastSuccess: stale.last_success ?? "never",
      asOf: body.meta.as_of ?? "unknown",
    };
  }

  return { kind: "ready", data: body.data };
}

/** Worst source status, for the top bar dot. Computed here rather than in a
 *  component so every consumer agrees on what "worst" means. */
export function worstStatus(sources: SourceState[]): SourceState["status"] {
  const order: SourceState["status"][] = ["failed", "unavailable", "stale", "delayed", "current"];
  for (const status of order) {
    if (sources.some((s) => s.status === status)) return status;
  }
  return "current";
}
