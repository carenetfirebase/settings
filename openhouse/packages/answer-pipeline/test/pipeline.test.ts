import test from 'node:test';
import assert from 'node:assert/strict';
import { buildDemoProperty, DEMO_PROPERTY_ID }
  from '../../../fixtures/demo-property/maple-crescent.ts';
import { createTruthEngine } from '../../truth-engine/src/engine.ts';
import { createAnswerPipeline } from '../src/pipeline.ts';
import { emptyFrame } from '../src/frame.ts';

function pipeline() {
  const store = buildDemoProperty();
  const engine = createTruthEngine(store);
  const property = store.getProperty(DEMO_PROPERTY_ID)!;
  const answer = createAnswerPipeline({
    engine,
    property,
    commentary: () => store.getCommentary(DEMO_PROPERTY_ID),
    disclosures: () => store.getDisclosures(DEMO_PROPERTY_ID),
  });
  return { store, engine, answer };
}

const ask = async (question: string, extra: Record<string, unknown> = {}) => {
  const { answer } = pipeline();
  return answer({ propertyId: DEMO_PROPERTY_ID, sessionId: 'session-1', question, ...extra });
};

test('a verified fact is answered from the structured path', async () => {
  const result = await ask('How old is the furnace?');
  assert.equal(result.retrievalPath, 'structured');
  assert.match(result.answer, /2019/);
  assert.deepEqual(result.resolvedFactKeys, ['mechanical.furnace.install_year']);
  assert.equal(result.blocked, false);
  assert.deepEqual(result.validatorFlags, []);
});

test('the ledger records the fact version used for the answer', async () => {
  const result = await ask('How old is the furnace?');
  assert.equal(result.ledgerEntry.factVersions['mechanical.furnace.install_year'], 2);
  assert.equal(result.ledgerEntry.provider, 'template');
  assert.ok(result.ledgerEntry.latencyMs >= 0);
});

test('a fact marked unknown is answered with candour, shaped by its reason', async () => {
  const result = await ask('How old are the windows?');
  assert.equal(result.retrievalPath, 'unknown');
  assert.match(result.answer, /seller doesn't have a record/i);
  assert.ok(!/\b(19|20)\d\d\b/.test(result.answer), 'no invented year');
});

test('a fact nobody has entered is never invented', async () => {
  const result = await ask('What is the fence made of?');
  assert.equal(result.blocked, false);
  assert.match(result.answer, /don't have verified information|doesn't have a record|still confirming/i);
});

test('the dishwasher exchange from the architecture works turn by turn', async () => {
  const { answer } = pipeline();
  const session = { propertyId: DEMO_PROPERTY_ID, sessionId: 'session-2' };

  const fridge = await answer({ ...session, question: 'How old is the fridge?', frame: emptyFrame() });
  assert.match(fridge.answer, /2023/);
  assert.equal(fridge.frame.topic, 'install_year');
  assert.equal(fridge.frame.room, 'kitchen');

  const dishwasher = await answer({
    ...session, question: 'What about the dishwasher?', frame: fridge.frame,
  });
  assert.equal(dishwasher.resolvedFactKeys[0], 'kitchen.appliance.dishwasher.install_year');
  assert.match(dishwasher.answer, /seller doesn't have a record/i);
  assert.ok(!/2023/.test(dishwasher.answer), 'the fridge answer must not bleed through');

  const furnace = await answer({
    ...session, question: "How old's the furnace?", frame: dishwasher.frame,
  });
  assert.match(furnace.answer, /2019/);
  assert.equal(furnace.frame.room, null, 'mechanical facts are not room scoped');
});

test('the most-asked question is answered honestly', async () => {
  const result = await ask('Is the basement suite legal?');
  assert.match(result.answer, /not legal/i);
  assert.equal(result.blocked, false);
});

test('asking about the basement surfaces the disclosure, unprompted and unsoftened', async () => {
  const result = await ask('Has the basement ever had water in it?');
  assert.match(result.answer, /June 2021|water entered/i);
  assert.match(result.answer, /remediat|repair|no recurrence/i);
});

test('a steering question is refused before any retrieval happens', async () => {
  const result = await ask('Is this a safe neighbourhood?');
  assert.equal(result.retrievalPath, 'boundary_refusal');
  assert.match(result.answer, /crime statistics/i);
  assert.equal(result.blocked, false);
});

test('a school question offers the catchment and declines the judgment', async () => {
  const result = await ask('Are the schools any good around here?');
  assert.equal(result.retrievalPath, 'boundary_refusal');
  assert.match(result.answer, /Maple Ridge Elementary/);
  assert.match(result.answer, /evaluate those yourself/i);
});

test('an advice question gives the fact and hands off the judgment', async () => {
  const offer = await ask('What should I offer?');
  assert.match(offer.answer, /\$899,900/);
  assert.match(offer.answer, /Sarah/);

  const rent = await ask('Can I rent out the basement?');
  assert.match(rent.answer, /municipal permitting/i);
  assert.match(rent.answer, /Not legal/i, 'the verified suite status still comes through');
});

test('an ambiguous question asks for context instead of guessing', async () => {
  const result = await ask("What's behind this door?");
  assert.match(result.answer, /which one you're looking at/i);
  assert.equal(result.retrievalPath, 'unknown');
});

test('requests to reach the agent are routed, not answered', async () => {
  const result = await ask('Can you ask the agent about the roof warranty?');
  assert.match(result.answer, /pass that to Sarah/i);
});

test('every answer stays inside the voice latency budget', async () => {
  const { answer } = pipeline();
  const questions = [
    'How old is the furnace?', 'What are the taxes?', 'Is the garage heated?',
    'Is this a safe neighbourhood?', 'How old are the windows?',
  ];
  for (const question of questions) {
    const result = await answer({
      propertyId: DEMO_PROPERTY_ID, sessionId: 'session-3', question,
    });
    assert.ok(result.latencyMs < 50, `${question} took ${result.latencyMs}ms`);
  }
});
