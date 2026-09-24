/**
 * Display formatting.
 *
 * The API's rule carries through to the screen: a value that could not be
 * computed is shown as MISSING, never as 0. Every formatter here returns
 * MISSING for null, undefined and non-finite input.
 */

export const MISSING = "—";

/** Typographic minus, so negative numbers align with positive ones. */
const MINUS = "−";

export function isNum(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function withSign(text: string, negative: boolean, signed: boolean, positive: boolean): string {
  if (negative) return `${MINUS}${text}`;
  if (signed && positive) return `+${text}`;
  return text;
}

export function fmtNumber(value: number | null | undefined, digits = 2, signed = false): string {
  if (!isNum(value)) return MISSING;
  const text = Math.abs(value).toLocaleString("en-US", {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
  // Rounding can turn a tiny negative into "0.00"; never print "−0.00".
  const roundsToZero = Number(Math.abs(value).toFixed(digits)) === 0;
  return withSign(text, value < 0 && !roundsToZero, signed, value > 0 && !roundsToZero);
}

/** A fraction as a percentage: 0.123 -> "12.3%". */
export function fmtPct(value: number | null | undefined, digits = 1, signed = false): string {
  if (!isNum(value)) return MISSING;
  return `${fmtNumber(value * 100, digits, signed)}%`;
}

const COMPACT_UNITS: [number, string][] = [
  [1e12, "T"],
  [1e9, "B"],
  [1e6, "M"],
  [1e3, "K"],
];

/** 1234567 -> "1.2M". Values under 1,000 are printed whole. */
export function fmtCompact(value: number | null | undefined, digits = 1): string {
  if (!isNum(value)) return MISSING;
  const abs = Math.abs(value);
  for (const [size, unit] of COMPACT_UNITS) {
    if (abs >= size) return withSign(`${(abs / size).toFixed(digits)}${unit}`, value < 0, false, false);
  }
  return withSign(Math.round(abs).toLocaleString("en-US"), value < 0, false, false);
}

export function fmtMoney(value: number | null | undefined, compact = false): string {
  if (!isNum(value)) return MISSING;
  const body = compact ? fmtCompact(Math.abs(value)) : fmtNumber(Math.abs(value), 2);
  return value < 0 ? `${MINUS}$${body}` : `$${body}`;
}

/** An API date ("2026-09-24") or timestamp, shown as "Sep 24, 2026". */
export function fmtDate(iso: string | null | undefined): string {
  if (!iso) return MISSING;
  const date = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Date(`${iso}T00:00:00Z`) : new Date(iso);
  if (Number.isNaN(date.getTime())) return MISSING;
  return date.toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
    timeZone: /^\d{4}-\d{2}-\d{2}$/.test(iso) ? "UTC" : undefined,
  });
}

export type Tone = "up" | "down" | "flat";

/** Direction as a glyph and a tone, so direction never relies on colour. */
export function direction(value: number | null | undefined): { glyph: string; tone: Tone } {
  if (!isNum(value) || value === 0) return { glyph: "–", tone: "flat" };
  return value > 0 ? { glyph: "▲", tone: "up" } : { glyph: "▼", tone: "down" };
}

/** Words that read wrong in sentence case. */
const ACRONYMS: Record<string, string> = {
  cik: "CIK",
  dcf: "DCF",
  eps: "EPS",
  fcf: "FCF",
  ma: "MA",
  macd: "MACD",
  roic: "ROIC",
  rsi: "RSI",
  vix: "VIX",
  wacc: "WACC",
  "52w": "52-week",
  f: "F",
  m: "M",
  z: "Z",
};

/** "investment_quality" -> "Investment quality"; "roic_vs_wacc" -> "ROIC vs WACC". */
export function humanize(key: string): string {
  const words = key.replace(/_/g, " ").trim().split(/\s+/).filter(Boolean);
  const out = words.map((word, i) => {
    const acronym = ACRONYMS[word.toLowerCase()];
    if (acronym) return acronym;
    return i === 0 ? word.charAt(0).toUpperCase() + word.slice(1) : word;
  });
  return out.join(" ");
}

/**
 * Simple moving average for chart overlays. A window containing a missing
 * value yields null rather than averaging around the gap.
 */
export function sma(values: readonly (number | null)[], window: number): (number | null)[] {
  if (window < 1) throw new Error("window must be >= 1");
  const out: (number | null)[] = [];
  let sum = 0;
  let missingInWindow = 0;
  for (let i = 0; i < values.length; i++) {
    const incoming = values[i];
    if (isNum(incoming)) sum += incoming;
    else missingInWindow++;
    if (i >= window) {
      const outgoing = values[i - window];
      if (isNum(outgoing)) sum -= outgoing;
      else missingInWindow--;
    }
    out.push(i + 1 >= window && missingInWindow === 0 ? sum / window : null);
  }
  return out;
}
