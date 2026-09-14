import type { CaseContext, Predicate } from '../../case-catalog/src/types.ts';
import { dhrDefinitions } from '../../case-catalog/src/index.ts';
import { evaluate } from '../../case-catalog/src/predicate.ts';
import type { CaseStore, LabCase, MaterialUse } from '../../truth-engine/src/types.ts';

export type LotHit = {
  caseId: string;
  caseNumber: string;
  practiceName: string;
  doctorName: string;
  patientInitials: string;
  status: string;
  role: MaterialUse['role'];
  brand: string;
  product: string;
  lot: string;
  /** Already in a patient's mouth, so notification is not optional. */
  delivered: boolean;
};

export type RecallResult = {
  lot: string;
  matched: number;
  delivered: number;
  inProduction: number;
  hits: LotHit[];
  /** Everything a notification letter needs, gathered once. */
  practicesToNotify: { practiceName: string; doctorName: string; cases: string[] }[];
};

/**
 * Lot genealogy.
 *
 * A manufacturer recalls a zirconia lot on a Tuesday afternoon. The question is
 * always the same — which patients received it — and the honest answer for most
 * labs today is several days in a filing cabinet. It should be one query, and
 * it should be exact: a partial match is worse than none, because it produces
 * confident notification of the wrong list.
 */
export function findByLot(store: CaseStore, lot: string): RecallResult {
  const needle = lot.trim().toLowerCase();
  const hits: LotHit[] = [];

  for (const labCase of store.listCases()) {
    for (const material of store.getMaterials(labCase.id)) {
      if (material.lot.trim().toLowerCase() !== needle) continue;
      hits.push({
        caseId: labCase.id,
        caseNumber: labCase.caseNumber,
        practiceName: labCase.practiceName,
        doctorName: labCase.doctorName,
        patientInitials: labCase.patientInitials,
        status: labCase.status,
        role: material.role,
        brand: material.brand,
        product: material.product,
        lot: material.lot,
        delivered: ['delivered', 'seated'].includes(labCase.status),
      });
    }
  }

  const byPractice = new Map<string, { practiceName: string; doctorName: string; cases: string[] }>();
  for (const hit of hits) {
    const key = `${hit.practiceName}::${hit.doctorName}`;
    const entry = byPractice.get(key) ??
      { practiceName: hit.practiceName, doctorName: hit.doctorName, cases: [] };
    entry.cases.push(hit.caseNumber);
    byPractice.set(key, entry);
  }

  return {
    lot,
    matched: hits.length,
    delivered: hits.filter((h) => h.delivered).length,
    inProduction: hits.filter((h) => !h.delivered).length,
    hits,
    practicesToNotify: [...byPractice.values()],
  };
}

export type DhrEntry = {
  factKey: string;
  label: string;
  value: string;
  confirmedBy: string | null;
  confirmedAt: string | null;
  source: string | null;
};

export type DeviceHistoryRecord = {
  caseNumber: string;
  practice: string;
  doctor: string;
  patientInitials: string;
  builtAt: string;
  complete: boolean;
  entries: DhrEntry[];
  missing: { factKey: string; label: string }[];
  materials: MaterialUse[];
  steps: { step: string; by: string; at: string; equipment?: string | null;
           program?: string | null }[];
};

/**
 * Assemble the Device History Record for one case.
 *
 * `complete` is computed from the catalog's DHR-flagged facts rather than
 * asserted by anyone. A lab that ticks "records complete" without the check is
 * guessing about its own filing, which is the failure mode this replaces.
 */
export function buildDeviceHistoryRecord(
  store: CaseStore, labCase: LabCase,
): DeviceHistoryRecord {
  const facts = new Map(store.getFacts(labCase.id).map((f) => [f.factKey, f]));
  const entries: DhrEntry[] = [];
  const missing: { factKey: string; label: string }[] = [];
  const claims = new Map(store.getClaims(labCase.id).map((c) => [c.id, c]));

  for (const definition of dhrDefinitions()) {
    const fact = facts.get(definition.key);
    if (!fact || fact.status !== 'confirmed') {
      // Only count what this case could have had. A denture case is not
      // incomplete for lacking an abutment part number.
      const applicable = isApplicable(definition.appliesWhen, labCase.context);
      if (applicable) missing.push({ factKey: definition.key, label: definition.label });
      continue;
    }
    const claim = fact.winningClaimId ? claims.get(fact.winningClaimId) : undefined;
    entries.push({
      factKey: definition.key,
      label: definition.label,
      value: fact.valueDisplay ?? String(fact.valueNormalized ?? ''),
      confirmedBy: fact.confirmedBy ?? null,
      confirmedAt: fact.confirmedAt ?? null,
      source: claim ? claim.source : null,
    });
  }

  return {
    caseNumber: labCase.caseNumber,
    practice: labCase.practiceName,
    doctor: labCase.doctorName,
    patientInitials: labCase.patientInitials,
    builtAt: new Date().toISOString(),
    complete: missing.length === 0,
    entries,
    missing,
    materials: store.getMaterials(labCase.id),
    steps: store.getSteps(labCase.id).map((s) => ({
      step: s.step, by: s.performedBy, at: s.performedAt,
      equipment: s.equipment, program: s.program,
    })),
  };
}

function isApplicable(pred: Predicate, ctx: CaseContext): boolean {
  return evaluate(pred, ctx) === true;
}
