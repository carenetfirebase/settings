import { catalog, CatalogProduct } from './shared';

const STOP = new Set([
  'the', 'a', 'an', 'of', 'some', 'fresh', 'organic', 'large', 'small', 'medium', 'lg', 'sm', 'pk', 'pack', 'bag', 'box',
  'can', 'jar', 'bottle', 'my', 'our', 'and', 'with', 'g', 'kg', 'ml', 'l', 'lb', 'oz', 'each',
]);

function singular(t: string): string {
  if (t.length > 4 && t.endsWith('ies')) return `${t.slice(0, -3)}y`;
  if (t.length > 4 && t.endsWith('oes')) return t.slice(0, -2);
  if (t.length > 3 && t.endsWith('s') && !t.endsWith('ss')) return t.slice(0, -1);
  return t;
}

export function tokens(s: string): string[] {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, ' ')
    .split(/\s+/)
    .filter((t) => t && !STOP.has(t) && !/^\d+$/.test(t))
    .map(singular);
}

/** Mirror of lib/domain/catalog/product_matcher.dart. */
export function bestMatch(query: string, minScore = 0.5, products: CatalogProduct[] = catalog): { product: CatalogProduct; score: number } | null {
  const q = query.trim().toLowerCase();
  if (!q) return null;
  const qt = new Set(tokens(q));
  let best: { product: CatalogProduct; score: number } | null = null;
  for (const p of products) {
    let s = 0;
    for (const n of [p.name, p.id.replace(/_/g, ' '), ...p.aliases]) {
      const nl = n.toLowerCase();
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
