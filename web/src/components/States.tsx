import type { ReactNode } from "react";

import type { ApiError } from "../api/client";
import type { ApiState } from "../api/useApi";

export function Loading({ label = "Loading…" }: { label?: string }) {
  return (
    <div className="state" role="status">
      {label}
    </div>
  );
}

export function ErrorState({ error, onRetry }: { error: ApiError; onRetry?: () => void }) {
  let title = "Something went wrong";
  if (error.unreachable) title = "The research API is not running";
  else if (error.status === 404) title = "Not found";
  else if (error.status === 503) title = "The database is unreachable";

  return (
    <div className="state" role="alert">
      <strong>{title}</strong>
      {error.unreachable ? (
        <p>
          Start it with <code>invest serve</code>, then try again.
        </p>
      ) : (
        <p>{error.message}</p>
      )}
      {onRetry && (
        <button className="icon-button" type="button" onClick={onRetry}>
          Try again
        </button>
      )}
    </div>
  );
}

export function Empty({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="state">
      <strong>{title}</strong>
      {children && <div>{children}</div>}
    </div>
  );
}

/**
 * Render an API result: a loading line, an error with a retry, or the data.
 * While a refetch is in flight the previous data stays visible.
 */
export function ApiView<T>({
  state,
  children,
  loadingLabel,
}: {
  state: ApiState<T>;
  children: (data: T) => ReactNode;
  loadingLabel?: string;
}) {
  if (state.data !== undefined) return <>{children(state.data)}</>;
  if (state.error) return <ErrorState error={state.error} onRetry={state.reload} />;
  return <Loading label={loadingLabel} />;
}
