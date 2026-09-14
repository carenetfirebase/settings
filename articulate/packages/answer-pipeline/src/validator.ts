import { checkAnswer } from '../../compliance/src/index.ts';
import type { BoundaryHit } from '../../compliance/src/index.ts';

export type GroundingKind =
  | 'fact' | 'unknown' | 'ask' | 'material' | 'timeline' | 'status' | 'policy';

export type GroundingItem = {
  kind: GroundingKind;
  factKey?: string;
  label: string;
  display?: string;
  value?: unknown;
  text?: string;
  confirmationLevel?: string | null;
  unknownReason?: string | null;
  sourceRef?: string | null;
};

export type ValidatorFlag = {
  rule: 'numeric_token' | 'identifier_token' | 'prohibited_claim'
      | 'phi_exposure' | 'certainty_calibration' | 'hedged_fact';
  detail: string;
  token?: string;
};

export type ValidationResult = {
  ok: boolean;
  flags: ValidatorFlag[];
  derivations: string[];
};

const TRIVIAL = new Set([0, 1, 2]);

/**
 * The validator.
 *
 * The system instructions tell the model never to state a value that is not on
 * the case. Models drift, so the instruction is backed by a parser: every
 * number, shade, lot and tooth reference in a generated answer must appear in
 * the grounding payload, or the answer does not go out.
 *
 * Two token classes are checked more strictly than numbers, because for these
 * "close" is the same as "wrong":
 *
 *   lot numbers  — a recall notice names an exact string
 *   tooth numbers — the wrong one is a wrong-site device
 */
export function validateAnswer(
  answerText: string, grounding: GroundingItem[],
): ValidationResult {
  const flags: ValidatorFlag[] = [];
  const derivations: string[] = [];

  const haystack = grounding
    .map((g) => [g.display, g.text, g.label, stringify(g.value)].filter(Boolean).join(' '))
    .join(' ');
  const lower = haystack.toLowerCase();
  const groundedNumbers = new Set(extractNumbers(haystack).map((t) => t.value));

  // 1. Exact-match tokens. No derivation is ever acceptable for these.
  for (const token of extractIdentifiers(answerText)) {
    if (lower.includes(token.text.toLowerCase())) continue;
    flags.push({
      rule: 'identifier_token',
      detail: `${token.kind} "${token.text}" is not on this case`,
      token: token.text,
    });
  }

  // 2. Numbers, with a narrow allowance for arithmetic the lab would do aloud.
  for (const token of extractNumbers(answerText)) {
    if (TRIVIAL.has(token.value)) continue;
    if (groundedNumbers.has(token.value)) continue;
    if (lower.includes(token.raw.toLowerCase())) continue;

    const derivation = derive(token.value, [...groundedNumbers]);
    if (derivation) { derivations.push(`${token.raw} = ${derivation}`); continue; }

    flags.push({
      rule: 'numeric_token',
      detail: `"${token.raw}" does not appear in the case record`,
      token: token.raw,
    });
  }

  // 3 and 4. Clinical boundary and PHI, on the way out.
  for (const hit of checkAnswer(answerText).flags) flags.push(fromBoundary(hit));

  // 5. Certainty calibration. A value the practice merely told us is not a
  //    value the lab has verified, and the sentence has to say which it is.
  const statedOnly = grounding.filter((g) => g.kind === 'fact').length > 0 &&
    grounding.filter((g) => g.kind === 'fact')
      .every((g) => g.confirmationLevel === 'practice_stated' ||
                    g.confirmationLevel === 'system_imported');
  if (statedOnly &&
      !/\b(you|your office|the (practice|office)|the rx|prescription|imported|per your)\b/i
        .test(answerText)) {
    flags.push({
      rule: 'certainty_calibration',
      detail: 'unverified value stated as a lab-confirmed fact',
    });
  }

  // 6. The inverse failure, and the one that actually costs trust: hedging a
  //    fact the lab does know. "I think it shipped Tuesday" is a worse answer
  //    than the record it came from.
  const hasConfirmed = grounding.some(
    (g) => g.kind === 'fact' && (g.confirmationLevel === 'lab_confirmed' ||
                                 g.confirmationLevel === 'document_verified'));
  if (hasConfirmed && /\b(i think|probably|should be|might be|i believe|maybe|roughly)\b/i
      .test(answerText)) {
    flags.push({
      rule: 'hedged_fact',
      detail: 'a confirmed fact was hedged',
    });
  }

  return { ok: flags.length === 0, flags, derivations };
}

type NumberToken = { raw: string; value: number };

export function extractNumbers(text: string): NumberToken[] {
  const tokens: NumberToken[] = [];
  // Skip anything embedded in an identifier-shaped token; those are checked
  // exactly, and splitting them into digits would produce noise.
  const masked = text
    .replace(/\b[A-Z]{1,4}[- ]?\d{2,}[A-Z0-9-]*\b/g, ' ')
    .replace(/#\s*\d{1,2}\b/g, ' ');
  for (const match of masked.matchAll(/\$?\d[\d,]*(?:\.\d+)?/g)) {
    const value = Number(match[0].replace(/[$,]/g, ''));
    if (Number.isFinite(value)) tokens.push({ raw: match[0], value });
  }
  return tokens;
}

export type IdentifierToken = { kind: 'tooth' | 'shade' | 'lot' | 'tracking'; text: string };

export function extractIdentifiers(text: string): IdentifierToken[] {
  const tokens: IdentifierToken[] = [];

  for (const m of text.matchAll(/#\s*(\d{1,2})\b/g)) {
    tokens.push({ kind: 'tooth', text: `#${m[1]}` });
  }
  for (const m of text.matchAll(/\b(?:shade\s+)?([ABCD][1-4](?:\.5)?|BL[1-4]|OM[1-3]|\dM[123])\b/g)) {
    tokens.push({ kind: 'shade', text: m[1] });
  }
  for (const m of text.matchAll(/\blots?\s+([A-Z0-9][A-Z0-9-]{2,})\b/gi)) {
    // A lot designation always carries a digit; "lot number" is prose.
    if (/\d/.test(m[1])) tokens.push({ kind: 'lot', text: m[1] });
  }
  for (const m of text.matchAll(/\b(1Z[A-Z0-9]{10,}|\d{12,22})\b/g)) {
    tokens.push({ kind: 'tracking', text: m[1] });
  }
  return tokens;
}

/** Arithmetic a person at the lab would do out loud, and nothing beyond it. */
function derive(value: number, grounded: number[]): string | null {
  for (const base of grounded) {
    if (near(base * 25.4, value)) return `${base} in → mm`;
    if (near(base / 25.4, value)) return `${base} mm → in`;
    if (near(base * 1000, value)) return `${base} mm → µm`;
    if (near(base / 1000, value)) return `${base} µm → mm`;
  }
  for (let i = 0; i < grounded.length; i += 1) {
    for (let j = i + 1; j < grounded.length; j += 1) {
      if (near(grounded[i] + grounded[j], value)) return `${grounded[i]} + ${grounded[j]}`;
      if (near(Math.abs(grounded[i] - grounded[j]), value)) {
        return `${grounded[i]} − ${grounded[j]}`;
      }
    }
  }
  return null;
}

function near(a: number, b: number): boolean {
  const scale = Math.max(Math.abs(a), Math.abs(b), 1);
  return Math.abs(a - b) / scale < 0.005;
}

function stringify(value: unknown): string {
  if (value === undefined || value === null) return '';
  if (Array.isArray(value)) return value.join(' ');
  return typeof value === 'object' ? JSON.stringify(value) : String(value);
}

function fromBoundary(hit: BoundaryHit): ValidatorFlag {
  return {
    rule: hit.kind === 'phi_exposure' ? 'phi_exposure' : 'prohibited_claim',
    detail: `${hit.rule}: "${hit.matched}"`,
  };
}
