import type { BoundaryHit, BoundaryKind } from './types.ts';

/**
 * The clinical boundary.
 *
 * A dental technician is not licensed to diagnose, to plan treatment, or to
 * tell a dentist how to prepare a tooth — and an AI speaking for the lab
 * inherits exactly that limit. The line is not "be cautious"; it is specific
 * and it is the line the lab already lives on every day:
 *
 *   the lab may state what it made, from what, to what specification, when,
 *   and what the material manufacturer instructs.
 *
 *   the lab may not state what should be done in a mouth.
 *
 * These are templates rather than generated text so that a regulatory adviser
 * can read this file and know precisely what the product says.
 */
type Rule = {
  rule: string;
  kind: BoundaryKind;
  pattern: RegExp;
  template: string;
  offerFactKeys: string[];
  escalate?: boolean;
};

const RULES: Rule[] = [
  {
    rule: 'treatment_planning',
    kind: 'clinical_judgment',
    pattern: /\b(should i (do|place|extract|crown|prep|treat)|what would you (do|recommend)|do you think i should|is (a )?(crown|bridge|implant|onlay|veneer) the right|what treatment)\b/i,
    template:
      "That's a treatment decision, and it's yours to make — we're not able to " +
      'advise on it. What we can tell you is exactly what this case specifies:',
    offerFactKeys: ['rx.restoration_type', 'rx.material', 'rx.tooth_numbers'],
  },
  {
    rule: 'prognosis',
    kind: 'clinical_judgment',
    pattern: /\bwill (it|this|that)\b[^?.]{0,40}\b(last|fail|hold up|survive|break|crack)\b|\bhow long (will|should) (it|this|they)\b|\bis it going to fail\b|\bwhat are the odds\b|\bwill the tooth\b/i,
    template:
      "We can't predict how a restoration will perform in a particular mouth. " +
      'We can tell you the material, how it was made, and what it is warranted for:',
    offerFactKeys: ['rx.material', 'material.primary_brand', 'outcome.warranty_period'],
  },
  {
    rule: 'preparation_technique',
    kind: 'clinical_technique',
    pattern: /\b(how much should i (reduce|prep|take off)|should i prep (it )?(deeper|more)|where should i put the margin|how deep (should|do) i)\b/i,
    template:
      'How much to reduce is a clinical judgment we cannot make for you. What ' +
      'we can give you is the measurement we took and what the material requires:',
    offerFactKeys: ['design.occlusal_clearance', 'design.minimum_thickness_required',
                    'design.clearance_deficient'],
  },
  {
    rule: 'seating_technique',
    kind: 'clinical_technique',
    pattern: /\b(how do i (seat|fit|adjust|trim) it|what do i adjust|where should i adjust|can i grind|can i (reduce|adjust) the)\b/i,
    template:
      'Adjusting chairside is your call and we would not want to direct it. We ' +
      'can tell you what the material tolerates and what the manufacturer ' +
      'instructs for finishing:',
    offerFactKeys: ['material.bonding_protocol', 'material.cement_recommendation',
                    'rx.material'],
  },
  {
    rule: 'diagnosis',
    kind: 'clinical_judgment',
    pattern: /\b(is (it|this|the tooth|the patient) (infected|cracked|non.?vital|failing)|does (it|this) need (a )?(root canal|endo|extraction)|what'?s wrong with the tooth|is that decay)\b/i,
    template:
      "We're a laboratory — we can't offer a diagnosis, and we wouldn't be able " +
      'to see what you can. On the case itself:',
    offerFactKeys: ['rx.tooth_numbers', 'case.notes_to_practice'],
    escalate: true,
  },
  {
    rule: 'material_substitution',
    kind: 'rx_deviation',
    pattern: /\b(just (use|do|make it in)|can you (swap|substitute|change it to|use .* instead)|go ahead and (use|change)|make it (in )?\w+ instead)\b/i,
    template:
      "We can't change the prescribed material on our own — a substitution needs " +
      'your written authorisation on the case, and then we will make it exactly ' +
      'as you specify. Shall I put that request through to your technician?',
    offerFactKeys: ['rx.material', 'rx.material_alternate_authorized'],
    escalate: true,
  },
  {
    rule: 'skip_a_step',
    kind: 'rx_deviation',
    pattern: /\b(skip the (try.?in|bite|impression)|don'?t bother with|just (guess|estimate|pick) (the|a) (shade|bite|margin)|make it up|use your judgement on the shade)\b/i,
    template:
      "We'd rather not guess at that — a guessed shade or bite is the most " +
      'common reason a case comes back. If you can send it through we will get ' +
      'straight on with it, or your technician can talk through the options.',
    offerFactKeys: ['case.hold_reason'],
    escalate: true,
  },
  {
    rule: 'billing_advice',
    kind: 'billing_advice',
    pattern: /\b(what code should i (bill|submit|use)|how do i bill (this|it)|will insurance (cover|pay)|can i bill it as)\b/i,
    template:
      'We can tell you the code we billed this case under, but what you submit ' +
      'to a payer is your decision and your liability — we are not able to ' +
      'advise on coding.',
    offerFactKeys: ['commercial.billing_code', 'commercial.quoted_price'],
  },
  {
    rule: 'regulatory_opinion',
    kind: 'regulatory_opinion',
    pattern: /\b(are|is)\b[^?]{0,24}\b(compliant|compliance)\b|\bdoes (this|that|it) meet (the )?(regulations?|requirements?|standards?)\b|\bis (this|that|it) (fda|mdr|ce|legal|allowed)\b|\b(fda|mdr|ce)[- ]?(approved|registered|compliant|cleared)\b/i,
    template:
      'We can show you exactly what we recorded and issued for this case. ' +
      'Whether that satisfies a particular regulation is a question for your ' +
      "own adviser — we're not able to give a compliance opinion.",
    offerFactKeys: ['reg.device_statement_issued', 'reg.dhr_complete',
                    'reg.lot_traceable', 'reg.quality_system'],
  },
];

/** What the lab must never state, however the question arrived. */
const ANSWER_RULES: { rule: string; kind: BoundaryKind; pattern: RegExp }[] = [
  { rule: 'answer_diagnosis', kind: 'clinical_judgment',
    pattern: /\b(the tooth is (cracked|infected|non.?vital)|you (should|need to) (extract|do endo|prep|reduce)|i(t)?'?d recommend you)\b/i },
  { rule: 'answer_prognosis', kind: 'clinical_judgment',
    pattern: /\b(it will last|should last (for )?\d+ (years|yrs)|it won'?t fail|guaranteed not to)\b/i },
  { rule: 'answer_technique_instruction', kind: 'clinical_technique',
    pattern: /\breduce (the|it)\b[^.]{0,24}\b(another|by)\b\s*[\d.]|\btake (another|off) [\d.]|\bgrind (off|down) the\b|\badjust the (occlusion|contact) (by|until)\b/i },
  { rule: 'answer_substitution_promise', kind: 'rx_deviation',
    pattern: /\b(we('| a)?ll just (use|swap|substitute)|we changed (it|the material) to|we went with \w+ instead)\b/i },
  { rule: 'answer_compliance_opinion', kind: 'regulatory_opinion',
    pattern: /\b(this (is|was) (fully )?compliant|meets? (all )?(fda|mdr|ce|regulatory) requirements|approved by the fda)\b/i },
  { rule: 'answer_billing_instruction', kind: 'billing_advice',
    pattern: /\b(bill it as|submit it under|you can code (it|this) as|insurance will cover)\b/i },
];

export function screenQuestion(text: string) {
  for (const rule of RULES) {
    const match = text.match(rule.pattern);
    if (!match) continue;
    return {
      hit: { kind: rule.kind, rule: rule.rule, matched: match[0] } satisfies BoundaryHit,
      template: rule.template,
      offerFactKeys: rule.offerFactKeys,
      escalate: rule.escalate === true,
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
