import { useState } from "react";

import { paths } from "../api/client";
import type { AttributionResponse, CalibrationResponse, GroupStats } from "../api/types";
import { useApi } from "../api/useApi";
import { PageHead, Panel } from "../components/Panel";
import { DivergingBar, RValue } from "../components/SignalBits";
import { ApiView, Empty } from "../components/States";
import { MISSING, fmtNumber, fmtPct, isNum } from "../lib/format";

type Origin = "" | "live" | "backfill";

function OriginPicker({ value, onChange }: { value: Origin; onChange: (o: Origin) => void }) {
  return (
    <label className="filters">
      <span className="muted">Origin</span>
      <select className="select" value={value} onChange={(e) => onChange(e.target.value as Origin)}>
        <option value="">Live and backfill</option>
        <option value="live">Live only</option>
        <option value="backfill">Backfill only</option>
      </select>
    </label>
  );
}

const BACKFILL_WARNING =
  "Backfilled signals are point-in-time but scanned over today's universe, so they carry survivorship bias. Treat them as evidence about the rules, not a track record.";

function SizeNote({ group }: { group: GroupStats }) {
  return group.enough ? null : <span className="chip warn">too few ({group.closed})</span>;
}

// ------------------------------------------------------------------ Calibration

export function Calibration() {
  const [origin, setOrigin] = useState<Origin>("");
  const cal = useApi<CalibrationResponse>(paths.calibration({ origin: origin || undefined, fired_only: true }));

  return (
    <>
      <PageHead crumb="Lab" title="Calibration" aside={<OriginPicker value={origin} onChange={setOrigin} />}>
        Does a higher score earn more? Fired signals grouped by score, with results in R after costs
        from closed trades only.
      </PageHead>
      {origin !== "live" && <div className="banner warn">{BACKFILL_WARNING}</div>}
      <ApiView state={cal}>
        {(data) => {
          const max = Math.max(0, ...data.buckets.map((b) => Math.abs(b.mean_r ?? 0)));
          return (
            <>
              <div className={`banner${data.monotonic === false ? " bad" : ""}`}>
                <span className="verdict">
                  {data.monotonic === true
                    ? "▲ Calibrated so far: higher buckets have earned more."
                    : data.monotonic === false
                      ? "▼ Not calibrated: a higher score has not meant a better result."
                      : "? Not enough closed trades yet to judge."}
                </span>{" "}
                {data.note}
              </div>
              <Panel title="By score" subtitle={`${data.overall.closed} closed of ${data.overall.signals} fired`} bodyClassName="">
                {data.overall.signals === 0 ? (
                  <Empty title="No fired signals in the ledger yet">
                    Run <code>invest signals backfill --start 2025-01-01</code>, or record daily with{" "}
                    <code>invest signals record</code>.
                  </Empty>
                ) : (
                  <div className="table-wrap">
                    <table>
                      <thead>
                        <tr>
                          <th>Score</th>
                          <th className="r">Signals</th>
                          <th className="r">Closed</th>
                          <th className="r">Mean R</th>
                          <th aria-hidden="true" />
                          <th className="r">Win rate</th>
                          <th className="r">+1R before −1R</th>
                          <th className="r">Avg best / worst</th>
                          <th />
                        </tr>
                      </thead>
                      <tbody>
                        {[...data.buckets, data.overall].map((b) => (
                          <tr key={b.label}>
                            <td className="strong">{b.label}</td>
                            <td className="r">{b.signals}</td>
                            <td className="r">{b.closed}</td>
                            <td className="r">
                              <RValue value={b.mean_r} />
                            </td>
                            <td>
                              <DivergingBar value={b.mean_r} max={max} />
                            </td>
                            <td className="r">{fmtPct(b.win_rate, 0)}</td>
                            <td className="r">{fmtPct(b.first_up_rate, 0)}</td>
                            <td className="r num muted">
                              {fmtNumber(b.mean_mfe, 1, true)} / {fmtNumber(b.mean_mae, 1, true)}
                            </td>
                            <td>{b.signals > 0 && <SizeNote group={b} />}</td>
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

// ------------------------------------------------------------------ Attribution

export function Attribution() {
  const [origin, setOrigin] = useState<Origin>("");
  const attr = useApi<AttributionResponse>(paths.attribution({ origin: origin || undefined }));

  return (
    <>
      <PageHead crumb="Lab" title="Layer Attribution" aside={<OriginPicker value={origin} onChange={setOrigin} />}>
        Does each gate and veto earn its place? Blocked setups are recorded and scored exactly like
        fired ones, so what a rule blocks can be compared with what it lets through.
      </PageHead>
      {origin !== "live" && <div className="banner warn">{BACKFILL_WARNING}</div>}
      <ApiView state={attr}>
        {(data) => {
          const ref = data.reference;
          return (
            <>
              <div className="banner">{data.note}</div>
              <Panel
                title="Against fired signals"
                subtitle={`reference mean ${isNum(ref.mean_r) ? `${fmtNumber(ref.mean_r, 2, true)}R` : MISSING} · ${ref.closed} closed`}
                bodyClassName=""
              >
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Group</th>
                        <th className="r">Signals</th>
                        <th className="r">Closed</th>
                        <th className="r">Mean R</th>
                        <th className="r">Difference</th>
                        <th className="r">t</th>
                        <th>Verdict</th>
                      </tr>
                    </thead>
                    <tbody>
                      {data.groups.map((g) => {
                        const t = g.t_vs_reference;
                        const clear = isNum(t) && Math.abs(t) > data.t_stat_bar && g.enough && ref.enough;
                        return (
                          <tr key={g.label}>
                            <td className="strong">{g.label}</td>
                            <td className="r">{g.signals}</td>
                            <td className="r">{g.closed}</td>
                            <td className="r">
                              <RValue value={g.mean_r} />
                            </td>
                            <td className="r">
                              <RValue value={g.diff_vs_reference} />
                            </td>
                            <td className="r num">{fmtNumber(t, 1, true)}</td>
                            <td>
                              {g.signals === 0 ? (
                                <span className="muted">{g.label.startsWith("Blocked") ? "Nothing blocked yet" : "No signals yet"}</span>
                              ) : clear ? (
                                <span className="chip good">✓ Clear difference</span>
                              ) : (
                                <span className="chip warn">? Not yet distinguishable</span>
                              )}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </Panel>
            </>
          );
        }}
      </ApiView>
    </>
  );
}
