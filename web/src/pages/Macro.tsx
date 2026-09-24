import { paths } from "../api/client";
import type { RegimeResponse } from "../api/types";
import { useApi } from "../api/useApi";
import { REGIME_TONE } from "../components/Layout";
import { Kpi, PageHead, Panel } from "../components/Panel";
import { ApiView, Empty } from "../components/States";
import { MISSING, direction, fmtDate, fmtNumber, fmtPct, humanize } from "../lib/format";

export function Macro() {
  const regime = useApi<RegimeResponse>(paths.regime());

  return (
    <>
      <PageHead crumb="Markets · context" title="Macro & Rates">
        Named indicators with conventional thresholds. This is context for a person reading the
        market: it never moves a score, because a dozen recessions cannot validate a timing rule.
      </PageHead>

      <ApiView state={regime}>
        {(data) => {
          const tone = REGIME_TONE[data.regime];
          return (
            <>
              <div className="grid kpis">
                <Kpi
                  label="Regime"
                  hint="context"
                  value={<span className={tone === "good" ? "up" : tone === "bad" ? "down" : undefined}>{humanize(data.regime)}</span>}
                  foot={data.reliable ? "Enough signals to name a regime" : "Too few signals to be reliable"}
                />
                <Kpi label="Risk score" value={fmtNumber(data.risk_score, 2, true)} foot="Mean direction, −1 (risk-off) to +1 (risk-on)" />
                <Kpi label="Signal coverage" value={fmtPct(data.coverage, 0)} foot={`${data.signals.filter((s) => s.direction !== null).length} of ${data.signals.length} signals available`} />
                <Kpi label="As of" value={<span style={{ fontSize: 18 }}>{fmtDate(data.meta.as_of)}</span>} foot="Point-in-time: vintages known on this date" />
              </div>

              <div className="banner">{data.note}</div>

              <Panel title="Signals" subtitle="each with its published threshold" bodyClassName="">
                {data.signals.length === 0 ? (
                  <Empty title="No macro data stored">
                    Run <code>invest ingest macro</code> (needs a free FRED key).
                  </Empty>
                ) : (
                  <div className="table-wrap">
                    <table>
                      <thead>
                        <tr>
                          <th>Signal</th>
                          <th className="r">Reading</th>
                          <th>Direction</th>
                          <th>What it means</th>
                        </tr>
                      </thead>
                      <tbody>
                        {data.signals.map((s) => {
                          const d = direction(s.direction);
                          return (
                            <tr key={s.name}>
                              <td className="strong">{humanize(s.name)}</td>
                              <td className="r">{fmtNumber(s.value, 2)}</td>
                              <td className={d.tone === "flat" ? "muted" : d.tone}>
                                {s.direction === null
                                  ? MISSING
                                  : `${d.glyph} ${d.tone === "up" ? "risk-on" : d.tone === "down" ? "risk-off" : "neutral"}`}
                              </td>
                              <td>{s.unavailable_reason ? <span className="muted">{s.unavailable_reason}</span> : s.detail}</td>
                            </tr>
                          );
                        })}
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
