import type { Score } from "../api/types";
import { MISSING, fmtNumber, fmtPct, humanize, isNum } from "../lib/format";

/**
 * A score is never shown without its parts: every component, its weight, and
 * the reason any component could not be computed.
 */
export function ScoreCard({ score, note }: { score: Score; note?: string }) {
  const totalWeight = score.components.reduce((sum, c) => sum + c.weight, 0);

  return (
    <section className="panel score-card" aria-label={humanize(score.name)}>
      <div className="score-top">
        <div>
          <h3 className="score-name">{humanize(score.name)}</h3>
          <div className="score-meta" style={{ textAlign: "left" }}>
            Coverage {fmtPct(score.coverage, 0)}
            {!score.reliable && <span className="chip warn" style={{ marginLeft: 6 }}>unreliable</span>}
          </div>
        </div>
        <div className="score-value num">
          {isNum(score.value) ? fmtNumber(score.value, 0) : MISSING}
          <small>/100</small>
        </div>
      </div>

      {note && <p className="banner warn" style={{ fontSize: 11.5 }}>{note}</p>}

      {score.components.map((c) => {
        const available = isNum(c.value);
        const share = totalWeight > 0 ? c.weight / totalWeight : null;
        return (
          <div key={c.name} className={`component${available ? "" : " unavailable"}`}>
            <span title={c.detail}>{humanize(c.name)}</span>
            <div className="track" aria-hidden="true">
              {available && <i style={{ width: `${Math.max(0, Math.min(100, c.value ?? 0))}%` }} />}
            </div>
            <span className="n">{available ? fmtNumber(c.value, 0) : MISSING}</span>
            <span className="component-detail">
              {available ? c.detail : c.unavailable_reason ?? "Not available"}
              {share !== null && ` · weight ${fmtPct(share, 0)}`}
            </span>
          </div>
        );
      })}

      {score.warnings.length > 0 && (
        <ul className="warnings">
          {score.warnings.map((w) => (
            <li key={w}>{w}</li>
          ))}
        </ul>
      )}
    </section>
  );
}
