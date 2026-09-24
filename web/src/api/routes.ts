/**
 * Top-level paths served by the research API (`invest serve`).
 *
 * The site and the API share one origin in production, so the client calls
 * these paths directly. The Vite dev server imports this list to proxy the
 * same paths to the API, which keeps the two from drifting apart.
 */
export const API_PREFIXES = [
  "/health",
  "/universe",
  "/securities",
  "/snapshots",
  "/conflicts",
  "/regime",
  "/stats",
  "/signals",
  "/markets",
  "/lab",
] as const;

export const DEFAULT_API_ORIGIN = "http://127.0.0.1:8000";
