import { useState } from "react";
import { Link, useSearchParams } from "react-router";

import { paths } from "../api/client";
import type { LedgerResponse, ScanResponse, Signal, SignalStatus } from "../api/types";
import { useApi } from "../api/useApi";
import { PageHead, Panel } from "../components/Panel";
import { CheckChip, GateBanner, OutcomeChip, RValue, StatusChip, TradeCard } from "../components/SignalBits";
import { ApiView, Empty } from "../components/States";
import { MISSING, fmtDate, fmtNumber } from "../lib/format";

const STATUS_ORDER: SignalStatus[] = [
  "card",
  "vetoed",
  "gate_closed",
  "invalid_levels",
  "no_pullback",
  "not_in_uptrend",
  "insufficient_data",
];

function component(signal: Signal, name: string): number | null {
  return signal.score.components.find((c) => c.name === name)?.value ?? null;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Point-in-time control, kept in the URL (?as_of=2026-03-02) so a past scan
 * can be linked to. Empty means today.
 */
function useAsOf(): [string | undefined, (value: string) => void] {
  const [params, setParams] = useSearchParams();
  const raw = params.get("as_of") ?? "";
  const asOf = ISO_DATE.test(raw) ? raw : undefined;
  const set = (value: string) => {
    const next = new URLSearchParams(params);
    if (value) next.set("as_of", value);
    else next.delete("as_of");
    setParams(next, { replace: true });
  };
  return [asOf, set];
}

function AsOfPicker({ value, onChange }: { value: string | undefined; onChange: (v: string) => void }) {
  return (
    <label className="filters">
      <span className="muted">As of</span>
      <input
        className="select"
        type="date"
        value={value ?? ""}
        max={new Date().toISOString().slice(0, 10)}
        onChange={(e) => onChange(e.target.value)}
        aria-label="Scan as of date (empty for today)"
      />
      {value && (
        <button type="button" className="icon-button" onClick={() => onChange("")}>
          Today
        </button>
      )}
    </label>
  );
}

// ------------------------------------------------------------------ Scanner

export function Scanner() {
  const [asOf, setAsOf] = useAsOf();
  const scan = useApi<ScanResponse>(paths.scan(asOf));
  const [status, setStatus] = useState<SignalStatus | "all">("all");

  return (
    <>
      <PageHead
        crumb="Signals"
        title="Scanner"
        aside={
          <div className="filters">
          <AsOfPicker value={asOf} onChange={setAsOf} />
          <label>
            <span className="visually-hidden">Filter by status</span>
            <select className="select" value={status} onChange={(e) => setStatus(e.target.value as SignalStatus | "all")}>
              <option value="all">All symbols</option>
              {STATUS_ORDER.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </select>
          </label>
          </div>
        }
      >
        Every stock through the trend gate, its own uptrend, a pullback entry, and the quality and
        earnings vetoes, with the reason each one stops where it does. Scanning records nothing.
      </PageHead>

      <ApiView state={scan} loadingLabel="Running the engine…">
        {(data) => {
          const rows = data.signals.filter((s) => status === "all" || s.status === status);
          return (
            <>
              <GateBanner gate={data.gate} volatility={data.volatility} />
              {data.warnings.map((w) => (
                <div key={w} className="banner warn">
                  {w}
                </div>
              ))}
              <div className="chips">
                {STATUS_ORDER.filter((s) => data.counts[s]).map((s) => (
                  <button key={s} type="button" className="chip-button" onClick={() => setStatus(s)} aria-label={`Show ${s.replace(/_/g, " ")}`}>
                    <StatusChip status={s} /> <span className="num">{data.counts[s]}</span>
                  </button>
                ))}
              </div>
              <Panel title={`As of ${fmtDate(data.as_of)}`} subtitle={`model ${data.model_version}`} bodyClassName="">
                {rows.length === 0 ? (
                  <Empty title="Nothing matches this filter" />
                ) : (
                  <div className="table-wrap">
                    <table>
                      <thead>
                        <tr>
                          <th>Symbol</th>
                          <th>Status</th>
                          <th className="r">Trend</th>
                          <th className="r">Rel. strength</th>
                          <th className="r">Pullback</th>
                          <th className="r">Score</th>
                          <th>Why</th>
                        </tr>
                      </thead>
                      <tbody>
                        {rows.map((s) => (
                          <tr key={s.ticker}>
                            <td>
                              <Link to={`/research/${s.ticker}`}>{s.ticker}</Link>
                              <div className="muted" style={{ fontSize: 11 }}>{s.sector ?? MISSING}</div>
                            </td>
                            <td>
                              <StatusChip status={s.status} />
                            </td>
                            <td className="r">{fmtNumber(component(s, "trend"), 0)}</td>
                            <td className="r">{fmtNumber(component(s, "relative_strength"), 0)}</td>
                            <td className="r">{fmtNumber(component(s, "pullback"), 0)}</td>
                            <td className="r strong">{s.is_candidate ? fmtNumber(s.final_score, 0) : MISSING}</td>
                            <td style={{ maxWidth: 480 }}>{s.reasons[0] ?? "Every rule passed."}</td>
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

// ------------------------------------------------------------------ Trade cards

export function TradeCards() {
  const [asOf, setAsOf] = useAsOf();
  const scan = useApi<ScanResponse>(paths.scan(asOf));
  return (
    <>
      <PageHead crumb="Signals" title="Trade Cards" aside={<AsOfPicker value={asOf} onChange={setAsOf} />}>
        Setups that passed every gate and veto on the chosen day (today unless you pick a date), best
        score first. Each card states its entry, stop, target, size and the level that breaks the thesis.
      </PageHead>
      <ApiView state={scan} loadingLabel="Running the engine…">
        {(data) => {
          const cards = data.signals.filter((s) => s.fired);
          const blocked = data.signals.filter((s) => s.is_candidate && !s.fired);
          return (
            <>
              <GateBanner gate={data.gate} volatility={data.volatility} />
              {cards.length === 0 ? (
                <Panel>
                  <Empty title={asOf ? `No trade cards on ${fmtDate(asOf)}` : "No trade cards today"}>
                    {data.gate.passed !== true
                      ? "The trend gate is not open, so no new longs are allowed."
                      : "No stock in the universe is pulling back in an uptrend right now. That is a normal state."}
                  </Empty>
                </Panel>
              ) : (
                <div className="grid cards">
                  {cards.map((s) => (
                    <TradeCard key={s.ticker} signal={s} />
                  ))}
                </div>
              )}
              {blocked.length > 0 && (
                <Panel title="Setups that were blocked" subtitle="recorded in the ledger so the Lab can test the blocks" bodyClassName="">
                  <div className="table-wrap">
                    <table>
                      <tbody>
                        {blocked.map((s) => (
                          <tr key={s.ticker}>
                            <td>
                              <Link to={`/research/${s.ticker}`}>{s.ticker}</Link>
                            </td>
                            <td>
                              <StatusChip status={s.status} />
                            </td>
                            <td>
                              <div className="chips">
                                {s.checks
                                  .filter((c) => c.passed === false)
                                  .map((c) => (
                                    <CheckChip key={c.name} check={c} />
                                  ))}
                              </div>
                            </td>
                            <td>{s.reasons[0]}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </Panel>
              )}
            </>
          );
        }}
      </ApiView>
    </>
  );
}

// ------------------------------------------------------------------ Ledger

const PAGE_SIZE = 100;

export function SignalLedger() {
  const [origin, setOrigin] = useState<"" | "live" | "backfill">("");
  const [firedOnly, setFiredOnly] = useState(false);
  const [limit, setLimit] = useState(PAGE_SIZE);
  const ledger = useApi<LedgerResponse>(
    paths.ledger({ origin: origin || undefined, fired_only: firedOnly || undefined, limit }),
  );

  return (
    <>
      <PageHead
        crumb="Signals"
        title="Signal Ledger"
        aside={
          <div className="filters">
            <label>
              Origin
              <select className="select" value={origin} onChange={(e) => setOrigin(e.target.value as typeof origin)}>
                <option value="">Live and backfill</option>
                <option value="live">Live only</option>
                <option value="backfill">Backfill only</option>
              </select>
            </label>
            <label>
              <input type="checkbox" checked={firedOnly} onChange={(e) => setFiredOnly(e.target.checked)} />
              Fired only
            </label>
          </div>
        }
      >
        Every setup the engine has found, fired or blocked, and what happened next, in R after costs.
        The ledger is append-only: rows are never edited after the fact.
      </PageHead>
      <ApiView state={ledger}>
        {(data) => (
          <>
            <div className="banner">{data.note}</div>
            <Panel title="Entries" subtitle={`newest first · ${data.count} shown`} bodyClassName="">
              {data.count === 0 ? (
                <Empty title="The ledger is empty">
                  Record today's signals with <code>invest signals record</code>, or reconstruct history with{" "}
                  <code>invest signals backfill --start 2025-01-01</code>. Then run <code>invest signals evaluate</code>.
                </Empty>
              ) : (
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Date</th>
                        <th>Symbol</th>
                        <th>Origin</th>
                        <th>Signal</th>
                        <th className="r">Score</th>
                        <th className="r">Entry / stop / target</th>
                        <th>Outcome</th>
                        <th className="r">Result</th>
                        <th className="r">Best / worst</th>
                        <th className="r">Days</th>
                      </tr>
                    </thead>
                    <tbody>
                      {data.entries.map((e) => (
                        <tr key={e.signal_id}>
                          <td>{fmtDate(e.as_of_date)}</td>
                          <td>
                            <Link to={`/research/${e.ticker}`}>{e.ticker}</Link>
                          </td>
                          <td>
                            <span className={`chip${e.origin === "live" ? " good" : ""}`}>{e.origin}</span>
                          </td>
                          <td>
                            <StatusChip status={e.status} />
                          </td>
                          <td className="r">{fmtNumber(e.final_score, 0)}</td>
                          <td className="r num">
                            {fmtNumber(e.entry)} / {fmtNumber(e.stop)} / {fmtNumber(e.target)}
                          </td>
                          <td>
                            <OutcomeChip entry={e} />
                          </td>
                          <td className="r">
                            <RValue value={e.r_net} />
                          </td>
                          <td className="r num muted">
                            {fmtNumber(e.mfe_r, 1, true)} / {fmtNumber(e.mae_r, 1, true)}
                          </td>
                          <td className="r">{e.bars_held ?? MISSING}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {data.count >= limit && (
                    <div className="panel-b">
                      <button type="button" className="icon-button" onClick={() => setLimit((n) => n + PAGE_SIZE)}>
                        Show {PAGE_SIZE} more
                      </button>
                    </div>
                  )}
                </div>
              )}
            </Panel>
          </>
        )}
      </ApiView>
    </>
  );
}
