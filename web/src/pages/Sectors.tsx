import { paths } from "../api/client";
import type { SectorsResponse } from "../api/types";
import { useApi } from "../api/useApi";
import { PageHead, Panel } from "../components/Panel";
import { DivergingBar } from "../components/SignalBits";
import { ApiView, Empty } from "../components/States";
import { MISSING, fmtDate, fmtNumber, fmtPct, isNum } from "../lib/format";

/**
 * Sector leadership: each sector fund's 12-month return, skipping the latest
 * month, relative to the S&P 500 proxy. This is the sector half of the
 * relative-strength input, so it is scored.
 */
export function Sectors() {
  const sectors = useApi<SectorsResponse>(paths.sectors());

  return (
    <>
      <PageHead crumb="Markets · scored" title="Sectors & Rotation">
        Sectors ranked by 12-month momentum skipping the latest month, relative to the S&amp;P 500.
        A stock's sector rank is half of its relative-strength score. 1- and 3-month columns are
        shown for context only.
      </PageHead>
      <ApiView state={sectors}>
        {(data) => {
          const max = Math.max(0, ...data.sectors.map((s) => Math.abs(s.relative_12_1 ?? 0)));
          const any = data.sectors.some((s) => isNum(s.momentum_12_1));
          return (
            <>
              {data.warnings.map((w) => (
                <div key={w} className="banner warn">
                  {w}
                </div>
              ))}
              <Panel title={`Relative to ${data.benchmark}`} subtitle={`as of ${fmtDate(data.as_of)}`} bodyClassName="">
                {!any ? (
                  <Empty title="No sector history stored">
                    Run <code>invest universe seed</code>, then <code>invest ingest prices</code>, to load the sector funds.
                  </Empty>
                ) : (
                  <div className="table-wrap">
                    <table>
                      <thead>
                        <tr>
                          <th>Fund</th>
                          <th>Sector</th>
                          <th className="r">12-1 mo vs {data.benchmark}</th>
                          <th aria-hidden="true" />
                          <th className="r">Rank</th>
                          <th className="r">3 mo vs {data.benchmark}</th>
                          <th className="r">1 mo vs {data.benchmark}</th>
                        </tr>
                      </thead>
                      <tbody>
                        {data.sectors.map((s) => (
                          <tr key={s.ticker}>
                            <td className="strong">{s.ticker}</td>
                            <td>{s.sector ?? MISSING}</td>
                            <td className={`r ${isNum(s.relative_12_1) ? (s.relative_12_1 >= 0 ? "up" : "down") : ""}`}>
                              {isNum(s.relative_12_1) ? `${s.relative_12_1 >= 0 ? "▲" : "▼"} ${fmtPct(s.relative_12_1, 1, true)}` : MISSING}
                            </td>
                            <td>
                              <DivergingBar value={s.relative_12_1} max={max} />
                            </td>
                            <td className="r">{isNum(s.percentile) ? `${fmtNumber(s.percentile, 0)}th` : MISSING}</td>
                            <td className="r muted">{fmtPct(s.relative_3m, 1, true)}</td>
                            <td className="r muted">{fmtPct(s.relative_1m, 1, true)}</td>
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
