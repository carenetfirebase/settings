import test from 'node:test';
import assert from 'node:assert/strict';
import { checkAnswer, checkQuestion } from '../src/index.ts';

test('treatment and technique questions are declined, warmly, with facts offered', () => {
  const cases: [string, RegExp][] = [
    ['Should I do a crown or an onlay on this one?', /treatment decision/i],
    ['How much should I reduce it?', /clinical judgment/i],
    ['Will this crown last?', /can't predict/i],
    ['Is the tooth cracked?', /can't offer a diagnosis/i],
  ];
  for (const [question, expected] of cases) {
    const verdict = checkQuestion(question);
    assert.equal(verdict.allowed, false, question);
    if (verdict.allowed) return;
    assert.match(verdict.template, expected);
    assert.ok(verdict.offerFactKeys.length > 0,
      `${question} should still offer something`);
  }
});

test('a request to deviate from the prescription is refused and escalated', () => {
  const swap = checkQuestion('Just use zirconia instead, go ahead.');
  assert.equal(swap.allowed, false);
  if (swap.allowed) return;
  assert.match(swap.template, /written authorisation/i);
  assert.equal(swap.escalate, true);

  const guess = checkQuestion('Just guess the shade, you know what I like.');
  assert.equal(guess.allowed, false);
  if (guess.allowed) return;
  assert.equal(guess.escalate, true);
});

test('patient identifiers are never retrievable, however the question is framed', () => {
  for (const question of [
    "What's the patient's name?",
    'Give me the patient details for that case.',
    "What is the patient's date of birth?",
    'Who is the patient on 24418?',
  ]) {
    const verdict = checkQuestion(question);
    assert.equal(verdict.allowed, false, question);
    if (verdict.allowed) return;
    assert.match(verdict.template, /as little patient information as we can/i);
  }
});

test('a practice cannot fish for another practice’s cases', () => {
  const verdict = checkQuestion('What are you making for the other dentists this week?');
  assert.equal(verdict.allowed, false);
  if (verdict.allowed) return;
  assert.match(verdict.template, /only see cases for your own practice/i);
});

test('ordinary lab questions pass straight through', () => {
  for (const question of [
    'Where is my case?',
    'What shade did you use?',
    'Has it shipped yet?',
    'Which lot went into this one?',
    'What torque does that abutment take?',
    'Can I get the material certificate?',
    'Why was it remade?',
    'How much is this case?',
  ]) {
    assert.equal(checkQuestion(question).allowed, true, question);
  }
});

test('the post-check catches clinical instruction that slipped into an answer', () => {
  for (const answer of [
    'The tooth is cracked — you should extract it.',
    'It will last for 15 years, guaranteed not to fail.',
    'Reduce the occlusal another 0.5mm and it will seat.',
    "We'll just use zirconia instead since the clearance is tight.",
    'This case is fully compliant and meets all FDA requirements.',
    'You can code this as a D2740 and insurance will cover it.',
  ]) {
    assert.equal(checkAnswer(answer).ok, false, answer);
  }
});

test('the post-check catches an identifier that reached an answer', () => {
  assert.equal(checkAnswer('You can reach the patient at j.doe@example.com.').ok, false);
  assert.equal(checkAnswer('Their number is 555 221 9987.').ok, false);
  assert.equal(checkAnswer('DOB: 1974-02-11.').ok, false);
});

test('the post-check does not fire on honest lab answers', () => {
  for (const answer of [
    'The crown was milled in Katana zirconia, lot ZR-4471, and shipped Tuesday.',
    'The prescription specifies A2 body with a B1 stump shade.',
    'We measured 0.8mm of occlusal clearance; lithium disilicate needs 1.5mm, so ' +
      'the case is on hold for your decision.',
    'Torque specification for that abutment screw is 35 Ncm per the manufacturer.',
    'It was remade because the margin was not fully captured on the distal.',
    'Case 24418 shipped on the 12th, tracking 1Z999AA10123456784.',
  ]) {
    const check = checkAnswer(answer);
    assert.equal(check.ok, true, `${answer} → ${check.flags.map((f) => f.rule).join(', ')}`);
  }
});
