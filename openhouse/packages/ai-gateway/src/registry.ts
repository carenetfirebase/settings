import type {
  CompletionProvider, EmbeddingProvider, ExtractionProvider, SpeechProvider,
} from './interfaces.ts';

export type GatewayConfig = {
  speech?: SpeechProvider[];
  completion: CompletionProvider[];
  extraction?: ExtractionProvider[];
  embedding?: EmbeddingProvider[];
};

export type FailoverEvent = {
  provider: string;
  error: string;
  at: string;
};

/**
 * Provider selection and failover.
 *
 * Ordered lists, tried in order. The interesting property is that failover is
 * observable: every fall-through is recorded, because a provider that quietly
 * degrades is worse than one that fails loudly.
 */
export class AiGateway {
  private readonly config: GatewayConfig;
  readonly failovers: FailoverEvent[] = [];

  constructor(config: GatewayConfig) {
    if (config.completion.length === 0) {
      throw new Error('AiGateway needs at least one completion provider');
    }
    this.config = config;
  }

  completion(): CompletionProvider { return this.config.completion[0]; }

  speech(): SpeechProvider | undefined { return this.config.speech?.[0]; }

  /** Capability gate: never hand a session to a provider that cannot barge in. */
  speechWithBargeIn(): SpeechProvider | undefined {
    return this.config.speech?.find((p) => p.capabilities().bargeIn);
  }

  async withCompletionFailover<T>(
    run: (provider: CompletionProvider) => Promise<T>,
  ): Promise<T> {
    let lastError: unknown;
    for (const provider of this.config.completion) {
      try {
        return await run(provider);
      } catch (error) {
        lastError = error;
        this.failovers.push({
          provider: provider.name,
          error: error instanceof Error ? error.message : String(error),
          at: new Date().toISOString(),
        });
      }
    }
    throw lastError instanceof Error
      ? lastError
      : new Error('every completion provider failed');
  }
}
