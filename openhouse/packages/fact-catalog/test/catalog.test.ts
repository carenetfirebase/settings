import test from 'node:test';
import assert from 'node:assert/strict';
import {
  CATALOG_VERSION, FACT_DEFINITIONS, QUESTION_TEMPLATES, SECTIONS,
  applicabilityFields, definitionsInSection, disclosureDefinitions,
  getDefinition, normalizeQuestion, splitByApplicability, validateCatalog,
} from '../src/index.ts';

test('the catalog is internally consistent', () => {
  assert.deepEqual(validateCatalog(), []);
});

test('the catalog is large enough to cover a real listing', () => {
  assert.ok(FACT_DEFINITIONS.length >= 300,
    `expected ~300 definitions, got ${FACT_DEFINITIONS.length}`);
});

test('every section A-L carries definitions', () => {
  for (const section of SECTIONS) {
    assert.ok(definitionsInSection(section.key).length > 0,
      `section ${section.key} (${section.label}) is empty`);
  }
});

test('the facts the architecture names by key exist', () => {
  for (const key of [
    'mechanical.furnace.install_year',
    'exterior.roof.replacement_year',
    'exterior.windows.replacement_year',
    'basement.suite_status',
    'kitchen.appliance.refrigerator.install_year',
    'kitchen.appliance.dishwasher.install_year',
    'electrical.service_amperage',
    'exterior.garage.heated',
  ]) {
    assert.ok(getDefinition(key), `missing catalog key ${key}`);
  }
});

test('a condo is not scored against roof, lot or septic facts', () => {
  const condo = splitByApplicability({
    property_type: 'condo_apartment',
    has_basement: false, has_garage: false, has_suite: false,
    water_source: 'municipal', has_septic: false,
  });
  const applicable = new Set(condo.applicable.map((d) => d.key));
  assert.ok(!applicable.has('exterior.roof.replacement_year'));
  assert.ok(!applicable.has('property.lot_size'));
  assert.ok(!applicable.has('utilities.septic.last_pumped'));
  assert.ok(applicable.has('condo.fee_monthly'));
  assert.ok(applicable.has('mechanical.water_heater.install_year'));
});

test('a detached house is not scored against condo bylaws', () => {
  const house = splitByApplicability({ property_type: 'detached' });
  const applicable = new Set(house.applicable.map((d) => d.key));
  assert.ok(!applicable.has('condo.bylaws.pets'));
  assert.ok(applicable.has('exterior.roof.replacement_year'));
});

test('unanswered setup questions leave facts unresolved, not applicable', () => {
  // has_garage is unanswered, so "is the garage heated?" is neither in nor out.
  const partial = splitByApplicability({ property_type: 'detached' });
  const unresolved = new Set(partial.unresolved.map((d) => d.key));
  assert.ok(unresolved.has('exterior.garage.heated'));
  assert.ok(!partial.applicable.some((d) => d.key === 'exterior.garage.heated'));
  assert.ok(!partial.notApplicable.some((d) => d.key === 'exterior.garage.heated'));

  const fields = partial.missingFields.map((f) => f.field);
  assert.ok(fields.includes('has_garage'));
  // Ranked by the weight of what answering unlocks.
  assert.ok(partial.missingFields[0].weight >= partial.missingFields.at(-1)!.weight);
});

test('answering the setup question resolves the fact', () => {
  const withGarage = splitByApplicability({ property_type: 'detached', has_garage: true });
  assert.ok(withGarage.applicable.some((d) => d.key === 'exterior.garage.heated'));

  const without = splitByApplicability({ property_type: 'detached', has_garage: false });
  assert.ok(without.notApplicable.some((d) => d.key === 'exterior.garage.heated'));
});

test('every applicability field is answerable at setup', () => {
  const fields = applicabilityFields();
  assert.ok(fields.includes('property_type'));
  // Fields are plain snake_case flags a person can be asked in one sentence.
  for (const field of fields) {
    assert.match(field, /^[a-z][a-z0-9_]*$/, `unusable setup field: ${field}`);
  }
});

test('disclosure facts are weighted and never trivial', () => {
  const disclosures = disclosureDefinitions();
  assert.ok(disclosures.length >= 30);
  for (const def of disclosures) assert.ok(def.coverageWeight >= 6);
});

test('question templates resolve to real keys and collapse duplicates', () => {
  assert.ok(QUESTION_TEMPLATES.length > 400);
  const normalized = QUESTION_TEMPLATES.map((q) => q.normalized);
  assert.equal(new Set(normalized).size, normalized.length);

  const roofAge = QUESTION_TEMPLATES.find((q) => q.normalized === 'how old is the roof');
  assert.ok(roofAge);
  assert.ok(roofAge.factKeys.includes('exterior.roof.replacement_year'));

  const bigTicket = QUESTION_TEMPLATES.find(
    (q) => q.normalized === 'how old are the big ticket items');
  assert.ok(bigTicket && bigTicket.factKeys.length >= 4);
});

test('question normalization survives the way people actually talk', () => {
  assert.equal(normalizeQuestion("So, how old's the FURNACE?"), 'how olds the furnace');
  assert.equal(normalizeQuestion('What about the dishwasher?'), 'what about the dishwasher');
});

test('catalog version is pinned', () => {
  assert.equal(CATALOG_VERSION, 1);
});
