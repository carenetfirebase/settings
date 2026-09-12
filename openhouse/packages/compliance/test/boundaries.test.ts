import test from 'node:test';
import assert from 'node:assert/strict';
import { checkAnswer, checkQuestion } from '../src/index.ts';

const ctx = { agentName: 'Sarah', priceDisplay: '$899,900' };

test('the fair housing questions from the architecture are refused warmly', () => {
  const cases: [string, RegExp][] = [
    ['Is this a safe neighbourhood?', /crime statistics/i],
    ['Are the schools good?', /which schools serve this address/i],
    ['What kind of people live around here?', /not able to describe who lives/i],
  ];
  for (const [question, expected] of cases) {
    const verdict = checkQuestion(question, ctx);
    assert.equal(verdict.allowed, false, question);
    if (verdict.allowed) return;
    assert.match(verdict.template, expected);
    // A refusal that leaves the visitor with nothing damages the agent's brand.
    assert.ok(verdict.template.length > 60);
    assert.ok(!/cannot|refuse|prohibited|policy/i.test(verdict.template),
      'the refusal must not read as a lecture');
  }
});

test('steering questions are caught however they are phrased', () => {
  for (const question of [
    'Is this a good area for families?',
    'Would you say this is a nice part of town?',
    'Is it a family friendly street?',
    'What are the neighbours like?',
    'Is the neighbourhood diverse?',
    'How are the schools rated?',
    'Is this a rough area?',
  ]) {
    assert.equal(checkQuestion(question, ctx).allowed, false, question);
  }
});

test('licensed advice questions get their template and still offer facts', () => {
  const offer = checkQuestion('What should I offer on this place?', ctx);
  assert.equal(offer.allowed, false);
  if (offer.allowed) return;
  assert.match(offer.template, /\$899,900/);
  assert.match(offer.template, /Sarah/);
  assert.ok(offer.offerFactKeys.includes('listing.price.list'));

  const rent = checkQuestion('Can I rent out the basement?', ctx);
  assert.equal(rent.allowed, false);
  if (rent.allowed) return;
  assert.ok(rent.offerFactKeys.includes('basement.suite_status'),
    'the refusal must still surface the verified suite status');

  const crack = checkQuestion('Is this crack serious?', ctx);
  assert.equal(crack.allowed, false);
  if (crack.allowed) return;
  assert.match(crack.template, /inspection/i);
});

test('ordinary property questions pass straight through', () => {
  for (const question of [
    'How old is the furnace?',
    'What are the property taxes?',
    'Is the garage heated?',
    'Which schools serve this address?',
    'How many bedrooms are there?',
    'What stays with the house?',
    'Has the basement ever had water in it?',
  ]) {
    assert.equal(checkQuestion(question, ctx).allowed, true, question);
  }
});

test('the answer post-check catches claims that slipped past generation', () => {
  const blocked = [
    'This is a great deal at this price.',
    'The home will appreciate nicely over the next few years.',
    'You could legally rent the basement out.',
    'The crack is just cosmetic, nothing to worry about.',
    'The renovation was fully permitted and up to code.',
    'It sits in a very safe neighbourhood with excellent schools.',
    'The area is mostly young families.',
  ];
  for (const answer of blocked) {
    assert.equal(checkAnswer(answer).ok, false, answer);
  }
});

test('the answer post-check does not fire on honest factual answers', () => {
  const allowed = [
    'The furnace was installed in 2019.',
    'The basement suite is not legal. The separate entrance is there, but the ' +
      'suite is not registered with the city.',
    'There was water in the basement in June 2021. It was remediated in August ' +
      '2021 and there has been no recurrence.',
    'Maple Ridge Elementary is 0.6 km away and Bow Valley High School is 2.1 km away.',
    'Two permits are on file: basement development in 2019 and the deck in 2021.',
    "I don't have a verified date for the windows. Would you like me to ask Sarah?",
  ];
  for (const answer of allowed) {
    const check = checkAnswer(answer);
    assert.equal(check.ok, true,
      `${answer} → ${check.flags.map((f) => f.rule).join(', ')}`);
  }
});
