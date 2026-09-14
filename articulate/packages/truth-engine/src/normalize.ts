import type { CaseFactDefinition, JsonValue } from '../../case-catalog/src/index.ts';

export type NormalizeResult =
  | { ok: true; value: JsonValue; display: string }
  | { ok: false; reason: string };

/** Universal 1–32, FDI quadrant notation, and Palmer, normalised to FDI. */
export function parseTeeth(raw: string, notation = 'universal'): number[] | null {
  const tokens = raw.toUpperCase().match(/#?\s*(\d{1,2})/g);
  if (!tokens) return null;
  const numbers = tokens.map((t) => Number(t.replace(/[^\d]/g, '')));
  if (numbers.some((n) => !Number.isFinite(n))) return null;

  if (notation === 'fdi') {
    return numbers.every(isFdi) ? numbers : null;
  }
  if (!numbers.every((n) => n >= 1 && n <= 32)) return null;
  return numbers.map(universalToFdi);
}

function isFdi(n: number): boolean {
  const quadrant = Math.floor(n / 10);
  const position = n % 10;
  return quadrant >= 1 && quadrant <= 4 && position >= 1 && position <= 8;
}

/** Universal 1–16 is upper right→left, 17–32 is lower left→right. */
export function universalToFdi(n: number): number {
  if (n <= 8) return 10 + (9 - n);
  if (n <= 16) return 20 + (n - 8);
  if (n <= 24) return 30 + (25 - n);
  return 40 + (n - 24);
}

export function fdiToUniversal(fdi: number): number {
  const quadrant = Math.floor(fdi / 10);
  const position = fdi % 10;
  if (quadrant === 1) return 9 - position;
  if (quadrant === 2) return 8 + position;
  if (quadrant === 3) return 25 - position;
  return 24 + position;
}

export function formatTeeth(fdi: number[], notation = 'universal'): string {
  const values = notation === 'fdi' ? fdi : fdi.map(fdiToUniversal);
  return values.map((n) => `#${n}`).join(', ');
}

const SHADE = /^(?:([ABCD])\s*([1-4])(?:\.5)?|(BL[1-4]|OM[1-3])|(\d(?:\.5)?M[123])|(0M[123]))$/i;

/**
 * Coerce a raw value to the fact's declared type.
 *
 * Anything that will not coerce is refused and sent for manual entry rather
 * than stored loosely. A value the engine cannot compare cannot take part in
 * conflict detection, and a tooth number that skips conflict detection is
 * exactly the failure this system exists to prevent.
 */
export function normalizeValue(def: CaseFactDefinition, raw: unknown, ctx: {
  toothNotation?: string;
} = {}): NormalizeResult {
  if (raw === null || raw === undefined) return { ok: false, reason: 'empty value' };
  const text = String(raw).trim();
  if (text === '') return { ok: false, reason: 'empty value' };

  switch (def.dataType) {
    case 'text':
      return { ok: true, value: text, display: text };

    case 'integer': {
      const match = text.replace(/,/g, '').match(/-?\d+/);
      if (!match) return { ok: false, reason: `no whole number in "${text}"` };
      const value = Number(match[0]);
      return { ok: true, value, display: String(value) };
    }

    case 'number':
    case 'dimension':
    case 'torque': {
      const match = text.replace(/,/g, '').match(/-?\d+(?:\.\d+)?/);
      if (!match) return { ok: false, reason: `no number in "${text}"` };
      const value = Number(match[0]);
      return {
        ok: true, value,
        display: def.unit ? `${trim(value)} ${def.unit}` : trim(value),
      };
    }

    case 'money': {
      const value = Number.parseFloat(text.replace(/[^\d.,-]/g, '').replace(/,/g, ''));
      if (!Number.isFinite(value)) return { ok: false, reason: `no amount in "${text}"` };
      return { ok: true, value, display: formatMoney(value) };
    }

    case 'boolean': {
      const t = text.toLowerCase();
      if (/^(y|yes|true|1|received|done|complete|present|pass)\b/.test(t)) {
        return { ok: true, value: true, display: 'Yes' };
      }
      if (/^(n|no|false|0|not received|missing|absent|fail|none)\b/.test(t)) {
        return { ok: true, value: false, display: 'No' };
      }
      return { ok: false, reason: `not a yes/no value: "${text}"` };
    }

    case 'enum': {
      const options = def.enumOptions ?? [];
      const slug = text.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
      const exact = options.find((o) => o === slug);
      if (exact) return { ok: true, value: exact, display: humanize(exact) };
      const loose = options.find(
        (o) => o.includes(slug) || slug.includes(o) ||
               humanize(o).toLowerCase() === text.toLowerCase());
      if (loose) return { ok: true, value: loose, display: humanize(loose) };
      return { ok: false, reason: `"${text}" is not one of ${options.join(', ')}` };
    }

    case 'date': {
      const iso = text.match(/\b(\d{4})-(\d{2})-(\d{2})\b/);
      if (iso) return { ok: true, value: iso[0], display: iso[0] };
      const parsed = new Date(text);
      if (!Number.isNaN(parsed.valueOf())) {
        const value = parsed.toISOString().slice(0, 10);
        return { ok: true, value, display: value };
      }
      return { ok: false, reason: `no date in "${text}"` };
    }

    case 'datetime': {
      const parsed = new Date(text);
      if (Number.isNaN(parsed.valueOf())) return { ok: false, reason: `no timestamp in "${text}"` };
      const value = parsed.toISOString();
      return { ok: true, value, display: value.slice(0, 16).replace('T', ' ') };
    }

    case 'shade': {
      const cleaned = text.trim().replace(/\s+/g, '');
      if (!SHADE.test(cleaned)) {
        return { ok: false, reason: `"${text}" is not a recognised shade designation` };
      }
      const value = cleaned.toUpperCase();
      return { ok: true, value, display: value };
    }

    case 'lot': {
      // Lots are opaque supplier strings. They are normalised for comparison
      // only — never reformatted, because the string on the packet is the
      // string a recall notice will name.
      const value = text.replace(/\s+/g, ' ').trim();
      if (value.length < 3) return { ok: false, reason: `"${text}" is too short for a lot` };
      return { ok: true, value, display: value };
    }

    case 'tooth':
    case 'tooth_set': {
      const teeth = parseTeeth(text, ctx.toothNotation ?? 'universal');
      if (!teeth || teeth.length === 0) {
        return { ok: false, reason: `no tooth number in "${text}"` };
      }
      if (def.dataType === 'tooth' && teeth.length > 1) {
        return { ok: false, reason: 'single tooth expected' };
      }
      return {
        ok: true,
        value: teeth,
        display: formatTeeth(teeth, ctx.toothNotation ?? 'universal'),
      };
    }
  }
}

/**
 * Is the difference between two values material?
 *
 * The thresholds are where the domain lives. A tooth number differing at all is
 * a hard stop; a lot number differing at all means two different batches went
 * in and both must be recorded; a cement space differing by 5µm is noise that
 * would train technicians to dismiss the queue.
 */
export function materiallyDiffers(
  def: CaseFactDefinition, a: JsonValue | undefined, b: JsonValue | undefined,
): boolean {
  if (a === undefined || b === undefined) return false;

  switch (def.dataType) {
    case 'tooth':
    case 'tooth_set':
      return JSON.stringify(a) !== JSON.stringify(b);
    case 'shade':
    case 'lot':
    case 'enum':
    case 'boolean':
      return a !== b;
    case 'torque':
      return relativeGap(a, b) > 0.001;
    case 'dimension':
      return relativeGap(a, b) > 0.05;
    case 'integer':
      return Number(a) !== Number(b);
    case 'number':
    case 'money':
      return relativeGap(a, b) > 0.02;
    case 'date':
    case 'datetime':
      return String(a).slice(0, 10) !== String(b).slice(0, 10);
    case 'text':
      return normalizeText(a) !== normalizeText(b);
  }
}

function relativeGap(a: JsonValue, b: JsonValue): number {
  const [x, y] = [Number(a), Number(b)];
  if (!Number.isFinite(x) || !Number.isFinite(y)) return String(a) === String(b) ? 0 : 1;
  const scale = Math.max(Math.abs(x), Math.abs(y));
  return scale === 0 ? 0 : Math.abs(x - y) / scale;
}

function normalizeText(v: JsonValue): string {
  return String(v).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

export function humanize(slug: string): string {
  const word = slug.replace(/_/g, ' ');
  return word.charAt(0).toUpperCase() + word.slice(1);
}

export function formatMoney(amount: number): string {
  return `$${amount.toLocaleString('en-US', { minimumFractionDigits: 2,
                                              maximumFractionDigits: 2 })}`;
}

function trim(n: number): string { return String(Number(n.toFixed(3))); }
