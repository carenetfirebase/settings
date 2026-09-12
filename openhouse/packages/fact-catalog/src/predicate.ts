import type { ApplicabilityContext, JsonValue, Predicate, Ternary } from './types.ts';

/**
 * Three-valued predicate evaluation.
 *
 * The third value matters. If the agent has not yet said whether the home has
 * a garage, "is the garage heated?" is neither applicable nor inapplicable —
 * it is unresolved. Counting unresolved facts as applicable inflates the
 * denominator and makes coverage look broken; counting them as inapplicable
 * silently drops real buyer questions. So they come out as 'unknown' and the
 * console asks the agent one short setup question instead of guessing.
 */
export function evaluate(pred: Predicate, ctx: ApplicabilityContext): Ternary {
  if ('always' in pred) return true;

  if ('all' in pred) {
    let sawUnknown = false;
    for (const p of pred.all) {
      const r = evaluate(p, ctx);
      if (r === false) return false;
      if (r === 'unknown') sawUnknown = true;
    }
    return sawUnknown ? 'unknown' : true;
  }

  if ('any' in pred) {
    let sawUnknown = false;
    for (const p of pred.any) {
      const r = evaluate(p, ctx);
      if (r === true) return true;
      if (r === 'unknown') sawUnknown = true;
    }
    return sawUnknown ? 'unknown' : false;
  }

  if ('not' in pred) {
    const r = evaluate(pred.not, ctx);
    return r === 'unknown' ? 'unknown' : !r;
  }

  const actual = ctx[pred.field];
  if (actual === undefined || actual === null) return 'unknown';

  switch (pred.op) {
    case 'eq':     return sameValue(actual, pred.value);
    case 'ne':     return !sameValue(actual, pred.value);
    case 'in':     return pred.value.some((v) => sameValue(actual, v));
    case 'not_in': return !pred.value.some((v) => sameValue(actual, v));
    case 'is_true':  return actual === true;
    case 'is_false': return actual === false;
    case 'gte':    return typeof actual === 'number' ? actual >= pred.value : 'unknown';
    case 'lte':    return typeof actual === 'number' ? actual <= pred.value : 'unknown';
  }
}

function sameValue(a: JsonValue, b: JsonValue): boolean {
  if (typeof a !== 'object' || a === null) return a === b;
  return JSON.stringify(a) === JSON.stringify(b);
}

/** Every context field the predicate reads — the source of the setup questionnaire. */
export function referencedFields(pred: Predicate, into: Set<string> = new Set()): Set<string> {
  if ('always' in pred) return into;
  if ('all' in pred) { for (const p of pred.all) referencedFields(p, into); return into; }
  if ('any' in pred) { for (const p of pred.any) referencedFields(p, into); return into; }
  if ('not' in pred) return referencedFields(pred.not, into);
  into.add(pred.field);
  return into;
}
