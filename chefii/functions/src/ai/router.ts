import { validate } from '../schemas';
import { AiProvider, AiTask, ProviderError, StructuredRequest, StructuredResponse } from './provider';

export interface UsageEvent {
  task: AiTask;
  provider: string;
  model: string;
  ok: boolean;
  latencyMs: number;
  inputTokens?: number;
  outputTokens?: number;
  errorKind?: 'provider' | 'schema';
}

export interface RouterOptions {
  primary: AiProvider;
  optional?: AiProvider;
  /** The user allowed the optional provider (privacy setting). */
  allowOptional: boolean;
  onUsage?: (e: UsageEvent) => void | Promise<void>;
}

/**
 * Picks a provider per task (never calls both "just because"):
 *  - images (receipt, scan, meal photo) → primary (Gemini) only
 *  - conversation/recipes → optional (OpenAI) when enabled AND allowed by the
 *    user, falling back to primary on a retryable failure or invalid output.
 * Output must pass schema validation or the next provider is tried; if none
 * succeeds, the caller receives a ProviderError (never a fabricated result).
 */
export class AiRouter {
  constructor(private readonly opts: RouterOptions) {}

  chain(task: AiTask, hasImages: boolean): AiProvider[] {
    const { primary, optional, allowOptional } = this.opts;
    const conversational = task === 'chat' || task === 'chef_recipes';
    if (!hasImages && conversational && optional && allowOptional) return [optional, primary];
    return [primary];
  }

  async run<T>(req: StructuredRequest): Promise<{ data: T; response: StructuredResponse }> {
    const providers = this.chain(req.task, !!req.images?.length);
    let lastError: unknown;
    for (const p of providers) {
      const started = Date.now();
      try {
        const response = await p.generate(req);
        const data = validate<T>(req.schema, response.json);
        await this.opts.onUsage?.({ task: req.task, provider: p.name, model: response.model, ok: true, latencyMs: Date.now() - started, inputTokens: response.inputTokens, outputTokens: response.outputTokens });
        return { data, response };
      } catch (e) {
        lastError = e;
        const isSchema = !(e instanceof ProviderError);
        await this.opts.onUsage?.({ task: req.task, provider: p.name, model: 'unknown', ok: false, latencyMs: Date.now() - started, errorKind: isSchema ? 'schema' : 'provider' });
        if (e instanceof ProviderError && !e.retryable) break;
      }
    }
    if (lastError instanceof ProviderError) throw lastError;
    throw new ProviderError('The assistant returned an unusable answer', true, 'router');
  }
}
