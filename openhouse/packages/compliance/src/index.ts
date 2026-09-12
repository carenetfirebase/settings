import * as fairHousing from './fair-housing.ts';
import * as advice from './advice-boundary.ts';
import type { AnswerCheck, BoundaryVerdict } from './types.ts';

export * from './types.ts';
export { FAIR_HOUSING_TEMPLATES, FAIR_HOUSING_OFFERS } from './fair-housing.ts';

export type BoundaryContext = {
  agentName?: string | null;
  priceDisplay?: string | null;
};

/**
 * Pre-check, before any retrieval or generation (§11 step 3).
 *
 * Fair housing runs first: a question can be both a valuation question and a
 * steering question, and the steering refusal is the one that must win.
 */
export function checkQuestion(text: string, ctx: BoundaryContext = {}): BoundaryVerdict {
  const housing = fairHousing.screenQuestion(text);
  if (housing) {
    return {
      allowed: false,
      hit: housing,
      template: fill(fairHousing.FAIR_HOUSING_TEMPLATES[housing.rule] ??
                     fairHousing.FAIR_HOUSING_TEMPLATES.area_quality, ctx),
      offerFactKeys: fairHousing.FAIR_HOUSING_OFFERS[housing.rule] ?? [],
    };
  }

  const adviceMatch = advice.screenQuestion(text);
  if (adviceMatch) {
    return {
      allowed: false,
      hit: adviceMatch.hit,
      template: fill(adviceMatch.template, ctx),
      offerFactKeys: adviceMatch.offerFactKeys,
    };
  }

  return { allowed: true };
}

/** Post-check, on the generated answer (§11 step 12). */
export function checkAnswer(text: string): AnswerCheck {
  const flags = [...fairHousing.screenAnswer(text), ...advice.screenAnswer(text)];
  return { ok: flags.length === 0, flags };
}

function fill(template: string, ctx: BoundaryContext): string {
  return template
    .replaceAll('{agent}', ctx.agentName ?? 'the listing agent')
    .replaceAll('{price}', ctx.priceDisplay ?? 'the list price');
}
