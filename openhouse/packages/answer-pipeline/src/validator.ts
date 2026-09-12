import { checkAnswer } from '../../compliance/src/index.ts';
import type { BoundaryHit } from '../../compliance/src/index.ts';
import type { GroundingItem } from '../../ai-gateway/src/index.ts';

export type ValidatorFlag = {
  rule: 'numeric_token' | 'prohibited_claim' | 'fair_housing' | 'certainty_calibration';
  detail: string;
  token?: string;
};

export type ValidationResult = {
  ok: boolean;
  flags: ValidatorFlag[];
  /** Derivations we accepted, logged so a reviewer can check the arithmetic. */
  derivations: string[];
};

/** Numbers that are not property claims: counts of sentences, ordinals, years-ago. */
const TRIVIAL_NUMBERS = new Set([0, 1, 2]);

/**
 * The validator (§11.6). Runs on every generated answer before it is spoken.
 *
 * This is what turns the zero-hallucination policy from a prompt into a system
 * property. Prompts are requests; validators are guarantees. A blocked answer
 * is a bug, and we want to see every one of them — hence `flags`, which go
 * straight to the ledger.
 */
export function validateAnswer(
  answerText: string,
  grounding: GroundingItem[],
): ValidationResult {
  const flags: ValidatorFlag[] = [];
  const derivations: string[] = [];

  // 1. Every number, year and measurement must be traceable to the payload.
  const groundedNumbers = collectGroundedNumbers(grounding);
  const groundedText = grounding
    .map((g) => [g.display, g.text, stringify(g.value)].filter(Boolean).join(' '))
    .join(' ')
    .toLowerCase();

  for (const token of extractNumbers(answerText)) {
    if (TRIVIAL_NUMBERS.has(token.value)) continue;
    if (groundedNumbers.has(token.value)) continue;
    if (groundedText.includes(token.raw.toLowerCase())) continue;

    const derivation = deriveFrom(token.value, groundedNumbers);
    if (derivation) { derivations.push(`${token.raw} = ${derivation}`); continue; }

    flags.push({
      rule: 'numeric_token',
      detail: `"${token.raw}" does not appear in the grounding payload`,
      token: token.raw,
    });
  }

  // 2 and 3. Prohibited claim patterns and the fair housing linter.
  const boundary = checkAnswer(answerText);
  for (const hit of boundary.flags) flags.push(fromBoundary(hit));

  // 4. Certainty calibration: an answer sourced from commentary must not use
  //    verified-fact phrasing. "The seller mentions", not "The home has".
  const onlyCommentary =
    grounding.length > 0 && grounding.every((g) => g.kind === 'commentary');
  if (onlyCommentary && !/\b(mentions?|says?|said|describes?|notes?|tells? me|according to)\b/i.test(answerText)) {
    flags.push({
      rule: 'certainty_calibration',
      detail: 'commentary stated with verified-fact phrasing',
    });
  }

  return { ok: flags.length === 0, flags, derivations };
}

type NumberToken = { raw: string; value: number };

/**
 * Numbers as they appear in speech: 2019, $4,620, 2,140 sq ft, 96%, 8.5 ft.
 * Ordinals and words are ignored — this looks for claims, not prose.
 */
export function extractNumbers(text: string): NumberToken[] {
  const tokens: NumberToken[] = [];
  const pattern = /\$?\d[\d,]*(?:\.\d+)?/g;
  for (const match of text.matchAll(pattern)) {
    const raw = match[0];
    const value = Number(raw.replace(/[$,]/g, ''));
    if (Number.isFinite(value)) tokens.push({ raw, value });
  }
  return tokens;
}

function collectGroundedNumbers(grounding: GroundingItem[]): Set<number> {
  const numbers = new Set<number>();
  for (const item of grounding) {
    for (const source of [item.display, item.text, stringify(item.value)]) {
      if (!source) continue;
      for (const token of extractNumbers(source)) numbers.add(token.value);
    }
  }
  return numbers;
}

/**
 * Trivially derived values are allowed, with the derivation logged: a unit
 * conversion, a simple sum, or an age computed from a year. Anything cleverer
 * than this is the model reasoning about property facts, which is exactly what
 * it must not do.
 */
function deriveFrom(value: number, grounded: Set<number>): string | null {
  const values = [...grounded];
  const currentYear = new Date().getUTCFullYear();

  for (const base of values) {
    if (base > 1900 && base <= currentYear && currentYear - base === value) {
      return `${currentYear} − ${base} (age in years)`;
    }
    if (near(base * 0.092903, value)) return `${base} sq ft → m²`;
    if (near(base * 10.7639, value)) return `${base} m² → sq ft`;
    if (near(base * 0.3048, value)) return `${base} ft → m`;
    if (near(base / 12, value)) return `${base} ÷ 12 (annual → monthly)`;
    if (near(base * 12, value)) return `${base} × 12 (monthly → annual)`;
  }

  for (let i = 0; i < values.length; i += 1) {
    for (let j = i + 1; j < values.length; j += 1) {
      if (near(values[i] + values[j], value)) return `${values[i]} + ${values[j]}`;
    }
  }

  // Three-term sums cover "gas + power + water".
  for (let i = 0; i < values.length; i += 1) {
    for (let j = i + 1; j < values.length; j += 1) {
      for (let k = j + 1; k < values.length; k += 1) {
        if (near(values[i] + values[j] + values[k], value)) {
          return `${values[i]} + ${values[j]} + ${values[k]}`;
        }
      }
    }
  }
  return null;
}

function near(a: number, b: number): boolean {
  const scale = Math.max(Math.abs(a), Math.abs(b), 1);
  return Math.abs(a - b) / scale < 0.01;
}

function stringify(value: unknown): string {
  if (value === undefined || value === null) return '';
  return typeof value === 'object' ? JSON.stringify(value) : String(value);
}

function fromBoundary(hit: BoundaryHit): ValidatorFlag {
  return {
    rule: hit.kind === 'fair_housing' ? 'fair_housing' : 'prohibited_claim',
    detail: `${hit.rule}: "${hit.matched}"`,
  };
}
