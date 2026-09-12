/**
 * The AI Gateway (§1.2).
 *
 * The only place provider SDKs are allowed to appear. Everything upstream —
 * the answer pipeline, the ingestion jobs, the voice session — speaks these
 * interfaces, so swapping a realtime voice vendor is a config change plus a
 * capability check rather than a refactor. Assume we switch at least once in
 * the first year.
 */
import type { FactDefinition, JsonValue } from '../../fact-catalog/src/index.ts';

export type EphemeralCredential = {
  /** Short-lived and exchanged immediately; the provider key never reaches the client. */
  token: string;
  expiresAt: string;
  sessionId: string;
  provider: string;
};

export type RealtimeSessionConfig = {
  propertyId: string;
  sessionId: string;
  instructions: string;
  /** The sealed fact pack. The model may not state a property fact outside it. */
  factPack: unknown;
  voice?: string;
  tools: ToolDefinition[];
};

export type ToolDefinition = {
  name: string;
  description: string;
  parameters: Record<string, JsonValue>;
};

export type ProviderCapabilities = {
  bargeIn: boolean;
  toolCalls: boolean;
  maxContextKb: number;
};

export type SpeechProvider = {
  readonly name: string;
  createSession(cfg: RealtimeSessionConfig): Promise<EphemeralCredential>;
  capabilities(): ProviderCapabilities;
};

export type DocumentPage = {
  documentId: string;
  pageNumber: number;
  text: string;
  layout?: unknown;
};

export type ExtractedClaim = {
  factKey: string;
  valueRaw: string;
  page: number;
  bbox?: { x: number; y: number; w: number; h: number } | null;
  snippet: string;
  confidence: number;
};

export type ExtractionProvider = {
  readonly name: string;
  /**
   * Scoped to the applicable subset of the catalog for this document type —
   * a furnace invoice sees ~15 keys, not 300 (§8.1). The scoping roughly
   * doubles precision and cuts cost by an order of magnitude.
   */
  extractFacts(pages: DocumentPage[], catalog: FactDefinition[]): Promise<ExtractedClaim[]>;
};

export type GroundingKind =
  | 'fact' | 'unknown' | 'commentary' | 'document' | 'public' | 'disclosure';

export type GroundingItem = {
  kind: GroundingKind;
  factKey?: string;
  label: string;
  /** Human-readable value: "2019", "$4,620", "Not legal". */
  display?: string;
  value?: JsonValue;
  verificationLevel?: string | null;
  unknownReason?: string | null;
  text?: string;
  sourceRef?: string | null;
};

export type GroundedRequest = {
  question: string;
  /** Conversation frame (§11.3): room and topic carried between turns. */
  frame?: { room?: string | null; topic?: string | null };
  grounding: GroundingItem[];
  agentName?: string | null;
  /** Hard cap; a voice answer that runs long breaks the conversational illusion. */
  maxSentences?: number;
};

export type GroundedResponse = {
  text: string;
  provider: string;
  model: string;
  latencyMs: number;
};

export type CompletionProvider = {
  readonly name: string;
  readonly model: string;
  /**
   * Phrase, do not decide. The grounding payload is the entire permitted
   * universe of property-specific claims; anything outside it is a bug the
   * validator (§11.6) is there to catch.
   */
  complete(req: GroundedRequest): Promise<GroundedResponse>;
};

export type EmbeddingProvider = {
  readonly name: string;
  readonly dimensions: number;
  embed(texts: string[]): Promise<number[][]>;
};

export type Identification = { label: string; confidence: number };

export type VisionProvider = {
  readonly name: string;
  /**
   * Reserved (§11.5). Vision may propose an object identity; it may never
   * confirm a condition. No structural, electrical, plumbing or inspection
   * diagnosis, ever.
   */
  identify(image: Uint8Array, ctx: { propertyId: string; roomId?: string })
    : Promise<{ candidates: Identification[]; caveats: string[] }>;
};
