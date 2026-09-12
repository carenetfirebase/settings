import type { FactDataType, FactDefinition, JsonValue } from '../../fact-catalog/src/index.ts';

export type NormalizeResult =
  | { ok: true; value: JsonValue; display: string }
  | { ok: false; reason: string };

const MONTHS = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

/**
 * Coerce a raw extracted string into the fact's declared type (§8 NORMALIZE).
 *
 * Anything that will not coerce is rejected outright and flagged for manual
 * entry. A value the engine cannot compare is a value that cannot participate
 * in conflict detection, and a fact that silently skips conflict detection is
 * exactly the failure this product exists to prevent.
 */
export function normalizeValue(def: FactDefinition, raw: unknown): NormalizeResult {
  if (raw === null || raw === undefined) return { ok: false, reason: 'empty value' };
  const text = String(raw).trim();
  if (text === '') return { ok: false, reason: 'empty value' };

  switch (def.dataType) {
    case 'year': return normalizeYear(text);
    case 'date': return normalizeDate(text);
    case 'money': return normalizeMoney(text);
    case 'number':
    case 'dimension': return normalizeNumber(text, def.unit);
    case 'boolean': return normalizeBoolean(text);
    case 'enum': return normalizeEnum(text, def);
    case 'text': return { ok: true, value: text, display: text };
  }
}

function normalizeYear(text: string): NormalizeResult {
  const match = text.match(/\b(1[89]\d{2}|20\d{2})\b/);
  if (!match) return { ok: false, reason: `no year in "${text}"` };
  const year = Number(match[1]);
  const now = new Date().getUTCFullYear();
  if (year > now + 2) return { ok: false, reason: `year ${year} is in the future` };
  return { ok: true, value: year, display: String(year) };
}

function normalizeDate(text: string): NormalizeResult {
  const iso = text.match(/\b(\d{4})-(\d{2})-(\d{2})\b/);
  if (iso) return { ok: true, value: iso[0], display: iso[0] };

  const monthYear = text.toLowerCase().match(/\b([a-z]{3,9})\.?\s+(\d{1,2})?,?\s*(\d{4})\b/);
  if (monthYear) {
    const monthIndex = MONTHS.indexOf(monthYear[1].slice(0, 3));
    if (monthIndex >= 0) {
      const day = monthYear[2] ? Number(monthYear[2]) : 1;
      const value = `${monthYear[3]}-${pad(monthIndex + 1)}-${pad(day)}`;
      return { ok: true, value, display: value };
    }
  }
  const year = text.match(/\b(1[89]\d{2}|20\d{2})\b/);
  if (year) return { ok: true, value: `${year[1]}-01-01`, display: year[1] };
  return { ok: false, reason: `no date in "${text}"` };
}

function normalizeMoney(text: string): NormalizeResult {
  const cleaned = text.replace(/[^\d.,-]/g, '').replace(/,/g, '');
  const amount = Number.parseFloat(cleaned);
  if (!Number.isFinite(amount)) return { ok: false, reason: `no amount in "${text}"` };
  return { ok: true, value: amount, display: formatMoney(amount) };
}

function normalizeNumber(text: string, unit?: string): NormalizeResult {
  // "12 ft x 14 ft" is a dimension pair, not a scalar; keep both numbers so a
  // room size compares as a room size.
  const pair = text.match(/(\d+(?:\.\d+)?)\s*(?:ft|feet|')?\s*[x×by]+\s*(\d+(?:\.\d+)?)/i);
  if (pair) {
    const [w, l] = [Number(pair[1]), Number(pair[2])];
    return {
      ok: true,
      value: { width: w, length: l, unit: unit ?? 'ft' },
      display: `${trim(w)} × ${trim(l)} ${unit ?? 'ft'}`,
    };
  }
  const cleaned = text.replace(/,/g, '').match(/-?\d+(?:\.\d+)?/);
  if (!cleaned) return { ok: false, reason: `no number in "${text}"` };
  const value = Number(cleaned[0]);
  return { ok: true, value, display: unit ? `${trim(value)} ${unit}` : trim(value) };
}

function normalizeBoolean(text: string): NormalizeResult {
  const t = text.toLowerCase();
  if (/^(y|yes|true|1|present|included|has)\b/.test(t)) {
    return { ok: true, value: true, display: 'Yes' };
  }
  if (/^(n|no|false|0|absent|none|not included)\b/.test(t)) {
    return { ok: true, value: false, display: 'No' };
  }
  return { ok: false, reason: `not a yes/no value: "${text}"` };
}

function normalizeEnum(text: string, def: FactDefinition): NormalizeResult {
  const options = def.enumOptions ?? [];
  const slug = text.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
  const exact = options.find((o) => o === slug);
  if (exact) return { ok: true, value: exact, display: humanize(exact) };

  const loose = options.find(
    (o) => slug.includes(o) || o.includes(slug) ||
           humanize(o).toLowerCase() === text.toLowerCase());
  if (loose) return { ok: true, value: loose, display: humanize(loose) };

  return { ok: false, reason: `"${text}" is not one of ${options.join(', ')}` };
}

export function humanize(slug: string): string {
  const word = slug.replace(/_/g, ' ');
  return word.charAt(0).toUpperCase() + word.slice(1);
}

export function formatMoney(amount: number): string {
  return `$${amount.toLocaleString('en-CA', { maximumFractionDigits: 2 })}`;
}

function pad(n: number): string { return String(n).padStart(2, '0'); }
function trim(n: number): string { return String(Number(n.toFixed(2))); }

/**
 * Are two normalized values materially different (§7.3)?
 *
 * Tuning matters more than the rule: surveys and MLS sheets routinely disagree
 * by a foot, and an agent who is shown forty false conflicts stops reading them,
 * which costs more than the conflicts catch.
 */
export function materiallyDiffers(
  dataType: FactDataType, a: JsonValue | undefined, b: JsonValue | undefined,
): { differs: boolean; severity: 'soft' | 'hard' } {
  if (a === undefined || b === undefined) return { differs: false, severity: 'soft' };

  switch (dataType) {
    case 'year':
      return { differs: numeric(a) !== numeric(b), severity: 'hard' };
    case 'date':
      return { differs: String(a) !== String(b), severity: 'hard' };
    case 'money':
      return { differs: relativeGap(a, b) > 0.02, severity: 'hard' };
    case 'dimension':
      return { differs: dimensionGap(a, b) > 0.03, severity: 'hard' };
    case 'number':
      return { differs: relativeGap(a, b) > 0.03, severity: 'hard' };
    case 'enum':
    case 'boolean':
      return { differs: a !== b, severity: 'hard' };
    case 'text': {
      const differs = normalizeText(a) !== normalizeText(b);
      return { differs, severity: 'soft' };
    }
  }
}

function numeric(v: JsonValue): number {
  return typeof v === 'number' ? v : Number(String(v).replace(/[^\d.-]/g, ''));
}

function relativeGap(a: JsonValue, b: JsonValue): number {
  const [x, y] = [numeric(a), numeric(b)];
  if (!Number.isFinite(x) || !Number.isFinite(y)) return String(a) === String(b) ? 0 : 1;
  const scale = Math.max(Math.abs(x), Math.abs(y));
  return scale === 0 ? 0 : Math.abs(x - y) / scale;
}

function dimensionGap(a: JsonValue, b: JsonValue): number {
  const areaOf = (v: JsonValue): number => {
    if (typeof v === 'object' && v !== null && 'width' in v && 'length' in v) {
      return Number((v as Record<string, JsonValue>).width) *
             Number((v as Record<string, JsonValue>).length);
    }
    return numeric(v);
  };
  const [x, y] = [areaOf(a), areaOf(b)];
  const scale = Math.max(Math.abs(x), Math.abs(y));
  return scale === 0 ? 0 : Math.abs(x - y) / scale;
}

function normalizeText(v: JsonValue): string {
  return String(v).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}
