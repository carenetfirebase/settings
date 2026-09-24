import { useCallback, useEffect, useState } from "react";

import { ApiError, getJson } from "./client";

export interface ApiState<T> {
  data: T | undefined;
  error: ApiError | undefined;
  /** True only until the first response; refetches keep showing old data. */
  loading: boolean;
  /** True while any request is in flight, including refetches. */
  refreshing: boolean;
  reload: () => void;
}

/**
 * Fetch a GET endpoint. Pass `null` to skip (e.g. no ticker chosen yet).
 *
 * On refetch the previous data stays on screen, so a page never flashes to an
 * empty skeleton and back.
 */
export function useApi<T>(path: string | null): ApiState<T> {
  const [data, setData] = useState<T>();
  const [error, setError] = useState<ApiError>();
  const [inFlight, setInFlight] = useState(path !== null);
  const [generation, setGeneration] = useState(0);

  useEffect(() => {
    if (path === null) {
      setInFlight(false);
      return;
    }
    const controller = new AbortController();
    setInFlight(true);
    getJson<T>(path, controller.signal)
      .then((result) => {
        setData(result);
        setError(undefined);
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        setError(err instanceof ApiError ? err : new ApiError(-1, String(err), path));
      })
      .finally(() => {
        if (!controller.signal.aborted) setInFlight(false);
      });
    return () => controller.abort();
  }, [path, generation]);

  const reload = useCallback(() => setGeneration((g) => g + 1), []);

  return {
    data,
    error,
    loading: inFlight && data === undefined && error === undefined,
    refreshing: inFlight,
    reload,
  };
}
