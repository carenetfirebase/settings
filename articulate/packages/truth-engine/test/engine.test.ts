import test from 'node:test';
import assert from 'node:assert/strict';
import { buildDemoLab } from '../../../fixtures/demo-lab.ts';
import { createTruthEngine } from '../src/engine.ts';
import {
  fdiToUniversal, materiallyDiffers, normalizeValue, parseTeeth, universalToFdi,
} from '../src/normalize.ts';
import { getDefinition } from '../../case-catalog/src/index.ts';

const setup = () => {
  const store = buildDemoLab();
  return { store, engine: createTruthEngine(store) };
};

test('tooth notation round-trips between Universal and FDI', () => {
  for (let universal = 1; universal <= 32; universal += 1) {
    assert.equal(fdiToUniversal(universalToFdi(universal)), universal);
  }
  // The classic ones, checked by hand: #3 is upper right first molar (FDI 16),
  // #19 is lower left first molar (FDI 36).
  assert.equal(universalToFdi(3), 16);
  assert.equal(universalToFdi(19), 36);
  assert.deepEqual(parseTeeth('#18, #19, #20'), [37, 36, 35]);
});

test('shades are validated, not accepted as free text', () => {
  const shade = getDefinition('rx.shade_body')!;
  assert.equal(normalizeValue(shade, 'a2').ok, true);
  assert.equal(normalizeValue(shade, 'BL3').ok, true);
  assert.equal(normalizeValue(shade, '2M2').ok, true);
  assert.equal(normalizeValue(shade, 'sort of yellowish').ok, false);
  assert.equal(normalizeValue(shade, 'A9').ok, false);
});

test('a lot number is stored exactly as the supplier printed it', () => {
  const lot = getDefinition('material.primary_lot')!;
  const result = normalizeValue(lot, 'ZR-24-0881');
  assert.equal(result.ok, true);
  if (!result.ok) return;
  assert.equal(result.value, 'ZR-24-0881');
});

test('materiality is tuned per type so the bench is not flooded', () => {
  const clearance = getDefinition('design.occlusal_clearance')!;
  assert.equal(materiallyDiffers(clearance, 1.4, 1.42), false, '1.4% is measurement noise');
  assert.equal(materiallyDiffers(clearance, 1.4, 1.8), true);

  const torque = getDefinition('implant.torque_spec')!;
  assert.equal(materiallyDiffers(torque, 35, 30), true, 'torque has no tolerance');

  const teeth = getDefinition('rx.tooth_numbers')!;
  assert.equal(materiallyDiffers(teeth, [36], [35]), true, 'any tooth difference is a conflict');
});

test('a tooth-number disagreement stops the case and picks no winner', () => {
  const { engine } = setup();
  const conflicts = engine.detectConflicts('case-24418');
  const tooth = conflicts.find((c) => c.factKey === 'rx.tooth_numbers');
  assert.ok(tooth);
  assert.equal(tooth.safety, 'patient_safety');
  assert.equal(tooth.stopsProduction, true);
  assert.equal(tooth.claims.length, 2);

  // And nothing resolved it on the way past.
  assert.deepEqual(engine.resolve('case-24418', ['rx.tooth_numbers'])
    .filter((f) => f.status === 'confirmed'), []);
  assert.ok(engine.blockers('case-24418').some(
    (b) => b.kind === 'conflict' && b.phase === 'start'));
});

test('confirming one side clears the stop', () => {
  const { store, engine } = setup();
  const winner = store.getClaims('case-24418').find(
    (c) => c.factKey === 'rx.tooth_numbers' && c.valueRaw === '#19')!;
  store.confirm('case-24418', winner.id, 'Priya R.');

  assert.equal(engine.detectConflicts('case-24418').length, 0);
  const [tooth] = engine.resolve('case-24418', ['rx.tooth_numbers']);
  assert.equal(tooth.status, 'confirmed');
  assert.equal(tooth.display, '#19');
});

test('readiness measures whether the bench can start, not whether the case is done', () => {
  const { engine } = setup();
  // 24430 is mid-production with no material lot opened yet. That is normal,
  // and it must not read as "not ready".
  const inProduction = engine.score('case-24430');
  assert.equal(inProduction.readiness, 1);
  assert.ok(engine.blockers('case-24430').every((b) => b.phase !== 'start'));

  // 24418 is genuinely stuck at the start.
  assert.ok(engine.blockers('case-24418').some((b) => b.phase === 'start'));
});

test('a fact marked unknown is resolved work, not an outstanding ask', () => {
  const { engine } = setup();
  const [stump] = engine.resolve('case-24423', ['rx.stump_shade']);
  assert.equal(stump.status, 'unknown');
  assert.equal(stump.unknownReason, 'practice_has_not_supplied');
  assert.ok(!engine.asks('case-24423', 20).some((a) => a.factKey === 'rx.stump_shade'));
});

test('asks are phrased for a person and ranked by what is holding the case', () => {
  const { engine } = setup();
  const asks = engine.asks('case-24428', 6);
  assert.ok(asks.length > 0);
  for (const ask of asks) {
    assert.match(ask.question, /\?$|\.$/);
    assert.ok(ask.question.length > 10);
  }
  for (let i = 1; i < asks.length; i += 1) {
    assert.ok(asks[i - 1].priority >= asks[i].priority);
  }
});

test('the DHR score is computed from the record, never asserted', () => {
  const { engine } = setup();
  const seated = engine.score('case-24401');
  const inDesign = engine.score('case-24430');
  assert.ok(seated.dhrCompleteness > inDesign.dhrCompleteness,
    'a finished case has a fuller record than one still in design');
  assert.ok(seated.dhrOutstanding.length < inDesign.dhrOutstanding.length);
});

test('the case pack carries what a practice may hear, and nothing else', () => {
  const { engine } = setup();
  const pack = engine.buildCasePack('case-24401');
  assert.equal(pack.facts['material.primary_lot'].v, 'ZR-24-0881');
  assert.ok(!('case.patient_initials' in pack.facts), 'PHI must never enter a pack');
  assert.ok(!('commercial.margin' in pack.facts), 'lab-internal costs must never enter a pack');
  assert.equal(pack.is_demo, true);
  assert.ok(pack.content_hash.startsWith('sha256:'));
});

test('the pack hash is stable across builds and moves when the case does', () => {
  const { store, engine } = setup();
  const first = engine.buildCasePack('case-24423').content_hash;
  assert.equal(engine.buildCasePack('case-24423').content_hash, first);
  store.correct('case-24423', 'rx.stump_shade', 'A1', 'Marcus L.');
  assert.notEqual(engine.buildCasePack('case-24423').content_hash, first);
});

test('resolution stays inside a conversational latency budget', () => {
  const { engine } = setup();
  const started = performance.now();
  for (let i = 0; i < 200; i += 1) {
    engine.resolve('case-24401', ['material.primary_lot', 'delivery.tracking_number']);
  }
  const per = (performance.now() - started) / 200;
  assert.ok(per < 5, `resolve averaged ${per.toFixed(2)}ms`);
});
