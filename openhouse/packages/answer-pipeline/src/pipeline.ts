import { FACT_BY_KEY } from '../../fact-catalog/src/index.ts';
import { checkQuestion } from '../../compliance/src/index.ts';
import type { GroundingItem } from '../../ai-gateway/src/index.ts';
import { TemplateCompletionProvider } from '../../ai-gateway/src/index.ts';
import type { CompletionProvider } from '../../ai-gateway/src/index.ts';
import type { TruthEngine } from '../../truth-engine/src/engine.ts';
import { formatMoney, humanize } from '../../truth-engine/src/normalize.ts';
import type { Commentary, Disclosure, Property, ResolvedFact }
  from '../../truth-engine/src/types.ts';
import { classify } from './classify.ts';
import { advanceFrame, emptyFrame, resolveElliptical } from './frame.ts';
import type { Frame } from './frame.ts';
import { resolveFactKeys } from './resolve-keys.ts';
import { validateAnswer } from './validator.ts';
import type { ValidatorFlag } from './validator.ts';

export type RetrievalPath =
  | 'structured' | 'document' | 'commentary' | 'public' | 'unknown' | 'boundary_refusal';

export type AnswerRequest = {
  propertyId: string;
  sessionId: string;
  question: string;
  frame?: Frame;
  roomKey?: string | null;
};

export type AnswerResult = {
  answer: string;
  retrievalPath: RetrievalPath;
  resolvedFactKeys: string[];
  factVersions: Record<string, number>;
  validatorFlags: ValidatorFlag[];
  blocked: boolean;
  frame: Frame;
  latencyMs: number;
  provider: string;
  model: string;
  /** Written to `answer_ledger`; the caller persists it. */
  ledgerEntry: LedgerEntry;
};

export type LedgerEntry = {
  sessionId: string;
  propertyId: string;
  questionText: string;
  questionCategory: string;
  resolvedFactKeys: string[];
  factVersions: Record<string, number>;
  retrievalPath: RetrievalPath;
  answerText: string;
  validatorFlags: ValidatorFlag[];
  blocked: boolean;
  latencyMs: number;
  provider: string;
  model: string;
};

/** Retrieval sources the pipeline can reach past the Truth Engine. */
export type DocumentRetriever = {
  search(propertyId: string, question: string, limit: number)
    : { label: string; text: string; documentId: string; page: number; score: number }[];
};

export type PipelineDeps = {
  engine: TruthEngine;
  property: Property;
  completion?: CompletionProvider;
  retriever?: DocumentRetriever;
  commentary?: () => Commentary[];
  disclosures?: () => Disclosure[];
};

/**
 * The grounded answer pipeline (§11).
 *
 * Ordering is the whole point: a verified structured fact outranks a document
 * chunk that mentions something similar, and nothing reaches generation that
 * did not come out of retrieval. The model phrases; it does not decide.
 */
export function createAnswerPipeline(deps: PipelineDeps) {
  const completion = deps.completion ?? new TemplateCompletionProvider();
  const agentName = deps.property.agentName ?? 'the listing agent';
  const priceDisplay = deps.property.listPrice != null
    ? formatMoney(deps.property.listPrice)
    : null;

  // Published listing chrome — the address and the price on the sign. The
  // visitor already sees these, and the validator needs them in the payload so
  // saying the address out loud is not mistaken for an invented number.
  const identity: GroundingItem[] = [
    { kind: 'fact', label: 'Address', display: deps.property.addressLine1,
      text: `${deps.property.addressLine1}, ${deps.property.city}` },
    ...(priceDisplay
      ? [{ kind: 'fact' as const, label: 'List price', display: priceDisplay,
           value: deps.property.listPrice ?? undefined }]
      : []),
  ];

  return async function answer(req: AnswerRequest): Promise<AnswerResult> {
    const started = performance.now();
    const frameIn = req.frame ?? emptyFrame();

    // 2. Classify.
    const classification = classify(req.question);

    // 3. Boundary pre-check — before retrieval, before generation.
    const boundary = checkQuestion(req.question, { agentName, priceDisplay });
    if (!boundary.allowed) {
      const offered = deps.engine
        .resolve(deps.property.id, boundary.offerFactKeys)
        .filter((f) => f.status === 'verified' && f.visibility === 'public');

      // Only add a fact the refusal template has not already stated — the
      // offer-strategy template names the price itself.
      const additions = offered.filter(
        (f) => !boundary.template.includes(displayValue(f)));
      const text = additions.length > 0
        ? `${boundary.template} ${additions.map(factSentence).join(' ')}`
        : boundary.template;

      return finish({
        text,
        path: 'boundary_refusal',
        facts: offered,
        category: boundary.hit.kind,
        grounding: offered.map(toGrounding),
        // A template is not generated text, so the numeric check has nothing to
        // police; the compliance post-check still runs inside validateAnswer.
        frame: frameIn,
      });
    }

    if (classification.intent === 'smalltalk') {
      return finish({
        text: `I'm the AI guide for ${deps.property.addressLine1}. Ask me anything ` +
              `about the home — I'll only tell you what's been verified.`,
        path: 'structured', facts: [], category: 'smalltalk', grounding: [], frame: frameIn,
      });
    }

    if (classification.needsRoomContext && !req.roomKey) {
      // Ambiguity handled well is a trust-building moment (§11.4).
      return finish({
        text: "I can't see which one you're looking at. If you tell me the room " +
              "you're in, or tap the tag nearby, I can tell you what's there.",
        path: 'unknown', facts: [], category: 'ambiguous', grounding: [], frame: frameIn,
      });
    }

    if (classification.intent === 'agent_request' ||
        classification.intent === 'document_request' ||
        classification.intent === 'action') {
      return finish({
        text: `I can pass that to ${agentName} for you — I'll note it now.`,
        path: 'structured', facts: [], category: classification.intent,
        grounding: [], frame: frameIn,
      });
    }

    // 4. Resolve candidate fact keys: the frame first, then the question.
    const elliptical = resolveElliptical(req.question, frameIn);
    const candidates = elliptical.length > 0 ? elliptical : topCandidates(req.question);

    // 5. Structured lookup — authoritative. If this hits, 6–8 do not run.
    const resolved = deps.engine.resolve(deps.property.id, candidates)
      .filter((f) => f.visibility === 'public');

    const verified = resolved.filter((f) => f.status === 'verified');
    const unknown = resolved.filter((f) => f.status === 'unknown');
    const disclosures = relevantDisclosures(deps.disclosures?.() ?? [], candidates);

    if (verified.length > 0 || disclosures.length > 0) {
      const grounding: GroundingItem[] = [
        ...disclosures.map(toDisclosureGrounding),
        ...verified.slice(0, 3).map(toGrounding),
      ];
      const generated = await completion.complete({
        question: req.question, grounding, agentName, maxSentences: 3,
        frame: { room: frameIn.room, topic: frameIn.topic },
      });
      return finish({
        text: generated.text, path: 'structured', facts: verified,
        category: categoryOf(candidates), grounding,
        frame: advanceFrame(frameIn, verified.map((f) => f.factKey)),
        provider: generated.provider, model: generated.model,
      });
    }

    if (unknown.length > 0) {
      const grounding = unknown.slice(0, 2).map(toGrounding);
      const generated = await completion.complete({
        question: req.question, grounding, agentName, maxSentences: 2,
      });
      return finish({
        text: generated.text, path: 'unknown', facts: unknown,
        category: categoryOf(candidates), grounding,
        frame: advanceFrame(frameIn, unknown.map((f) => f.factKey)),
        provider: generated.provider, model: generated.model,
      });
    }

    // 6. Document retrieval — public documents only.
    const hits = deps.retriever?.search(deps.property.id, req.question, 3) ?? [];
    if (hits.length > 0) {
      const grounding: GroundingItem[] = hits.slice(0, 1).map((hit) => ({
        kind: 'document', label: hit.label, text: hit.text,
        sourceRef: `doc:${hit.documentId}#${hit.page}`,
      }));
      const generated = await completion.complete({
        question: req.question, grounding, agentName, maxSentences: 2,
      });
      return finish({
        text: generated.text, path: 'document', facts: [],
        category: categoryOf(candidates), grounding, frame: frameIn,
        provider: generated.provider, model: generated.model,
      });
    }

    // 7. Commentary.
    const commentary = relevantCommentary(deps.commentary?.() ?? [], req.question, frameIn);
    if (commentary) {
      const grounding: GroundingItem[] = [{
        kind: 'commentary', label: commentary.topic ?? 'The home', text: commentary.text,
        verificationLevel: commentary.author === 'seller' ? 'seller_provided' : 'agent_commentary',
      }];
      const generated = await completion.complete({
        question: req.question, grounding, agentName, maxSentences: 2,
      });
      return finish({
        text: generated.text, path: 'commentary', facts: [],
        category: categoryOf(candidates), grounding, frame: frameIn,
        provider: generated.provider, model: generated.model,
      });
    }

    // 9. Nothing found. Never a dead end.
    return finish({
      text: `I don't have verified information about that. Would you like me to ` +
            `ask ${agentName}?`,
      path: 'unknown', facts: [], category: categoryOf(candidates),
      grounding: [], frame: frameIn,
    });

    type FinishArgs = {
      text: string;
      path: RetrievalPath;
      facts: ResolvedFact[];
      category: string;
      grounding: GroundingItem[];
      frame: Frame;
      provider?: string;
      model?: string;
    };

    function finish(args: FinishArgs): AnswerResult {
      // 11 and 12. Validate, then the compliance post-check (both inside
      // validateAnswer). A blocked answer never reaches the visitor.
      const validation = validateAnswer(args.text, [...identity, ...args.grounding]);
      const blocked = !validation.ok;
      const text = blocked
        ? `I don't have verified information about that. Would you like me to ask ${agentName}?`
        : args.text;

      const factVersions: Record<string, number> = {};
      for (const fact of args.facts) factVersions[fact.factKey] = fact.version;

      const ledgerEntry: LedgerEntry = {
        sessionId: req.sessionId,
        propertyId: deps.property.id,
        questionText: req.question,
        questionCategory: args.category,
        resolvedFactKeys: args.facts.map((f) => f.factKey),
        factVersions,
        retrievalPath: blocked ? 'unknown' : args.path,
        answerText: text,
        validatorFlags: validation.flags,
        blocked,
        latencyMs: Math.round(performance.now() - started),
        provider: args.provider ?? 'template',
        model: args.model ?? 'phrasebook-v1',
      };

      return {
        answer: text,
        retrievalPath: ledgerEntry.retrievalPath,
        resolvedFactKeys: ledgerEntry.resolvedFactKeys,
        factVersions,
        validatorFlags: validation.flags,
        blocked,
        frame: args.frame,
        latencyMs: ledgerEntry.latencyMs,
        provider: ledgerEntry.provider,
        model: ledgerEntry.model,
        ledgerEntry,
      };
    }
  };
}

// ---------------------------------------------------------------- helpers --

function toGrounding(fact: ResolvedFact): GroundingItem {
  return {
    kind: fact.status === 'unknown' ? 'unknown' : 'fact',
    factKey: fact.factKey,
    label: fact.definition.label,
    display: fact.display ?? displayValue(fact),
    value: fact.value,
    verificationLevel: fact.verificationLevel ?? null,
    unknownReason: fact.unknownReason ?? null,
    sourceRef: fact.source?.documentId ? `doc:${fact.source.documentId}` : null,
  };
}

function toDisclosureGrounding(disclosure: Disclosure): GroundingItem {
  const remediation = disclosure.remediated && disclosure.remediationDetail
    ? ` ${disclosure.remediationDetail}`
    : '';
  return {
    kind: 'disclosure',
    label: disclosure.title,
    text: `${disclosure.detail}${remediation}`,
  };
}

function displayValue(fact: ResolvedFact): string {
  const value = fact.value;
  if (value === undefined || value === null) return '';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'string') return value.includes('_') ? humanize(value) : value;
  if (fact.definition.dataType === 'money' && typeof value === 'number') {
    return formatMoney(value);
  }
  return String(value);
}

function factSentence(fact: ResolvedFact): string {
  return `${fact.definition.label}: ${displayValue(fact).replace(/\.\s*$/, '')}.`;
}

/**
 * Keep only the keys that are close to the best match.
 *
 * A question about the furnace should be answered about the furnace. Reading
 * out every fuzzy match turns a one-sentence answer into a recital, and the
 * brevity constraint is what makes voice feel like a conversation (§10.7).
 */
function topCandidates(question: string): string[] {
  const ranked = resolveFactKeys(question);
  if (ranked.length === 0) return [];
  const best = ranked[0].score;
  const threshold = best >= 1 ? 1 : best - 0.06;
  return ranked.filter((c) => c.score >= threshold).map((c) => c.factKey);
}

function categoryOf(candidates: string[]): string {
  const first = candidates[0];
  return first ? FACT_BY_KEY.get(first)?.category ?? 'unknown' : 'unknown';
}

/**
 * A disclosure attached to a fact the visitor just asked about is surfaced
 * whether or not they asked about the defect. Omitting it would manufacture a
 * non-disclosure claim (§12.3).
 */
function relevantDisclosures(disclosures: Disclosure[], candidates: string[]): Disclosure[] {
  const keys = new Set(candidates);
  return disclosures.filter((d) => d.factKey && keys.has(d.factKey));
}

function relevantCommentary(
  commentary: Commentary[], question: string, frame: Frame,
): Commentary | undefined {
  const approved = commentary.filter((c) => c.approved && c.visibility === 'public');
  const words = new Set(question.toLowerCase().split(/[^a-z]+/).filter((w) => w.length > 3));

  let best: { item: Commentary; score: number } | undefined;
  for (const item of approved) {
    const haystack = new Set(
      `${item.topic ?? ''} ${item.text}`.toLowerCase().split(/[^a-z]+/));
    let score = 0;
    // Whole words only: "deep" must not match "deeper" and drag a kitchen
    // anecdote into a question about the lot.
    for (const word of words) if (haystack.has(word)) score += 1;
    if (frame.room && item.topic === frame.room) score += 2;
    if (score >= 2 && (!best || score > best.score)) best = { item, score };
  }
  return best?.item;
}

export { emptyFrame } from './frame.ts';
export type { Frame } from './frame.ts';
