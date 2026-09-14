import type {
  CaseContext, CaseFactDefinition, JsonValue, Necessity, SafetyClass, Visibility,
} from '../../case-catalog/src/index.ts';

export type ClaimSource =
  | 'rx_document'      // the written prescription
  | 'scan_metadata'    // what the intake file says about itself
  | 'practice_message' // the office told us, in writing
  | 'lab_entry'        // a technician entered it at the bench
  | 'lms_import'       // pulled from the lab management system
  | 'supplier_record'  // a material certificate or packing slip
  | 'ai_extraction';   // read off a document by a model

export type ClaimStatus = 'pending' | 'accepted' | 'rejected' | 'superseded';

export type FactStatus =
  | 'confirmed' | 'unknown' | 'not_applicable' | 'pending_review' | 'conflicted';

export type ConfirmationLevel =
  | 'lab_confirmed'      // a named person at the lab stands behind it
  | 'document_verified'  // read from the Rx or a certificate, checked
  | 'practice_stated'    // the office said so
  | 'system_imported'    // came from an integration, unreviewed by a person
  | 'supplier_stated';

export type UnknownReason =
  | 'practice_has_not_supplied'
  | 'not_recorded_at_the_time'
  | 'not_applicable'
  | 'awaiting_supplier'
  | 'will_follow_up';

export type CaseClaim = {
  id: string;
  caseId: string;
  factKey: string;
  valueRaw?: string | null;
  valueNormalized?: JsonValue;
  source: ClaimSource;
  sourceDocumentId?: string | null;
  sourcePage?: number | null;
  sourceSnippet?: string | null;
  confidence?: number | null;
  assertedBy?: string | null;
  assertedAt: string;
  status: ClaimStatus;
};

export type CaseFact = {
  caseId: string;
  factKey: string;
  valueNormalized?: JsonValue;
  valueDisplay?: string | null;
  status: FactStatus;
  confirmationLevel?: ConfirmationLevel | null;
  unknownReason?: UnknownReason | null;
  winningClaimId?: string | null;
  confirmedBy?: string | null;
  confirmedAt?: string | null;
  visibility: Visibility;
  version: number;
  notes?: string | null;
};

export type LabCase = {
  id: string;
  caseNumber: string;
  practiceId: string;
  practiceName: string;
  doctorName: string;
  patientInitials: string;
  /** Predicate inputs: restoration_type, material_class, is_implant… */
  context: CaseContext;
  receivedAt: string;
  dueDate: string;
  seatDate?: string | null;
  status: string;
  isDemo?: boolean;
};

export type ProductionStep = {
  id: string;
  caseId: string;
  step: string;
  performedBy: string;
  performedAt: string;
  equipment?: string | null;
  program?: string | null;
  notes?: string | null;
};

export type MaterialUse = {
  id: string;
  caseId: string;
  role: 'primary' | 'ingot' | 'stain_glaze' | 'resin' | 'acrylic' | 'alloy' | 'teeth';
  brand: string;
  product: string;
  lot: string;
  expiry?: string | null;
  certificateRef?: string | null;
};

export type PracticeMessage = {
  id: string;
  caseId: string;
  direction: 'to_practice' | 'from_practice';
  body: string;
  at: string;
  aboutFactKeys?: string[];
};

export type CaseStore = {
  getCase(caseId: string): LabCase | undefined;
  listCases(): LabCase[];
  getClaims(caseId: string): CaseClaim[];
  getFacts(caseId: string): CaseFact[];
  getSteps(caseId: string): ProductionStep[];
  getMaterials(caseId: string): MaterialUse[];
  getMessages(caseId: string): PracticeMessage[];
};

export type ResolvedFact = {
  factKey: string;
  definition: CaseFactDefinition;
  status: FactStatus;
  value?: JsonValue;
  display?: string | null;
  confirmationLevel?: ConfirmationLevel | null;
  unknownReason?: UnknownReason | null;
  visibility: Visibility;
  version: number;
  source?: {
    claimId: string;
    source: ClaimSource;
    documentId?: string | null;
    page?: number | null;
    snippet?: string | null;
    assertedBy?: string | null;
  } | null;
};

export type ConflictingClaim = {
  claimId: string;
  value: JsonValue | undefined;
  display: string;
  source: ClaimSource;
  documentId?: string | null;
  page?: number | null;
  snippet?: string | null;
};

export type Conflict = {
  factKey: string;
  label: string;
  safety: SafetyClass;
  /**
   * A patient-safety conflict is a hard stop: the case does not move until a
   * person resolves it. Nothing in this system picks a winner between "the Rx
   * says tooth 19" and "the scan says tooth 20".
   */
  stopsProduction: boolean;
  answerWeight: number;
  claims: ConflictingClaim[];
};

export type SectionScore = {
  section: string;
  label: string;
  applicable: number;
  resolved: number;
  ratio: number;
};

export type CaseScore = {
  /** Can the bench start? Counts only facts that hold up the start. */
  readiness: number;
  blockingOutstanding: number;
  /** What share of what a dentist would ask can be answered. */
  answerCoverage: number;
  /** Device History Record completeness — computed, never asserted. */
  dhrCompleteness: number;
  dhrOutstanding: string[];
  applicableCount: number;
  resolvedCount: number;
  sections: SectionScore[];
  unresolvedApplicability: number;
};

export type Ask = {
  factKey: string;
  label: string;
  question: string;
  necessity: Necessity;
  safety: SafetyClass;
  answerWeight: number;
  priority: number;
  section: string;
  helpText?: string | null;
};

export type CasePackEntry = {
  v?: JsonValue;
  d?: string;
  s: 'confirmed' | 'unknown' | 'practice_stated' | 'supplier_stated' | 'imported';
  src?: string;
};

/**
 * The sealed payload an answer may draw from. PHI never enters it, and neither
 * does anything marked lab_only — a leak would require a bug in the builder,
 * not a clever question.
 */
export type CasePack = {
  case_id: string;
  case_number: string;
  practice: string;
  doctor: string;
  built_at: string;
  content_hash: string;
  status: string;
  due_date: string;
  facts: Record<string, CasePackEntry>;
  unknown_keys: string[];
  unknown_reasons: Record<string, UnknownReason>;
  /** What the lab is waiting on, phrased as it would be asked. */
  open_asks: { factKey: string; question: string }[];
  materials: { role: string; brand: string; product: string; lot: string }[];
  timeline: { step: string; at: string; by: string }[];
  is_demo: boolean;
};
