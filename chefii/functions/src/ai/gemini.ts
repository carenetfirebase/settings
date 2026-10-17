import { GoogleGenAI } from '@google/genai';
import { AiProvider, parseJsonText, ProviderError, StructuredRequest, StructuredResponse } from './provider';

/** Primary provider: receipts, fridge scans, normalisation, and fallback chef. */
export class GeminiProvider implements AiProvider {
  readonly name = 'gemini' as const;
  readonly supportsImages = true;
  private readonly client: GoogleGenAI;

  constructor(apiKey: string, private readonly textModel: string, private readonly visionModel: string) {
    this.client = new GoogleGenAI({ apiKey });
  }

  async generate(req: StructuredRequest): Promise<StructuredResponse> {
    const model = req.images?.length ? this.visionModel : this.textModel;
    const contents = req.messages.map((m, i) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [
        ...(i === req.messages.length - 1 ? (req.images ?? []).map((img) => ({ inlineData: { mimeType: img.mimeType, data: img.base64 } })) : []),
        { text: m.text },
      ],
    }));
    try {
      const res = await this.client.models.generateContent({
        model,
        contents,
        config: {
          systemInstruction: req.system,
          responseMimeType: 'application/json',
          responseJsonSchema: req.schema,
          temperature: req.temperature ?? 0.2,
        },
      });
      const text = res.text;
      if (!text) throw new ProviderError('Empty response', true, this.name);
      return {
        json: parseJsonText(text, this.name),
        provider: this.name,
        model,
        inputTokens: res.usageMetadata?.promptTokenCount,
        outputTokens: res.usageMetadata?.candidatesTokenCount,
      };
    } catch (e) {
      if (e instanceof ProviderError) throw e;
      const status = (e as { status?: number }).status;
      throw new ProviderError(`Gemini request failed${status ? ` (${status})` : ''}`, status === undefined || status === 429 || status >= 500, this.name);
    }
  }
}
