import { useState } from "react";

import { paths } from "../api/client";
import type { ConflictsResponse, HealthResponse, StatsResponse } from "../api/types";
import { useApi } from "../api/useApi";
import { Kpi, PageHead, Panel } from "../components/Panel";
import { ApiView, Empty } from "../components/States";
import { MISSING, fmtDate, fmtNumber, humanize } from "../lib/format";

export function DataFeeds() {
  const stats = useApi<StatsResponse>(paths.stats());
  const health = useApi<HealthResponse>(paths.health());

  return (
    <>
      <PageHead crumb="System" title="Data Feeds">
        What is stored today. Per-feed freshness, delay and failover checks arrive with the V1 feeds.
      </PageHead>
      <div className="grid kpis">
        <Kpi
          label="API"
          value={health.data ? <span className="up">● Connected</span> : health.error ? <span className="down">● Offline</span> : "…"}
          foot={health.data ? `Version ${health.data.version} · database ${health.data.database}` : health.error?.message}
        />
        <Kpi
          label="Access"
          value={health.data ? (health.data.read_only ? "Read-only" : "Read-write") : MISSING}
          foot="Enforced by the database, not by convention"
        />
        <Kpi
          label="Stored rows"
          value={stats.data ? fmtNumber(Object.values(stats.data.tables).reduce((a, b) => a + b, 0), 0) : stats.error ? MISSING : "…"}
          foot={stats.data ? `${Object.keys(stats.data.tables).length} tables` : undefined}
        />
      </div>
      <Panel title="Rows per table" bodyClassName="">
        <ApiView state={stats}>
          {(s) => (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Table</th>
                    <th className="r">Rows</th>
                  </tr>
                </thead>
                <tbody>
                  {Object.entries(s.tables)
                    .sort(([a], [b]) => a.localeCompare(b))
                    .map(([table, rows]) => (
                      <tr key={table}>
                        <td className="strong">{table}</td>
                        <td className={`r${rows === 0 ? " muted" : ""}`}>{fmtNumber(rows, 0)}</td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
          )}
        </ApiView>
      </Panel>
    </>
  );
}

const SEVERITIES = ["all", "critical", "warning", "info"] as const;

export function DataQuality() {
  const [severity, setSeverity] = useState<(typeof SEVERITIES)[number]>("all");
  const conflicts = useApi<ConflictsResponse>(
    paths.conflicts({ limit: 500, severity: severity === "all" ? undefined : severity }),
  );

  return (
    <>
      <PageHead
        crumb="System"
        title="Data Quality"
        aside={
          <label>
            <span className="visually-hidden">Severity</span>
            <select className="select" value={severity} onChange={(e) => setSeverity(e.target.value as typeof severity)}>
              {SEVERITIES.map((s) => (
                <option key={s} value={s}>
                  {s === "all" ? "All severities" : humanize(s)}
                </option>
              ))}
            </select>
          </label>
        }
      >
        Everything the validation gate flagged. Bad data is quarantined and shown here, never
        silently dropped or patched.
      </PageHead>
      <Panel title="Validation conflicts" subtitle={conflicts.data ? `${conflicts.data.count} shown` : undefined} bodyClassName="">
        <ApiView state={conflicts}>
          {(c) =>
            c.count === 0 ? (
              <Empty title="No conflicts">The validation gate has nothing flagged at this severity.</Empty>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Detected</th>
                      <th>Severity</th>
                      <th>Type</th>
                      <th>Where</th>
                      <th className="r">Source A</th>
                      <th className="r">Source B</th>
                      <th>Detail</th>
                    </tr>
                  </thead>
                  <tbody>
                    {c.conflicts.map((x) => (
                      <tr key={x.id}>
                        <td>{fmtDate(x.detected_at)}</td>
                        <td>
                          <span className={`chip ${x.severity === "critical" ? "bad" : x.severity === "warning" ? "warn" : ""}`}>
                            {x.severity === "critical" ? "✕" : x.severity === "warning" ? "!" : "i"} {x.severity}
                          </span>
                          {x.resolved && <span className="chip good" style={{ marginLeft: 4 }}>✓ resolved</span>}
                        </td>
                        <td>{humanize(x.conflict_type)}</td>
                        <td>
                          {x.table_name}
                          {x.metric_name && <span className="muted"> · {x.metric_name}</span>}
                          {x.obs_date && <span className="muted"> · {fmtDate(x.obs_date)}</span>}
                        </td>
                        <td className="r">
                          {fmtNumber(x.value_a, 2)} <span className="muted">{x.source_a ?? ""}</span>
                        </td>
                        <td className="r">
                          {fmtNumber(x.value_b, 2)} <span className="muted">{x.source_b ?? ""}</span>
                        </td>
                        <td>{x.detail ?? MISSING}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )
          }
        </ApiView>
      </Panel>
    </>
  );
}
