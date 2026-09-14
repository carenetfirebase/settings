import test from 'node:test';
import assert from 'node:assert/strict';
import { buildDemoLab } from '../../../fixtures/demo-lab.ts';
import { buildDeviceHistoryRecord, findByLot } from '../src/index.ts';

test('a recalled lot resolves to exactly the cases that used it', () => {
  const store = buildDemoLab();
  const result = findByLot(store, 'ZR-24-0881');

  assert.equal(result.matched, 2);
  assert.deepEqual(result.hits.map((h) => h.caseNumber).sort(), ['24401', '24411']);
  assert.equal(result.delivered, 1, '24401 is already seated in a patient');
  assert.equal(result.inProduction, 1);
});

test('the recall result is a notification list, not a spreadsheet to interpret', () => {
  const result = findByLot(buildDemoLab(), 'ZR-24-0881');
  assert.equal(result.practicesToNotify.length, 1);
  assert.equal(result.practicesToNotify[0].practiceName, 'Hale Family Dentistry');
  assert.deepEqual(result.practicesToNotify[0].cases.sort(), ['24401', '24411']);
});

test('lot matching is exact — a near miss is a wrong notification list', () => {
  const store = buildDemoLab();
  assert.equal(findByLot(store, 'ZR-24-088').matched, 0);
  assert.equal(findByLot(store, 'ZR-24-0882').matched, 0);
  assert.equal(findByLot(store, '  zr-24-0881  ').matched, 2, 'case and padding are forgiving');
});

test('an unused lot returns an empty list rather than a guess', () => {
  const result = findByLot(buildDemoLab(), 'ZR-99-9999');
  assert.equal(result.matched, 0);
  assert.deepEqual(result.practicesToNotify, []);
});

test('the device history record names what is missing instead of claiming complete', () => {
  const store = buildDemoLab();
  const inDesign = buildDeviceHistoryRecord(store, store.getCase('case-24430')!);
  assert.equal(inDesign.complete, false);
  assert.ok(inDesign.missing.length > 0);
  assert.ok(inDesign.missing.some((m) => m.factKey.startsWith('qc.')));

  const seated = buildDeviceHistoryRecord(store, store.getCase('case-24401')!);
  assert.ok(seated.entries.length > inDesign.entries.length);
  assert.ok(seated.entries.some((e) => e.factKey === 'material.primary_lot'));
  assert.ok(seated.steps.length >= 5, 'the manufacturing timeline is part of the record');
});

test('a record only counts what this case could have had', () => {
  const store = buildDemoLab();
  const denture = buildDeviceHistoryRecord(store, store.getCase('case-24428')!);
  assert.ok(!denture.missing.some((m) => m.factKey.startsWith('implant.')),
    'a partial denture is not incomplete for lacking an abutment part number');
});

test('every record entry carries who stood behind it and when', () => {
  const store = buildDemoLab();
  const record = buildDeviceHistoryRecord(store, store.getCase('case-24401')!);
  for (const entry of record.entries) {
    assert.ok(entry.confirmedBy, `${entry.factKey} has no attribution`);
    assert.ok(entry.confirmedAt);
    assert.ok(entry.source);
  }
});
