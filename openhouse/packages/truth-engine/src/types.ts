import type {
  ApplicabilityContext, FactDataType, FactDefinition, FactVisibility, JsonValue,
} from '../../fact-catalog/src/index.ts';

export type ClaimSourceType =
  | 'agent_input' | 'document' | 'mls' | 'seller_disclosure'
  | 'public_data' | 'ai_extraction';

export type ClaimStatus = 'pending' | 'accepted' | 'rejected' | 'superseded';

export type FactStatus =
  | 'verified' | 'unknown' | 'not_applicable' | 'pending_review' | 'conflicted';

export type VerificationLevel =
  | 'agent_confirmed' | 'document_verified' | 'seller_provided'
  | 'agent_commentary' | 'public_source';

export type UnknownReason =
  | 'seller_does_not_know' | 'no_documentation' | 'not_applicable' | 'will_follow_up';

export type FactClaim = {
  id: string;
  propertyId: string;
  factKey: string;
  roomId?: string | null;
  valueRaw?: string | null;
  valueNormalized?: JsonValue;
  sourceType: ClaimSourceType;
  sourceDocumentId?: string | null;
  sourcePage?: number | null;
  sourceSnippet?: string | null;
  extractionConfidence?: number | null;
  assertedBy?: string | null;
  assertedAt: string;
  status: ClaimStatus;
};

export type PropertyFact = {
  propertyId: string;
  factKey: string;
  roomId?: string | null;
  valueNormalized?: JsonValue;
  valueDisplay?: string | null;
  status: FactStatus;
  verificationLevel?: VerificationLevel | null;
  unknownReason?: UnknownReason | null;
  winningClaimId?: string | null;
  confirmedBy?: string | null;
  confirmedAt?: string | null;
  visibility: FactVisibility;
  version: number;
  notes?: string | null;
};

export type Room = {
  id: string;
  key: string;
  name: string;
  sortOrder: number;
  dimensions?: { width: number; length: number; unit: string } | null;
  adjacency: string[];
  description?: string | null;
};

export type Commentary = {
  id: string;
  scope: 'property' | 'room' | 'feature';
  roomId?: string | null;
  topic?: string | null;
  author: 'agent' | 'seller';
  text: string;
  visibility: FactVisibility;
  approved: boolean;
};

export type Inclusion = {
  kind: 'included' | 'excluded' | 'negotiable';
  item: string;
  detail?: string | null;
};

export type Disclosure = {
  id: string;
  factKey?: string | null;
  title: string;
  detail: string;
  occurredOn?: string | null;
  remediated: boolean;
  remediationDetail?: string | null;
  reviewed: boolean;
};

export type Property = {
  id: string;
  slug: string;
  status: 'draft' | 'published' | 'unpublished' | 'archived';
  addressLine1: string;
  city: string;
  province: string;
  postalCode?: string | null;
  propertyType: string;
  listPrice?: number | null;
  bedrooms?: number | null;
  bathrooms?: number | null;
  livingAreaSqft?: number | null;
  yearBuilt?: number | null;
  applicability: ApplicabilityContext;
  agentName?: string | null;
  isDemo?: boolean;
};

/** What the Truth Engine needs from storage. Postgres behind it in production. */
export type TruthStore = {
  getProperty(propertyId: string): Property | undefined;
  getRooms(propertyId: string): Room[];
  getClaims(propertyId: string): FactClaim[];
  getFacts(propertyId: string): PropertyFact[];
  getCommentary(propertyId: string): Commentary[];
  getInclusions(propertyId: string): Inclusion[];
  getDisclosures(propertyId: string): Disclosure[];
};

export type ResolvedFact = {
  factKey: string;
  roomId?: string | null;
  definition: FactDefinition;
  status: FactStatus;
  value?: JsonValue;
  display?: string | null;
  verificationLevel?: VerificationLevel | null;
  unknownReason?: UnknownReason | null;
  visibility: FactVisibility;
  version: number;
  /** Where the winning claim came from, for "Verify It". */
  source?: {
    claimId: string;
    sourceType: ClaimSourceType;
    documentId?: string | null;
    page?: number | null;
    snippet?: string | null;
  } | null;
};

export type ConflictingClaim = {
  claimId: string;
  value: JsonValue | undefined;
  display: string;
  sourceType: ClaimSourceType;
  documentId?: string | null;
  page?: number | null;
  snippet?: string | null;
};

export type Conflict = {
  factKey: string;
  roomId?: string | null;
  label: string;
  dataType: FactDataType;
  severity: 'soft' | 'hard';
  coverageWeight: number;
  blocksPublish: boolean;
  claims: ConflictingClaim[];
};

export type SectionScore = {
  section: string;
  label: string;
  applicableWeight: number;
  reviewedWeight: number;
  answerableWeight: number;
  preparation: number;
  answerCoverage: number;
};

export type CoverageScore = {
  applicableCount: number;
  reviewedCount: number;
  answerableCount: number;
  preparation: number;
  answerCoverage: number;
  sections: SectionScore[];
  /** Facts blocked on an unanswered setup question, excluded from both ratios. */
  unresolvedApplicability: number;
  missingSetupFields: { field: string; unlocks: number; weight: number }[];
};

export type Gap = {
  factKey: string;
  label: string;
  section: string;
  /** The question a visitor would actually ask — gap filling is question-shaped. */
  question: string;
  coverageWeight: number;
  questionFrequency: number;
  priority: number;
  status: FactStatus | 'unreviewed';
  helpText?: string | null;
};

export type FactPackEntry = {
  v?: JsonValue;
  d?: string;
  s: 'verified' | 'unknown' | 'seller_provided' | 'agent_commentary' | 'public';
  src?: string;
};

export type FactPack = {
  property_id: string;
  snapshot_hash: string;
  built_at: string;
  address: string;
  price?: { v: number; s: string } | null;
  headline: Record<string, JsonValue>;
  facts: Record<string, FactPackEntry>;
  rooms: {
    id: string; key: string; name: string; adjacency: string[];
    facts: Record<string, FactPackEntry>;
  }[];
  commentary: { scope: string; room?: string | null; by: string; text: string }[];
  inclusions: { included: string[]; excluded: string[]; negotiable: string[] };
  disclosures: {
    title: string; detail: string; occurred_on?: string | null;
    remediated: boolean; remediation_detail?: string | null;
  }[];
  /**
   * Confirmed-unknown keys, stated explicitly. Telling the model what it does
   * not know measurably reduces confabulation compared with omission (§7.5).
   */
  unknown_keys: string[];
  unknown_reasons: Record<string, UnknownReason>;
  is_demo: boolean;
};
