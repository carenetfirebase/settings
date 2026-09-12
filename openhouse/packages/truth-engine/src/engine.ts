import {
  FACT_BY_KEY, FACT_DEFINITIONS, QUESTION_TEMPLATES, SECTIONS, SECTION_LABEL,
  splitByApplicability,
} from '../../fact-catalog/src/index.ts';
import type { FactDefinition, JsonValue } from '../../fact-catalog/src/index.ts';
import { humanize, materiallyDiffers } from './normalize.ts';
import type {
  Conflict, ConflictingClaim, CoverageScore, FactClaim, FactPack, FactPackEntry,
  Gap, Property, PropertyFact, ResolvedFact, SectionScore, TruthStore,
  VerificationLevel,
} from './types.ts';

/**
 * The Property Truth Engine (§7).
 *
 * No LLM dependency, no HTTP, no React. Pure data logic over a store, which is
 * what makes the zero-hallucination guarantee auditable: the boundary between
 * "retrieved" and "generated" is a function signature, not a convention.
 */
export type TruthEngine = {
  resolve(propertyId: string, factKeys: string[]): ResolvedFact[];
  detectConflicts(propertyId: string): Conflict[];
  score(propertyId: string): CoverageScore;
  gaps(propertyId: string, limit?: number): Gap[];
  buildFactPack(propertyId: string): FactPack;
  applicableDefinitions(property: Property): FactDefinition[];
  publishBlockers(propertyId: string): PublishBlocker[];
};

export type PublishBlocker = {
  kind: 'conflict' | 'unreviewed_disclosure';
  factKey: string;
  label: string;
  detail: string;
};

/** Conflicts on facts this important stop a publish outright (§7.3). */
export const PUBLISH_BLOCKING_WEIGHT = 7;

/** Source hierarchy (§7.2). Rank 1 is strongest. */
const LEVEL_RANK: Record<VerificationLevel, number> = {
  agent_confirmed: 1,
  document_verified: 2,
  seller_provided: 3,
  agent_commentary: 4,
  public_source: 5,
};

export function levelFromSource(sourceType: FactClaim['sourceType']): VerificationLevel {
  switch (sourceType) {
    case 'agent_input':       return 'agent_confirmed';
    case 'document':
    case 'ai_extraction':     return 'document_verified';
    case 'seller_disclosure': return 'seller_provided';
    case 'mls':               return 'public_source';
    case 'public_data':       return 'public_source';
  }
}

export function createTruthEngine(store: TruthStore): TruthEngine {
  const propertyOrThrow = (propertyId: string): Property => {
    const property = store.getProperty(propertyId);
    if (!property) throw new Error(`unknown property ${propertyId}`);
    return property;
  };

  const applicableDefinitions = (property: Property): FactDefinition[] =>
    splitByApplicability(property.applicability).applicable;

  const resolve = (propertyId: string, factKeys: string[]): ResolvedFact[] => {
    const facts = indexFacts(store.getFacts(propertyId));
    const claimsById = new Map(store.getClaims(propertyId).map((c) => [c.id, c]));
    const out: ResolvedFact[] = [];

    for (const key of factKeys) {
      const definition = FACT_BY_KEY.get(key);
      if (!definition) continue;

      // Room-scoped keys may resolve to several rows; property-scoped to one.
      const matches = facts.get(key) ?? [];
      if (matches.length === 0) continue;

      for (const fact of matches) {
        const claim = fact.winningClaimId ? claimsById.get(fact.winningClaimId) : undefined;
        out.push({
          factKey: key,
          roomId: fact.roomId ?? null,
          definition,
          status: fact.status,
          value: fact.valueNormalized,
          display: fact.valueDisplay ?? null,
          verificationLevel: fact.verificationLevel ?? null,
          unknownReason: fact.unknownReason ?? null,
          visibility: fact.visibility,
          version: fact.version,
          source: claim
            ? {
                claimId: claim.id,
                sourceType: claim.sourceType,
                documentId: claim.sourceDocumentId ?? null,
                page: claim.sourcePage ?? null,
                snippet: claim.sourceSnippet ?? null,
              }
            : null,
        });
      }
    }
    return out;
  };

  const detectConflicts = (propertyId: string): Conflict[] => {
    const live = store.getClaims(propertyId)
      .filter((c) => c.status === 'accepted' || c.status === 'pending');

    const groups = new Map<string, FactClaim[]>();
    for (const claim of live) {
      const groupKey = `${claim.factKey}::${claim.roomId ?? ''}`;
      const group = groups.get(groupKey) ?? [];
      group.push(claim);
      groups.set(groupKey, group);
    }

    const conflicts: Conflict[] = [];
    for (const [, group] of groups) {
      if (group.length < 2) continue;
      const definition = FACT_BY_KEY.get(group[0].factKey);
      if (!definition) continue;

      let differs = false;
      let severity: 'soft' | 'hard' = 'soft';
      for (let i = 0; i < group.length; i += 1) {
        for (let j = i + 1; j < group.length; j += 1) {
          const verdict = materiallyDiffers(
            definition.dataType, group[i].valueNormalized, group[j].valueNormalized);
          if (!verdict.differs) continue;
          differs = true;
          if (verdict.severity === 'hard') severity = 'hard';
        }
      }
      if (!differs) continue;

      const blocksPublish =
        severity === 'hard' && definition.coverageWeight >= PUBLISH_BLOCKING_WEIGHT;

      conflicts.push({
        factKey: definition.key,
        roomId: group[0].roomId ?? null,
        label: definition.label,
        dataType: definition.dataType,
        severity,
        coverageWeight: definition.coverageWeight,
        blocksPublish,
        claims: group.map(toConflictingClaim),
      });
    }

    // The queue is read top-down and the top is where attention is: publish
    // blockers first, then weight, then a stable key order.
    return conflicts.sort(
      (a, b) => Number(b.blocksPublish) - Number(a.blocksPublish) ||
                b.coverageWeight - a.coverageWeight ||
                a.factKey.localeCompare(b.factKey));
  };

  const score = (propertyId: string): CoverageScore => {
    const property = propertyOrThrow(propertyId);
    const split = splitByApplicability(property.applicability);
    const facts = indexFacts(store.getFacts(propertyId));

    const sectionTotals = new Map<string, SectionScore>();
    for (const section of SECTIONS) {
      sectionTotals.set(section.key, {
        section: section.key,
        label: section.label,
        applicableWeight: 0,
        reviewedWeight: 0,
        answerableWeight: 0,
        preparation: 0,
        answerCoverage: 0,
      });
    }

    let applicableWeight = 0;
    let reviewedWeight = 0;
    let answerableWeight = 0;
    let reviewedCount = 0;
    let answerableCount = 0;

    for (const definition of split.applicable) {
      const weight = definition.coverageWeight;
      const bucket = sectionTotals.get(definition.section)!;
      applicableWeight += weight;
      bucket.applicableWeight += weight;

      const status = bestStatusFor(facts.get(definition.key));
      const reviewed =
        status === 'verified' || status === 'unknown' || status === 'not_applicable';
      const answerable = status === 'verified';

      if (reviewed) {
        reviewedWeight += weight;
        bucket.reviewedWeight += weight;
        reviewedCount += 1;
      }
      if (answerable) {
        answerableWeight += weight;
        bucket.answerableWeight += weight;
        answerableCount += 1;
      }
    }

    for (const bucket of sectionTotals.values()) {
      bucket.preparation = ratio(bucket.reviewedWeight, bucket.applicableWeight);
      bucket.answerCoverage = ratio(bucket.answerableWeight, bucket.applicableWeight);
    }

    return {
      applicableCount: split.applicable.length,
      reviewedCount,
      answerableCount,
      preparation: ratio(reviewedWeight, applicableWeight),
      answerCoverage: ratio(answerableWeight, applicableWeight),
      sections: [...sectionTotals.values()]
        .filter((s) => s.applicableWeight > 0)
        .sort((a, b) => b.answerCoverage - a.answerCoverage),
      unresolvedApplicability: split.unresolved.length,
      missingSetupFields: split.missingFields,
    };
  };

  const gaps = (propertyId: string, limit = 20): Gap[] => {
    const property = propertyOrThrow(propertyId);
    const split = splitByApplicability(property.applicability);
    const facts = indexFacts(store.getFacts(propertyId));
    const frequency = questionFrequencyByKey();

    const out: Gap[] = [];
    for (const definition of split.applicable) {
      const status = bestStatusFor(facts.get(definition.key));
      if (status === 'verified' || status === 'unknown' || status === 'not_applicable') {
        continue;
      }
      const freq = frequency.get(definition.key) ?? definition.coverageWeight * 5;
      out.push({
        factKey: definition.key,
        label: definition.label,
        section: SECTION_LABEL[definition.section] ?? definition.section,
        // Nobody wants to fill in "Electrical service amperage". Everybody
        // understands "Do you know what the electrical service is?" (§4).
        question: questionShape(definition),
        coverageWeight: definition.coverageWeight,
        questionFrequency: freq,
        priority: definition.coverageWeight * freq,
        status: status ?? 'unreviewed',
        helpText: definition.helpText ?? null,
      });
    }

    return out
      .sort((a, b) => b.priority - a.priority || a.factKey.localeCompare(b.factKey))
      .slice(0, limit);
  };

  const publishBlockers = (propertyId: string): PublishBlocker[] => {
    const blockers: PublishBlocker[] = detectConflicts(propertyId)
      .filter((c) => c.blocksPublish)
      .map((c) => ({
        kind: 'conflict' as const,
        factKey: c.factKey,
        label: c.label,
        detail: `${c.claims.length} sources disagree: ` +
                c.claims.map((claim) => claim.display).join(' vs '),
      }));

    const facts = indexFacts(store.getFacts(propertyId));
    const property = propertyOrThrow(propertyId);
    const applicable = new Set(applicableDefinitions(property).map((d) => d.key));

    for (const definition of FACT_DEFINITIONS) {
      if (!definition.isDisclosure || !applicable.has(definition.key)) continue;
      const rows = facts.get(definition.key) ?? [];
      const hasClaimAwaitingReview = rows.some(
        (f) => f.status === 'pending_review' || f.status === 'conflicted');
      if (!hasClaimAwaitingReview) continue;
      blockers.push({
        kind: 'unreviewed_disclosure',
        factKey: definition.key,
        label: definition.label,
        detail: 'A disclosure item is still unreviewed.',
      });
    }
    return blockers;
  };

  const buildFactPack = (propertyId: string): FactPack => {
    const property = propertyOrThrow(propertyId);
    const rooms = store.getRooms(propertyId);
    const facts = store.getFacts(propertyId);
    const claims = new Map(store.getClaims(propertyId).map((c) => [c.id, c]));

    const packFacts: Record<string, FactPackEntry> = {};
    const unknownKeys: string[] = [];
    const unknownReasons: Record<string, FactPack['unknown_reasons'][string]> = {};
    const roomFacts = new Map<string, Record<string, FactPackEntry>>();

    for (const fact of facts) {
      const definition = FACT_BY_KEY.get(fact.factKey);
      if (!definition) continue;

      // A fact pack is a published artefact. Agent-only facts never enter it,
      // so a leak would require a bug in the *builder*, not in the prompt.
      if (fact.visibility !== 'public') continue;

      if (fact.status === 'unknown') {
        unknownKeys.push(fact.factKey);
        if (fact.unknownReason) unknownReasons[fact.factKey] = fact.unknownReason;
        const entry: FactPackEntry = { s: 'unknown' };
        placeEntry(fact, entry, packFacts, roomFacts);
        continue;
      }

      if (fact.status !== 'verified') continue;

      const claim = fact.winningClaimId ? claims.get(fact.winningClaimId) : undefined;
      const entry: FactPackEntry = {
        v: fact.valueNormalized,
        d: fact.valueDisplay ?? undefined,
        s: packStatus(fact.verificationLevel),
      };
      if (claim?.sourceDocumentId) entry.src = `doc:${claim.sourceDocumentId}`;
      placeEntry(fact, entry, packFacts, roomFacts);
    }

    const pack: FactPack = {
      property_id: property.id,
      snapshot_hash: '',
      built_at: new Date().toISOString(),
      address: `${property.addressLine1}, ${property.city}, ${property.province}`,
      price: property.listPrice != null
        ? { v: property.listPrice, s: 'verified' }
        : null,
      headline: {
        bedrooms: property.bedrooms ?? null,
        bathrooms: property.bathrooms ?? null,
        living_area_sqft: property.livingAreaSqft ?? null,
        year_built: property.yearBuilt ?? null,
        property_type: property.propertyType,
      },
      facts: packFacts,
      rooms: rooms
        .slice()
        .sort((a, b) => a.sortOrder - b.sortOrder)
        .map((room) => ({
          id: room.key,
          key: room.key,
          name: room.name,
          adjacency: room.adjacency,
          facts: roomFacts.get(room.id) ?? {},
        })),
      commentary: store.getCommentary(propertyId)
        .filter((c) => c.approved && c.visibility === 'public')
        .map((c) => ({
          scope: c.scope,
          room: c.roomId ? rooms.find((r) => r.id === c.roomId)?.key ?? null : null,
          by: c.author,
          text: c.text,
        })),
      inclusions: groupInclusions(store.getInclusions(propertyId)),
      // Disclosures are always present and never softened (§12.3).
      disclosures: store.getDisclosures(propertyId).map((d) => ({
        title: d.title,
        detail: d.detail,
        occurred_on: d.occurredOn ?? null,
        remediated: d.remediated,
        remediation_detail: d.remediationDetail ?? null,
      })),
      unknown_keys: unknownKeys.sort(),
      unknown_reasons: unknownReasons,
      is_demo: property.isDemo === true,
    };

    pack.snapshot_hash = `sha256:${hashObject({ ...pack, built_at: '', snapshot_hash: '' })}`;
    return pack;
  };

  return {
    resolve, detectConflicts, score, gaps, buildFactPack,
    applicableDefinitions, publishBlockers,
  };
}

// ---------------------------------------------------------------- helpers --

function indexFacts(facts: PropertyFact[]): Map<string, PropertyFact[]> {
  const index = new Map<string, PropertyFact[]>();
  for (const fact of facts) {
    const rows = index.get(fact.factKey) ?? [];
    rows.push(fact);
    index.set(fact.factKey, rows);
  }
  return index;
}

/**
 * A room-scoped key can be verified in one room and unreviewed in another.
 * Coverage takes the strongest state so that finishing the kitchen counts as
 * progress, rather than being erased by an untouched spare bedroom.
 */
function bestStatusFor(rows: PropertyFact[] | undefined): PropertyFact['status'] | undefined {
  if (!rows || rows.length === 0) return undefined;
  const order: PropertyFact['status'][] =
    ['verified', 'unknown', 'not_applicable', 'conflicted', 'pending_review'];
  for (const status of order) {
    if (rows.some((r) => r.status === status)) return status;
  }
  return rows[0].status;
}

function ratio(part: number, whole: number): number {
  return whole === 0 ? 0 : Math.round((part / whole) * 1000) / 1000;
}

function toConflictingClaim(claim: FactClaim): ConflictingClaim {
  return {
    claimId: claim.id,
    value: claim.valueNormalized,
    display: claim.valueRaw ?? displayOf(claim.valueNormalized),
    sourceType: claim.sourceType,
    documentId: claim.sourceDocumentId ?? null,
    page: claim.sourcePage ?? null,
    snippet: claim.sourceSnippet ?? null,
  };
}

function displayOf(value: JsonValue | undefined): string {
  if (value === undefined || value === null) return '—';
  if (typeof value === 'object') return JSON.stringify(value);
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'string' && value.includes('_')) return humanize(value);
  return String(value);
}

function packStatus(level: VerificationLevel | null | undefined): FactPackEntry['s'] {
  switch (level) {
    case 'seller_provided':  return 'seller_provided';
    case 'agent_commentary': return 'agent_commentary';
    case 'public_source':    return 'public';
    default:                 return 'verified';
  }
}

function placeEntry(
  fact: PropertyFact,
  entry: FactPackEntry,
  packFacts: Record<string, FactPackEntry>,
  roomFacts: Map<string, Record<string, FactPackEntry>>,
): void {
  if (!fact.roomId) { packFacts[fact.factKey] = entry; return; }
  const bucket = roomFacts.get(fact.roomId) ?? {};
  bucket[fact.factKey] = entry;
  roomFacts.set(fact.roomId, bucket);
}

function groupInclusions(inclusions: { kind: string; item: string }[]) {
  const out = { included: [] as string[], excluded: [] as string[], negotiable: [] as string[] };
  for (const inclusion of inclusions) {
    if (inclusion.kind === 'included') out.included.push(inclusion.item);
    else if (inclusion.kind === 'excluded') out.excluded.push(inclusion.item);
    else out.negotiable.push(inclusion.item);
  }
  return out;
}

let frequencyCache: Map<string, number> | undefined;
function questionFrequencyByKey(): Map<string, number> {
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

/** Turn a catalog label into the question a visitor would actually ask. */
function questionShape(definition: FactDefinition): string {
  const first = definition.answersQuestions[0];
  if (!first) return `Do you know the ${definition.label.toLowerCase()}?`;
  const question = first.trim();
  const capitalized = question.charAt(0).toUpperCase() + question.slice(1);
  return capitalized.endsWith('?') ? capitalized : `${capitalized}?`;
}

/**
 * Deterministic content hash over a fact pack. Key order must not change the
 * hash, or a republish with identical content would invalidate every cache and
 * break snapshot comparison.
 */
export function hashObject(value: unknown): string {
  const json = stableStringify(value);
  // FNV-1a, 128 bits as four interleaved lanes. Not cryptographic — it names a
  // snapshot, it does not authenticate one.
  const lanes = [0x811c9dc5, 0x01000193, 0x9e3779b9, 0x85ebca6b];
  for (let i = 0; i < json.length; i += 1) {
    const code = json.charCodeAt(i);
    const lane = i % 4;
    lanes[lane] = Math.imul(lanes[lane] ^ code, 16777619) >>> 0;
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
