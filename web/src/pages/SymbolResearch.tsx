import { useState } from "react";
import { Link, useParams } from "react-router";

import { paths } from "../api/client";
import type {
  AnalysisResponse,
  DisclosuresResponse,
  FundamentalsResponse,
  InsiderResponse,
  PriceResponse,
  ReportResponse,
  SecuritySummary,
  SnapshotsResponse,
  UniverseResponse,
} from "../api/types";
import { useApi } from "../api/useApi";
import { PageHead, Panel } from "../components/Panel";
import { PriceChart } from "../components/PriceChart";
import { ScoreCard } from "../components/ScoreCard";
import { ApiView, Empty } from "../components/States";
import {
  MISSING,
  direction,
  fmtCompact,
  fmtDate,
  fmtMoney,
  fmtNumber,
  fmtPct,
  humanize,
  isNum,
} from "../lib/format";

const TABS = ["Fundamentals", "Insiders", "Congress", "Report", "History"] as const;
type Tab = (typeof TABS)[number];

/** See docs/ENGINE_INPUTS.md, "Where the existing scores stand". */
const LEGACY_SETUP_NOTE =
  "Legacy research score: it includes RSI, MACD and 52-week position, which are not 10/10 inputs, so it never feeds a trade card. The Scanner uses the V1 signal score instead.";

/** Enough daily bars to draw a 200-day average across the visible range. */
const PRICE_BARS = 650;

export function SymbolResearch() {
  const { ticker } = useParams();
  return ticker ? <Symbol ticker={ticker.toUpperCase()} /> : <Picker />;
}

function Picker() {
  const universe = useApi<UniverseResponse>(paths.universe());
  return (
    <>
      <PageHead crumb="Research" title="Symbol Research">
        Pick a symbol, or type one in the search bar.
      </PageHead>
      <Panel>
        <ApiView state={universe}>
          {(data) =>
            data.count === 0 ? (
              <Empty title="Universe is empty">
                Run <code>invest bootstrap</code>.
              </Empty>
            ) : (
              <div className="chips">
                {data.securities.map((s) => (
                  <Link key={s.ticker} to={`/research/${s.ticker}`} className="chip" style={{ textDecoration: "none" }} title={s.name}>
                    <strong>{s.ticker}</strong>
                    <span className="muted">{s.name}</span>
                  </Link>
                ))}
              </div>
            )
          }
        </ApiView>
      </Panel>
    </>
  );
}

function Symbol({ ticker }: { ticker: string }) {
  const security = useApi<SecuritySummary>(paths.security(ticker));
  const [tab, setTab] = useState<Tab>("Fundamentals");

  return (
    <ApiView state={security} loadingLabel={`Loading ${ticker}…`}>
      {(s) => (
        <>
          <PageHead
            crumb="Research"
            title={
              <>
                {s.ticker} <span className="muted" style={{ fontWeight: 500, fontSize: 15 }}>{s.name}</span>
              </>
            }
            aside={
              <div className="chips">
                {s.exchange && <span className="chip">{s.exchange}</span>}
                {s.sector && <span className="chip">{s.sector}</span>}
                {s.data_quality_flag === "ok" ? (
                  <span className="chip good">✓ CIK verified</span>
                ) : (
                  <span className="chip warn">! {humanize(s.data_quality_flag)}</span>
                )}
              </div>
            }
          />
          <ChartPanel ticker={s.ticker} />
          <Scores ticker={s.ticker} />
          <div className="tabs" role="tablist" aria-label="Research sections">
            {TABS.map((t) => (
              <button key={t} type="button" role="tab" className="tab" aria-selected={tab === t} onClick={() => setTab(t)}>
                {t === "Congress" ? "Congress (firewalled)" : t}
              </button>
            ))}
          </div>
          <div role="tabpanel">
            {tab === "Fundamentals" && <Fundamentals ticker={s.ticker} />}
            {tab === "Insiders" && <Insiders ticker={s.ticker} />}
            {tab === "Congress" && <Congress ticker={s.ticker} />}
            {tab === "Report" && <Report ticker={s.ticker} />}
            {tab === "History" && <History ticker={s.ticker} />}
          </div>
        </>
      )}
    </ApiView>
  );
}

function ChartPanel({ ticker }: { ticker: string }) {
  const prices = useApi<PriceResponse>(paths.prices(ticker, { limit: PRICE_BARS }));
  const bars = prices.data?.bars ?? [];
  const last = [...bars].reverse().find((b) => isNum(b.close));
  const prev = last ? bars[bars.indexOf(last) - 1] : undefined;
  const change = last && prev && isNum(last.close) && isNum(prev.close) ? last.close - prev.close : null;
  const d = direction(change);

  return (
    <Panel
      title={
        <>
          Daily price{" "}
          {last && (
            <span className="num" style={{ marginLeft: 8 }}>
              {fmtNumber(last.close)}{" "}
              {isNum(change) && prev && isNum(prev.close) && (
                <span className={d.tone === "flat" ? "muted" : d.tone}>
                  {d.glyph} {fmtNumber(change, 2, true)} ({fmtPct(change / prev.close, 2, true)})
                </span>
              )}
            </span>
          )}
        </>
      }
      subtitle={last ? `Close ${fmtDate(last.obs_date)} · ${last.source}` : undefined}
      bodyClassName=""
    >
      <ApiView state={prices}>
        {(data) => (
          <>
            <PriceChart bars={data.bars} />
            <p className="muted" style={{ fontSize: 11.5, padding: "6px 14px 12px" }}>{data.adjustment_note}</p>
          </>
        )}
      </ApiView>
    </Panel>
  );
}

function Scores({ ticker }: { ticker: string }) {
  const analysis = useApi<AnalysisResponse>(paths.analysis(ticker));
  return (
    <ApiView state={analysis} loadingLabel="Scoring…">
      {(a) => {
        const scores = [a.investment_quality, a.trade_setup, a.confidence];
        // Each card already lists its own warnings; the banner adds only the rest.
        const onCards = new Set(scores.flatMap((s) => s.warnings));
        const extra = a.warnings.filter((w) => !onCards.has(w));
        return (
          <>
            <div className="grid" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))" }}>
              {scores.map((s) => (
                <ScoreCard key={s.name} score={s} note={s === a.trade_setup ? LEGACY_SETUP_NOTE : undefined} />
              ))}
            </div>
            {(extra.length > 0 || a.meta.note) && (
              <div className="banner">
                {a.meta.note && <div>{a.meta.note}</div>}
                {extra.length > 0 && (
                  <ul style={{ margin: "6px 0 0", paddingLeft: 18 }}>
                    {extra.map((w) => (
                      <li key={w}>{w}</li>
                    ))}
                  </ul>
                )}
              </div>
            )}
          </>
        );
      }}
    </ApiView>
  );
}

function Fundamentals({ ticker }: { ticker: string }) {
  const fundamentals = useApi<FundamentalsResponse>(paths.fundamentals(ticker, { years: 5 }));
  return (
    <Panel title="Annual fundamentals" subtitle="as filed with the SEC, restatement-aware" bodyClassName="">
      <ApiView state={fundamentals}>
        {(f) => {
          const metrics = Object.keys(f.series);
          const years = [...new Set(metrics.flatMap((m) => f.series[m]?.map((p) => p.fiscal_year) ?? []))]
            .filter((y): y is number => y !== null)
            .sort((a, b) => b - a);
          if (metrics.length === 0) {
            return (
              <Empty title="No fundamentals stored">
                Run <code>invest ingest fundamentals {ticker}</code>.
              </Empty>
            );
          }
          return (
            <>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Metric</th>
                      {years.map((y) => (
                        <th key={y} className="r">FY{y}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {metrics.map((m) => (
                      <tr key={m}>
                        <td className="strong">{humanize(m)}</td>
                        {years.map((y) => {
                          const point = f.series[m]?.find((p) => p.fiscal_year === y);
                          return (
                            <td key={y} className="r" title={point ? `Filed ${fmtDate(point.filed_date)} · ${point.form_type ?? ""} · ${point.unit}` : "Not reported"}>
                              {point ? (point.unit === "USD" ? fmtCompact(point.value) : fmtNumber(point.value, 2)) : MISSING}
                            </td>
                          );
                        })}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {f.metrics_missing.length > 0 && (
                <p className="muted" style={{ fontSize: 11.5, padding: "8px 12px 12px" }}>
                  Not found in filings: {f.metrics_missing.map(humanize).join(", ")}.
                </p>
              )}
            </>
          );
        }}
      </ApiView>
    </Panel>
  );
}

function Insiders({ ticker }: { ticker: string }) {
  const insider = useApi<InsiderResponse>(paths.insider(ticker, { lookback: 365 }));
  return (
    <Panel title="Insider activity" subtitle="Form 4 · last 365 days · by filing date" bodyClassName="">
      <ApiView state={insider}>
        {(i) => (
          <>
            <div className="panel-b" style={{ display: "grid", gap: 8 }}>
              <div className="chips">
                <span className="chip good">▲ {i.buys} open-market buys · {fmtMoney(i.buy_value, true)}</span>
                <span className="chip bad">▼ {i.sells} open-market sales · {fmtMoney(i.sell_value, true)}</span>
                <span className="chip">Net buy ratio {fmtNumber(i.net_buy_ratio, 2)}</span>
                <span className="chip">{i.total_filings} filings</span>
              </div>
              <p className="muted" style={{ fontSize: 11.5 }}>{i.interpretation_note}</p>
            </div>
            {i.transactions.length === 0 ? (
              <Empty title="No insider filings in this window" />
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Insider</th>
                      <th>Traded</th>
                      <th>Filed</th>
                      <th>Type</th>
                      <th className="r">Shares</th>
                      <th className="r">Price</th>
                    </tr>
                  </thead>
                  <tbody>
                    {i.transactions.map((t, idx) => (
                      <tr key={`${t.insider_name}-${t.transaction_date}-${idx}`}>
                        <td className="strong">
                          {t.insider_name}
                          {t.officer_title && <div className="muted" style={{ fontWeight: 400, fontSize: 11 }}>{t.officer_title}</div>}
                        </td>
                        <td>{fmtDate(t.transaction_date)}</td>
                        <td>
                          {fmtDate(t.filed_date)} <span className="muted">+{t.disclosure_lag_days}d</span>
                        </td>
                        <td>
                          {t.is_discretionary ? <strong style={{ color: "var(--ink-1)" }}>{t.code_meaning}</strong> : <span className="muted">{t.code_meaning}</span>}
                        </td>
                        <td className="r">{fmtNumber(t.shares, 0)}</td>
                        <td className="r">{fmtNumber(t.price_per_share, 2)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </>
        )}
      </ApiView>
    </Panel>
  );
}

function Congress({ ticker }: { ticker: string }) {
  const disclosures = useApi<DisclosuresResponse>(paths.disclosures(ticker, { lookback: 730 }));
  return (
    <Panel title="Congressional disclosures" subtitle="firewalled · 0 weight in every score" bodyClassName="">
      <ApiView state={disclosures}>
        {(d) => (
          <>
            <div className="panel-b">
              <div className="banner warn">
                <strong>Research context only.</strong> {d.firewall_note}
              </div>
            </div>
            {d.disclosures.length === 0 ? (
              <Empty title="No disclosures in the last two years" />
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Member</th>
                      <th>Type</th>
                      <th>Traded</th>
                      <th>Disclosed</th>
                      <th className="r">Amount range</th>
                    </tr>
                  </thead>
                  <tbody>
                    {d.disclosures.map((x, idx) => (
                      <tr key={`${x.politician_name}-${x.transaction_date}-${idx}`}>
                        <td className="strong">
                          {x.politician_name}
                          {x.chamber && <div className="muted" style={{ fontWeight: 400, fontSize: 11 }}>{x.chamber}</div>}
                        </td>
                        <td>{x.transaction_type ?? MISSING}</td>
                        <td>{fmtDate(x.transaction_date)}</td>
                        <td>
                          {fmtDate(x.disclosure_date)} <span className="muted">+{x.disclosure_lag_days}d</span>
                        </td>
                        <td className="r">
                          {fmtMoney(x.amount_range_low, true)} – {fmtMoney(x.amount_range_high, true)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </>
        )}
      </ApiView>
    </Panel>
  );
}

function Report({ ticker }: { ticker: string }) {
  const report = useApi<ReportResponse>(paths.report(ticker));
  return (
    <Panel title="Research report" subtitle="deterministic · not saved from here" bodyClassName="">
      <ApiView state={report} loadingLabel="Rendering report…">
        {(r) => <pre className="report">{r.report_text}</pre>}
      </ApiView>
    </Panel>
  );
}

function History({ ticker }: { ticker: string }) {
  const snapshots = useApi<SnapshotsResponse>(paths.snapshots({ ticker, limit: 100 }));
  return (
    <Panel title="Saved research runs" subtitle="immutable snapshots" bodyClassName="">
      <ApiView state={snapshots}>
        {(data) =>
          data.count === 0 ? (
            <Empty title="No saved runs for this symbol">
              Run <code>invest analyze {ticker}</code> to save one.
            </Empty>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Saved</th>
                    <th>As of</th>
                    <th>Model</th>
                    <th className="r">Quality</th>
                    <th className="r">Setup</th>
                    <th className="r">Confidence</th>
                  </tr>
                </thead>
                <tbody>
                  {data.snapshots.map((s) => (
                    <tr key={s.id}>
                      <td>{fmtDate(s.created_at)}</td>
                      <td>{fmtDate(s.as_of_date)}</td>
                      <td className="muted">{s.model_version}</td>
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
  );
}
