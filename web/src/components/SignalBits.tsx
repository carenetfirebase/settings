import { Link } from "react-router";

import type { Check, LedgerEntry, Signal, SignalStatus, VolatilityInfo } from "../api/types";
import { MISSING, fmtNumber, fmtPct, humanize, isNum } from "../lib/format";

const CHECK_LABEL: Record<string, string> = {
  trend_gate: "Trend gate",
  stock_trend: "Uptrend",
  quality_veto: "Quality",
  earnings_veto: "Earnings",
  levels: "Levels",
};

/** A gate or veto. Pass, fail and unknown each carry a glyph, not just colour. */
export function CheckChip({ check }: { check: Check }) {
  const label = CHECK_LABEL[check.name] ?? humanize(check.name);
  const [tone, glyph] =
    check.passed === true ? ["good", "✓"] : check.passed === false ? ["bad", "✕"] : ["warn", "?"];
  return (
    <span className={`chip ${tone}`} title={check.detail}>
      {glyph} {label}
    </span>
  );
}

const STATUS: Record<SignalStatus, { label: string; tone: string; glyph: string }> = {
  card: { label: "Card", tone: "good", glyph: "✓" },
  vetoed: { label: "Vetoed", tone: "bad", glyph: "✕" },
  gate_closed: { label: "Gate closed", tone: "warn", glyph: "■" },
  invalid_levels: { label: "Levels invalid", tone: "", glyph: "–" },
  no_pullback: { label: "No pullback", tone: "", glyph: "–" },
  not_in_uptrend: { label: "Not in uptrend", tone: "", glyph: "–" },
  insufficient_data: { label: "Insufficient data", tone: "", glyph: "?" },
};

export function StatusChip({ status }: { status: SignalStatus }) {
  const s = STATUS[status];
  return (
    <span className={`chip ${s.tone}`}>
      {s.glyph} {s.label}
    </span>
  );
}

const OUTCOME: Record<string, { label: string; tone: string; glyph: string }> = {
  target: { label: "Target", tone: "good", glyph: "▲" },
  stop: { label: "Stop", tone: "bad", glyph: "▼" },
  time: { label: "Time exit", tone: "", glyph: "◷" },
  open: { label: "Open", tone: "warn", glyph: "●" },
  pending: { label: "Waiting", tone: "", glyph: "…" },
  expired: { label: "Never triggered", tone: "", glyph: "–" },
};

export function OutcomeChip({ entry }: { entry: LedgerEntry }) {
  if (!entry.outcome_status) return <span className="chip">Unscored</span>;
  const o = OUTCOME[entry.outcome_status] ?? { label: entry.outcome_status, tone: "", glyph: "" };
  return (
    <span className={`chip ${o.tone}`}>
      {o.glyph} {o.label}
    </span>
  );
}

/** An R value with its sign as a glyph. */
export function RValue({ value }: { value: number | null }) {
  if (!isNum(value)) return <span className="muted">{MISSING}</span>;
  const tone = value > 0 ? "up" : value < 0 ? "down" : "muted";
  return (
    <span className={`num ${tone}`}>
      {value > 0 ? "▲ " : value < 0 ? "▼ " : ""}
      {fmtNumber(value, 2, true)}R
    </span>
  );
}

/**
 * A diverging bar around zero, for a table cell. The value is always printed
 * beside it, so the bar never carries information on its own.
 */
export function DivergingBar({ value, max }: { value: number | null; max: number }) {
  if (!isNum(value) || max <= 0) return <span className="dbar" aria-hidden="true" />;
  const width = Math.min(50, (Math.abs(value) / max) * 50);
  return (
    <span className="dbar" aria-hidden="true">
      <i
        style={{
          left: value >= 0 ? "50%" : `${50 - width}%`,
          width: `${width}%`,
          background: value >= 0 ? "var(--up)" : "var(--down)",
        }}
      />
    </span>
  );
}

export function GateBanner({ gate, volatility }: { gate: Check; volatility: VolatilityInfo }) {
  const open = gate.passed === true;
  const tone = open ? "good" : gate.passed === false ? "bad" : "warn";
  const state = open ? "▲ Trend gate open: longs allowed" : gate.passed === false ? "▼ Trend gate closed: no new longs" : "? Trend gate unknown: treated as closed";
  return (
    <div className={`banner ${tone === "bad" ? "bad" : tone === "warn" ? "warn" : ""}`} style={open ? { borderColor: "color-mix(in srgb, var(--up) 45%, transparent)", background: "var(--up-soft)" } : undefined}>
      <strong>{state}.</strong> {gate.detail}
      <div className="muted" style={{ marginTop: 4 }}>
        Risk scale {fmtPct(volatility.multiplier, 0)} of base. {volatility.detail}
      </div>
    </div>
  );
}

const COMPONENT_LABEL: Record<string, string> = {
  trend: "Trend strength",
  relative_strength: "Relative strength",
  pullback: "Pullback entry",
  ecosystem_lead_lag: "Ecosystem lead-lag",
};

export function TradeCard({ signal }: { signal: Signal }) {
  const levels = signal.levels;
  const vetoChecks = signal.checks.filter((c) => c.name !== "levels");
  const unverified = signal.reasons.filter((r) => r.startsWith("Unverified"));

  return (
    <article className="panel trade-card" aria-label={`${signal.ticker} trade card`}>
      <header className="tc-top">
        <div>
          <h3 className="tc-title">
            <Link to={`/research/${signal.ticker}`}>{signal.ticker}</Link> <span className="chip good">LONG</span>
          </h3>
          <div className="muted" style={{ fontSize: 12 }}>
            {signal.name ?? MISSING} · {signal.sector ?? "No sector"} · pullback in uptrend
          </div>
        </div>
        <div className="score-value num" title="Score out of 100. Calibration is measured in the Lab.">
          {fmtNumber(signal.final_score, 0)}
          <small>/100</small>
        </div>
      </header>

      <div style={{ display: "grid", gap: 6 }}>
        {signal.score.components.map((c) => {
          const available = isNum(c.value);
          return (
            <div key={c.name} className={`component${available ? "" : " unavailable"}`}>
              <span>{COMPONENT_LABEL[c.name] ?? humanize(c.name)}</span>
              <div className="track" aria-hidden="true">
                {available && <i style={{ width: `${c.value}%` }} />}
              </div>
              <span className="n">{available ? fmtNumber(c.value, 0) : "V2"}</span>
              <span className="component-detail">{available ? c.detail : c.unavailable_reason}</span>
            </div>
          );
        })}
      </div>

      <div className="chips">
        {vetoChecks.map((c) => (
          <CheckChip key={c.name} check={c} />
        ))}
        <span className={`chip${signal.insider_bonus > 0 ? " good" : ""}`} title={signal.insider_detail ?? ""}>
          {signal.insider_bonus > 0 ? `+${fmtNumber(signal.insider_bonus, 0)} insider` : "Insider: neutral"}
        </span>
      </div>

      {levels && (
        <div className="kv">
          <div>
            <span>ENTRY (buy-stop)</span>
            <b className="num">{fmtNumber(levels.entry)}</b>
          </div>
          <div>
            <span>STOP · −1R</span>
            <b className="num down">{fmtNumber(levels.stop)}</b>
          </div>
          <div>
            <span>TARGET · +{levels.target_r}R</span>
            <b className="num up">{fmtNumber(levels.target)}</b>
          </div>
        </div>
      )}

      {levels && signal.sizing && (
        <p className="tc-rule">
          <strong>Breaks the thesis:</strong> a trade below {fmtNumber(levels.stop)}.{" "}
          <strong>Size:</strong> {signal.sizing.detail} <strong>Time stop:</strong> {levels.time_stop_days} trading days.
          The buy-stop expires after {levels.trigger_window_days} days if price never turns up.
        </p>
      )}

      {unverified.length > 0 && (
        <ul className="warnings">
          {unverified.map((w) => (
            <li key={w}>{w}</li>
          ))}
        </ul>
      )}

      <p className="muted" style={{ fontSize: 11.5 }}>
        Paper trading from this card arrives in V1.2. Until then, record signals with{" "}
        <code>invest signals record</code>.
      </p>
    </article>
  );
}
