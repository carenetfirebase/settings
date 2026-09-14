import type { BoundaryHit } from './types.ts';

/**
 * Protected health information.
 *
 * A lab holds less PHI than a practice, and that is an asset worth defending:
 * a case number, initials and a tooth number run a laboratory perfectly well.
 * Two rules follow, and both are enforced structurally rather than asked for
 * politely.
 *
 *   1. PHI never enters an answer payload. The case pack excludes it at build
 *      time, so a leak needs a bug in the builder, not a clever question.
 *   2. An identified requester only ever reaches their own practice's cases.
 */
const PHI_REQUEST =
  /\b(what(?:'s| is) the patient'?s? (name|address|phone|email|date of birth|dob|insurance)|who is the patient|(give|send|tell) me the patient'?s?\b|full name of the patient|patient'?s? (details|record|chart|history|information|info)\b)/i;

const CROSS_PRACTICE =
  /\b(other (practices?|offices?|dentists?|labs?)|another (practice|office|dentist)|(everyone|all) (else|your other)|list (all|every) (cases?|patients?)|who else)\b/i;

export const PHI_TEMPLATE =
  'We keep as little patient information as we can — a case number, initials ' +
  "and the tooth is all we hold, and we're not able to share patient details. " +
  'If you have the case number I can tell you anything about the device itself.';

export const CROSS_PRACTICE_TEMPLATE =
  'I can only see cases for your own practice. For anything else, your ' +
  'technician can help directly.';

export function screenQuestion(text: string): {
  hit: BoundaryHit; template: string;
} | null {
  const phi = text.match(PHI_REQUEST);
  if (phi) {
    return {
      hit: { kind: 'phi_exposure', rule: 'patient_identifiers', matched: phi[0] },
      template: PHI_TEMPLATE,
    };
  }
  const cross = text.match(CROSS_PRACTICE);
  if (cross) {
    return {
      hit: { kind: 'phi_exposure', rule: 'cross_practice', matched: cross[0] },
      template: CROSS_PRACTICE_TEMPLATE,
    };
  }
  return null;
}

/**
 * Last line of defence on the way out: a payload that should never have
 * contained an identifier, checked for one anyway. Free to run, and the one
 * time it fires it will have been worth every cycle.
 */
const IDENTIFIER_SHAPES: { rule: string; pattern: RegExp }[] = [
  { rule: 'email', pattern: /\b[\w.+-]+@[\w-]+\.[\w.]{2,}\b/ },
  { rule: 'phone', pattern: /\b(?:\+?1[ .-]?)?\(?\d{3}\)?[ .-]\d{3}[ .-]\d{4}\b/ },
  { rule: 'date_of_birth', pattern: /\b(?:dob|date of birth)\b[:\s]*\d/i },
  { rule: 'ssn', pattern: /\b\d{3}-\d{2}-\d{4}\b/ },
  { rule: 'health_id', pattern: /\b(?:mrn|member id|policy (?:no|number))\b[:\s]*[\w-]+/i },
];

export function screenAnswer(text: string): BoundaryHit[] {
  const hits: BoundaryHit[] = [];
  for (const { rule, pattern } of IDENTIFIER_SHAPES) {
    const match = text.match(pattern);
    if (match) hits.push({ kind: 'phi_exposure', rule, matched: match[0] });
  }
  return hits;
}
