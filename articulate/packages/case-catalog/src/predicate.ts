import type { CaseContext, JsonValue, Predicate, Ternary } from './types.ts';

/**
 * Three-valued applicability.
 *
 * "Unknown" is the whole point. Until the prescription says whether this is
 * screw-retained, "what torque value?" is neither required nor irrelevant — it
 * is unresolved, and the right move is to ask the practice one short question
 * rather than guess and either nag or silently skip a blocking field.
 */
export function evaluate(pred: Predicate, ctx: CaseContext): Ternary {
  if ('always' in pred) return true;

  if ('all' in pred) {
    let unknown = false;
    for (const p of pred.all) {
      const r = evaluate(p, ctx);
      if (r === false) return false;
      if (r === 'unknown') unknown = true;
    }
    return unknown ? 'unknown' : true;
  }

  if ('any' in pred) {
    let unknown = false;
    for (const p of pred.any) {
      const r = evaluate(p, ctx);
      if (r === true) return true;
      if (r === 'unknown') unknown = true;
    }
    return unknown ? 'unknown' : false;
  }

  if ('not' in pred) {
    const r = evaluate(pred.not, ctx);
    return r === 'unknown' ? 'unknown' : !r;
  }

  const actual = ctx[pred.field];
  if (actual === undefined || actual === null) return 'unknown';

  switch (pred.op) {
    case 'eq':       return same(actual, pred.value);
    case 'ne':       return !same(actual, pred.value);
    case 'in':       return pred.value.some((v) => same(actual, v));
    case 'not_in':   return !pred.value.some((v) => same(actual, v));
    case 'is_true':  return actual === true;
    case 'is_false': return actual === false;
    case 'gte':      return typeof actual === 'number' ? actual >= pred.value : 'unknown';
    case 'lte':      return typeof actual === 'number' ? actual <= pred.value : 'unknown';
  }
}

function same(a: JsonValue, b: JsonValue): boolean {
  if (typeof a !== 'object' || a === null) return a === b;
  return JSON.stringify(a) === JSON.stringify(b);
}

export function referencedFields(pred: Predicate, into: Set<string> = new Set()): Set<string> {
  if ('always' in pred) return into;
  if ('all' in pred) { for (const p of pred.all) referencedFields(p, into); return into; }
  if ('any' in pred) { for (const p of pred.any) referencedFields(p, into); return into; }
  if ('not' in pred) return referencedFields(pred.not, into);
  into.add(pred.field);
  return into;
}
