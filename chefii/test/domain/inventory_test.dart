import 'package:chefii/data/repositories/inventory_repository.dart';
import 'package:chefii/data/store/memory_doc_store.dart';
import 'package:chefii/domain/inventory/consumption_planner.dart';
import 'package:chefii/domain/models/codec.dart';
import 'package:chefii/domain/models/inventory.dart';
import 'package:chefii/domain/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

const hid = 'h1';
const uid = 'u1';

const eggs = FoodProduct(
  id: 'egg',
  name: 'Eggs',
  category: FoodCategory.dairy,
  defaultUnit: Unit.piece,
  bridge: UnitBridge(gramsPerPiece: 50),
  allergens: ['egg'],
);
const milk = FoodProduct(
  id: 'milk',
  name: 'Milk',
  category: FoodCategory.dairy,
  defaultUnit: Unit.ml,
  bridge: UnitBridge(gramsPerMl: 1.03),
);

NewLotInput lotOf(FoodProduct p, Quantity q, {String location = 'fridge', CalendarDate? useBy}) => NewLotInput(
      product: p,
      quantity: q,
      locationId: location,
      source: LotSource.manual,
      provenance: const Provenance(source: ProvenanceSource.user),
      useByDate: useBy,
    );

void main() {
  group('Quantity', () {
    test('converts within a dimension', () {
      expect(const Quantity(1.5, Unit.kg).to(Unit.g).amount, 1500);
      expect(const Quantity(2, Unit.tbsp).to(Unit.ml).amount, 30);
      expect(const Quantity(1, Unit.dozen).to(Unit.piece).amount, 12);
    });

    test('refuses to cross dimensions without a bridge', () {
      expect(() => const Quantity(2, Unit.piece).to(Unit.g), throwsA(isA<UnitConversionException>()));
      expect(const Quantity(2, Unit.piece).tryConvert(Unit.g), isNull);
    });

    test('bridged conversion is flagged as an estimate', () {
      final r = const Quantity(100, Unit.g).tryConvert(Unit.piece, const UnitBridge(gramsPerPiece: 50))!;
      expect(r.quantity.amount, 2);
      expect(r.isEstimate, isTrue);
    });

    test('parses common unit aliases', () {
      expect(Unit.tryParse('Grams'), Unit.g);
      expect(Unit.tryParse('L'), Unit.l);
      expect(Unit.tryParse('tablespoons'), Unit.tbsp);
      expect(Unit.tryParse('furlongs'), isNull);
    });

    test('formats cleanly', () {
      expect(const Quantity(2, Unit.piece).format(), '2 pc');
      expect(const Quantity(1.25, Unit.kg).format(), '1.25 kg');
    });
  });

  group('ConsumptionPlanner', () {
    InventoryLot lot(String id, double qty, {CalendarDate? useBy, String loc = 'fridge', int ageDays = 0}) =>
        InventoryLot(
          id: id,
          householdId: hid,
          productId: 'egg',
          productName: 'Eggs',
          category: FoodCategory.dairy,
          quantity: Quantity(qty, Unit.piece),
          initialQuantity: Quantity(qty, Unit.piece),
          locationId: loc,
          acquiredAt: DateTime.utc(2026, 1, 10 - ageDays),
          source: LotSource.manual,
          provenance: const Provenance(source: ProvenanceSource.user),
          updatedAt: DateTime.utc(2026),
          useByDate: useBy,
        );

    const planner = ConsumptionPlanner();

    test('uses earliest confirmed date first, then oldest', () {
      final plan = planner.plan(
        lots: [
          lot('new', 6),
          lot('old', 2, ageDays: 5),
          lot('dated', 3, useBy: const CalendarDate(2026, 1, 12)),
        ],
        requested: const Quantity(6, Unit.piece),
      );
      expect(plan.allocations.map((a) => a.lot.id), ['dated', 'old', 'new']);
      expect(plan.allocations.map((a) => a.take.amount), [3, 2, 1]);
      expect(plan.isFullySatisfied, isTrue);
    });

    test('freezer stock is used last; preferred lot first', () {
      final plan = planner.plan(
        lots: [lot('frozen', 4, loc: 'freezer', ageDays: 9), lot('fresh', 4), lot('tapped', 4)],
        requested: const Quantity(5, Unit.piece),
        preferLotId: 'tapped',
      );
      expect(plan.allocations.map((a) => a.lot.id), ['tapped', 'fresh']);
    });

    test('reports shortfall instead of going negative', () {
      final plan = planner.plan(lots: [lot('a', 2)], requested: const Quantity(5, Unit.piece));
      expect(plan.allocations.single.take.amount, 2);
      expect(plan.shortfall.amount, 3);
    });

    test('converts grams to pieces through a bridge', () {
      final plan = planner.plan(
        lots: [lot('a', 12)],
        requested: const Quantity(100, Unit.g),
        bridge: const UnitBridge(gramsPerPiece: 50),
      );
      expect(plan.allocations.single.take.amount, 2);
      expect(plan.usesEstimates, isTrue);
    });

    test('skips lots with incompatible units', () {
      final plan = planner.plan(lots: [lot('a', 12)], requested: const Quantity(100, Unit.g));
      expect(plan.allocations, isEmpty);
      expect(plan.incompatibleLotIds, ['a']);
      expect(plan.shortfall.amount, 100);
    });
  });

  group('InventoryRepository', () {
    late MemoryDocStore store;
    late InventoryRepository repo;

    setUp(() {
      store = MemoryDocStore();
      repo = InventoryRepository(store, clock: () => DateTime.utc(2026, 3, 1, 12));
    });

    Future<double> eggCount() async =>
        (await repo.lotsForProduct(hid, 'egg')).fold<double>(0, (s, l) => s + l.quantity.amount);

    test('adding is idempotent per operation id', () async {
      final r1 = await repo.addLots(householdId: hid, operationId: 'op1', actorUid: uid, inputs: [lotOf(eggs, const Quantity(12, Unit.piece))]);
      final r2 = await repo.addLots(householdId: hid, operationId: 'op1', actorUid: uid, inputs: [lotOf(eggs, const Quantity(12, Unit.piece))]);
      expect(r1.alreadyApplied, isFalse);
      expect(r2.alreadyApplied, isTrue);
      expect(await eggCount(), 12);
      expect(await repo.product(hid, 'egg'), isNotNull);
    });

    test('rejects zero or negative intake', () {
      expect(
        () => repo.addLots(householdId: hid, operationId: 'x', actorUid: uid, inputs: [lotOf(eggs, const Quantity(0, Unit.piece))]),
        throwsA(isA<InventoryException>()),
      );
    });

    test('"I used two eggs" deducts once even when retried', () async {
      await repo.addLots(householdId: hid, operationId: 'add', actorUid: uid, inputs: [lotOf(eggs, const Quantity(12, Unit.piece))]);
      const req = ConsumeRequest(productId: 'egg', productName: 'Eggs', quantity: Quantity(2, Unit.piece));
      await repo.consume(householdId: hid, operationId: 'use1', actorUid: uid, requests: [req]);
      final retry = await repo.consume(householdId: hid, operationId: 'use1', actorUid: uid, requests: [req]);
      expect(retry.alreadyApplied, isTrue);
      expect(await eggCount(), 10);
    });

    test('concurrent double taps with the same key apply once', () async {
      await repo.addLots(householdId: hid, operationId: 'add', actorUid: uid, inputs: [lotOf(eggs, const Quantity(12, Unit.piece))]);
      const req = ConsumeRequest(productId: 'egg', productName: 'Eggs', quantity: Quantity(3, Unit.piece));
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) repo.consume(householdId: hid, operationId: 'tap', actorUid: uid, requests: [req]),
      ]);
      expect(results.where((r) => !r.alreadyApplied).length, 1);
      expect(await eggCount(), 9);
    });

    test('over-consumption clamps at zero and records a discrepancy', () async {
      await repo.addLots(householdId: hid, operationId: 'add', actorUid: uid, inputs: [lotOf(eggs, const Quantity(2, Unit.piece))]);
      final r = await repo.consume(
        householdId: hid,
        operationId: 'use',
        actorUid: uid,
        requests: const [ConsumeRequest(productId: 'egg', productName: 'Eggs', quantity: Quantity(5, Unit.piece))],
      );
      expect(r.discrepancies.single, contains('3 pc more than recorded'));
      final lots = await repo.lotsForProduct(hid, 'egg');
      expect(lots, isEmpty, reason: 'depleted lots are excluded from active stock');
    });

    test('multi-ingredient cooking is atomic across products', () async {
      await repo.addLots(
        householdId: hid,
        operationId: 'add',
        actorUid: uid,
        inputs: [lotOf(eggs, const Quantity(6, Unit.piece)), lotOf(milk, const Quantity(1, Unit.l))],
      );
      final r = await repo.consume(
        householdId: hid,
        operationId: 'cook:s1',
        actorUid: uid,
        kind: OperationKind.cook,
        requests: const [
          ConsumeRequest(productId: 'egg', productName: 'Eggs', quantity: Quantity(3, Unit.piece)),
          ConsumeRequest(productId: 'milk', productName: 'Milk', quantity: Quantity(125, Unit.ml)),
        ],
      );
      expect(r.operation.adjustmentIds, hasLength(2));
      final milkLot = (await repo.lotsForProduct(hid, 'milk')).single;
      expect(milkLot.quantity.amount, closeTo(0.875, 1e-9));
      expect(milkLot.quantity.unit, Unit.l);
    });

    test('undo restores stock exactly once', () async {
      await repo.addLots(householdId: hid, operationId: 'add', actorUid: uid, inputs: [lotOf(eggs, const Quantity(12, Unit.piece))]);
      await repo.consume(
        householdId: hid,
        operationId: 'oops',
        actorUid: uid,
        requests: const [ConsumeRequest(productId: 'egg', productName: 'Eggs', quantity: Quantity(4, Unit.piece))],
      );
      expect(await eggCount(), 8);
      await repo.undo(householdId: hid, targetOperationId: 'oops', actorUid: uid);
      expect(await eggCount(), 12);
      final again = await repo.undo(householdId: hid, targetOperationId: 'oops', actorUid: uid);
      expect(again.alreadyApplied, isTrue);
      expect(await eggCount(), 12);
    });

    test('undoing an intake after partial use clamps and reports', () async {
      await repo.addLots(householdId: hid, operationId: 'add', actorUid: uid, inputs: [lotOf(eggs, const Quantity(6, Unit.piece))]);
      await repo.consume(
        householdId: hid,
        operationId: 'use',
        actorUid: uid,
        requests: const [ConsumeRequest(productId: 'egg', productName: 'Eggs', quantity: Quantity(2, Unit.piece))],
      );
      final r = await repo.undo(householdId: hid, targetOperationId: 'add', actorUid: uid);
      expect(r.discrepancies, isNotEmpty);
      expect(await eggCount(), 0);
    });

    test('correction confirms the lot and records the delta', () async {
      final add = await repo.addLots(
        householdId: hid,
        operationId: 'add',
        actorUid: uid,
        inputs: [
          NewLotInput(
            product: eggs,
            quantity: const Quantity(12, Unit.piece),
            locationId: 'fridge',
            source: LotSource.receipt,
            provenance: const Provenance(source: ProvenanceSource.receiptAi, confidence: 0.5),
          ),
        ],
      );
      final lotId = add.operation.lotIdsCreated.single;
      var lot = (await repo.lotsForProduct(hid, 'egg')).single;
      expect(lot.statusOn(const CalendarDate(2026, 3, 1)), InventoryStatus.needsReview);

      await repo.correctCount(householdId: hid, operationId: 'fix', actorUid: uid, newQuantities: {lotId: const Quantity(10, Unit.piece)});
      lot = (await repo.lotsForProduct(hid, 'egg')).single;
      expect(lot.quantity.amount, 10);
      expect(lot.statusOn(const CalendarDate(2026, 3, 1)), InventoryStatus.confirmed);
    });

    test('mark empty only touches the chosen lot', () async {
      final add = await repo.addLots(
        householdId: hid,
        operationId: 'add',
        actorUid: uid,
        inputs: [lotOf(eggs, const Quantity(6, Unit.piece)), lotOf(eggs, const Quantity(6, Unit.piece))],
      );
      await repo.markEmpty(householdId: hid, operationId: 'empty', actorUid: uid, lotId: add.operation.lotIdsCreated.last);
      final lots = await repo.lotsForProduct(hid, 'egg');
      expect(lots.single.id, add.operation.lotIdsCreated.first);
      expect(lots.single.quantity.amount, 6);
    });

    test('move and undo restore location', () async {
      final add = await repo.addLots(householdId: hid, operationId: 'add', actorUid: uid, inputs: [lotOf(milk, const Quantity(1, Unit.l))]);
      final lotId = add.operation.lotIdsCreated.single;
      await repo.moveLot(householdId: hid, operationId: 'mv', actorUid: uid, lotId: lotId, toLocationId: 'freezer');
      expect((await repo.lotsForProduct(hid, 'milk')).single.locationId, 'freezer');
      await repo.undo(householdId: hid, targetOperationId: 'mv', actorUid: uid);
      expect((await repo.lotsForProduct(hid, 'milk')).single.locationId, 'fridge');
    });

    test('status reflects recorded dates without claiming safety', () async {
      await repo.addLots(
        householdId: hid,
        operationId: 'add',
        actorUid: uid,
        inputs: [lotOf(milk, const Quantity(1, Unit.l), useBy: const CalendarDate(2026, 2, 27))],
      );
      final lot = (await repo.lotsForProduct(hid, 'milk')).single;
      expect(lot.statusOn(const CalendarDate(2026, 3, 1)), InventoryStatus.pastRecordedDate);
      expect(InventoryStatus.pastRecordedDate.label, 'Past recorded date');
    });
  });
}
