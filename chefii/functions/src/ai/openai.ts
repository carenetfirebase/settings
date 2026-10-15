import OpenAI from 'openai';
import { AiProvider, parseJsonText, ProviderError, StructuredRequest, StructuredResponse } from './provider';

/** Optional specialised provider: conversation and recipe writing. */
export class OpenAiProvider implements AiProvider {
  readonly name = 'openai' as const;
  readonly supportsImages = false; // images stay with the primary provider by design
  private readonly client: OpenAI;

  constructor(apiKey: string, private readonly model: string) {
    this.client = new OpenAI({ apiKey });
  }

  async generate(req: StructuredRequest): Promise<StructuredResponse> {
    if (req.images?.length) throw new ProviderError('Images are routed to the primary provider', false, this.name);
    try {
      const res = await this.client.responses.create({
        model: this.model,
        instructions: req.system,
        input: req.messages.map((m) => ({ role: m.role, content: m.text })),
        text: { format: { type: 'json_schema', name: req.schemaName, schema: req.schema, strict: true } },
        store: false, // do not retain conversations on the provider side
      });
      if (!res.output_text) throw new ProviderError('Empty response', true, this.name);
      return {
        json: parseJsonText(res.output_text, this.name),
        provider: this.name,
        model: this.model,
        inputTokens: res.usage?.input_tokens,
        outputTokens: res.usage?.output_tokens,
      };
    } catch (e) {
      if (e instanceof ProviderError) throw e;
      const status = (e as { status?: number }).status;
      throw new ProviderError(`OpenAI request failed${status ? ` (${status})` : ''}`, status === undefined || status === 429 || status >= 500, this.name);
    }
  }
}
