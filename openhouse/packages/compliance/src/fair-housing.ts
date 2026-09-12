import type { BoundaryHit } from './types.ts';

/**
 * Fair housing (§12.1).
 *
 * Steering liability attaches to the agent, and an AI that answers "is this a
 * good family neighbourhood?" has created it. These patterns are deliberately
 * broad: a false refusal costs one redirect, a false permit costs a complaint.
 */
type Rule = { rule: string; pattern: RegExp; };

const QUESTION_RULES: Rule[] = [
  { rule: 'safety_judgment',
    pattern: /\b(safe|unsafe|dangerous|sketchy|rough|crime[- ]?ridden|is it safe)\b/i },
  { rule: 'area_quality',
    pattern: /\b(good|bad|nice|decent|desirable|up[- ]and[- ]coming|going downhill)\s+(neighbou?rhood|area|part of town|street|block)\b/i },
  { rule: 'neighbourhood_character',
    pattern: /\b(what (kind|sort|type) of (people|families|folks|crowd)|who lives (here|around here|nearby)|what are the neighbours like)\b/i },
  { rule: 'race_ethnicity_religion',
    pattern: /\b(rac(e|ial)|ethnic|white|black|asian|hispanic|latino|jewish|muslim|christian|church[- ]going|immigrant|diverse|diversity)\b/i },
  { rule: 'familial_status',
    pattern: /\b(family|families|kid|kids|children|child)[- ]?(friendly|oriented)\b|\b(good|right) (place|area|neighbou?rhood) (to raise|for) (a )?(kids|children|family)\b|\b(families|kids|children)\s+(around here|nearby|in the area|on the street|in the neighbou?rhood)\b/i },
  { rule: 'age_composition',
    pattern: /\b(young|old|older|retired|elderly|middle[- ]aged)\s+(people|couples|families|folks|professionals|residents|crowd)\b|\b(retirees|seniors|elderly)\b|\baverage age (of|in) the\b/i },
  { rule: 'disability',
    pattern: /\b(disabled|handicapped|group home|halfway house|special needs)\s+(people|residents|neighbou?rs)\b/i },
  { rule: 'sexual_orientation_gender',
    pattern: /\b(gay|lesbian|lgbt|queer|trans(gender)?)\s+(neighbou?rhood|area|friendly|community)\b/i },
  // Any judgment word within the same clause as "school" — catchment questions
  // ("which schools serve this address") carry none and pass through.
  { rule: 'school_quality',
    pattern: /\bschools?\b[^?.]*\b(good|bad|best|worst|top|bottom|rated|rating|ranking|quality|score|reputation)\b|\b(good|bad|best|worst|top|bottom|highly[- ]rated|poorly[- ]rated)\b[^?.]*\bschools?\b/i },
];

/** The same judgments are forbidden in an answer, however the question arrived. */
const ANSWER_RULES: Rule[] = [
  // Two shapes: a bare safety verdict ("it is a safe area"), and any quality
  // adjective attached to a place noun ("a nice neighbourhood").
  { rule: 'answer_area_judgment',
    pattern: /\b(it'?s|it is|this is|you'?re in)\s+(a\s+)?(very |really |quite |pretty )?(safe|unsafe|dangerous|sketchy)\b|\b(nice|good|great|desirable|family[- ]friendly|quiet|up[- ]and[- ]coming)\s+(neighbou?rhood|area|street|block|part of town)\b/i },
  { rule: 'answer_school_judgment',
    pattern: /\b(excellent|great|top[- ]rated|highly[- ]rated|good)\s+schools?\b/i },
  { rule: 'answer_demographics',
    pattern: /\b(mostly|mainly|predominantly)\s+(young|old|white|black|asian|jewish|christian|muslim|families|retirees|professionals)\b/i },
  { rule: 'answer_crime_claim',
    pattern: /\b(low|high|no)\s+crime\b|\bcrime (is|rate is) (low|high)\b/i },
];

export const FAIR_HOUSING_TEMPLATES: Record<string, string> = {
  safety_judgment:
    "That's not something I can assess. I can tell you the property's location " +
    'and the amenities nearby, and public crime statistics are published by the ' +
    'city — {agent} can also point you to local resources.',
  area_quality:
    "I'm not able to rate a neighbourhood — that's a judgment I'd rather leave " +
    'with you. I can tell you what\'s nearby and answer anything about the home itself.',
  neighbourhood_character:
    "I'm not able to describe who lives in an area. I can share verified " +
    'information about the property and the amenities around it.',
  race_ethnicity_religion:
    "I'm not able to discuss the demographics of an area. I can tell you about " +
    'the home and what\'s nearby.',
  familial_status:
    "I can't characterise who a neighbourhood suits — that's yours to judge. " +
    'I can tell you the schools that serve this address, the parks nearby, and ' +
    'anything about the house itself.',
  age_composition:
    "I'm not able to describe who lives nearby. I can tell you about the property " +
    'and the amenities around it.',
  disability:
    "I'm not able to discuss who lives in an area. I can tell you about the home, " +
    'including its accessibility features.',
  sexual_orientation_gender:
    "I'm not able to describe an area's residents. I can tell you about the " +
    'property and what\'s nearby.',
  school_quality:
    'I can tell you which schools serve this address and how far they are. School ' +
    "quality ratings are subjective and I'd rather you evaluate those yourself — " +
    'the provincial education site publishes results.',
};

/** Facts a refusal may still offer, so the visitor is never left empty-handed. */
export const FAIR_HOUSING_OFFERS: Record<string, string[]> = {
  safety_judgment: ['location.transit.nearest_stop', 'location.amenities.parks'],
  area_quality: ['location.amenities.groceries', 'location.amenities.parks'],
  neighbourhood_character: ['location.amenities.parks'],
  race_ethnicity_religion: [],
  familial_status: ['location.schools.catchment', 'location.amenities.parks'],
  age_composition: ['location.amenities.parks'],
  disability: ['structure.accessibility.features', 'structure.accessibility.step_free_entry'],
  sexual_orientation_gender: [],
  school_quality: ['location.schools.catchment'],
};

export function screenQuestion(text: string): BoundaryHit | null {
  for (const { rule, pattern } of QUESTION_RULES) {
    const match = text.match(pattern);
    if (match) return { kind: 'fair_housing', rule, matched: match[0] };
  }
  return null;
}

export function screenAnswer(text: string): BoundaryHit[] {
  const hits: BoundaryHit[] = [];
  for (const { rule, pattern } of ANSWER_RULES) {
    const match = text.match(pattern);
    if (match) hits.push({ kind: 'fair_housing', rule, matched: match[0] });
  }
  return hits;
}
