import * as clinical from './clinical-boundary.ts';
import * as phi from './phi.ts';
import type { AnswerCheck, BoundaryVerdict } from './types.ts';

export * from './types.ts';
export { PHI_TEMPLATE, CROSS_PRACTICE_TEMPLATE } from './phi.ts';

export type BoundaryContext = {
  technicianName?: string | null;
  labName?: string | null;
};

/**
 * Pre-check, before retrieval or generation.
 *
 * PHI runs first. A question can be both a patient-identity request and a
 * clinical one, and the identity refusal is the one that has to win.
 */
export function checkQuestion(text: string, ctx: BoundaryContext = {}): BoundaryVerdict {
  const phiHit = phi.screenQuestion(text);
  if (phiHit) {
    return {
      allowed: false,
      hit: phiHit.hit,
      template: fill(phiHit.template, ctx),
      offerFactKeys: [],
      escalate: false,
    };
  }

  const clinicalHit = clinical.screenQuestion(text);
  if (clinicalHit) {
    return {
      allowed: false,
      hit: clinicalHit.hit,
      template: fill(clinicalHit.template, ctx),
      offerFactKeys: clinicalHit.offerFactKeys,
      escalate: clinicalHit.escalate,
    };
  }

  return { allowed: true };
}

/** Post-check, on the generated answer. */
export function checkAnswer(text: string): AnswerCheck {
  const flags = [...phi.screenAnswer(text), ...clinical.screenAnswer(text)];
  return { ok: flags.length === 0, flags };
}

function fill(template: string, ctx: BoundaryContext): string {
  return template
    .replaceAll('{technician}', ctx.technicianName ?? 'your technician')
    .replaceAll('{lab}', ctx.labName ?? 'the lab');
}
