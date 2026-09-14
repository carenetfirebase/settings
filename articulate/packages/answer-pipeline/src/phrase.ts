import { humanize } from '../../truth-engine/src/normalize.ts';
import type { GroundingItem } from './validator.ts';

export type PhraseRequest = {
  question: string;
  grounding: GroundingItem[];
  technicianName?: string | null;
  labName?: string | null;
  maxSentences?: number;
};

/**
 * Compose an answer from the grounding payload, without a model.
 *
 * This is the floor of the fallback ladder and the reference implementation of
 * "phrase, do not decide": it can only ever emit values that are in the
 * payload, so it cannot invent one. A model-backed provider implements the same
 * signature and passes through the same validator — the difference is how it
 * reads, not what it may say.
 */
export function phrase(req: PhraseRequest): string {
  const technician = req.technicianName ?? 'your technician';
  const facts = req.grounding.filter((g) => g.kind === 'fact');
  const unknowns = req.grounding.filter((g) => g.kind === 'unknown');
  const asks = req.grounding.filter((g) => g.kind === 'ask');
  const status = req.grounding.filter((g) => g.kind === 'status');
  const materials = req.grounding.filter((g) => g.kind === 'material');
  const policy = req.grounding.filter((g) => g.kind === 'policy');

  const sentences: string[] = [];

  // What is blocking the case leads. A practice that has to ask twice for the
  // same missing item is a practice that starts calling a different lab.
  for (const ask of asks.slice(0, 2)) sentences.push(ask.text ?? ask.label);

  for (const item of status.slice(0, 1)) sentences.push(item.text ?? item.label);

  for (const fact of facts.slice(0, 3)) sentences.push(factSentence(fact));

  for (const material of materials.slice(0, 2)) {
    sentences.push(`${material.label}: ${material.display ?? material.text}.`);
  }

  for (const unknown of unknowns.slice(0, 2)) {
    sentences.push(unknownSentence(unknown, technician));
  }

  for (const item of policy.slice(0, 1)) sentences.push(item.text ?? item.label);

  if (sentences.length === 0) {
    return `I don't have that on the case record. Shall I put it to ${technician}?`;
  }
  return sentences.slice(0, req.maxSentences ?? 3).join(' ');
}

function factSentence(item: GroundingItem): string {
  const value = item.display ?? format(item.value);
  const stated = item.confirmationLevel === 'practice_stated'
    ? ' (as your office gave it to us)'
    : '';

  if (typeof item.value === 'boolean') {
    return item.value
      ? `Yes — ${lower(item.label)} is confirmed${stated}.`
      : `No — ${lower(item.label)} is not${stated}.`;
  }
  return `${cap(item.label)}: ${strip(value)}${stated}.`;
}

function unknownSentence(item: GroundingItem, technician: string): string {
  const subject = lower(item.label);
  switch (item.unknownReason) {
    case 'practice_has_not_supplied':
      return `We don't have the ${subject} — it hasn't come through from your office yet.`;
    case 'not_recorded_at_the_time':
      return `The ${subject} wasn't recorded on this case, so I'd rather not guess at it.`;
    case 'awaiting_supplier':
      return `We're waiting on the supplier for the ${subject}.`;
    case 'will_follow_up':
      return `${cap(technician)} is confirming the ${subject} and will come back to you.`;
    default:
      return `I don't have the ${subject} on record. Shall I ask ${technician}?`;
  }
}

function format(value: unknown): string {
  if (value === undefined || value === null) return 'not recorded';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (Array.isArray(value)) return value.join(', ');
  if (typeof value === 'string') return value.includes('_') ? humanize(value) : value;
  return String(value);
}

const cap = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);
const lower = (s: string): string => s.charAt(0).toLowerCase() + s.slice(1);
const strip = (s: string): string => s.replace(/\.\s*$/, '');
