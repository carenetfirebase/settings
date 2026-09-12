import { FACT_BY_KEY } from '../../fact-catalog/src/index.ts';
import type { JsonValue } from '../../fact-catalog/src/index.ts';
import { normalizeValue } from './normalize.ts';
import { levelFromSource } from './engine.ts';
import type {
  Commentary, Disclosure, FactClaim, Inclusion, Property, PropertyFact, Room,
  TruthStore, UnknownReason,
} from './types.ts';

export type PropertyRecord = {
  property: Property;
  rooms: Room[];
  claims: FactClaim[];
  facts: PropertyFact[];
  commentary: Commentary[];
  inclusions: Inclusion[];
  disclosures: Disclosure[];
};

/**
 * Reference implementation of the store, and the reference implementation of
 * the verification state machine (§9.2). Postgres will replace the storage;
 * the transitions below are the specification either way, which is why they
 * live in the engine package rather than in a route handler.
 */
export class InMemoryStore implements TruthStore {
  private records = new Map<string, PropertyRecord>();
  private sequence = 0;

  load(record: PropertyRecord): void {
    this.records.set(record.property.id, record);
  }

  record(propertyId: string): PropertyRecord {
    const record = this.records.get(propertyId);
    if (!record) throw new Error(`unknown property ${propertyId}`);
    return record;
  }

  getProperty(propertyId: string): Property | undefined {
    return this.records.get(propertyId)?.property;
  }
  getRooms(propertyId: string): Room[] { return this.record(propertyId).rooms; }
  getClaims(propertyId: string): FactClaim[] { return this.record(propertyId).claims; }
  getFacts(propertyId: string): PropertyFact[] { return this.record(propertyId).facts; }
  getCommentary(propertyId: string): Commentary[] { return this.record(propertyId).commentary; }
  getInclusions(propertyId: string): Inclusion[] { return this.record(propertyId).inclusions; }
  getDisclosures(propertyId: string): Disclosure[] { return this.record(propertyId).disclosures; }

  nextId(prefix: string): string {
    this.sequence += 1;
    return `${prefix}-${this.sequence}`;
  }

  addClaim(propertyId: string, claim: Omit<FactClaim, 'id' | 'propertyId' | 'assertedAt'> &
                                    Partial<Pick<FactClaim, 'id' | 'assertedAt'>>): FactClaim {
    const definition = FACT_BY_KEY.get(claim.factKey);
    if (!definition) throw new Error(`claim against unknown fact key ${claim.factKey}`);

    // A document-sourced claim with no page citation is refused here as well as
    // by the database: if the model cannot point at where it read something, it
    // invented it (§8.1).
    if ((claim.sourceType === 'document' || claim.sourceType === 'ai_extraction') &&
        claim.sourcePage == null) {
      throw new Error(`uncited ${claim.sourceType} claim for ${claim.factKey}`);
    }

    let normalized = claim.valueNormalized;
    if (normalized === undefined && claim.valueRaw != null) {
      const result = normalizeValue(definition, claim.valueRaw);
      if (!result.ok) throw new Error(`cannot normalize ${claim.factKey}: ${result.reason}`);
      normalized = result.value;
    }

    const row: FactClaim = {
      id: claim.id ?? this.nextId('claim'),
      propertyId,
      assertedAt: claim.assertedAt ?? new Date().toISOString(),
      ...claim,
      valueNormalized: normalized,
    };
    this.record(propertyId).claims.push(row);
    this.refreshFactRow(propertyId, row.factKey, row.roomId ?? null);
    return row;
  }

  /** CONFIRM — the claim becomes the resolved truth. */
  confirmClaim(propertyId: string, claimId: string, agentId: string): PropertyFact {
    const record = this.record(propertyId);
    const claim = record.claims.find((c) => c.id === claimId);
    if (!claim) throw new Error(`unknown claim ${claimId}`);

    claim.status = 'accepted';
    for (const other of record.claims) {
      if (other.id !== claim.id &&
          other.factKey === claim.factKey &&
          (other.roomId ?? null) === (claim.roomId ?? null) &&
          other.status === 'pending') {
        other.status = 'superseded';
      }
    }

    const definition = FACT_BY_KEY.get(claim.factKey)!;
    // Display comes from the normalized value, not the raw document string: the
    // invoice says "Sept 2019" and the visitor should hear "2019".
    const display = claim.valueRaw != null
      ? (() => {
          const result = normalizeValue(definition, claim.valueRaw);
          return result.ok ? result.display : claim.valueRaw!;
        })()
      : null;

    return this.writeFact(propertyId, {
      factKey: claim.factKey,
      roomId: claim.roomId ?? null,
      valueNormalized: claim.valueNormalized,
      valueDisplay: display,
      status: 'verified',
      verificationLevel: levelFromSource(claim.sourceType),
      unknownReason: null,
      winningClaimId: claim.id,
      confirmedBy: agentId,
      confirmedAt: new Date().toISOString(),
      visibility: definition.defaultVisibility,
    });
  }

  /** EDIT — the agent's value supersedes the extracted one and is agent-confirmed. */
  editClaim(propertyId: string, claimId: string, newValueRaw: string, agentId: string): PropertyFact {
    const record = this.record(propertyId);
    const original = record.claims.find((c) => c.id === claimId);
    if (!original) throw new Error(`unknown claim ${claimId}`);

    const replacement = this.addClaim(propertyId, {
      factKey: original.factKey,
      roomId: original.roomId ?? null,
      valueRaw: newValueRaw,
      sourceType: 'agent_input',
      assertedBy: agentId,
      status: 'pending',
    });
    original.status = 'superseded';
    return this.confirmClaim(propertyId, replacement.id, agentId);
  }

  /** REJECT — the claim is out; the fact goes back to unreviewed unless another claim stands. */
  rejectClaim(propertyId: string, claimId: string): void {
    const record = this.record(propertyId);
    const claim = record.claims.find((c) => c.id === claimId);
    if (!claim) throw new Error(`unknown claim ${claimId}`);
    claim.status = 'rejected';
    this.refreshFactRow(propertyId, claim.factKey, claim.roomId ?? null);
  }

  /**
   * MARK UNKNOWN — a stored state, not an absent row (§0.3).
   *
   * The reason shapes the visitor answer: "the seller doesn't have a record of
   * that" reads as candour, "I don't have that information" reads as a gap.
   */
  markUnknown(
    propertyId: string, factKey: string, reason: UnknownReason,
    roomId: string | null = null,
  ): PropertyFact {
    const definition = FACT_BY_KEY.get(factKey);
    if (!definition) throw new Error(`unknown fact key ${factKey}`);
    return this.writeFact(propertyId, {
      factKey,
      roomId,
      valueNormalized: undefined,
      valueDisplay: null,
      status: reason === 'not_applicable' ? 'not_applicable' : 'unknown',
      verificationLevel: null,
      unknownReason: reason,
      winningClaimId: null,
      confirmedBy: null,
      confirmedAt: new Date().toISOString(),
      visibility: definition.defaultVisibility,
    });
  }

  setVisibility(propertyId: string, factKey: string, visibility: PropertyFact['visibility']): void {
    const fact = this.record(propertyId).facts.find((f) => f.factKey === factKey);
    if (fact) { fact.visibility = visibility; fact.version += 1; }
  }

  private writeFact(
    propertyId: string,
    next: Omit<PropertyFact, 'propertyId' | 'version'>,
  ): PropertyFact {
    const record = this.record(propertyId);
    const existing = record.facts.find(
      (f) => f.factKey === next.factKey && (f.roomId ?? null) === (next.roomId ?? null));

    if (!existing) {
      const row: PropertyFact = { propertyId, version: 1, ...next };
      record.facts.push(row);
      return row;
    }

    const changed =
      JSON.stringify(existing.valueNormalized) !== JSON.stringify(next.valueNormalized) ||
      existing.status !== next.status ||
      existing.visibility !== next.visibility;

    Object.assign(existing, next);
    if (changed) existing.version += 1;
    return existing;
  }

  /**
   * Recompute the resolved row after a claim changes. This never picks a winner
   * on its own: a higher-ranked claim wins only when the agent has confirmed it.
   * The engine proposes, the agent disposes (§7.2).
   */
  private refreshFactRow(propertyId: string, factKey: string, roomId: string | null): void {
    const record = this.record(propertyId);
    const fact = record.facts.find(
      (f) => f.factKey === factKey && (f.roomId ?? null) === roomId);
    if (fact && fact.status === 'verified') return;

    const live = record.claims.filter(
      (c) => c.factKey === factKey &&
             (c.roomId ?? null) === roomId &&
             (c.status === 'pending' || c.status === 'accepted'));

    if (live.length === 0) {
      if (fact && fact.status !== 'unknown' && fact.status !== 'not_applicable') {
        record.facts = record.facts.filter((f) => f !== fact);
      }
      return;
    }

    const definition = FACT_BY_KEY.get(factKey)!;
    this.writeFact(propertyId, {
      factKey,
      roomId,
      valueNormalized: undefined,
      valueDisplay: null,
      status: 'pending_review',
      verificationLevel: null,
      unknownReason: null,
      winningClaimId: null,
      visibility: definition.defaultVisibility,
    });
  }
}

export function claimValue(claim: FactClaim): JsonValue | undefined {
  return claim.valueNormalized;
}
