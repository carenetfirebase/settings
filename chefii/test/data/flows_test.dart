import 'dart:typed_data';

import 'package:chefii/data/ai/demo_ai_gateway.dart';
import 'package:chefii/data/paths.dart';
import 'package:chefii/data/repositories/health_repositories.dart';
import 'package:chefii/data/repositories/inventory_repository.dart';
import 'package:chefii/data/repositories/kitchen_repositories.dart';
import 'package:chefii/data/repositories/receipt_repository.dart';
import 'package:chefii/data/store/memory_doc_store.dart';
import 'package:chefii/domain/models/codec.dart';
import 'package:chefii/domain/models/health.dart';
import 'package:chefii/domain/models/inventory.dart';
import 'package:chefii/domain/models/professional.dart';
import 'package:chefii/domain/models/profile.dart';
import 'package:chefii/domain/models/receipt.dart';
import 'package:chefii/domain/models/recipe.dart';
import 'package:chefii/domain/recipes/curated_recipes.dart';
import 'package:chefii/domain/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

const hid = 'h1';
const uid = 'u1';
const locations = {StorageKind.fridge: 'fridge', StorageKind.freezer: 'freezer', StorageKind.pantry: 'pantry'};

void main() {
  late MemoryDocStore store;
  late InventoryRepository inventory;
  late ReceiptRepository receipts;
  late ReceiptImportService importer;

  setUp(() {
    store = MemoryDocStore();
    inventory = InventoryRepository(store);
    receipts = ReceiptRepository(store);
    importer = ReceiptImportService(store, inventory);
  });

  Future<PurchaseReceipt> demoReceipt() async {
    final id = await receipts.createJob(householdId: hid, uid: uid, imageHashes: ['abc']);
    await receipts.markUploaded(hid, id, ['demo://x']);
    final ai = DemoAiGateway(
      receipts: receipts,
      inventory: inventory,
      dietaryOf: () async => const DietaryProfile(),
      latency: Duration.zero,
    );
    await ai.processReceipt(householdId: hid, receiptId: id);
    return (await receipts.get(hid, id))!;
  }

  group('Receipt pipeline', () {
    test('image validation sniffs content, not extensions', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]);
      expect(ReceiptImageRules.validate(jpeg, null), isNull);
      expect(ReceiptImageRules.validate(Uint8List.fromList([1, 2, 3, 4]), null), isNotNull);
      expect(ReceiptImageRules.validate(Uint8List(0), 'image/jpeg'), isNotNull);
    });

    test('duplicate images are detected by hash', () async {
      await demoReceipt();
      expect(await receipts.findByImageHash(hid, 'abc'), isNotNull);
      expect(await receipts.findByImageHash(hid, 'zzz'), isNull);
    });

    test('blocks import until unknown items are resolved', () async {
      final r = await demoReceipt();
      expect(r.status, ReceiptStatus.needsReview);
      expect(r.isDemo, isTrue);
      expect(ReceiptImportService.blockingLines(r).map((l) => l.id), containsAll(['l9', 'l12']));
      expect(() => importer.confirm(receipt: r, uid: uid, locationIds: locations), throwsA(isA<ReceiptValidationException>()));
    });

    test('imports reviewed receipt once, excluding non-food', () async {
      var r = await demoReceipt();
      final fixed = r.lines.map((l) {
        if (l.id == 'l9') return l.copyWith(quantity: const Quantity(4, Unit.piece), userEdited: true);
        if (l.id == 'l12') return l.copyWith(excluded: true);
        return l;
      }).toList();
      await receipts.saveLines(hid, r.id, fixed);
      r = (await receipts.get(hid, r.id))!;

      final first = await importer.confirm(receipt: r, uid: uid, locationIds: locations);
      expect(first.alreadyApplied, isFalse);
      expect(first.operation.lotIdsCreated, hasLength(10), reason: '12 lines - soap - unknown');

      // Retrying (e.g. after a network drop) never duplicates stock.
      final again = await importer.confirm(receipt: (await receipts.get(hid, r.id))!, uid: uid, locationIds: locations);
      expect(again.alreadyApplied, isTrue);

      final lots = await inventory.activeLots(hid);
      expect(lots, hasLength(10));
      expect(lots.any((l) => l.productName == 'Dish soap'), isFalse);
      final apples = lots.singleWhere((l) => l.productId == 'apple');
      expect(apples.quantity, const Quantity(4, Unit.piece));
      expect(apples.statusOn(CalendarDate.fromDateTime(DateTime.now())), InventoryStatus.confirmed);
      final yogurt = lots.singleWhere((l) => l.productId == 'greek_yogurt');
      expect(yogurt.needsReview, isTrue, reason: 'low-confidence line not edited by the user');
      expect(yogurt.provenance.raw, 'GRK YOG PLN 750G');

      final updated = (await receipts.get(hid, r.id))!;
      expect(updated.status, ReceiptStatus.imported);
      expect(() => receipts.saveLines(hid, r.id, updated.lines), throwsA(isA<ReceiptValidationException>()));
    });

    test('cancelled receipts are not processed', () async {
      final id = await receipts.createJob(householdId: hid, uid: uid, imageHashes: ['h']);
      await receipts.cancel(hid, id);
      final ai = DemoAiGateway(receipts: receipts, inventory: inventory, dietaryOf: () async => const DietaryProfile(), latency: Duration.zero);
      await ai.processReceipt(householdId: hid, receiptId: id);
      expect((await receipts.get(hid, id))!.lines, isEmpty);
    });
  });

  group('Storage places', () {
    NewLotInput lot(String loc, double n, CalendarDate? useBy) => NewLotInput(
          product: const FoodProduct(id: 'peas', name: 'Peas', category: FoodCategory.frozen, defaultUnit: Unit.g),
          quantity: Quantity(n, Unit.g),
          locationId: loc,
          source: LotSource.manual,
          provenance: const Provenance(source: ProvenanceSource.user),
          useByDate: useBy,
        );

    test('households can add, rename and remove their own places', () async {
      final garage = await inventory.addLocation(hid, name: '  Garage freezer ', kind: StorageKind.freezer);
      expect(garage.id, 'loc_garage_freezer');
      var all = await inventory.watchLocations(hid).first;
      expect(all.map((l) => l.name), ['Fridge', 'Freezer', 'Pantry', 'Garage freezer']);
      await expectLater(inventory.addLocation(hid, name: 'garage FREEZER', kind: StorageKind.pantry), throwsA(isA<InventoryException>()));
      await expectLater(inventory.removeLocation(hid, 'fridge'), throwsA(isA<InventoryException>()));
      await inventory.renameLocation(hid, garage, 'Chest freezer');
      all = await inventory.watchLocations(hid).first;
      expect(all.last.name, 'Chest freezer');

      await inventory.addLots(householdId: hid, operationId: 'g1', actorUid: uid, inputs: [lot(garage.id, 200, null)]);
      await expectLater(inventory.removeLocation(hid, garage.id), throwsA(isA<InventoryException>()));
      await inventory.consume(householdId: hid, operationId: 'g2', actorUid: uid, requests: [ConsumeRequest(productId: 'peas', productName: 'Peas', quantity: const Quantity(200, Unit.g))]);
      await inventory.removeLocation(hid, garage.id);
      expect((await inventory.watchLocations(hid).first).length, 3);
    });

    test('a custom freezer is used after fresher-dated stock elsewhere, like the built-in freezer', () async {
      final garage = await inventory.addLocation(hid, name: 'Garage freezer', kind: StorageKind.freezer);
      const soon = CalendarDate(2026, 11, 1);
      await inventory.addLots(householdId: hid, operationId: 'p1', actorUid: uid, inputs: [lot(garage.id, 300, soon), lot('fridge', 300, const CalendarDate(2026, 12, 1))]);
      await inventory.consume(householdId: hid, operationId: 'p2', actorUid: uid, requests: [ConsumeRequest(productId: 'peas', productName: 'Peas', quantity: const Quantity(100, Unit.g))]);
      final lots = await inventory.lotsForProduct(hid, 'peas');
      expect(lots.firstWhere((l) => l.locationId == garage.id).quantity.amount, 300);
      expect(lots.firstWhere((l) => l.locationId == 'fridge').quantity.amount, 200);
    });
  });

  group('Cooking flow', () {
    test('one confirmation deducts all ingredients, logs journal, saves leftovers', () async {
      await inventory.addLots(
        householdId: hid,
        operationId: 'stock',
        actorUid: uid,
        inputs: [
          for (final (pid, q) in [
            ('lentils', const Quantity(500, Unit.g)),
            ('coconut_milk', const Quantity(800, Unit.ml)),
            ('onion', const Quantity(3, Unit.piece)),
            ('garlic', const Quantity(10, Unit.piece)),
          ])
            NewLotInput(
              product: FoodProduct(id: pid, name: pid, category: FoodCategory.pantry, defaultUnit: q.unit),
              quantity: q,
              locationId: 'pantry',
              source: LotSource.manual,
              provenance: const Provenance(source: ProvenanceSource.user),
            ),
        ],
      );
      final cooking = CookingRepository(store, inventory);
      final journal = JournalRepository(store);
      final session = await cooking.start(householdId: hid, uid: uid, recipe: curatedById['red-lentil-dal']!, servings: 4);
      expect(session.consumptions, isNotEmpty);

      final confirmed = session.consumptions
          .map((c) => c.productId == 'garlic' ? c.copyWith(actual: const Quantity(4, Unit.piece)) : c)
          .toList();
      final result = await cooking.confirmIngredients(session, confirmed);
      expect(result.discrepancies, isNotEmpty, reason: 'stock for spinach, rice etc. was never recorded');
      final again = await cooking.confirmIngredients(session, confirmed);
      expect(again.alreadyApplied, isTrue);

      final lentils = (await inventory.lotsForProduct(hid, 'lentils')).single;
      expect(lentils.quantity.amount, 300);
      final garlic = (await inventory.lotsForProduct(hid, 'garlic')).single;
      expect(garlic.quantity.amount, 6, reason: 'user-confirmed actual amount wins over the plan');

      await cooking.complete((await cooking.get(hid, session.id))!,
          portionsEaten: 1, leftoverPortions: 2, rating: 5, mealType: MealType.dinner);
      final meals = await journal.range(uid, DateTime.utc(2000), DateTime.utc(2100));
      expect(meals.single.title, 'Red lentil & coconut dal');
      final leftovers = await inventory.lotsForProduct(hid, 'leftover_red-lentil-dal');
      expect(leftovers.single.quantity, const Quantity(2, Unit.piece));
      expect(leftovers.single.estimatedBestBefore, isNotNull);
    });
  });

  group('Planning', () {
    test('shopping list adds only what the plan is missing, merged by product', () async {
      final planning = PlanningRepository(store);
      final today = CalendarDate.fromDateTime(DateTime.now());
      await planning.assign(householdId: hid, uid: uid, date: today, mealType: MealType.breakfast, recipe: curatedById['soft-scrambled-eggs']!, portions: 2);
      await planning.assign(householdId: hid, uid: uid, date: today.addDays(1), mealType: MealType.breakfast, recipe: curatedById['spinach-feta-omelette']!, portions: 1);
      final entries = await planning.range(hid, today, today.addDays(7));
      expect(entries, hasLength(2));
      final eggLot = InventoryLot(
        id: 'e', householdId: hid, productId: 'egg', productName: 'Eggs', category: FoodCategory.dairy,
        quantity: const Quantity(4, Unit.piece), initialQuantity: const Quantity(12, Unit.piece), locationId: 'fridge',
        acquiredAt: DateTime.utc(2026), source: LotSource.manual, provenance: const Provenance(source: ProvenanceSource.user), updatedAt: DateTime.utc(2026),
      );
      await planning.addMissingForPlan(householdId: hid, entries: entries, lots: [eggLot], recipeOf: (e) => curatedById[e.recipeId]);
      final items = await planning.watchShopping(hid).first;
      final eggs = items.singleWhere((i) => i.productId == 'egg');
      expect(eggs.quantity, const Quantity(5, Unit.piece), reason: '6 + 3 needed, 4 on hand');
      expect(eggs.forRecipeTitles, hasLength(2));
    });
  });

  group('Professional sharing', () {
    test('grants are scoped, audited and revocable', () async {
      final sharing = SharingRepository(store);
      final health = HealthRepository(store);
      const pro = ProfessionalProfile(
        uid: 'pro1', displayName: 'Dr. Lee', kind: ProfessionalKind.dietitian, regulatoryBody: 'CDO',
        registrationNumber: '123', province: 'ON', status: VerificationStatus.verified,
      );
      await health.addGlucose(uid: uid, value: 5.4, unit: GlucoseUnit.mmolL, measuredAt: DateTime.now());
      final grant = await sharing.grant(
        ownerUid: uid, ownerName: 'Ava', professional: pro, categories: [ShareCategory.glucose],
        rangeStart: DateTime.now().subtract(const Duration(days: 30)), duration: const Duration(days: 30),
      );
      expect(grant.id, shareGrantId(uid, 'pro1'));
      expect((await sharing.readClientCategory(grant, ShareCategory.glucose, viewerUid: 'pro1')), hasLength(1));
      expect(() => sharing.readClientCategory(grant, ShareCategory.journal, viewerUid: 'pro1'), throwsStateError);
      expect(() => sharing.readClientCategory(grant, ShareCategory.glucose, viewerUid: 'someone-else'), throwsStateError);

      await sharing.revoke(grant);
      final revoked = await sharing.watchGrant(grant.id).first;
      expect(revoked!.status, GrantStatus.revoked);
      expect(() => sharing.readClientCategory(revoked, ShareCategory.glucose, viewerUid: 'pro1'), throwsStateError);
      final audit = await store.query(UserPaths(uid).audit);
      expect(audit.map((d) => d.data['action']), containsAll(['share.granted', 'share.revoked']));
    });

    test('unverified professionals cannot be granted access', () {
      final sharing = SharingRepository(store);
      const pro = ProfessionalProfile(
        uid: 'p', displayName: 'X', kind: ProfessionalKind.dentist, regulatoryBody: '', registrationNumber: '',
        province: 'ON', status: VerificationStatus.pending,
      );
      expect(
        () => sharing.grant(ownerUid: uid, ownerName: 'A', professional: pro, categories: [ShareCategory.oral], rangeStart: DateTime.now(), duration: const Duration(days: 1)),
        throwsStateError,
      );
    });
  });

  test('glucose validation catches implausible values and converts units', () async {
    final health = HealthRepository(store);
    expect(GlucoseEntry.validate(540, GlucoseUnit.mmolL), isNotNull);
    final e = await health.addGlucose(uid: uid, value: 108, unit: GlucoseUnit.mgdL, measuredAt: DateTime.now());
    expect(e.valueMmolL, closeTo(5.99, 0.01));
    expect(() => health.addGlucose(uid: uid, value: -1, unit: GlucoseUnit.mmolL, measuredAt: DateTime.now()), throwsArgumentError);
  });

  test('memory store persists and restores timestamps', () async {
    await store.set('a/b', {'t': DateTime.utc(2026, 1, 2), 'n': 1});
    final copy = MemoryDocStore()..importJson(store.exportJson());
    expect((await copy.get('a/b'))!.data['t'], DateTime.utc(2026, 1, 2));
  });
}
