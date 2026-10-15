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

const FOLD: Record<string, string> = {
  à: 'a', á: 'a', â: 'a', ä: 'a', ã: 'a', å: 'a', ç: 'c', é: 'e', è: 'e', ê: 'e', ë: 'e',
  í: 'i', ì: 'i', î: 'i', ï: 'i', ñ: 'n', ó: 'o', ò: 'o', ô: 'o', ö: 'o', õ: 'o',
  ú: 'u', ù: 'u', û: 'u', ü: 'u', ÿ: 'y', æ: 'ae', œ: 'oe', ß: 'ss',
};

/** Mirrors AllergenGuard.normalise: fold accents, keep [a-z0-9'- ], pad with spaces. */
export const normalise = (s: string): string => {
  const folded = [...s.toLowerCase()].map((c) => FOLD[c] ?? c).join('');
  return ` ${folded.replace(/[’‘`]/g, "'").replace(/[^a-z0-9'\- ]/g, ' ').replace(/\s+/g, ' ').trim()} `;
};

const escape = (s: string): string => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const patterns = new Map<string, string>();
const wordPattern = (term: string): string => {
  let p = patterns.get(term);
  if (p === undefined) {
    p = `(^|[^a-z])${escape(normalise(term).trim())}(?:s|es)?(?=[^a-z]|$)`;
    patterns.set(term, p);
  }
  return p;
};

/** Whole-word match after removing exclusions, also only at word boundaries. */
function containsAny(text: string, terms: string[], exclusions: string[]): boolean {
  let t = text;
  for (const ex of exclusions) t = t.replace(new RegExp(wordPattern(ex), 'g'), (_m, lead: string) => `${lead} `);
  return terms.some((term) => new RegExp(wordPattern(term)).test(t));
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
