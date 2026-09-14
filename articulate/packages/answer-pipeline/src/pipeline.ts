import { FACT_BY_KEY } from '../../case-catalog/src/index.ts';
import { checkQuestion } from '../../compliance/src/index.ts';
import type { TruthEngine } from '../../truth-engine/src/engine.ts';
import { humanize } from '../../truth-engine/src/normalize.ts';
import type { CaseStore, LabCase, ResolvedFact } from '../../truth-engine/src/types.ts';
import { phrase } from './phrase.ts';
import { topCandidates } from './resolve-keys.ts';
import { validateAnswer } from './validator.ts';
import type { GroundingItem, ValidatorFlag } from './validator.ts';

export type RetrievalPath =
  | 'case_record' | 'status' | 'materials' | 'unknown' | 'blocked_on_practice'
  | 'boundary_refusal' | 'routed_to_technician';

/** Who is asking. The lab sees everything on its own cases; a practice does not. */
export type Requester =
  | { kind: 'practice'; practiceId: string; name: string }
  | { kind: 'lab'; userId: string; name: string };

export type AnswerRequest = {
  caseId: string;
  question: string;
  requester: Requester;
  sessionId: string;
};

export type AnswerResult = {
  answer: string;
  retrievalPath: RetrievalPath;
  resolvedFactKeys: string[];
  factVersions: Record<string, number>;
  validatorFlags: ValidatorFlag[];
  blocked: boolean;
  escalated: boolean;
  latencyMs: number;
  ledgerEntry: LedgerEntry;
};

export type LedgerEntry = {
  sessionId: string;
  caseId: string;
  askedBy: string;
  questionText: string;
  questionCategory: string;
  resolvedFactKeys: string[];
  factVersions: Record<string, number>;
  retrievalPath: RetrievalPath;
  answerText: string;
  validatorFlags: ValidatorFlag[];
  blocked: boolean;
  escalated: boolean;
  latencyMs: number;
  at: string;
};

export type PipelineDeps = {
  engine: TruthEngine;
  store: CaseStore;
  labName: string;
  technicianName?: string | null;
};

/**
 * The grounded answer pipeline.
 *
 * Ordering is the point. A confirmed fact on the case outranks everything; the
 * boundary layer runs before any retrieval, so a clinical question never even
 * reaches the record; and nothing is generated that did not come out of
 * retrieval first.
 */
export function createAnswerPipeline(deps: PipelineDeps) {
  return async function answer(req: AnswerRequest): Promise<AnswerResult> {
    const started = performance.now();
    const labCase = deps.store.getCase(req.caseId);

    if (!labCase) {
      return finish({
        text: `I can't find that case number. Your technician can look it up directly.`,
        path: 'routed_to_technician', facts: [], grounding: [], category: 'unknown_case',
      });
    }

    // Access before anything else: a practice reaches only its own cases, and
    // the refusal is identical to the one for a case that does not exist, so
    // the boundary cannot be used to enumerate case numbers.
    if (req.requester.kind === 'practice' && req.requester.practiceId !== labCase.practiceId) {
      return finish({
        text: `I can't find that case number. Your technician can look it up directly.`,
        path: 'routed_to_technician', facts: [], grounding: [], category: 'access_denied',
      });
    }

    const technician = deps.technicianName ?? 'your technician';

    // Boundary pre-check.
    const boundary = checkQuestion(req.question, {
      technicianName: technician, labName: deps.labName,
    });
    if (!boundary.allowed) {
      const offered = visible(
        deps.engine.resolve(req.caseId, boundary.offerFactKeys), req.requester)
        .filter((f) => f.status === 'confirmed');

      const grounding = offered.map(toGrounding);
      const text = offered.length > 0
        ? `${boundary.template} ${offered.map(factLine).join(' ')}`
        : boundary.template;

      return finish({
        text, path: 'boundary_refusal', facts: offered, grounding,
        category: boundary.hit.kind, escalated: boundary.escalate,
      });
    }

    const candidates = topCandidates(req.question);

    // A fact two sources disagree about is not unknown and it is not confirmed.
    // Saying so — with both values and why the case is stopped — is the most
    // useful sentence this system can produce.
    const conflict = deps.engine.detectConflicts(req.caseId)
      .find((c) => candidates.includes(c.factKey));
    if (conflict) {
      const values = conflict.claims
        .map((claim) => `${claim.display} on the ${humanize(claim.source).toLowerCase()}`)
        .join(', and ');
      const grounding: GroundingItem[] = conflict.claims.map((claim) => ({
        kind: 'fact', factKey: conflict.factKey, label: conflict.label,
        display: claim.display, value: claim.value,
        confirmationLevel: 'document_verified',
      }));
      const text = `Two sources disagree on the ${conflict.label.toLowerCase()}: ` +
        `${values}. We've held the case rather than choose one — can you confirm ` +
        `which is correct?`;
      return finish({
        text, path: 'blocked_on_practice', facts: [], grounding,
        category: 'conflict',
      });
    }

    const resolved = visible(deps.engine.resolve(req.caseId, candidates), req.requester);
    const confirmed = resolved.filter((f) => f.status === 'confirmed');
    const unknown = resolved.filter((f) => f.status === 'unknown');

    // "Where is my case" is the question, so it gets a real answer rather than
    // a field read-out: status, what it is waiting on, and when it lands.
    if (isStatusQuestion(candidates, req.question)) {
      return statusAnswer(labCase, req, finish);
    }

    if (confirmed.length > 0) {
      const grounding = confirmed.slice(0, 3).map(toGrounding);
      return finish({
        text: phrase({
          question: req.question, grounding, technicianName: technician,
          labName: deps.labName, maxSentences: 3,
        }),
        path: candidates[0]?.startsWith('material.') ? 'materials' : 'case_record',
        facts: confirmed, grounding, category: categoryOf(candidates),
      });
    }

    if (unknown.length > 0) {
      const grounding = unknown.slice(0, 2).map(toGrounding);
      return finish({
        text: phrase({
          question: req.question, grounding, technicianName: technician,
          maxSentences: 2,
        }),
        path: 'unknown', facts: unknown, grounding, category: categoryOf(candidates),
      });
    }

    // Nothing on the record. If the specific thing being asked about is what we
    // are waiting on them for, say so. Otherwise this is an honest unknown —
    // answering an unrelated question with a list of unrelated requests is
    // worse than saying we don't know.
    const candidateKeys = new Set(candidates);
    const asks = deps.engine.asks(req.caseId, 12)
      .filter((ask) => candidateKeys.has(ask.factKey));
    if (asks.length > 0 && asks[0].necessity === 'blocking') {
      const grounding: GroundingItem[] = asks.slice(0, 2).map((ask) => ({
        kind: 'ask', label: ask.label, text: ask.question, factKey: ask.factKey,
      }));
      return finish({
        text: phrase({ question: req.question, grounding, technicianName: technician,
                       maxSentences: 2 }),
        path: 'blocked_on_practice', facts: [], grounding, category: 'blocked',
      });
    }

    return finish({
      text: `I don't have that on the case record. Shall I put it to ${technician}?`,
      path: 'unknown', facts: [], grounding: [], category: categoryOf(candidates),
    });

    type FinishArgs = {
      text: string;
      path: RetrievalPath;
      facts: ResolvedFact[];
      grounding: GroundingItem[];
      category: string;
      escalated?: boolean;
    };

    function finish(args: FinishArgs): AnswerResult {
      const validation = validateAnswer(args.text, args.grounding);
      const blocked = !validation.ok;
      const text = blocked
        ? `Let me get that checked rather than tell you something I'm not sure of — ` +
          `${technician} will come straight back to you.`
        : args.text;

      const factVersions: Record<string, number> = {};
      for (const fact of args.facts) factVersions[fact.factKey] = fact.version;

      const ledgerEntry: LedgerEntry = {
        sessionId: req.sessionId,
        caseId: req.caseId,
        askedBy: req.requester.name,
        questionText: req.question,
        questionCategory: args.category,
        resolvedFactKeys: args.facts.map((f) => f.factKey),
        factVersions,
        retrievalPath: blocked ? 'routed_to_technician' : args.path,
        answerText: text,
        validatorFlags: validation.flags,
        blocked,
        // A blocked answer is always a person's problem now, not a silent retry.
        escalated: (args.escalated ?? false) || blocked,
        latencyMs: Math.round(performance.now() - started),
        at: new Date().toISOString(),
      };

      return {
        answer: text,
        retrievalPath: ledgerEntry.retrievalPath,
        resolvedFactKeys: ledgerEntry.resolvedFactKeys,
        factVersions,
        validatorFlags: validation.flags,
        blocked,
        escalated: ledgerEntry.escalated,
        latencyMs: ledgerEntry.latencyMs,
        ledgerEntry,
      };
    }

    function statusAnswer(
      target: LabCase, request: AnswerRequest,
      done: (args: FinishArgs) => AnswerResult,
    ): AnswerResult {
      const keys = ['case.status', 'case.hold_reason', 'delivery.ship_date',
                    'delivery.expected_arrival', 'delivery.tracking_number',
                    'delivery.carrier', 'delivery.delay_reason',
                    'delivery.revised_due_date'];
      const facts = visible(deps.engine.resolve(request.caseId, keys), request.requester)
        .filter((f) => f.status === 'confirmed');
      const byKey = new Map(facts.map((f) => [f.factKey, f]));

      const grounding: GroundingItem[] = [];
      const parts: string[] = [];

      const statusLabel = humanize(target.status);
      grounding.push({
        kind: 'status', label: 'Case status',
        text: `Case ${target.caseNumber} is ${statusLabel.toLowerCase()}.`,
        display: statusLabel,
      });
      parts.push(`Case ${target.caseNumber} is ${statusLabel.toLowerCase()}.`);

      const hold = byKey.get('case.hold_reason');
      if (hold) {
        grounding.push(toGrounding(hold));
        parts.push(`It's waiting on you: ${strip(hold.display ?? '')}.`);
      }

      const delay = byKey.get('delivery.delay_reason');
      if (delay) {
        grounding.push(toGrounding(delay));
        parts.push(`${strip(delay.display ?? '')}.`);
      }

      const shipped = byKey.get('delivery.ship_date');
      const arrival = byKey.get('delivery.expected_arrival') ??
                      byKey.get('delivery.revised_due_date');
      const tracking = byKey.get('delivery.tracking_number');
      const carrier = byKey.get('delivery.carrier');

      if (shipped && tracking) {
        grounding.push(toGrounding(shipped), toGrounding(tracking));
        if (carrier) grounding.push(toGrounding(carrier));
        parts.push(`It shipped ${strip(shipped.display ?? '')}` +
                   `${carrier ? ` with ${strip(carrier.display ?? '')}` : ''}, ` +
                   `tracking ${strip(tracking.display ?? '')}.`);
      } else if (arrival) {
        grounding.push(toGrounding(arrival));
        parts.push(`It's due back with you ${strip(arrival.display ?? '')}.`);
      } else {
        grounding.push({
          kind: 'status', label: 'Due date',
          text: `Due back ${target.dueDate}.`, display: target.dueDate,
        });
        parts.push(`Due back ${target.dueDate}.`);
      }

      return done({
        text: parts.slice(0, 3).join(' '),
        path: 'status',
        facts,
        grounding,
        category: 'status',
      });
    }
  };
}

// ---------------------------------------------------------------- helpers --

/** PHI and lab-internal facts never leave the lab. */
function visible(facts: ResolvedFact[], requester: Requester): ResolvedFact[] {
  if (requester.kind === 'lab') return facts.filter((f) => f.visibility !== 'phi');
  return facts.filter((f) => f.visibility === 'practice');
}

function toGrounding(fact: ResolvedFact): GroundingItem {
  return {
    kind: fact.status === 'unknown' ? 'unknown' : 'fact',
    factKey: fact.factKey,
    label: fact.definition.label,
    display: fact.display ?? undefined,
    value: fact.value,
    confirmationLevel: fact.confirmationLevel ?? null,
    unknownReason: fact.unknownReason ?? null,
    sourceRef: fact.source?.documentId ?? null,
  };
}

function factLine(fact: ResolvedFact): string {
  return `${fact.definition.label}: ${strip(fact.display ?? '')}.`;
}

const STATUS_KEYS = new Set([
  'case.status', 'delivery.ship_date', 'delivery.expected_arrival',
  'delivery.tracking_number', 'delivery.delay_reason', 'case.hold_reason',
  'delivery.delivered_at', 'delivery.revised_due_date', 'case.due_date',
]);

/**
 * "Where is my case", in all the ways a practice says it.
 *
 * Worth matching on shape as well as on resolved keys: "is it ready?" and "did
 * it arrive?" carry no distinctive vocabulary, and answering them with a single
 * field read-out is the behaviour that makes people phone instead.
 */
const STATUS_INTENT =
  /\b(where is|where'?s|status|ready yet|is it ready|has it (shipped|gone|left|arrived)|did it (ship|arrive|go out)|when (will|does) it|when did it ship|on (its|the) way|tracking|how long|running late|why is it (late|delayed|on hold)|what(?:'s| is) happening|any update|chase)\b/i;

function isStatusQuestion(candidates: string[], question: string): boolean {
  if (STATUS_INTENT.test(question)) return true;
  return candidates.length > 0 && STATUS_KEYS.has(candidates[0]);
}

function categoryOf(candidates: string[]): string {
  const first = candidates[0];
  return first ? FACT_BY_KEY.get(first)?.category ?? 'unknown' : 'unknown';
}

function strip(s: string): string { return s.replace(/\.\s*$/, ''); }
