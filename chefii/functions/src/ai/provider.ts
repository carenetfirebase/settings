/** Provider-neutral contract for structured generation. */
export type AiTask = 'receipt' | 'scan' | 'chef_recipes' | 'chat' | 'meal_estimate';

export interface ImagePart {
  mimeType: string;
  base64: string;
}

export interface StructuredRequest {
  task: AiTask;
  system: string;
  /** Conversation turns; the last is the current user message. */
  messages: Array<{ role: 'user' | 'assistant'; text: string }>;
  images?: ImagePart[];
  schema: Record<string, unknown>;
  schemaName: string;
  /** Lower for extraction, higher for creative recipes. */
  temperature?: number;
}

export interface StructuredResponse {
  json: unknown;
  provider: 'gemini' | 'openai' | 'fake';
  model: string;
  inputTokens?: number;
  outputTokens?: number;
}

export class ProviderError extends Error {
  constructor(message: string, public readonly retryable: boolean, public readonly provider: string) {
    super(message);
  }
}

export interface AiProvider {
  readonly name: 'gemini' | 'openai' | 'fake';
  readonly supportsImages: boolean;
  generate(req: StructuredRequest): Promise<StructuredResponse>;
}

export function parseJsonText(text: string, provider: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    throw new ProviderError('Model returned malformed JSON', true, provider);
  }
}
