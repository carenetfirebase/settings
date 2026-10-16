import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/services/analytics.dart';
import '../data/ai/ai_gateway.dart';
import '../data/errors.dart';
import '../data/repositories/inventory_repository.dart';
import '../data/repositories/receipt_repository.dart';
import '../domain/catalog/catalog.dart';
import '../domain/inventory/inventory_command_parser.dart';
import '../domain/models/codec.dart';
import '../domain/models/inventory.dart';
import '../domain/models/meals.dart';
import '../domain/models/planning.dart';
import '../domain/models/receipt.dart';
import '../domain/models/recipe.dart';
import '../domain/units/units.dart';
import 'providers.dart';

class NotSignedInException implements Exception, CodedError {
  @override
  AppErrorCode get code => AppErrorCode.notSignedIn;
  @override
  Map<String, Object?> get args => const {};
  @override
  String toString() => 'Please sign in to continue.';
}

class ReceiptPage {
  const ReceiptPage(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;
}

class DuplicateReceiptException implements Exception, CodedError {
  DuplicateReceiptException(this.existing);
  final PurchaseReceipt existing;
  @override
  AppErrorCode get code => AppErrorCode.receiptDuplicate;
  @override
  Map<String, Object?> get args => const {};
  @override
  String toString() => 'This receipt looks like one you already scanned.';
}

/// Every user-initiated mutation goes through here: it binds the signed-in
/// user and household, mints idempotency keys and logs privacy-safe events.
class AppActions {
  AppActions(this.ref);

  final Ref ref;
  static const _uuid = Uuid();

  String get uid => ref.read(uidProvider) ?? (throw NotSignedInException());
  String get hid => ref.read(householdIdProvider) ?? (throw NotSignedInException());
  Analytics get _analytics => ref.read(analyticsProvider);
  InventoryRepository get _inv => ref.read(inventoryRepoProvider);

  /// New idempotency key. UI keeps one per pending action so a double tap
  /// or retry reuses it.
  static String newOpId([String prefix = 'op']) => '${prefix}_${_uuid.v4()}';

  // -------------------------------------------------------------- inventory

  static InventoryException _notRecorded(FoodProduct p) =>
      InventoryException('No ${p.name} recorded in your kitchen.', code: AppErrorCode.inventoryProductNotRecorded, args: {'product': p.name});

  Future<OperationResult> applyCommand(InventoryCommand c, {required String opId}) async {
    final p = c.product!;
    _analytics.log(AnalyticsEvents.voiceCommand, {'kind': c.action.name});
    switch (c.action) {
      case InventoryCommandAction.add:
        return addManual(product: p, quantity: c.quantity!, opId: opId);
      case InventoryCommandAction.consume:
      case InventoryCommandAction.discard:
        if (c.quantity == null) {
          // "threw out the spinach": discard everything recorded for it.
          final lots = await _inv.lotsForProduct(hid, p.id);
          if (lots.isEmpty) throw _notRecorded(p);
          return _inv.consume(
            householdId: hid,
            operationId: opId,
            actorUid: uid,
            kind: c.action == InventoryCommandAction.discard ? OperationKind.discard : OperationKind.consume,
            reason: c.action == InventoryCommandAction.discard ? 'Discarded' : 'Used', // l10n-ignore: stored record text, written without a locale
            requests: [for (final l in lots) ConsumeRequest(productId: p.id, productName: p.name, quantity: l.quantity, lotId: l.id)],
          );
        }
        return consume(product: p, quantity: c.quantity!, opId: opId, discard: c.action == InventoryCommandAction.discard);
      case InventoryCommandAction.markEmpty:
        final lots = await _inv.lotsForProduct(hid, p.id);
        if (lots.isEmpty) throw _notRecorded(p);
        return _inv.consume(
          householdId: hid,
          operationId: opId,
          actorUid: uid,
          reason: 'Marked empty', // l10n-ignore: stored record text, written without a locale
          summary: '${p.name} marked empty', // l10n-ignore: stored record text, written without a locale
          requests: [for (final l in lots) ConsumeRequest(productId: p.id, productName: p.name, quantity: l.quantity, lotId: l.id)],
        );
      case InventoryCommandAction.setCount:
        final lots = await _inv.lotsForProduct(hid, p.id);
        if (lots.isEmpty) return addManual(product: p, quantity: c.quantity!, opId: opId);
        // Put the verified total on the newest lot, zero the rest.
        lots.sort((a, b) => b.acquiredAt.compareTo(a.acquiredAt));
        return _inv.correctCount(
          householdId: hid,
          operationId: opId,
          actorUid: uid,
          newQuantities: {
            for (var i = 0; i < lots.length; i++)
              lots[i].id: i == 0
                  ? (c.quantity!.tryConvert(lots[i].quantity.unit, p.bridge)?.quantity ?? lots[i].quantity)
                  : Quantity(0, lots[i].quantity.unit),
          },
        );
    }
  }

  Future<OperationResult> addManual({
    required FoodProduct product,
    required Quantity quantity,
    required String opId,
    String? locationId,
    CalendarDate? useBy,
    LotSource source = LotSource.manual,
    String? packageDescription,
  }) {
    _analytics.log(AnalyticsEvents.inventoryAdjusted, {'kind': 'add', 'source': source.name});
    return _inv.addLots(
      householdId: hid,
      operationId: opId,
      actorUid: uid,
      inputs: [
        NewLotInput(
          product: product,
          quantity: quantity,
          locationId: locationId ?? product.defaultStorage.name,
          source: source,
          provenance: const Provenance(source: ProvenanceSource.user),
          useByDate: useBy,
          packageDescription: packageDescription,
        ),
      ],
    );
  }

  Future<OperationResult> consume({required FoodProduct product, required Quantity quantity, required String opId, String? lotId, bool discard = false}) {
    _analytics.log(AnalyticsEvents.inventoryAdjusted, {'kind': discard ? 'discard' : 'consume'});
    return _inv.consume(
      householdId: hid,
      operationId: opId,
      actorUid: uid,
      kind: discard ? OperationKind.discard : OperationKind.consume,
      reason: discard ? 'Discarded' : 'Used', // l10n-ignore: stored record text, written without a locale
      requests: [ConsumeRequest(productId: product.id, productName: product.name, quantity: quantity, lotId: lotId, bridge: product.bridge)],
    );
  }

  /// Uses from one specific lot (the minus button on an item).
  Future<OperationResult> useFromLot(InventoryLot lot, Quantity quantity, {required String opId, bool discard = false}) {
    _analytics.log(AnalyticsEvents.inventoryAdjusted, {'kind': discard ? 'discard' : 'consume', 'source': 'lot'});
    return _inv.consume(
      householdId: hid,
      operationId: opId,
      actorUid: uid,
      kind: discard ? OperationKind.discard : OperationKind.consume,
      reason: discard ? 'Discarded' : 'Used', // l10n-ignore: stored record text, written without a locale
      requests: [ConsumeRequest(productId: lot.productId, productName: lot.productName, quantity: quantity, lotId: lot.id)],
    );
  }

  Future<OperationResult> markEmpty(InventoryLot lot, {required String opId, bool discarded = false}) {
    _analytics.log(AnalyticsEvents.inventoryAdjusted, {'kind': discarded ? 'discard' : 'empty'});
    return _inv.markEmpty(householdId: hid, operationId: opId, actorUid: uid, lotId: lot.id, discarded: discarded);
  }

  Future<OperationResult> correct(Map<String, Quantity> counts, {required String opId}) {
    _analytics.log(AnalyticsEvents.inventoryAdjusted, {'kind': 'correction', 'count': counts.length});
    return _inv.correctCount(householdId: hid, operationId: opId, actorUid: uid, newQuantities: counts);
  }

  Future<OperationResult> move(InventoryLot lot, StorageLocation to, {required String opId}) =>
      _inv.moveLot(householdId: hid, operationId: opId, actorUid: uid, lotId: lot.id, toLocationId: to.id, toLocationName: to.name);

  Future<OperationResult> undo(String operationId) {
    _analytics.log(AnalyticsEvents.inventoryUndo);
    return _inv.undo(householdId: hid, targetOperationId: operationId, actorUid: uid);
  }

  /// Onboarding "Start with example ingredients". Clearly sourced as demo.
  Future<OperationResult> seedExampleKitchen() {
    const picks = <(String, double, Unit, String)>[
      ('egg', 10, Unit.piece, 'fridge'),
      ('milk', 1500, Unit.ml, 'fridge'),
      ('butter', 200, Unit.g, 'fridge'),
      ('greek_yogurt', 500, Unit.g, 'fridge'),
      ('parmesan', 120, Unit.g, 'fridge'),
      ('spinach', 142, Unit.g, 'fridge'),
      ('lemon', 3, Unit.piece, 'fridge'),
      ('bell_pepper', 2, Unit.piece, 'fridge'),
      ('salmon', 300, Unit.g, 'fridge'),
      ('onion', 4, Unit.piece, 'pantry'),
      ('garlic', 10, Unit.piece, 'pantry'),
      ('avocado', 2, Unit.piece, 'pantry'),
      ('pasta', 500, Unit.g, 'pantry'),
      ('crushed_tomato', 796, Unit.ml, 'pantry'),
      ('rice', 900, Unit.g, 'pantry'),
      ('lentils', 450, Unit.g, 'pantry'),
      ('coconut_milk', 400, Unit.ml, 'pantry'),
      ('olive_oil', 500, Unit.ml, 'pantry'),
      ('oats', 1000, Unit.g, 'pantry'),
      ('salt', 500, Unit.g, 'pantry'),
      ('cumin', 40, Unit.g, 'pantry'),
      ('bread', 680, Unit.g, 'pantry'),
      ('peas', 750, Unit.g, 'freezer'),
      ('shrimp', 400, Unit.g, 'freezer'),
    ];
    return _inv.addLots(
      householdId: hid,
      operationId: 'example_kitchen_$hid',
      actorUid: uid,
      kind: OperationKind.manualAdd,
      summary: 'Added example ingredients', // l10n-ignore: stored record text, written without a locale
      inputs: [
        for (final (id, amount, unit, loc) in picks)
          NewLotInput(
            product: catalogById[id]!.product,
            quantity: Quantity(amount, unit),
            locationId: loc,
            source: LotSource.demo,
            provenance: const Provenance(source: ProvenanceSource.demo, confidence: 0.9),
          ),
      ],
    );
  }

  // -------------------------------------------------------------- receipts

  /// Validates, de-duplicates, uploads and starts server extraction.
  /// Returns the receipt id; progress arrives on the receipt document.
  Future<String> submitReceipt(List<ReceiptPage> pages, {bool allowDuplicate = false}) async {
    if (pages.isEmpty) throw ReceiptValidationException('Add at least one photo.', code: AppErrorCode.receiptNoPhotos);
    if (pages.length > ReceiptImageRules.maxPages) {
      throw ReceiptValidationException('Up to ${ReceiptImageRules.maxPages} pages per receipt.',
          code: AppErrorCode.receiptTooManyPages, args: {'max': ReceiptImageRules.maxPages});
    }
    for (final p in pages) {
      final err = ReceiptImageRules.validate(p.bytes, p.mimeType);
      if (err != null) throw ReceiptValidationException(err, code: ReceiptImageRules.check(p.bytes, p.mimeType));
    }
    final repo = ref.read(receiptRepoProvider);
    final hashes = pages.map((p) => ReceiptImageRules.hash(p.bytes)).toList();
    if (!allowDuplicate) {
      for (final h in hashes) {
        final existing = await repo.findByImageHash(hid, h);
        if (existing != null) throw DuplicateReceiptException(existing);
      }
    }
    final household = hid;
    final id = await repo.createJob(householdId: household, uid: uid, imageHashes: hashes);
    _analytics.log(AnalyticsEvents.receiptCaptured, {'count': pages.length});
    final uploader = ref.read(imageUploaderProvider);
    final paths = <String>[];
    try {
      for (var i = 0; i < pages.length; i++) {
        paths.add(await uploader.uploadReceiptPage(
          householdId: household,
          receiptId: id,
          page: i,
          bytes: pages[i].bytes,
          contentType: pages[i].mimeType,
        ));
      }
      await repo.markUploaded(household, id, paths);
    } catch (e) {
      await repo.markFailed(household, id, 'upload_failed', 'We couldn\'t upload the photo. Check your connection and try again.'); // l10n-ignore: stored record text, written without a locale
      rethrow;
    }
    unawaited(_process(household, id));
    return id;
  }

  Future<void> _process(String household, String id) async {
    try {
      await ref.read(aiGatewayProvider).processReceipt(householdId: household, receiptId: id);
    } on AiUnavailableException catch (e) {
      _analytics.log(AnalyticsEvents.receiptFailed, {'error_code': e.retryable ? 'unavailable' : 'rejected'});
      await ref.read(receiptRepoProvider).markFailed(household, id, e.retryable ? 'unavailable' : 'rejected', e.message);
    } catch (_) {
      _analytics.log(AnalyticsEvents.receiptFailed, {'error_code': 'unknown'});
      await ref.read(receiptRepoProvider).markFailed(household, id, 'unknown', 'Something went wrong reading this receipt.'); // l10n-ignore: stored record text, written without a locale
    }
  }

  Future<void> retryReceipt(String id) async {
    await ref.read(receiptRepoProvider).writeExtraction(hid, id, {'status': ReceiptStatus.uploaded.name});
    // writeExtraction refuses terminal states; failed receipts are reset explicitly.
    await ref.read(docStoreProvider).set('households/$hid/receipts/$id', {'status': ReceiptStatus.uploaded.name, 'errorCode': null, 'errorMessage': null}, merge: true);
    unawaited(_process(hid, id));
  }

  Future<OperationResult> confirmReceipt(PurchaseReceipt r) async {
    final locations = {for (final l in ref.read(storageLocationsProvider)) l.kind: l.id};
    final result = await ref.read(receiptImportProvider).confirm(receipt: r, uid: uid, locationIds: locations);
    _analytics.log(AnalyticsEvents.receiptImported, {
      'item_count_bucket': countBucket(result.operation.lotIdsCreated.length),
      'has_demo': r.isDemo,
    });
    await ref.read(profileRepoProvider).addNotification(
          uid,
          AppNotification(
            id: 'receipt_${r.id}',
            kind: NotificationKind.receipt,
            title: 'Receipt added to your kitchen', // l10n-ignore: stored record text, written without a locale
            body: result.operation.summary,
            createdAt: DateTime.now().toUtc(),
            route: '/receipt/${r.id}/done',
          ),
        );
    return result;
  }

  // -------------------------------------------------------------- cooking

  Future<CookingSession> startCooking(Recipe recipe, int servings, {String? mealPlanEntryId}) async {
    _analytics.log(AnalyticsEvents.cookingStarted, {'source': recipe.origin.name});
    return ref.read(cookingRepoProvider).start(householdId: hid, uid: uid, recipe: recipe, servings: servings, mealPlanEntryId: mealPlanEntryId);
  }

  Future<OperationResult> confirmCooking(CookingSession s, List<IngredientConsumption> confirmed) =>
      ref.read(cookingRepoProvider).confirmIngredients(s, confirmed);

  Future<void> completeCooking(CookingSession s, {required double portionsEaten, required int leftoverPortions, int? rating, required MealType mealType}) async {
    await ref.read(cookingRepoProvider).complete(s, portionsEaten: portionsEaten, leftoverPortions: leftoverPortions, rating: rating, mealType: mealType);
    _analytics.log(AnalyticsEvents.cookingCompleted, {'meal_type': mealType.name});
  }

  // -------------------------------------------------------------- shopping

  /// Moves checked shopping items into inventory as one operation.
  Future<OperationResult?> addCheckedToKitchen(List<ShoppingItem> checked, {required String opId}) async {
    final inputs = <NewLotInput>[];
    for (final i in checked) {
      if (i.quantity == null) continue;
      final product = (i.productId == null ? null : catalogById[i.productId]?.product) ??
          FoodProduct(id: i.productId ?? 'p_${i.id}', name: i.name, category: i.category, defaultUnit: i.quantity!.unit);
      inputs.add(NewLotInput(
        product: product,
        quantity: i.quantity!,
        locationId: product.defaultStorage.name,
        source: LotSource.manual,
        provenance: const Provenance(source: ProvenanceSource.user, confidence: 0.9),
      ));
    }
    if (inputs.isEmpty) return null;
    final result = await _inv.addLots(
      householdId: hid,
      operationId: opId,
      actorUid: uid,
      inputs: inputs,
      summary: 'Added ${inputs.length} item${inputs.length == 1 ? '' : 's'} from your shopping list', // l10n-ignore: stored record text, written without a locale
    );
    await ref.read(planningRepoProvider).clearChecked(hid, checked);
    return result;
  }
}

final actionsProvider = Provider<AppActions>((ref) => AppActions(ref));
