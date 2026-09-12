import test from 'node:test';
import assert from 'node:assert/strict';
import { validateAnswer } from '../src/validator.ts';
import type { GroundingItem } from '../../ai-gateway/src/index.ts';

const furnace: GroundingItem = {
  kind: 'fact', factKey: 'mechanical.furnace.install_year',
  label: 'Furnace installation year', display: '2019', value: 2019,
  verificationLevel: 'document_verified',
};
const taxes: GroundingItem = {
  kind: 'fact', factKey: 'taxes.annual_amount', label: 'Annual property tax',
  display: '$4,620', value: 4620, verificationLevel: 'document_verified',
};
const area: GroundingItem = {
  kind: 'fact', factKey: 'property.living_area', label: 'Living area above grade',
  display: '2140 sqft', value: 2140, verificationLevel: 'document_verified',
};

test('a number in the payload passes', () => {
  const result = validateAnswer('The furnace was installed in 2019.', [furnace]);
  assert.equal(result.ok, true);
});

test('a number that is not in the payload blocks the answer', () => {
  const result = validateAnswer('The furnace was installed in 2015.', [furnace]);
  assert.equal(result.ok, false);
  assert.equal(result.flags[0].rule, 'numeric_token');
  assert.equal(result.flags[0].token, '2015');
});

test('a plausible-sounding invention is still an invention', () => {
  // The kind of sentence a realtime model produces when it drifts: correct
  // shape, correct tone, one number nobody ever verified.
  const result = validateAnswer(
    'The furnace was installed in 2019 and has a 12 year warranty remaining.',
    [furnace]);
  assert.equal(result.ok, false);
  assert.equal(result.flags[0].token, '12');
});

test('trivially derived values are allowed, with the derivation logged', () => {
  const thisYear = new Date().getUTCFullYear();
  const age = thisYear - 2019;
  const result = validateAnswer(`The furnace is about ${age} years old.`, [furnace]);
  assert.equal(result.ok, true);
  assert.match(result.derivations[0], /age in years/);

  const monthly = validateAnswer('That works out to about $385 a month.', [taxes]);
  assert.equal(monthly.ok, true);
  assert.match(monthly.derivations[0], /annual → monthly/);
});

test('a sum across grounded values is allowed', () => {
  const gas: GroundingItem = { kind: 'fact', label: 'Gas', display: '$1,180', value: 1180 };
  const power: GroundingItem = { kind: 'fact', label: 'Power', display: '$1,460', value: 1460 };
  const water: GroundingItem = { kind: 'fact', label: 'Water', display: '$960', value: 960 };
  const result = validateAnswer(
    'Gas, power and water came to $3,600 over the year.', [gas, power, water]);
  assert.equal(result.ok, true);
  assert.match(result.derivations[0], /1180 \+ 1460 \+ 960/);
});

test('unit conversions are allowed', () => {
  const result = validateAnswer('That is about 199 square metres.', [area]);
  assert.equal(result.ok, true);
  assert.match(result.derivations[0], /sq ft → m²/);
});

test('small counts in prose do not trip the checker', () => {
  const result = validateAnswer('There are 2 sources on file for that.', [furnace]);
  assert.equal(result.ok, true);
});

test('prohibited claim patterns are caught even with clean numbers', () => {
  const result = validateAnswer(
    'The furnace was installed in 2019, so the house is in great shape.', [furnace]);
  assert.equal(result.ok, false);
  assert.ok(result.flags.some((f) => f.rule === 'prohibited_claim'));
});

test('fair housing language in an answer is caught', () => {
  const result = validateAnswer(
    'The taxes are $4,620 and it is a very safe neighbourhood.', [taxes]);
  assert.equal(result.ok, false);
  assert.ok(result.flags.some((f) => f.rule === 'fair_housing'));
});

test('commentary stated as verified fact fails calibration', () => {
  const commentary: GroundingItem = {
    kind: 'commentary', label: 'Kitchen', text: 'The pantry is deeper than it looks.',
    verificationLevel: 'agent_commentary',
  };
  assert.equal(validateAnswer('The pantry is deeper than it looks.', [commentary]).ok, false);
  assert.equal(
    validateAnswer('Sarah mentions the pantry is deeper than it looks.', [commentary]).ok,
    true);
});

test('an answer with no grounding may still say it knows nothing', () => {
  const result = validateAnswer(
    "I don't have verified information about that. Would you like me to ask Sarah?", []);
  assert.equal(result.ok, true);
});

test('numbers formatted differently still match the payload', () => {
  assert.equal(validateAnswer('The taxes are $4,620 a year.', [taxes]).ok, true);
  assert.equal(validateAnswer('The taxes are 4620 a year.', [taxes]).ok, true);
  assert.equal(validateAnswer('The home is 2,140 square feet.', [area]).ok, true);
});
