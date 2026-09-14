import test from 'node:test';
import assert from 'node:assert/strict';
import { DEMO_PRACTICE_ID, LAB_NAME, buildDemoLab } from '../../../fixtures/demo-lab.ts';
import { createTruthEngine } from '../../truth-engine/src/engine.ts';
import { createAnswerPipeline } from '../src/pipeline.ts';
import type { Requester } from '../src/pipeline.ts';

const OKAFOR: Requester =
  { kind: 'practice', practiceId: DEMO_PRACTICE_ID, name: 'Dr. Okafor' };
const HALE: Requester =
  { kind: 'practice', practiceId: 'practice-hale', name: 'Dr. Hale' };
const VOSS: Requester =
  { kind: 'practice', practiceId: 'practice-voss', name: 'Dr. Voss' };
const BENCH: Requester = { kind: 'lab', userId: 'u1', name: 'Priya R.' };

function harness() {
  const store = buildDemoLab();
  const answer = createAnswerPipeline({
    engine: createTruthEngine(store), store, labName: LAB_NAME, technicianName: 'Priya',
  });
  const ask = (caseId: string, question: string, requester: Requester = OKAFOR) =>
    answer({ caseId, question, requester, sessionId: 'test' });
  return { store, ask };
}

test('“where is my case” gets a real answer, not a field read-out', async () => {
  const { ask } = harness();
  const shipped = await ask('case-24411', 'Where is my case?', HALE);
  assert.equal(shipped.retrievalPath, 'status');
  assert.match(shipped.answer, /24411/);
  assert.match(shipped.answer, /772819930041/);
  assert.match(shipped.answer, /FedEx/);
  assert.equal(shipped.blocked, false);
});

test('a held case says what it is waiting on, unprompted', async () => {
  const { ask } = harness();
  const held = await ask('case-24423', 'Where is my case?');
  assert.match(held.answer, /waiting on you/i);
  assert.match(held.answer, /stump shade/i);
});

test('a delay states its reason rather than going quiet', async () => {
  const { ask } = harness();
  const delayed = await ask('case-24411', 'Why is it late?', HALE);
  assert.match(delayed.answer, /furnace fault/i);
});

test('a lot number comes back exactly, with its expiry', async () => {
  const { ask } = harness();
  const lot = await ask('case-24401', 'Which lot went into this case?', HALE);
  assert.match(lot.answer, /ZR-24-0881/);
  assert.equal(lot.blocked, false);
  assert.deepEqual(lot.validatorFlags, []);
});

test('a torque value is stated as the specification, exactly', async () => {
  const { ask } = harness();
  const torque = await ask('case-24430', 'What torque do I use?', VOSS);
  assert.match(torque.answer, /35 Ncm/);
  assert.match(torque.answer, /SCS-BLX-01/);
});

test('a missing value is an honest unknown, never a plausible guess', async () => {
  const { ask } = harness();
  const stump = await ask('case-24423', 'What is the stump shade?');
  assert.equal(stump.retrievalPath, 'unknown');
  assert.match(stump.answer, /hasn't come through from your office/i);
  assert.ok(!/\b[ABCD][1-4]\b/.test(stump.answer), 'no invented shade');
});

test('a remake answer gives the cause, the evidence and who pays', async () => {
  const { ask } = harness();
  const why = await ask('case-24390', 'Why was it remade?', HALE);
  assert.match(why.answer, /clinical margin/i);
  assert.match(why.answer, /obscured/i);

  const who = await ask('case-24390', 'Who pays for the remake?', HALE);
  assert.match(who.answer, /shared/i);
});

test('a clinical question is declined before any retrieval, with facts still offered', async () => {
  const { ask } = harness();
  const clinical = await ask('case-24418', 'Should I do a crown or an onlay?');
  assert.equal(clinical.retrievalPath, 'boundary_refusal');
  assert.match(clinical.answer, /treatment decision/i);
  assert.match(clinical.answer, /Crown/);
});

test('a request to deviate from the prescription is refused and escalated to a person', async () => {
  const { ask } = harness();
  const swap = await ask('case-24418', 'Just use e.max instead, go ahead.');
  assert.equal(swap.escalated, true);
  assert.match(swap.answer, /written authorisation/i);
});

test('patient identifiers are never returned, to anyone', async () => {
  const { ask } = harness();
  for (const requester of [OKAFOR, BENCH]) {
    const phi = await ask('case-24418', "What's the patient's name?", requester);
    assert.equal(phi.retrievalPath, 'boundary_refusal');
    assert.ok(!/M\.D\./.test(phi.answer));
  }
});

test('a practice cannot reach another practice’s case, and cannot tell it exists', async () => {
  const { ask } = harness();
  const foreign = await ask('case-24401', 'What shade did you use?', OKAFOR);
  const missing = await ask('case-99999', 'What shade did you use?', OKAFOR);
  assert.equal(foreign.answer, missing.answer,
    'the refusal must not distinguish a real case from a made-up one');
  assert.equal(foreign.resolvedFactKeys.length, 0);
});

test('the ledger records the fact versions behind every answer', async () => {
  const { ask } = harness();
  const result = await ask('case-24430', 'What torque do I use?', VOSS);
  assert.ok(result.ledgerEntry.factVersions['implant.torque_spec'] >= 1);
  assert.equal(result.ledgerEntry.askedBy, 'Dr. Voss');
  assert.ok(result.ledgerEntry.at);
});

test('every answer stays inside a conversational latency budget', async () => {
  const { ask } = harness();
  for (const question of [
    'Where is my case?', 'What shade did you use?', 'Which lot was it?',
    'Should I prep deeper?', "What's the patient's name?",
  ]) {
    const result = await ask('case-24418', question);
    assert.ok(result.latencyMs < 50, `${question} took ${result.latencyMs}ms`);
  }
});
