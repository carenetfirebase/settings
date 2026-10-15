import { allergenLexicon } from '../shared';

/**
 * Server-side mirror of lib/domain/safety/allergen_guard.dart, driven by the
 * same exported lexicon. AI output is never trusted to respect allergies:
 * every generated recipe passes through here, and again on the client.
 */
export interface DietaryProfile {
  allergyStatus?: string;
  allergies: string[];
  intolerances: string[];
  restrictions: string[];
  dislikes: string[];
}

export interface Conflict {
  ingredient: string;
  reason: string;
  severity: 'allergy' | 'intolerance' | 'restriction' | 'dislike';
  key: string;
}

const normalise = (s: string): string =>
  ` ${s.toLowerCase().replace(/[^a-z0-9àâçéèêëîïôûùüÿñæœ'\- ]/g, ' ').replace(/\s+/g, ' ').trim()} `;

const escape = (s: string): string => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function containsAny(text: string, terms: string[], exclusions: string[]): boolean {
  let t = text;
  for (const ex of exclusions) t = t.split(ex.toLowerCase()).join(' ');
  return terms.some((term) => new RegExp(`(^|[^a-z])${escape(term.toLowerCase())}(s|es)?([^a-z]|$)`).test(t));
}

export function detectAllergens(ingredient: string, productAllergens: string[] = []): Set<string> {
  const text = normalise(ingredient);
  const found = new Set<string>(productAllergens);
  for (const a of allergenLexicon.allergens) {
    if (containsAny(text, a.terms, a.exclusions)) found.add(a.key);
  }
  if (found.has('wheat')) found.add('gluten');
  return found;
}

export function checkIngredients(ingredients: Array<{ name: string; allergens?: string[] }>, p: DietaryProfile): Conflict[] {
  const out: Conflict[] = [];
  const labels = new Map(allergenLexicon.allergens.map((a) => [a.key, a.label]));
  for (const ing of ingredients) {
    const detected = detectAllergens(ing.name, ing.allergens ?? []);
    const text = normalise(ing.name);
    for (const k of p.allergies) {
      if (detected.has(k)) out.push({ ingredient: ing.name, reason: `Contains ${labels.get(k) ?? k}`, severity: 'allergy', key: k });
    }
    for (const k of p.intolerances) {
      const a = allergenLexicon.intolerances[k];
      if (a && detected.has(a)) out.push({ ingredient: ing.name, reason: `May not suit ${k} intolerance`, severity: 'intolerance', key: k });
    }
    for (const k of p.restrictions) {
      const r = allergenLexicon.restrictions.find((x) => x.key === k);
      if (!r) continue;
      if (r.excludedAllergens.some((a) => detected.has(a)) || containsAny(text, r.excludedTerms, r.exclusions)) {
        out.push({ ingredient: ing.name, reason: `Not ${r.label.toLowerCase()}`, severity: 'restriction', key: k });
      }
    }
    for (const d of p.dislikes) {
      const dn = normalise(d).trim();
      if (dn && containsAny(text, [dn], [])) out.push({ ingredient: ing.name, reason: `Prefers to avoid ${d}`, severity: 'dislike', key: d });
    }
  }
  return out;
}

export const isBlocked = (conflicts: Conflict[]): boolean =>
  conflicts.some((c) => c.severity === 'allergy' || c.severity === 'restriction');

/** Strictest combination for shared household meals. */
export function mergeProfiles(...ps: DietaryProfile[]): DietaryProfile {
  const u = (f: (p: DietaryProfile) => string[]) => [...new Set(ps.flatMap(f))];
  return { allergies: u((p) => p.allergies), intolerances: u((p) => p.intolerances), restrictions: u((p) => p.restrictions), dislikes: u((p) => p.dislikes) };
}
