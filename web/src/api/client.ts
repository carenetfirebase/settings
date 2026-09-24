/**
 * The one place the site talks to the research API.
 *
 * Every endpoint is a GET and every data endpoint accepts `as_of`, mirroring
 * the API's own contract. Errors carry the API's `detail` text unchanged, so
 * the page can say exactly what went wrong instead of a generic failure.
 */

export class ApiError extends Error {
  readonly status: number;
  readonly path: string;

  constructor(status: number, message: string, path: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.path = path;
  }

  /** True when no response arrived at all: the API is not running. */
  get unreachable(): boolean {
    return this.status === 0;
  }
}

export const UNREACHABLE_MESSAGE =
  "The research API is not reachable. Start it with `invest serve`, then reload.";

type QueryValue = string | number | boolean | null | undefined | readonly (string | number)[];

/** Build `path?query`, dropping empty values and repeating array keys. */
export function withQuery(path: string, query: Record<string, QueryValue> = {}): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value === null || value === undefined || value === "") continue;
    if (Array.isArray(value)) {
      for (const item of value) params.append(key, String(item));
    } else {
      params.append(key, String(value));
    }
  }
  const qs = params.toString();
  return qs ? `${path}?${qs}` : path;
}

export async function getJson<T>(path: string, signal?: AbortSignal): Promise<T> {
  let response: Response;
  try {
    response = await fetch(path, { signal, headers: { Accept: "application/json" } });
  } catch (error) {
    if (signal?.aborted) throw error;
    throw new ApiError(0, UNREACHABLE_MESSAGE, path);
  }

  if (!response.ok) {
    let detail = `${response.status} ${response.statusText}`.trim();
    try {
      const body: unknown = await response.json();
      if (body && typeof body === "object" && "detail" in body) {
        const value = (body as { detail: unknown }).detail;
        if (typeof value === "string") detail = value;
      }
    } catch {
      // Not JSON (e.g. a proxy error page): keep the status line.
    }
    throw new ApiError(response.status, detail, path);
  }

  return (await response.json()) as T;
}

const enc = encodeURIComponent;

/** Path builders for every endpoint the site uses. */
export const paths = {
  health: () => "/health",
  universe: () => "/universe",
  stats: () => "/stats",
  regime: (asOf?: string) => withQuery("/regime", { as_of: asOf }),
  conflicts: (query: { ticker?: string; severity?: string; limit?: number } = {}) =>
    withQuery("/conflicts", query),
  snapshots: (query: { ticker?: string; limit?: number } = {}) => withQuery("/snapshots", query),
  security: (ticker: string) => `/securities/${enc(ticker)}`,
  prices: (ticker: string, query: { limit?: number; as_of?: string } = {}) =>
    withQuery(`/securities/${enc(ticker)}/prices`, query),
  fundamentals: (ticker: string, query: { years?: number; as_of?: string } = {}) =>
    withQuery(`/securities/${enc(ticker)}/fundamentals`, query),
  analysis: (ticker: string, asOf?: string) =>
    withQuery(`/securities/${enc(ticker)}/analysis`, { as_of: asOf }),
  report: (ticker: string, asOf?: string) =>
    withQuery(`/securities/${enc(ticker)}/report`, { as_of: asOf }),
  insider: (ticker: string, query: { lookback?: number; as_of?: string } = {}) =>
    withQuery(`/securities/${enc(ticker)}/insider`, query),
  disclosures: (ticker: string, query: { lookback?: number; as_of?: string } = {}) =>
    withQuery(`/securities/${enc(ticker)}/disclosures`, query),
};
