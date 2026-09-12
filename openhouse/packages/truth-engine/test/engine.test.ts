import test from 'node:test';
import assert from 'node:assert/strict';
import { buildDemoProperty, DEMO_AGENT_ID, DEMO_PROPERTY_ID }
  from '../../../fixtures/demo-property/maple-crescent.ts';
import { createTruthEngine } from '../src/engine.ts';
import { InMemoryStore } from '../src/store.ts';

const engineFor = () => {
  const store = buildDemoProperty();
  return { store, engine: createTruthEngine(store) };
};

test('resolve returns the verified value with its provenance', () => {
  const { engine } = engineFor();
  const [furnace] = engine.resolve(DEMO_PROPERTY_ID, ['mechanical.furnace.install_year']);
  assert.equal(furnace.status, 'verified');
  assert.equal(furnace.value, 2019);
  assert.equal(furnace.verificationLevel, 'document_verified');
  assert.equal(furnace.source?.documentId, 'doc-furnace');
  assert.equal(furnace.source?.page, 1);
});

test('normalization coerces the shapes documents actually use', () => {
  const { engine } = engineFor();
  // "Sept 2019" on the invoice, "$4,620.00/yr" on the tax notice, "2140 sqft".
  assert.equal(engine.resolve(DEMO_PROPERTY_ID, ['mechanical.furnace.install_year'])[0].value, 2019);
  assert.equal(engine.resolve(DEMO_PROPERTY_ID, ['taxes.annual_amount'])[0].value, 4620);
  assert.equal(engine.resolve(DEMO_PROPERTY_ID, ['property.living_area'])[0].value, 2140);
});

test('an unknown fact resolves to unknown with its reason, not to nothing', () => {
  const { engine } = engineFor();
  const [windows] = engine.resolve(DEMO_PROPERTY_ID, ['exterior.windows.replacement_year']);
  assert.equal(windows.status, 'unknown');
  assert.equal(windows.unknownReason, 'seller_does_not_know');
  assert.equal(windows.value, undefined);
});

test('a fact nobody has touched resolves to nothing at all', () => {
  const { engine } = engineFor();
  assert.deepEqual(engine.resolve(DEMO_PROPERTY_ID, ['exterior.fence.ownership']), []);
});

test('two sources disagreeing on the roof year is a conflict that blocks publish', () => {
  const { engine } = engineFor();
  const conflicts = engine.detectConflicts(DEMO_PROPERTY_ID);
  const roof = conflicts.find((c) => c.factKey === 'exterior.roof.replacement_year');
  assert.ok(roof);
  assert.equal(roof.severity, 'hard');
  assert.equal(roof.blocksPublish, true);
  assert.deepEqual(roof.claims.map((c) => c.value), [2017, 2018]);
  assert.ok(engine.publishBlockers(DEMO_PROPERTY_ID).some(
    (b) => b.factKey === 'exterior.roof.replacement_year'));
});

test('resolving the conflict clears the publish blocker', () => {
  const { store, engine } = engineFor();
  const winner = store.getClaims(DEMO_PROPERTY_ID).find(
    (c) => c.factKey === 'exterior.roof.replacement_year' && c.valueNormalized === 2018)!;
  store.confirmClaim(DEMO_PROPERTY_ID, winner.id, DEMO_AGENT_ID);

  assert.equal(engine.detectConflicts(DEMO_PROPERTY_ID).length, 0);
  assert.deepEqual(engine.publishBlockers(DEMO_PROPERTY_ID), []);
  assert.equal(engine.resolve(DEMO_PROPERTY_ID, ['exterior.roof.replacement_year'])[0].value, 2018);
});

test('materiality is type-dependent so the agent is not drowned in noise', () => {
  const { store, engine } = engineFor();

  // A 1% difference between a survey and an MLS sheet is not a conflict.
  store.addClaim(DEMO_PROPERTY_ID, {
    factKey: 'property.living_area', valueRaw: '2,155 sqft',
    sourceType: 'document', sourceDocumentId: 'doc-survey', sourcePage: 1, status: 'pending',
  });
  assert.ok(!engine.detectConflicts(DEMO_PROPERTY_ID)
    .some((c) => c.factKey === 'property.living_area'));

  // A 15% difference is.
  store.addClaim(DEMO_PROPERTY_ID, {
    factKey: 'property.living_area', valueRaw: '2,460 sqft',
    sourceType: 'document', sourceDocumentId: 'doc-appraisal', sourcePage: 1, status: 'pending',
  });
  assert.ok(engine.detectConflicts(DEMO_PROPERTY_ID)
    .some((c) => c.factKey === 'property.living_area'));
});

test('a low-weight conflict sits in the queue instead of stopping the publish', () => {
  const { store, engine } = engineFor();
  for (const value of ['Aluminum', 'Vinyl']) {
    store.addClaim(DEMO_PROPERTY_ID, {
      factKey: 'exterior.eavestrough.material', valueRaw: value,
      sourceType: 'agent_input', status: 'pending',
    });
  }
  const conflict = engine.detectConflicts(DEMO_PROPERTY_ID)
    .find((c) => c.factKey === 'exterior.eavestrough.material');
  assert.ok(conflict);
  assert.equal(conflict.blocksPublish, false);
});

test('coverage is two numbers, and preparation can exceed answerability', () => {
  const { engine } = engineFor();
  const score = engine.score(DEMO_PROPERTY_ID);
  assert.ok(score.preparation > score.answerCoverage,
    'marking facts unknown counts as prepared but not answerable');
  assert.ok(score.answerCoverage > 0 && score.answerCoverage < 1);
  assert.equal(score.unresolvedApplicability, 0, 'the demo answers every setup question');
});

test('coverage matches a hand calculation on a tiny property', () => {
  const store = new InMemoryStore();
  store.load({
    property: {
      id: 'tiny', slug: 'tiny', status: 'draft', addressLine1: '1 Test', city: 'Calgary',
      province: 'AB', propertyType: 'condo_apartment',
      applicability: {
        property_type: 'condo_apartment', has_basement: false, has_garage: false,
        has_suite: false, has_ac: false, has_deck: false, has_fence: false,
        has_fireplace: false, has_ensuite: false, has_pool: false, has_hot_tub: false,
        has_solar: false, has_ev_charger: false, has_security_system: false,
        has_stucco: false, has_addition: false, has_crawlspace: false,
        has_heat_pump: false, has_in_floor_heat: false, has_hrv: false,
        has_sump_pump: false, has_kitchen_island: false, has_septic: false,
        has_wood_burning_appliance: false, has_basement_bathroom: false,
        is_tenanted: false, heating_type: 'forced_air_gas', water_source: 'municipal',
        radon_tested: false,
      },
    },
    rooms: [], claims: [], facts: [], commentary: [], inclusions: [], disclosures: [],
  });
  const engine = createTruthEngine(store);

  const applicable = engine.applicableDefinitions(store.getProperty('tiny')!);
  const totalWeight = applicable.reduce((sum, d) => sum + d.coverageWeight, 0);
  assert.equal(engine.score('tiny').preparation, 0);

  // Verify one fact, mark another unknown, and check both ratios by hand.
  const claim = store.addClaim('tiny', {
    factKey: 'condo.fee_monthly', valueRaw: '$540', sourceType: 'agent_input', status: 'pending',
  });
  store.confirmClaim('tiny', claim.id, 'agent');
  store.markUnknown('tiny', 'condo.reserve_fund_balance', 'no_documentation');

  const score = engine.score('tiny');
  const verifiedWeight = 10;   // condo.fee_monthly
  const unknownWeight = 9;     // condo.reserve_fund_balance
  assert.equal(score.answerCoverage, round(verifiedWeight / totalWeight));
  assert.equal(score.preparation, round((verifiedWeight + unknownWeight) / totalWeight));
});

test('a condo is never scored against facts it cannot have', () => {
  const { engine } = engineFor();
  const keys = new Set(engine.applicableDefinitions(
    { ...buildDemoProperty().getProperty(DEMO_PROPERTY_ID)! }).map((d) => d.key));
  assert.ok(keys.has('exterior.roof.replacement_year'));
  assert.ok(!keys.has('condo.fee_monthly'));
});

test('gaps are question-shaped and ranked by what buyers actually ask', () => {
  const { engine } = engineFor();
  const gaps = engine.gaps(DEMO_PROPERTY_ID, 10);
  assert.ok(gaps.length > 0);
  for (const gap of gaps) {
    assert.match(gap.question, /\?$/);
    assert.match(gap.question, /^[A-Z]/);
  }
  for (let i = 1; i < gaps.length; i += 1) {
    assert.ok(gaps[i - 1].priority >= gaps[i].priority, 'gaps must be ranked');
  }
  // Facts already marked unknown are finished work, not gaps.
  assert.ok(!gaps.some((g) => g.factKey === 'exterior.windows.replacement_year'));
});

test('the fact pack carries verified facts, unknowns and disclosures — and nothing private', () => {
  const { engine } = engineFor();
  const pack = engine.buildFactPack(DEMO_PROPERTY_ID);

  assert.equal(pack.facts['mechanical.furnace.install_year'].v, 2019);
  assert.equal(pack.facts['basement.suite_status'].v, 'not_legal');
  assert.ok(pack.unknown_keys.includes('exterior.windows.replacement_year'));
  assert.equal(pack.unknown_reasons['exterior.windows.replacement_year'], 'seller_does_not_know');
  assert.equal(pack.disclosures.length, 1);
  assert.match(pack.disclosures[0].detail, /northeast corner/);

  // Agent-only facts and unapproved or private commentary never enter the pack.
  assert.ok(!('legal.seller.reason_for_selling' in pack.facts));
  assert.ok(!pack.commentary.some((c) => /relocating/i.test(c.text)));
  assert.equal(pack.is_demo, true);
});

test('the fact pack is small enough to sit in a realtime session context', () => {
  const { engine } = engineFor();
  const bytes = Buffer.byteLength(JSON.stringify(engine.buildFactPack(DEMO_PROPERTY_ID)));
  assert.ok(bytes < 32_000, `fact pack is ${bytes} bytes`);
});

test('the fact pack hash is stable across builds and changes with content', () => {
  const { store, engine } = engineFor();
  const first = engine.buildFactPack(DEMO_PROPERTY_ID).snapshot_hash;
  assert.equal(engine.buildFactPack(DEMO_PROPERTY_ID).snapshot_hash, first);

  store.markUnknown(DEMO_PROPERTY_ID, 'exterior.fence.ownership', 'seller_does_not_know');
  assert.notEqual(engine.buildFactPack(DEMO_PROPERTY_ID).snapshot_hash, first);
});

test('the engine answers inside the voice latency budget', () => {
  const { engine } = engineFor();
  const started = performance.now();
  for (let i = 0; i < 100; i += 1) {
    engine.resolve(DEMO_PROPERTY_ID, ['mechanical.furnace.install_year', 'basement.suite_status']);
  }
  const perCall = (performance.now() - started) / 100;
  assert.ok(perCall < 10, `resolve averaged ${perCall.toFixed(2)}ms, budget is 10ms`);
});

function round(n: number): number { return Math.round(n * 1000) / 1000; }
