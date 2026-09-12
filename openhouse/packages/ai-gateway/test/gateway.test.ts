import test from 'node:test';
import assert from 'node:assert/strict';
import { AiGateway, TemplateCompletionProvider } from '../src/index.ts';
import type { CompletionProvider, GroundedRequest } from '../src/index.ts';

const provider = new TemplateCompletionProvider();

const req = (grounding: GroundedRequest['grounding'], question = 'test'): GroundedRequest =>
  ({ question, grounding, agentName: 'Sarah' });

test('a verified year is phrased as a plain statement', async () => {
  const { text } = await provider.complete(req([{
    kind: 'fact', factKey: 'mechanical.furnace.install_year',
    label: 'Furnace installation year', display: '2019', value: 2019,
    verificationLevel: 'document_verified',
  }]));
  assert.equal(text, 'The furnace was installed in 2019.');
});

test('an unknown is phrased from its reason, not as a shrug', async () => {
  const { text } = await provider.complete(req([{
    kind: 'unknown', factKey: 'exterior.windows.replacement_year',
    label: 'Window replacement year', unknownReason: 'seller_does_not_know',
  }]));
  assert.match(text, /seller doesn't have a record/);
  assert.ok(!/I'm sorry|at this time/.test(text));
});

test('commentary is attributed, never stated as verified fact', async () => {
  const { text } = await provider.complete(req([{
    kind: 'commentary', label: 'Kitchen', text: 'The island seats four.',
    verificationLevel: 'agent_commentary',
  }]));
  assert.match(text, /mentions/);
  assert.ok(!/^The island seats four/.test(text));
});

test('a disclosure leads the answer', async () => {
  const { text } = await provider.complete(req([
    { kind: 'fact', label: 'Basement suite status', display: 'Not legal', value: 'not_legal' },
    { kind: 'disclosure', label: 'Basement water intrusion, 2021',
      text: 'Water entered the basement in June 2021 and was remediated in August 2021.' },
  ]));
  assert.ok(text.startsWith('Water entered'), text);
});

test('empty grounding produces an offer to ask the agent, never an invention', async () => {
  const { text } = await provider.complete(req([]));
  assert.match(text, /don't have verified information/);
  assert.match(text, /Sarah/);
});

test('answers stay inside the voice brevity budget', async () => {
  const { text } = await provider.complete({
    ...req(Array.from({ length: 8 }, (_, i) => ({
      kind: 'fact' as const, label: `Fact ${i}`, display: String(i), value: i,
    }))),
    maxSentences: 3,
  });
  assert.ok(text.split('. ').length <= 3);
});

test('the gateway falls over to the next provider and records why', async () => {
  const broken: CompletionProvider = {
    name: 'broken', model: 'x',
    complete: async () => { throw new Error('provider outage'); },
  };
  const gateway = new AiGateway({ completion: [broken, provider] });
  const result = await gateway.withCompletionFailover((p) => p.complete(req([])));
  assert.equal(result.provider, 'template');
  assert.equal(gateway.failovers.length, 1);
  assert.match(gateway.failovers[0].error, /outage/);
});

test('speech providers are selected by capability, not by name', () => {
  const noBargeIn = {
    name: 'basic',
    createSession: async () => ({ token: 't', expiresAt: '', sessionId: 's', provider: 'basic' }),
    capabilities: () => ({ bargeIn: false, toolCalls: true, maxContextKb: 32 }),
  };
  const full = {
    name: 'realtime',
    createSession: async () => ({ token: 't', expiresAt: '', sessionId: 's', provider: 'realtime' }),
    capabilities: () => ({ bargeIn: true, toolCalls: true, maxContextKb: 128 }),
  };
  const gateway = new AiGateway({ completion: [provider], speech: [noBargeIn, full] });
  assert.equal(gateway.speechWithBargeIn()?.name, 'realtime');
});
