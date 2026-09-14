import test from 'node:test';
import assert from 'node:assert/strict';
import { validateAnswer } from '../src/validator.ts';
import type { GroundingItem } from '../src/validator.ts';

const lot: GroundingItem = {
  kind: 'fact', factKey: 'material.primary_lot', label: 'Primary material lot',
  display: 'ZR-24-0881', value: 'ZR-24-0881', confirmationLevel: 'lab_confirmed',
};
const tooth: GroundingItem = {
  kind: 'fact', factKey: 'rx.tooth_numbers', label: 'Tooth number(s)',
  display: '#19', value: [36], confirmationLevel: 'document_verified',
};
const shade: GroundingItem = {
  kind: 'fact', factKey: 'rx.shade_body', label: 'Body shade',
  display: 'A2', value: 'A2', confirmationLevel: 'lab_confirmed',
};
const clearance: GroundingItem = {
  kind: 'fact', factKey: 'design.occlusal_clearance', label: 'Occlusal clearance',
  display: '1.4 mm', value: 1.4, confirmationLevel: 'lab_confirmed',
};

test('values that are on the case pass', () => {
  assert.equal(validateAnswer('Lot ZR-24-0881 was used on #19 in A2.',
    [lot, tooth, shade]).ok, true);
});

test('a lot number that is one character off is refused', () => {
  const result = validateAnswer('We used lot ZR-24-0882.', [lot]);
  assert.equal(result.ok, false);
  assert.equal(result.flags[0].rule, 'identifier_token');
  assert.equal(result.flags[0].token, 'ZR-24-0882');
});

test('the wrong tooth is caught even when everything else is right', () => {
  const result = validateAnswer('The crown for #20 was milled from lot ZR-24-0881.',
    [lot, tooth]);
  assert.equal(result.ok, false);
  assert.ok(result.flags.some((f) => f.token === '#20'));
});

test('an invented shade is caught', () => {
  const result = validateAnswer('The body shade is A3.', [shade]);
  assert.equal(result.ok, false);
  assert.ok(result.flags.some((f) => f.rule === 'identifier_token'));
});

test('a plausible sentence with one invented number is still an invention', () => {
  const result = validateAnswer(
    'We measured 1.4 mm of clearance, and the material needs 1.5 mm.', [clearance]);
  assert.equal(result.ok, false);
  assert.ok(result.flags.some((f) => f.token === '1.5'));
});

test('unit conversion is allowed and the working is logged', () => {
  const result = validateAnswer('That is 1400 µm of clearance.', [clearance]);
  assert.equal(result.ok, true);
  assert.match(result.derivations[0], /mm → µm/);
});

test('an unverified value must be attributed, not stated as lab-confirmed', () => {
  const stated: GroundingItem = {
    kind: 'fact', label: 'Body shade', display: 'A2', value: 'A2',
    confirmationLevel: 'practice_stated',
  };
  assert.equal(validateAnswer('The body shade is A2.', [stated]).ok, false);
  assert.equal(validateAnswer('Your office gave the body shade as A2.', [stated]).ok, true);
});

test('a confirmed fact must not be hedged', () => {
  assert.equal(validateAnswer('I think it was lot ZR-24-0881.', [lot]).ok, false);
  assert.equal(validateAnswer('It was lot ZR-24-0881.', [lot]).ok, true);
});

test('clinical instruction and PHI in an answer are caught on the way out', () => {
  assert.equal(validateAnswer('Reduce the occlusal another 0.5mm.', [clearance]).ok, false);
  assert.equal(validateAnswer('Call the patient on 555 221 9987.', [lot]).ok, false);
});

test('an honest "we do not know" always passes', () => {
  assert.equal(validateAnswer(
    "I don't have that on the case record. Shall I put it to Priya?", []).ok, true);
});
