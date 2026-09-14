import { FACT_BY_KEY, QUESTION_TEMPLATES, normalizeQuestion }
  from '../../case-catalog/src/index.ts';

export type KeyCandidate = { factKey: string; score: number; via: 'exact' | 'trigram' | 'lexical' };

const INDEX = new Map(QUESTION_TEMPLATES.map((t) => [t.normalized, t]));

/** Deterministic first, fuzzy second. An identical question resolves identically. */
export function resolveFactKeys(question: string, limit = 6): KeyCandidate[] {
  const normalized = normalizeQuestion(question);

  const exact = INDEX.get(normalized);
  if (exact) return exact.factKeys.map((factKey) => ({ factKey, score: 1, via: 'exact' as const }));

  const scored = new Map<string, KeyCandidate>();
  const grams = trigrams(normalized);

  for (const template of QUESTION_TEMPLATES) {
    const similarity = jaccard(grams, trigrams(template.normalized));
    if (similarity < 0.34) continue;
    for (const factKey of template.factKeys) {
      const existing = scored.get(factKey);
      if (!existing || existing.score < similarity) {
        scored.set(factKey, { factKey, score: similarity, via: 'trigram' });
      }
    }
  }

  if (scored.size === 0) {
    const words = normalized.split(' ').filter((w) => w.length > 3 && !STOPWORDS.has(w));
    for (const [key, definition] of FACT_BY_KEY) {
      const haystack = `${key} ${definition.label}`.toLowerCase();
      const hits = words.filter((w) => haystack.includes(w)).length;
      if (hits === 0) continue;
      scored.set(key, { factKey: key, score: 0.2 + hits / 20, via: 'lexical' });
    }
  }

  return [...scored.values()]
    .sort((a, b) => b.score - a.score ||
                    (FACT_BY_KEY.get(b.factKey)?.answerWeight ?? 0) -
                    (FACT_BY_KEY.get(a.factKey)?.answerWeight ?? 0))
    .slice(0, limit);
}

/** Keep only what is close to the best match, so an answer stays one answer. */
export function topCandidates(question: string): string[] {
  const ranked = resolveFactKeys(question);
  if (ranked.length === 0) return [];
  const best = ranked[0].score;
  const threshold = best >= 1 ? 1 : best - 0.06;
  return ranked.filter((c) => c.score >= threshold).map((c) => c.factKey);
}

const STOPWORDS = new Set([
  'what', 'when', 'where', 'which', 'about', 'does', 'this', 'that', 'have',
  'there', 'they', 'with', 'from', 'been', 'much', 'many', 'your', 'like',
  'tell', 'know', 'case', 'did', 'you', 'the',
]);

function trigrams(text: string): Set<string> {
  const padded = `  ${text} `;
  const out = new Set<string>();
  for (let i = 0; i < padded.length - 2; i += 1) out.add(padded.slice(i, i + 3));
  return out;
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let shared = 0;
  for (const gram of a) if (b.has(gram)) shared += 1;
  return shared / (a.size + b.size - shared);
}
