import { catalog, CatalogProduct } from './shared';

const STOP = new Set([
  'the', 'a', 'an', 'of', 'some', 'fresh', 'organic', 'large', 'small', 'medium', 'lg', 'sm', 'pk', 'pack', 'bag', 'box',
  'can', 'jar', 'bottle', 'my', 'our', 'and', 'with', 'g', 'kg', 'ml', 'l', 'lb', 'oz', 'each',
  // French (Québec receipts and voice).
  'le', 'la', 'les', 'de', 'du', 'des', 'd', 'un', 'une', 'au', 'aux', 'et', 'avec', 'mon', 'ma', 'mes', 'nos',
  'frais', 'fraiche', 'bio', 'biologique', 'gros', 'grosse', 'petit', 'petite', 'sac', 'boite', 'pot', 'bouteille',
  'paquet', 'conserve', 'chaque', 'unite',
]);

const FOLD: Record<string, string> = {
  à: 'a', â: 'a', ä: 'a', ç: 'c', é: 'e', è: 'e', ê: 'e', ë: 'e', î: 'i', ï: 'i',
  ô: 'o', ö: 'o', û: 'u', ù: 'u', ü: 'u', ÿ: 'y', ñ: 'n', æ: 'ae', œ: 'oe',
};

/** Lower-case and fold accents so "Œufs" matches "oeufs" (mirrors ProductMatcher.fold). */
export const fold = (s: string): string => [...s.toLowerCase()].map((c) => FOLD[c] ?? c).join('');

function singular(t: string): string {
  if (t.length > 4 && (t.endsWith('eaux') || t.endsWith('oux'))) return t.slice(0, -1);
  if (t.length > 4 && t.endsWith('ies')) return `${t.slice(0, -3)}y`;
  if (t.length > 4 && t.endsWith('oes')) return t.slice(0, -2);
  if (t.length > 3 && t.endsWith('s') && !t.endsWith('ss')) return t.slice(0, -1);
  return t;
}

export function tokens(s: string): string[] {
  return fold(s)
    .replace(/['’]/g, ' ')
    .replace(/[^a-z0-9 ]/g, ' ')
    .split(/\s+/)
    .filter((t) => t && !STOP.has(t) && !/^\d+$/.test(t))
    .map(singular);
}

/** Mirror of lib/domain/catalog/product_matcher.dart. */
export function bestMatch(query: string, minScore = 0.5, products: CatalogProduct[] = catalog): { product: CatalogProduct; score: number } | null {
  const q = fold(query.trim());
  if (!q) return null;
  const qt = new Set(tokens(q));
  let best: { product: CatalogProduct; score: number } | null = null;
  for (const p of products) {
    let s = 0;
    for (const n of [p.name, p.id.replace(/_/g, ' '), ...p.aliases]) {
      const nl = fold(n);
      if (nl === q) {
        s = 1;
        break;
      }
      const nt = new Set(tokens(nl));
      if (!nt.size || !qt.size) continue;
      let inter = 0;
      nt.forEach((t) => qt.has(t) && inter++);
      if (!inter) continue;
      s = Math.max(s, 0.7 * (inter / nt.size) + 0.3 * (inter / qt.size));
    }
    if (s >= minScore && (!best || s > best.score)) best = { product: p, score: s };
  }
  return best;
}
