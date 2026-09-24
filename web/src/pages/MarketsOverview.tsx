import { useState } from "react";
import { Link } from "react-router";

import { paths } from "../api/client";
import type { UniverseResponse } from "../api/types";
import { useApi } from "../api/useApi";
import { PageHead, Panel } from "../components/Panel";
import { ApiView, Empty } from "../components/States";
import { MISSING, humanize } from "../lib/format";

const ALL = "All sectors";

export function MarketsOverview() {
  const universe = useApi<UniverseResponse>(paths.universe());
  const [sector, setSector] = useState(ALL);

  const sectors = universe.data
    ? [ALL, ...new Set(universe.data.securities.map((s) => s.sector ?? "Unclassified"))].sort((a, b) =>
        a === ALL ? -1 : b === ALL ? 1 : a.localeCompare(b),
      )
    : [ALL];

  return (
    <>
      <PageHead
        crumb="Markets"
        title="Overview"
        aside={
          <label>
            <span className="visually-hidden">Filter by sector</span>
            <select className="select" value={sector} onChange={(e) => setSector(e.target.value)}>
              {sectors.map((s) => (
                <option key={s}>{s}</option>
              ))}
            </select>
          </label>
        }
      >
        Every symbol the platform tracks. Relative-strength columns arrive with the V1 data feed.
      </PageHead>

      <ApiView state={universe}>
        {(data) => {
          const rows = data.securities.filter(
            (s) => sector === ALL || (s.sector ?? "Unclassified") === sector,
          );
          return (
            <>
              {data.meta.note && <div className="banner warn">{data.meta.note}</div>}
              <Panel title="Research universe" subtitle={`${rows.length} of ${data.count}`} bodyClassName="">
                {rows.length === 0 ? (
                  <Empty title="Nothing here">Run <code>invest bootstrap</code> to seed the universe.</Empty>
                ) : (
                  <div className="table-wrap">
                    <table>
                      <thead>
                        <tr>
                          <th>Symbol</th>
                          <th>Name</th>
                          <th>Sector</th>
                          <th>Exchange</th>
                          <th>CIK</th>
                          <th>Data status</th>
                        </tr>
                      </thead>
                      <tbody>
                        {rows.map((s) => (
                          <tr key={s.ticker}>
                            <td>
                              <Link to={`/research/${s.ticker}`}>{s.ticker}</Link>
                            </td>
                            <td>{s.name}</td>
                            <td>{s.sector ?? MISSING}</td>
                            <td>{s.exchange ?? MISSING}</td>
                            <td className="num">{s.cik ?? MISSING}</td>
                            <td>
                              {s.data_quality_flag === "ok" ? (
                                <span className="chip good">✓ verified</span>
                              ) : (
                                <span className="chip warn">! {humanize(s.data_quality_flag)}</span>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </Panel>
            </>
          );
        }}
      </ApiView>
    </>
  );
}
