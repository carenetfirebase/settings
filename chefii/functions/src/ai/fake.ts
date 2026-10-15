import { AiProvider, ProviderError, StructuredRequest, StructuredResponse } from './provider';

/** Deterministic provider for tests and the emulator (no network). */
export class FakeProvider implements AiProvider {
  readonly name = 'fake' as const;
  readonly supportsImages = true;
  calls: StructuredRequest[] = [];

  constructor(private readonly respond: (req: StructuredRequest) => unknown | Error) {}

  async generate(req: StructuredRequest): Promise<StructuredResponse> {
    this.calls.push(req);
    const out = this.respond(req);
    if (out instanceof Error) throw out instanceof ProviderError ? out : new ProviderError(out.message, true, this.name);
    return { json: out, provider: 'fake', model: 'fake-1' };
  }
}
