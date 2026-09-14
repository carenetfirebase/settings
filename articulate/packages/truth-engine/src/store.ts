import { FACT_BY_KEY } from '../../case-catalog/src/index.ts';
import { normalizeValue } from './normalize.ts';
import { levelFromSource } from './engine.ts';
import type {
  CaseClaim, CaseFact, CaseStore, LabCase, MaterialUse, PracticeMessage,
  ProductionStep, UnknownReason,
} from './types.ts';

export type CaseRecord = {
  labCase: LabCase;
  claims: CaseClaim[];
  facts: CaseFact[];
  steps: ProductionStep[];
  materials: MaterialUse[];
  messages: PracticeMessage[];
};

/**
 * Reference store and reference implementation of the bench state machine.
 *
 * Postgres replaces the storage; these transitions are the specification either
 * way, which is why they live here rather than inside a route handler.
 */
export class InMemoryCaseStore implements CaseStore {
  private records = new Map<string, CaseRecord>();
  private sequence = 0;

  load(record: CaseRecord): void { this.records.set(record.labCase.id, record); }

  record(caseId: string): CaseRecord {
    const record = this.records.get(caseId);
    if (!record) throw new Error(`unknown case ${caseId}`);
    return record;
  }

  getCase(caseId: string): LabCase | undefined { return this.records.get(caseId)?.labCase; }
  listCases(): LabCase[] { return [...this.records.values()].map((r) => r.labCase); }
  getClaims(caseId: string): CaseClaim[] { return this.record(caseId).claims; }
  getFacts(caseId: string): CaseFact[] { return this.record(caseId).facts; }
  getSteps(caseId: string): ProductionStep[] { return this.record(caseId).steps; }
  getMaterials(caseId: string): MaterialUse[] { return this.record(caseId).materials; }
  getMessages(caseId: string): PracticeMessage[] { return this.record(caseId).messages; }

  nextId(prefix: string): string {
    this.sequence += 1;
    return `${prefix}-${this.sequence}`;
  }

  addClaim(
    caseId: string,
    claim: Omit<CaseClaim, 'id' | 'caseId' | 'assertedAt'> &
           Partial<Pick<CaseClaim, 'id' | 'assertedAt'>>,
  ): CaseClaim {
    const definition = FACT_BY_KEY.get(claim.factKey);
    if (!definition) throw new Error(`claim against unknown fact key ${claim.factKey}`);

    // A claim read off a document with no page cannot be checked by the person
    // who has to stand behind it, so it is refused at the door.
    if ((claim.source === 'rx_document' || claim.source === 'ai_extraction') &&
        claim.sourcePage == null) {
      throw new Error(`uncited ${claim.source} claim for ${claim.factKey}`);
    }

    let normalized = claim.valueNormalized;
    let display: string | null = claim.valueRaw ?? null;
    if (claim.valueRaw != null) {
      const result = normalizeValue(definition, claim.valueRaw, {
        toothNotation: String(this.record(caseId).labCase.context.tooth_notation ?? 'universal'),
      });
      if (!result.ok) throw new Error(`cannot normalize ${claim.factKey}: ${result.reason}`);
      if (normalized === undefined) normalized = result.value;
      display = result.display;
    }

    const row: CaseClaim = {
      id: claim.id ?? this.nextId('claim'),
      caseId,
      assertedAt: claim.assertedAt ?? new Date().toISOString(),
      ...claim,
      valueNormalized: normalized,
    };
    this.record(caseId).claims.push(row);
    this.refreshFact(caseId, row.factKey, display);
    return row;
  }

  /** CONFIRM — a named person at the lab stands behind this value. */
  confirm(caseId: string, claimId: string, by: string): CaseFact {
    const record = this.record(caseId);
    const claim = record.claims.find((c) => c.id === claimId);
    if (!claim) throw new Error(`unknown claim ${claimId}`);

    claim.status = 'accepted';
    for (const other of record.claims) {
      if (other.id !== claim.id && other.factKey === claim.factKey &&
          other.status === 'pending') {
        other.status = 'superseded';
      }
    }

    const definition = FACT_BY_KEY.get(claim.factKey)!;
    const normalized = normalizeValue(definition, claim.valueRaw ?? '', {
      toothNotation: String(record.labCase.context.tooth_notation ?? 'universal'),
    });

    return this.write(caseId, {
      factKey: claim.factKey,
      valueNormalized: claim.valueNormalized,
      valueDisplay: normalized.ok ? normalized.display : claim.valueRaw ?? null,
      status: 'confirmed',
      confirmationLevel: levelFromSource(claim.source),
      unknownReason: null,
      winningClaimId: claim.id,
      confirmedBy: by,
      confirmedAt: new Date().toISOString(),
      visibility: definition.visibility,
    });
  }

  /** CORRECT — the lab's value supersedes whatever came in. */
  correct(caseId: string, factKey: string, newValue: string, by: string): CaseFact {
    const record = this.record(caseId);
    for (const claim of record.claims) {
      if (claim.factKey === factKey && claim.status === 'pending') {
        claim.status = 'superseded';
      }
    }
    const replacement = this.addClaim(caseId, {
      factKey, valueRaw: newValue, source: 'lab_entry', assertedBy: by, status: 'pending',
    });
    return this.confirm(caseId, replacement.id, by);
  }

  reject(caseId: string, claimId: string): void {
    const claim = this.record(caseId).claims.find((c) => c.id === claimId);
    if (!claim) throw new Error(`unknown claim ${claimId}`);
    claim.status = 'rejected';
    this.refreshFact(caseId, claim.factKey, null);
  }

  /**
   * MARK UNKNOWN — a stored state, not a missing row.
   *
   * "The practice has not supplied a stump shade" and "nobody has looked at
   * this yet" are different facts that drive different behaviour: the first
   * generates a message to the office, the second sits in the queue.
   */
  markUnknown(caseId: string, factKey: string, reason: UnknownReason): CaseFact {
    const definition = FACT_BY_KEY.get(factKey);
    if (!definition) throw new Error(`unknown fact key ${factKey}`);
    return this.write(caseId, {
      factKey,
      valueNormalized: undefined,
      valueDisplay: null,
      status: reason === 'not_applicable' ? 'not_applicable' : 'unknown',
      confirmationLevel: null,
      unknownReason: reason,
      winningClaimId: null,
      confirmedBy: null,
      confirmedAt: new Date().toISOString(),
      visibility: definition.visibility,
    });
  }

  addStep(caseId: string, step: Omit<ProductionStep, 'id' | 'caseId'>): ProductionStep {
    const row: ProductionStep = { id: this.nextId('step'), caseId, ...step };
    this.record(caseId).steps.push(row);
    return row;
  }

  addMaterial(caseId: string, material: Omit<MaterialUse, 'id' | 'caseId'>): MaterialUse {
    const row: MaterialUse = { id: this.nextId('mat'), caseId, ...material };
    this.record(caseId).materials.push(row);
    return row;
  }

  addMessage(caseId: string, message: Omit<PracticeMessage, 'id' | 'caseId'>): PracticeMessage {
    const row: PracticeMessage = { id: this.nextId('msg'), caseId, ...message };
    this.record(caseId).messages.push(row);
    return row;
  }

  setStatus(caseId: string, status: string): void {
    const record = this.record(caseId);
    record.labCase.status = status;
    record.labCase.context.is_on_hold = status === 'on_hold_pending_practice';
  }

  private write(caseId: string, next: Omit<CaseFact, 'caseId' | 'version'>): CaseFact {
    const record = this.record(caseId);
    const existing = record.facts.find((f) => f.factKey === next.factKey);
    if (!existing) {
      const row: CaseFact = { caseId, version: 1, ...next };
      record.facts.push(row);
      return row;
    }
    const changed =
      JSON.stringify(existing.valueNormalized) !== JSON.stringify(next.valueNormalized) ||
      existing.status !== next.status;
    Object.assign(existing, next);
    if (changed) existing.version += 1;
    return existing;
  }

  /**
   * Recompute the resolved row after a claim arrives. It never picks a winner:
   * extraction and imports propose, a person disposes.
   */
  private refreshFact(caseId: string, factKey: string, display: string | null): void {
    const record = this.record(caseId);
    const fact = record.facts.find((f) => f.factKey === factKey);
    if (fact && fact.status === 'confirmed') return;

    const live = record.claims.filter(
      (c) => c.factKey === factKey && (c.status === 'pending' || c.status === 'accepted'));

    if (live.length === 0) {
      if (fact && fact.status !== 'unknown' && fact.status !== 'not_applicable') {
        record.facts = record.facts.filter((f) => f !== fact);
      }
      return;
    }

    const definition = FACT_BY_KEY.get(factKey)!;
    this.write(caseId, {
      factKey,
      valueNormalized: undefined,
      valueDisplay: live.length === 1 ? display : null,
      status: 'pending_review',
      confirmationLevel: null,
      unknownReason: null,
      winningClaimId: null,
      confirmedBy: null,
      confirmedAt: null,
      visibility: definition.visibility,
    });
  }
}
