import { humanize } from '../../../truth-engine/src/normalize.ts';
import type {
  CompletionProvider, GroundedRequest, GroundedResponse, GroundingItem,
} from '../interfaces.ts';

/**
 * A CompletionProvider that phrases grounded answers without a model.
 *
 * This is not a stub. It is the floor of the fallback ladder and the reference
 * implementation of "the model's job is to phrase, not to decide": it can only
 * ever emit values that are in the grounding payload, so it is incapable of
 * hallucinating, and the eval harness can measure the rest of the pipeline
 * without a network call or an API key.
 *
 * An LLM-backed provider implements the same interface and passes through the
 * same validator. The difference is phrasing quality, not permitted content.
 */
export class TemplateCompletionProvider implements CompletionProvider {
  readonly name = 'template';
  readonly model = 'phrasebook-v1';

  async complete(req: GroundedRequest): Promise<GroundedResponse> {
    const started = performance.now();
    const text = phrase(req);
    return {
      text,
      provider: this.name,
      model: this.model,
      latencyMs: Math.round(performance.now() - started),
    };
  }
}

function phrase(req: GroundedRequest): string {
  const agent = req.agentName ?? 'the listing agent';
  const disclosures = req.grounding.filter((g) => g.kind === 'disclosure');
  const facts = req.grounding.filter((g) => g.kind === 'fact');
  const unknowns = req.grounding.filter((g) => g.kind === 'unknown');
  const commentary = req.grounding.filter((g) => g.kind === 'commentary');
  const documents = req.grounding.filter((g) => g.kind === 'document');
  const publicItems = req.grounding.filter((g) => g.kind === 'public');

  const sentences: string[] = [];

  // A disclosure leads. It is never softened, buried or omitted (§12.3).
  for (const item of disclosures) sentences.push(item.text ?? item.label);

  // A fact that only restates the disclosure adds nothing but length. The
  // disclosure is the fuller version, so the fact is what gets dropped.
  const disclosureWords = words(disclosures.map((d) => d.text ?? '').join(' '));
  const worthSaying = facts.filter((f) => overlap(words(f.display ?? ''), disclosureWords) < 0.6);

  for (const fact of worthSaying.slice(0, 3)) sentences.push(factSentence(fact));

  for (const unknown of unknowns.slice(0, 2)) {
    sentences.push(unknownSentence(unknown, agent));
  }

  for (const item of documents.slice(0, 1)) {
    sentences.push(`The ${item.label.toLowerCase()} shows ${item.text ?? item.display}.`);
  }

  // Commentary must not borrow verified-fact phrasing (§11.6 rule 4).
  for (const item of commentary.slice(0, 1)) {
    const author = item.verificationLevel === 'seller_provided' ? 'seller' : agent;
    sentences.push(`${cap(author)} mentions: ${stripTrailingPeriod(item.text ?? '')}.`);
  }

  for (const item of publicItems.slice(0, 1)) {
    sentences.push(`Public information lists ${item.text ?? item.display}.`);
  }

  if (sentences.length === 0) {
    return `I don't have verified information about that. Would you like me to ask ${agent}?`;
  }

  const limit = req.maxSentences ?? 3;
  return sentences.slice(0, limit).join(' ');
}

function factSentence(item: GroundingItem): string {
  const value = item.display ?? formatValue(item);
  const label = item.label;

  if (item.factKey?.endsWith('install_year') || item.factKey?.endsWith('replacement_year')) {
    return `${subjectFor(label)} in ${value}.`;
  }
  if (typeof item.value === 'boolean') {
    return item.value ? `Yes — ${lower(label)} is confirmed.` : `No — ${lower(label)} is not.`;
  }
  return `${cap(label)}: ${stripTrailingPeriod(value)}.`;
}

/** "Furnace installation year" → "The furnace was installed". */
function subjectFor(label: string): string {
  const noun = label
    .replace(/ installation year$/i, '')
    .replace(/ replacement year$/i, '')
    .replace(/ year$/i, '');
  const verb = /replacement/i.test(label) ? 'was replaced' : 'was installed';
  return `The ${noun.toLowerCase()} ${verb}`;
}

function unknownSentence(item: GroundingItem, agent: string): string {
  const subject = lower(item.label);
  switch (item.unknownReason) {
    case 'seller_does_not_know':
      return `The seller doesn't have a record of the ${subject}.`;
    case 'no_documentation':
      return `That's not something there's documentation for — ${agent} can follow up with the seller.`;
    case 'will_follow_up':
      return `${cap(agent)} is still confirming the ${subject} and can get back to you on it.`;
    default:
      return `I don't have a verified ${subject}. Would you like me to ask ${agent}?`;
  }
}

function formatValue(item: GroundingItem): string {
  const value = item.value;
  if (value === undefined || value === null) return 'not recorded';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'string') return value.includes('_') ? humanize(value) : value;
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function words(text: string): Set<string> {
  return new Set(text.toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length > 3));
}

function overlap(a: Set<string>, b: Set<string>): number {
  if (a.size === 0) return 0;
  let shared = 0;
  for (const word of a) if (b.has(word)) shared += 1;
  return shared / a.size;
}

const cap = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);
const lower = (s: string): string => s.charAt(0).toLowerCase() + s.slice(1);
const stripTrailingPeriod = (s: string): string => s.replace(/\.\s*$/, '');
