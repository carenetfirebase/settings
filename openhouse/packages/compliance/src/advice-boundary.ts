import type { BoundaryHit } from './types.ts';

/**
 * Licensed advice boundary (§12.2).
 *
 * Each row is a template, not a generated response — counsel can read this file
 * and know exactly what the product says. The shape is always the same: give
 * the verified fact, decline the judgment, name the person whose job it is.
 */
type Rule = {
  rule: string;
  kind: BoundaryHit['kind'];
  pattern: RegExp;
  template: string;
  offerFactKeys: string[];
};

const RULES: Rule[] = [
  {
    rule: 'offer_strategy',
    kind: 'offer_strategy',
    pattern: /\b(what should i offer|how much should i (offer|bid)|should i offer|will they take|would they accept|how low (can|will) they go|room to negotiate|lowball)\b/i,
    template:
      'The list price is {price}. I can\'t advise on offer strategy — that\'s ' +
      'exactly the kind of thing {agent} is here for.',
    offerFactKeys: ['listing.price.list', 'listing.offer_presentation'],
  },
  {
    rule: 'price_fairness',
    kind: 'valuation',
    pattern: /\b(is (the|this) price (fair|right|too high|too low)|is it (over|under)priced|is it worth\b|what('s| is) it (really )?worth)\b/i,
    template:
      'I can tell you the list price and any verified fact about the property. ' +
      'Assessing the pricing is {agent}\'s area.',
    offerFactKeys: ['listing.price.list', 'taxes.assessed_value'],
  },
  {
    rule: 'investment_merit',
    kind: 'investment_advice',
    pattern: /\b(good investment|is this a good (buy|deal|investment)|will (it|this) (appreciate|go up|hold its value)|resale value|flip this)\b/i,
    template:
      'I can\'t assess investment merit or predict what values will do. I can ' +
      'give you verified facts about the property, and {agent} can talk through ' +
      'the market with you.',
    offerFactKeys: ['listing.price.list', 'taxes.assessed_value', 'property.year_built'],
  },
  {
    rule: 'legal_permission',
    kind: 'legal_conclusion',
    pattern: /\b(can i (legally )?(rent|subdivide|build|add|convert|run a business)|am i allowed to|is it legal (to|for me)|would i be allowed)\b/i,
    template:
      'What you\'d be allowed to do depends on municipal permitting and the rules ' +
      'that apply to this property, so that\'s a question for the city or for ' +
      '{agent}. Here\'s what I can verify:',
    offerFactKeys: ['property.zoning', 'basement.suite_status',
                    'legal.secondary_suite_registration', 'basement.suite.separate_entrance'],
  },
  {
    rule: 'condition_diagnosis',
    kind: 'inspection_conclusion',
    pattern: /\b(is (this|that) (crack|stain|smell|noise|mark) (serious|bad|a problem|structural)|how bad is|do i need to (fix|replace)|is it about to (fail|go)|how much life (is )?left)\b/i,
    template:
      'I can\'t evaluate condition — a home inspection is the right way to answer ' +
      'that. What I can tell you is what\'s on record:',
    offerFactKeys: ['legal.disclosure.material_latent_defects',
                    'legal.inspection.recent_report'],
  },
  {
    rule: 'financing_tax_advice',
    kind: 'investment_advice',
    pattern: /\b(what (would|will) my (mortgage|payment)|can i afford|what rate (can|will) i get|tax (write[- ]?off|deduction)|should i (buy|wait))\b/i,
    template:
      'I can\'t advise on financing or tax — a mortgage professional and your ' +
      'accountant are the right people. I can give you the price, taxes and ' +
      'operating costs on record.',
    offerFactKeys: ['listing.price.list', 'taxes.annual_amount',
                    'costs.utilities.annual_gas', 'costs.utilities.annual_electricity'],
  },
];

/**
 * Claims a generated answer must never make, whatever the question was (§11.6).
 * These fire on the answer, after generation.
 */
const ANSWER_RULES: { rule: string; kind: BoundaryHit['kind']; pattern: RegExp }[] = [
  { rule: 'answer_valuation', kind: 'valuation',
    pattern: /\b(it'?s worth|market value is|underpriced|overpriced|a (great|good) (deal|buy|price)|priced (well|right|to sell))\b/i },
  { rule: 'answer_appreciation', kind: 'investment_advice',
    pattern: /\b(will (appreciate|increase in value|go up)|solid investment|values? (are|will be) (rising|going up))\b/i },
  { rule: 'answer_legal_conclusion', kind: 'legal_conclusion',
    pattern: /\b(you (can|could|would be able to) legally|it'?s legal to|you'?re allowed to|zoning allows you to)\b/i },
  { rule: 'answer_inspection_conclusion', kind: 'inspection_conclusion',
    pattern: /\b(nothing to worry about|that'?s (just )?(normal|cosmetic|nothing)|structurally sound|in (good|great) (shape|condition)|no (structural )?(issues|problems))\b/i },
  { rule: 'answer_permit_assertion', kind: 'permit_assertion',
    pattern: /\b(fully permitted|all (the )?permits (are|were) (in place|pulled)|up to code|meets? code)\b/i },
];

export type AdviceMatch = {
  hit: BoundaryHit;
  template: string;
  offerFactKeys: string[];
};

export function screenQuestion(text: string): AdviceMatch | null {
  for (const rule of RULES) {
    const match = text.match(rule.pattern);
    if (!match) continue;
    return {
      hit: { kind: rule.kind, rule: rule.rule, matched: match[0] },
      template: rule.template,
      offerFactKeys: rule.offerFactKeys,
    };
  }
  return null;
}

export function screenAnswer(text: string): BoundaryHit[] {
  const hits: BoundaryHit[] = [];
  for (const rule of ANSWER_RULES) {
    const match = text.match(rule.pattern);
    if (match) hits.push({ kind: rule.kind, rule: rule.rule, matched: match[0] });
  }
  return hits;
}
