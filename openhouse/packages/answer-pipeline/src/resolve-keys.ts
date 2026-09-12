import {
  FACT_BY_KEY, QUESTION_TEMPLATES, normalizeQuestion,
} from '../../fact-catalog/src/index.ts';

export type KeyCandidate = {
  factKey: string;
  score: number;
  via: 'exact' | 'trigram' | 'lexical';
};

const TEMPLATE_INDEX = new Map(QUESTION_TEMPLATES.map((t) => [t.normalized, t]));

/**
 * Step 4 (§11): deterministic first, fuzzy second.
 *
 * The exact table is what makes the common question path both fast and
 * reproducible — an identical question resolves to identical keys today and in
 * six months, which matters when the ledger is evidence.
 */
export function resolveFactKeys(question: string, limit = 6): KeyCandidate[] {
  const normalized = normalizeQuestion(question);

  const exact = TEMPLATE_INDEX.get(normalized);
  if (exact) {
    return exact.factKeys.map((factKey) => ({ factKey, score: 1, via: 'exact' as const }));
  }

  const scored = new Map<string, KeyCandidate>();
  const questionGrams = trigrams(normalized);

  for (const template of QUESTION_TEMPLATES) {
    const similarity = jaccard(questionGrams, trigrams(template.normalized));
    if (similarity < 0.34) continue;
    for (const factKey of template.factKeys) {
      const existing = scored.get(factKey);
      if (!existing || existing.score < similarity) {
        scored.set(factKey, { factKey, score: similarity, via: 'trigram' });
      }
    }
  }

  if (scored.size === 0) {
    // Last resort before giving up: content words against catalog labels.
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
                    (FACT_BY_KEY.get(b.factKey)?.coverageWeight ?? 0) -
                    (FACT_BY_KEY.get(a.factKey)?.coverageWeight ?? 0))
    .slice(0, limit);
}

const STOPWORDS = new Set([
  'what', 'when', 'where', 'which', 'about', 'does', 'this', 'that', 'have',
  'there', 'they', 'with', 'from', 'been', 'much', 'many', 'your', 'like',
  'tell', 'know', 'here', 'house', 'home', 'place',
]);

function trigrams(text: string): Set<string> {
  const padded = `  ${text} `;
  const grams = new Set<string>();
  for (let i = 0; i < padded.length - 2; i += 1) grams.add(padded.slice(i, i + 3));
  return grams;
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let shared = 0;
  for (const gram of a) if (b.has(gram)) shared += 1;
  return shared / (a.size + b.size - shared);
}
