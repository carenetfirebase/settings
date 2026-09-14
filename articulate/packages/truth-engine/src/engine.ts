import {
  CASE_FACTS, FACT_BY_KEY, QUESTION_TEMPLATES, SECTIONS, SECTION_LABEL,
  splitByApplicability,
} from '../../case-catalog/src/index.ts';
import type { CaseFactDefinition, JsonValue } from '../../case-catalog/src/index.ts';
import { humanize, materiallyDiffers } from './normalize.ts';
import type {
  Ask, CaseClaim, CaseFact, CasePack, CasePackEntry, CaseScore, CaseStore,
  Conflict, ConflictingClaim, ConfirmationLevel, LabCase, ResolvedFact, SectionScore,
} from './types.ts';

/**
 * The Case Truth Engine.
 *
 * Pure data logic over a store: no model, no network, no UI. That is what makes
 * the guarantee auditable — the boundary between "this is on the record" and
 * "this was generated" is a function signature rather than a convention.
 */
export type TruthEngine = {
  resolve(caseId: string, factKeys: string[]): ResolvedFact[];
  detectConflicts(caseId: string): Conflict[];
  score(caseId: string): CaseScore;
  asks(caseId: string, limit?: number, audience?: AskAudience): Ask[];
  blockers(caseId: string): Blocker[];
  buildCasePack(caseId: string): CasePack;
  applicableDefinitions(labCase: LabCase): CaseFactDefinition[];
};

export type BlockerPhase = 'start' | 'design' | 'production' | 'dispatch';

/**
 * Who an outstanding item belongs to.
 *
 * A missing stump shade is the practice's to send; a missing material lot is
 * the bench's to record. Mixing them produces a request list that makes the lab
 * look like it does not know its own job.
 */
export type AskAudience = 'practice' | 'lab';

export type Blocker = {
  kind: 'conflict' | 'missing_blocking_fact';
  factKey: string;
  label: string;
  detail: string;
  safety: string;
  /** The stage this actually holds up. A lot number does not block intake. */
  phase: BlockerPhase;
};

/**
 * Which stage a blocking fact holds up.
 *
 * Everything blocking is not blocking *now*: a case cannot start without a
 * tooth number, but it is perfectly normal for it to sit in design without a
 * material lot, because nobody has opened a puck yet. Collapsing the two makes
 * every case look stuck, and a board where everything is red is a board nobody
 * reads.
 */
const PHASE_BY_SECTION: Record<string, BlockerPhase> = {
  A: 'start', B: 'start', C: 'start',
  D: 'design', E: 'design', F: 'design',
  G: 'production', H: 'production',
  I: 'dispatch', J: 'dispatch', K: 'dispatch', L: 'dispatch',
};

export function levelFromSource(source: CaseClaim['source']): ConfirmationLevel {
  switch (source) {
    case 'lab_entry':        return 'lab_confirmed';
    case 'rx_document':
    case 'ai_extraction':    return 'document_verified';
    case 'practice_message': return 'practice_stated';
    case 'scan_metadata':
    case 'lms_import':       return 'system_imported';
    case 'supplier_record':  return 'supplier_stated';
  }
}

export function createTruthEngine(store: CaseStore): TruthEngine {
  const caseOrThrow = (caseId: string): LabCase => {
    const found = store.getCase(caseId);
    if (!found) throw new Error(`unknown case ${caseId}`);
    return found;
  };

  const applicableDefinitions = (labCase: LabCase): CaseFactDefinition[] =>
    splitByApplicability(labCase.context).applicable;

  const resolve = (caseId: string, factKeys: string[]): ResolvedFact[] => {
    const facts = new Map(store.getFacts(caseId).map((f) => [f.factKey, f]));
    const claims = new Map(store.getClaims(caseId).map((c) => [c.id, c]));
    const out: ResolvedFact[] = [];

    for (const key of factKeys) {
      const definition = FACT_BY_KEY.get(key);
      const fact = facts.get(key);
      if (!definition || !fact) continue;

      const claim = fact.winningClaimId ? claims.get(fact.winningClaimId) : undefined;
      out.push({
        factKey: key,
        definition,
        status: fact.status,
        value: fact.valueNormalized,
        display: fact.valueDisplay ?? null,
        confirmationLevel: fact.confirmationLevel ?? null,
        unknownReason: fact.unknownReason ?? null,
        visibility: fact.visibility,
        version: fact.version,
        source: claim
          ? {
              claimId: claim.id,
              source: claim.source,
              documentId: claim.sourceDocumentId ?? null,
              page: claim.sourcePage ?? null,
              snippet: claim.sourceSnippet ?? null,
              assertedBy: claim.assertedBy ?? null,
            }
          : null,
      });
    }
    return out;
  };

  const detectConflicts = (caseId: string): Conflict[] => {
    const live = store.getClaims(caseId)
      .filter((c) => c.status === 'accepted' || c.status === 'pending');

    const groups = new Map<string, CaseClaim[]>();
    for (const claim of live) {
      const group = groups.get(claim.factKey) ?? [];
      group.push(claim);
      groups.set(claim.factKey, group);
    }

    const conflicts: Conflict[] = [];
    for (const [factKey, group] of groups) {
      if (group.length < 2) continue;
      const definition = FACT_BY_KEY.get(factKey);
      if (!definition) continue;

      let differs = false;
      for (let i = 0; i < group.length && !differs; i += 1) {
        for (let j = i + 1; j < group.length; j += 1) {
          if (materiallyDiffers(definition, group[i].valueNormalized,
                                group[j].valueNormalized)) {
            differs = true;
            break;
          }
        }
      }
      if (!differs) continue;

      conflicts.push({
        factKey,
        label: definition.label,
        safety: definition.safety,
        // The Rx says one tooth and the scan says another. Nothing here picks a
        // winner; the case stops until a person does.
        stopsProduction: definition.safety === 'patient_safety',
        answerWeight: definition.answerWeight,
        claims: group.map(toConflictingClaim),
      });
    }

    return conflicts.sort(
      (a, b) => Number(b.stopsProduction) - Number(a.stopsProduction) ||
                b.answerWeight - a.answerWeight ||
                a.factKey.localeCompare(b.factKey));
  };

  const score = (caseId: string): CaseScore => {
    const labCase = caseOrThrow(caseId);
    const split = splitByApplicability(labCase.context);
    const facts = new Map(store.getFacts(caseId).map((f) => [f.factKey, f]));

    const sectionTotals = new Map<string, SectionScore>(
      SECTIONS.map((s) => [s.key, {
        section: s.key, label: s.label, applicable: 0, resolved: 0, ratio: 0,
      }]));

    let blockingTotal = 0;
    let blockingResolved = 0;
    let answerWeightTotal = 0;
    let answerWeightResolved = 0;
    let resolvedCount = 0;
    const dhrOutstanding: string[] = [];
    let dhrTotal = 0;
    let dhrResolved = 0;

    for (const definition of split.applicable) {
      const fact = facts.get(definition.key);
      const isResolved = fact !== undefined &&
        (fact.status === 'confirmed' || fact.status === 'unknown' ||
         fact.status === 'not_applicable');
      const isAnswerable = fact?.status === 'confirmed';

      const bucket = sectionTotals.get(definition.section)!;
      bucket.applicable += 1;
      if (isResolved) { bucket.resolved += 1; resolvedCount += 1; }

      // Readiness answers one question — can the bench start? — so it counts
      // only the facts that hold up the start. A blocking fact is satisfied by
      // a real value and never by "unknown": that is an honest answer for a
      // shade nobody recorded, not a substitute for knowing which tooth.
      if (definition.necessity === 'blocking' &&
          PHASE_BY_SECTION[definition.section] === 'start') {
        blockingTotal += 1;
        if (isAnswerable) blockingResolved += 1;
      }

      answerWeightTotal += definition.answerWeight;
      if (isAnswerable) answerWeightResolved += definition.answerWeight;

      if (definition.isDhr) {
        dhrTotal += 1;
        if (isAnswerable) dhrResolved += 1;
        else dhrOutstanding.push(definition.key);
      }
    }

    for (const bucket of sectionTotals.values()) {
      bucket.ratio = ratio(bucket.resolved, bucket.applicable);
    }

    return {
      readiness: ratio(blockingResolved, blockingTotal),
      blockingOutstanding: blockingTotal - blockingResolved,
      answerCoverage: ratio(answerWeightResolved, answerWeightTotal),
      dhrCompleteness: ratio(dhrResolved, dhrTotal),
      dhrOutstanding,
      applicableCount: split.applicable.length,
      resolvedCount,
      sections: [...sectionTotals.values()].filter((s) => s.applicable > 0),
      unresolvedApplicability: split.unresolved.length,
    };
  };

  const asks = (caseId: string, limit = 12, audience: AskAudience = 'practice'): Ask[] => {
    const labCase = caseOrThrow(caseId);
    const split = splitByApplicability(labCase.context);
    const facts = new Map(store.getFacts(caseId).map((f) => [f.factKey, f]));
    const frequency = questionFrequency();

    const necessityRank: Record<string, number> = {
      blocking: 1000, required: 200, expected: 40, optional: 5,
    };

    const out: Ask[] = [];
    for (const definition of split.applicable) {
      const fact = facts.get(definition.key);
      if (fact && (fact.status === 'confirmed' || fact.status === 'unknown' ||
                   fact.status === 'not_applicable')) continue;
      if (definition.visibility === 'lab_only') continue;

      // Sections A–C are what the practice supplies; anything else is the
      // bench's own work unless the catalog gives it a question to ask.
      const practiceAnswerable =
        definition.askPractice !== undefined || 'ABC'.includes(definition.section);
      if (audience === 'practice' && !practiceAnswerable) continue;
      if (audience === 'lab' && practiceAnswerable && definition.askPractice === undefined) {
        // Still shown to the bench — it is the bench that chases it.
      }

      out.push({
        factKey: definition.key,
        label: definition.label,
        // Nobody wants to fill in "Stump shade". Everybody understands "we need
        // the stump shade to match a translucent material — what is the
        // prepared tooth shade?"
        question: definition.askPractice ?? questionShape(definition),
        necessity: definition.necessity,
        safety: definition.safety,
        answerWeight: definition.answerWeight,
        priority: necessityRank[definition.necessity] * definition.answerWeight +
                  (frequency.get(definition.key) ?? 0),
        section: SECTION_LABEL[definition.section] ?? definition.section,
        helpText: definition.helpText ?? null,
      });
    }

    return out
      .sort((a, b) => b.priority - a.priority || a.factKey.localeCompare(b.factKey))
      .slice(0, limit);
  };

  const blockers = (caseId: string): Blocker[] => {
    const out: Blocker[] = detectConflicts(caseId)
      .filter((c) => c.stopsProduction)
      .map((c) => ({
        kind: 'conflict' as const,
        factKey: c.factKey,
        label: c.label,
        detail: `${c.claims.length} sources disagree: ` +
                c.claims.map((claim) => `${claim.display} (${humanize(claim.source)})`)
                  .join(' vs '),
        safety: c.safety,
        phase: PHASE_BY_SECTION[FACT_BY_KEY.get(c.factKey)?.section ?? 'A'] ?? 'start',
      }));

    // A key already in conflict is not also "missing" — that is the same
    // problem listed twice, and a queue that double-counts gets skimmed.
    const conflicted = new Set(out.map((b) => b.factKey));

    const labCase = caseOrThrow(caseId);
    const facts = new Map(store.getFacts(caseId).map((f) => [f.factKey, f]));
    for (const definition of applicableDefinitions(labCase)) {
      if (definition.necessity !== 'blocking') continue;
      if (conflicted.has(definition.key)) continue;
      if (facts.get(definition.key)?.status === 'confirmed') continue;
      out.push({
        kind: 'missing_blocking_fact',
        factKey: definition.key,
        label: definition.label,
        detail: definition.askPractice ?? `${definition.label} is not on the case.`,
        safety: definition.safety,
        phase: PHASE_BY_SECTION[definition.section] ?? 'start',
      });
    }

    const safetyRank: Record<string, number> = {
      patient_safety: 0, remake_risk: 1, commercial: 2, informational: 3,
    };
    const phaseRank: Record<BlockerPhase, number> = {
      start: 0, design: 1, production: 2, dispatch: 3,
    };
    return out.sort((a, b) =>
      phaseRank[a.phase] - phaseRank[b.phase] ||
      (safetyRank[a.safety] ?? 9) - (safetyRank[b.safety] ?? 9));
  };

  const buildCasePack = (caseId: string): CasePack => {
    const labCase = caseOrThrow(caseId);
    const packFacts: Record<string, CasePackEntry> = {};
    const unknownKeys: string[] = [];
    const unknownReasons: CasePack['unknown_reasons'] = {};

    for (const fact of store.getFacts(caseId)) {
      const definition = FACT_BY_KEY.get(fact.factKey);
      if (!definition) continue;

      // PHI and lab-internal facts never enter a pack. The pack is what an
      // answer is allowed to draw from, so exclusion here is the enforcement
      // point rather than a caution in a prompt.
      if (fact.visibility !== 'practice') continue;

      if (fact.status === 'unknown') {
        unknownKeys.push(fact.factKey);
        if (fact.unknownReason) unknownReasons[fact.factKey] = fact.unknownReason;
        packFacts[fact.factKey] = { s: 'unknown' };
        continue;
      }
      if (fact.status !== 'confirmed') continue;

      packFacts[fact.factKey] = {
        v: fact.valueNormalized,
        d: fact.valueDisplay ?? undefined,
        s: packStatus(fact.confirmationLevel),
      };
    }

    const pack: CasePack = {
      case_id: labCase.id,
      case_number: labCase.caseNumber,
      practice: labCase.practiceName,
      doctor: labCase.doctorName,
      built_at: new Date().toISOString(),
      content_hash: '',
      status: labCase.status,
      due_date: labCase.dueDate,
      facts: packFacts,
      unknown_keys: unknownKeys.sort(),
      unknown_reasons: unknownReasons,
      open_asks: asks(caseId, 5).map((a) => ({ factKey: a.factKey, question: a.question })),
      materials: store.getMaterials(caseId).map((m) => ({
        role: m.role, brand: m.brand, product: m.product, lot: m.lot,
      })),
      timeline: store.getSteps(caseId).map((s) => ({
        step: s.step, at: s.performedAt, by: s.performedBy,
      })),
      is_demo: labCase.isDemo === true,
    };

    pack.content_hash = `sha256:${hashObject({ ...pack, built_at: '', content_hash: '' })}`;
    return pack;
  };

  return {
    resolve, detectConflicts, score, asks, blockers, buildCasePack,
    applicableDefinitions,
  };
}

// ---------------------------------------------------------------- helpers --

function ratio(part: number, whole: number): number {
  return whole === 0 ? 1 : Math.round((part / whole) * 1000) / 1000;
}

function toConflictingClaim(claim: CaseClaim): ConflictingClaim {
  return {
    claimId: claim.id,
    value: claim.valueNormalized,
    display: claim.valueRaw ?? displayOf(claim.valueNormalized),
    source: claim.source,
    documentId: claim.sourceDocumentId ?? null,
    page: claim.sourcePage ?? null,
    snippet: claim.sourceSnippet ?? null,
  };
}

function displayOf(value: JsonValue | undefined): string {
  if (value === undefined || value === null) return '—';
  if (Array.isArray(value)) return value.join(', ');
  if (typeof value === 'object') return JSON.stringify(value);
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'string' && value.includes('_')) return humanize(value);
  return String(value);
}

function packStatus(level: ConfirmationLevel | null | undefined): CasePackEntry['s'] {
  switch (level) {
    case 'practice_stated': return 'practice_stated';
    case 'supplier_stated': return 'supplier_stated';
    case 'system_imported': return 'imported';
    default: return 'confirmed';
  }
}

let frequencyCache: Map<string, number> | undefined;
function questionFrequency(): Map<string, number> {
  if (frequencyCache) return frequencyCache;
  const map = new Map<string, number>();
  for (const template of QUESTION_TEMPLATES) {
    for (const key of template.factKeys) {
      map.set(key, Math.max(map.get(key) ?? 0, template.frequency));
    }
  }
  frequencyCache = map;
  return map;
}

function questionShape(definition: CaseFactDefinition): string {
  const first = definition.answersQuestions[0];
  if (!first) return `Do you have the ${definition.label.toLowerCase()}?`;
  const q = first.trim();
  const capitalized = q.charAt(0).toUpperCase() + q.slice(1);
  return capitalized.endsWith('?') ? capitalized : `${capitalized}?`;
}

/** Deterministic content hash; names a pack, does not authenticate one. */
export function hashObject(value: unknown): string {
  const json = stableStringify(value);
  const lanes = [0x811c9dc5, 0x01000193, 0x9e3779b9, 0x85ebca6b];
  for (let i = 0; i < json.length; i += 1) {
    const lane = i % 4;
    lanes[lane] = Math.imul(lanes[lane] ^ json.charCodeAt(i), 16777619) >>> 0;
  }
  return lanes.map((l) => l.toString(16).padStart(8, '0')).join('');
}

function stableStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null';
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, v]) => v !== undefined)
    .sort(([a], [b]) => a.localeCompare(b));
  return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${stableStringify(v)}`).join(',')}}`;
}

export { CASE_FACTS };
