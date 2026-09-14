import test from 'node:test';
import assert from 'node:assert/strict';
import {
  CASE_FACTS, QUESTION_TEMPLATES, SECTIONS, caseContextFields, definitionsInSection,
  dhrDefinitions, getDefinition, splitByApplicability, validateCatalog,
} from '../src/index.ts';

test('the catalog is internally consistent', () => {
  assert.deepEqual(validateCatalog(), []);
});

test('every section carries definitions and the catalog covers a real case', () => {
  assert.ok(CASE_FACTS.length >= 200, `only ${CASE_FACTS.length} definitions`);
  for (const section of SECTIONS) {
    assert.ok(definitionsInSection(section.key).length > 0, `section ${section.key} empty`);
  }
});

test('the facts a lab is judged on exist by name', () => {
  for (const key of [
    'rx.tooth_numbers', 'rx.material', 'rx.shade_body', 'rx.stump_shade',
    'material.primary_lot', 'implant.torque_spec', 'outcome.remake_cause',
    'delivery.tracking_number', 'reg.dhr_complete', 'qc.disinfected',
  ]) {
    assert.ok(getDefinition(key), `missing ${key}`);
  }
});

test('a crown case is not scored against abutments or denture teeth', () => {
  const crown = splitByApplicability({
    restoration_type: 'crown', material_class: 'zirconia', is_digital: true,
    is_on_hold: false, is_remake: false, is_delayed: false, is_outsourced: false,
    is_printed: false, is_screw_retained: false, uses_ti_base: false,
  });
  const keys = new Set(crown.applicable.map((d) => d.key));
  assert.ok(!keys.has('implant.torque_spec'));
  assert.ok(!keys.has('removable.tooth_mould'));
  assert.ok(keys.has('rx.tooth_numbers'));
  assert.ok(keys.has('material.primary_lot'));
});

test('an implant case picks up componentry a crown never needs', () => {
  const implant = splitByApplicability({
    restoration_type: 'implant_crown', material_class: 'zirconia',
    is_screw_retained: true, uses_ti_base: true, is_digital: true,
    is_printed: false, is_outsourced: false, is_remake: false, is_delayed: false,
    is_on_hold: false,
  });
  const keys = new Set(implant.applicable.map((d) => d.key));
  assert.ok(keys.has('implant.torque_spec'));
  assert.ok(keys.has('implant.ti_base_part_number'));
  assert.ok(keys.has('design.screw_access_position'));
  // Cement margin depth is a cemented-case concern only.
  assert.ok(!keys.has('implant.cement_gap_managed'));
});

test('an unanswered intake question leaves facts unresolved rather than guessed', () => {
  const partial = splitByApplicability({ restoration_type: 'crown' });
  const unresolved = new Set(partial.unresolved.map((d) => d.key));
  assert.ok(unresolved.has('material.shade_block_lot'),
    'material_class is unanswered, so ingot-lot applicability is unknown');
  assert.ok(partial.missingFields.some((f) => f.field === 'material_class'));
});

test('every blocking fact can actually be chased', () => {
  const blocking = CASE_FACTS.filter(
    (d) => d.necessity === 'blocking' && d.visibility === 'practice');
  for (const def of blocking) {
    const askable = def.askPractice ?? def.answersQuestions[0];
    assert.ok(askable && askable.length > 5, `${def.key} cannot be asked for`);
  }
});

test('the device history record is substantial and spans manufacture', () => {
  const dhr = dhrDefinitions();
  assert.ok(dhr.length >= 80, `only ${dhr.length} DHR facts`);
  const sections = new Set(dhr.map((d) => d.section));
  for (const required of ['B', 'G', 'H']) {
    assert.ok(sections.has(required as never), `DHR misses section ${required}`);
  }
});

test('patient-safety facts are never merely optional', () => {
  for (const def of CASE_FACTS.filter((d) => d.safety === 'patient_safety')) {
    assert.notEqual(def.necessity, 'optional', `${def.key} is safety-critical but optional`);
  }
});

test('question templates resolve to real keys and collapse duplicates', () => {
  assert.ok(QUESTION_TEMPLATES.length > 300);
  const normalized = QUESTION_TEMPLATES.map((q) => q.normalized);
  assert.equal(new Set(normalized).size, normalized.length);

  const where = QUESTION_TEMPLATES.find((q) => q.normalized === 'where is my case');
  assert.ok(where && where.factKeys.includes('case.status'));
  assert.equal(where.frequency, 100, 'the most-asked question should rank highest');
});

test('intake context fields are answerable in one short question each', () => {
  for (const field of caseContextFields()) {
    assert.match(field, /^[a-z][a-z0-9_]*$/);
  }
});
