import { Link } from "react-router";

import { paths } from "../api/client";
import type {
  ConflictsResponse,
  GateResponse,
  RegimeResponse,
  ScanResponse,
  SnapshotsResponse,
  UniverseResponse,
} from "../api/types";
import { useApi } from "../api/useApi";
import { REGIME_TONE } from "../components/Layout";
import { Kpi, PageHead, Panel } from "../components/Panel";
import { CheckChip } from "../components/SignalBits";
import { ApiView, Empty } from "../components/States";
import { MISSING, direction, fmtDate, fmtNumber, fmtPct, humanize } from "../lib/format";
import { ALL_PAGES, STATUS_LABEL } from "../siteMap";

export function CommandCenter() {
  const regime = useApi<RegimeResponse>(paths.regime());
  const universe = useApi<UniverseResponse>(paths.universe());
  const conflicts = useApi<ConflictsResponse>(paths.conflicts({ limit: 1000 }));
  const snapshots = useApi<SnapshotsResponse>(paths.snapshots({ limit: 8 }));
  const gate = useApi<GateResponse>(paths.gate());
  const scan = useApi<ScanResponse>(paths.scan());
  const cards = scan.data?.signals.filter((s) => s.fired) ?? [];

  const unverified = universe.data?.securities.filter((s) => s.data_quality_flag !== "ok").length;
  const open = conflicts.data?.conflicts.filter((c) => !c.resolved);
  const critical = open?.filter((c) => c.severity === "critical").length;
  const upcoming = ALL_PAGES.filter((p) => p.status === "v1");

  return (
    <>
      <PageHead crumb="Today" title="Command Center">
        The trend gate, today's trade cards, the macro backdrop and data health. Portfolio heat and
        positions arrive with paper trading in V1.2.
      </PageHead>

      <div className="grid kpis">
        <Kpi
          label="Trend gate"
          hint="scored"
          value={
            gate.data ? (
              gate.data.gate.passed === true ? (
                <span className="up">▲ Open</span>
              ) : gate.data.gate.passed === false ? (
                <span className="down">▼ Closed</span>
              ) : (
                <span className="muted">? Unknown</span>
              )
            ) : gate.error ? MISSING : "…"
          }
          foot={
            gate.data
              ? gate.data.gate.passed === true
                ? `Longs allowed · risk at ${fmtPct(gate.data.volatility.multiplier, 0)} of base`
                : gate.data.gate.passed === false
                  ? "No new longs"
                  : gate.data.gate.detail
              : gate.error?.message
          }
        />
        <Kpi
          label="Trade cards today"
          value={scan.data ? cards.length : scan.error ? MISSING : "…"}
          foot={
            scan.data ? (
              <Link to="/signals/cards">
                {cards.length ? "Open the cards →" : "No setup passed every rule today"}
              </Link>
            ) : (
              scan.error?.message
            )
          }
        />
        <Kpi
          label="Macro regime"
          hint="context"
          value={
            regime.data ? (
              <span className={REGIME_TONE[regime.data.regime] === "good" ? "up" : REGIME_TONE[regime.data.regime] === "bad" ? "down" : undefined}>
                {humanize(regime.data.regime)}
              </span>
            ) : regime.error ? MISSING : "…"
          }
          foot={
            regime.data
              ? `Risk score ${fmtNumber(regime.data.risk_score, 2, true)} · coverage ${fmtPct(regime.data.coverage, 0)}`
              : regime.error?.message
          }
        />
        <Kpi
          label="Research universe"
          value={universe.data ? universe.data.count : universe.error ? MISSING : "…"}
          foot={
            unverified === undefined
              ? universe.error?.message
              : unverified === 0
                ? "Every CIK verified against EDGAR"
                : `${unverified} not yet verified against EDGAR`
          }
        />
        <Kpi
          label="Open data conflicts"
          value={open ? open.length : conflicts.error ? MISSING : "…"}
          foot={open ? (critical ? `${critical} critical` : "None critical") : conflicts.error?.message}
        />
        <Kpi
          label="Portfolio heat"
          hint="V1.2"
          planned
          value="No broker yet"
          foot="Arrives with paper trading"
        />
      </div>

      <div className="grid main-side">
        <div className="grid" style={{ alignContent: "start" }}>
          <Panel title="Today's trade cards" subtitle={<Link to="/signals/scanner">Full scan →</Link>} bodyClassName="">
            <ApiView state={scan} loadingLabel="Running the engine…">
              {(data) =>
                cards.length === 0 ? (
                  <Empty title="No trade cards today">
                    {data.gate.passed !== true
                      ? "The trend gate is not open, so no new longs are allowed."
                      : "Nothing in the universe is pulling back in an uptrend and passing every veto."}
                  </Empty>
                ) : (
                  <div className="table-wrap">
                    <table>
                      <thead>
                        <tr>
                          <th>Symbol</th>
                          <th className="r">Score</th>
                          <th className="r">Entry</th>
                          <th className="r">Stop</th>
                          <th className="r">Target</th>
                          <th>Checks</th>
                        </tr>
                      </thead>
                      <tbody>
                        {cards.map((s) => (
                          <tr key={s.ticker}>
                            <td>
                              <Link to="/signals/cards">{s.ticker}</Link>
                            </td>
                            <td className="r strong">{fmtNumber(s.final_score, 0)}</td>
                            <td className="r">{fmtNumber(s.levels?.entry)}</td>
                            <td className="r down">{fmtNumber(s.levels?.stop)}</td>
                            <td className="r up">{fmtNumber(s.levels?.target)}</td>
                            <td>
                              <div className="chips">
                                {s.checks
                                  .filter((c) => c.name === "quality_veto" || c.name === "earnings_veto")
                                  .map((c) => (
                                    <CheckChip key={c.name} check={c} />
                                  ))}
                              </div>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )
              }
            </ApiView>
          </Panel>

          <Panel title="Macro regime signals" subtitle="context · never moves a score">
            <ApiView state={regime}>
              {(data) =>
                data.signals.length === 0 ? (
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
                          <th>Detail</th>
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
                                {s.direction === null ? MISSING : `${d.glyph} ${d.tone === "up" ? "risk-on" : d.tone === "down" ? "risk-off" : "neutral"}`}
                              </td>
                              <td>{s.unavailable_reason ?? s.detail}</td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                )
              }
            </ApiView>
          </Panel>

          <Panel title="Recent research runs" subtitle={<Link to="/research">Open a symbol →</Link>}>
            <ApiView state={snapshots}>
              {(data) =>
                data.count === 0 ? (
                  <Empty title="No research runs saved yet">
                    Run <code>invest analyze AAPL</code> to score a symbol and save a snapshot.
                  </Empty>
                ) : (
                  <div className="table-wrap">
                    <table>
                      <thead>
                        <tr>
                          <th>Symbol</th>
                          <th>As of</th>
                          <th className="r">Quality</th>
                          <th className="r">Setup</th>
                          <th className="r">Confidence</th>
                        </tr>
                      </thead>
                      <tbody>
                        {data.snapshots.map((s) => (
                          <tr key={s.id}>
                            <td>{s.ticker ? <Link to={`/research/${s.ticker}`}>{s.ticker}</Link> : MISSING}</td>
                            <td>{fmtDate(s.as_of_date)}</td>
                            <td className="r">{fmtNumber(s.investment_quality_score, 0)}</td>
                            <td className="r">{fmtNumber(s.trade_setup_score, 0)}</td>
                            <td className="r">{fmtNumber(s.confidence_score, 0)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )
              }
            </ApiView>
          </Panel>
        </div>

        <div className="grid" style={{ alignContent: "start" }}>
          <Panel title="Universe" subtitle={<Link to="/markets">All →</Link>}>
            <ApiView state={universe}>
              {(data) =>
                data.count === 0 ? (
                  <Empty title="Universe is empty">
                    Run <code>invest bootstrap</code>.
                  </Empty>
                ) : (
                  <div className="chips">
                    {data.securities.map((s) => (
                      <Link
                        key={s.ticker}
                        to={`/research/${s.ticker}`}
                        className={`chip${s.data_quality_flag === "ok" ? "" : " warn"}`}
                        title={`${s.name}${s.data_quality_flag === "ok" ? "" : ` · ${humanize(s.data_quality_flag)}`}`}
                        style={{ textDecoration: "none" }}
                      >
                        {s.ticker}
                      </Link>
                    ))}
                  </div>
                )
              }
            </ApiView>
          </Panel>

          <Panel title="Still to build in V1" subtitle={`${upcoming.length} pages`}>
            <div className="table-wrap">
              <table>
                <tbody>
                  {upcoming.map((p) => (
                    <tr key={p.id}>
                      <td>
                        <Link to={p.path}>{p.title}</Link>
                      </td>
                      <td className="r">
                        <span className="status-tag">{STATUS_LABEL[p.status]}</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Panel>
        </div>
      </div>
    </>
  );
}
