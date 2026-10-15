import '../../domain/inventory/consumption_planner.dart';
import '../../domain/models/codec.dart';
import '../../domain/models/inventory.dart';
import '../../domain/units/units.dart';
import '../paths.dart';
import '../store/doc_store.dart';

class NewLotInput {
  const NewLotInput({
    required this.product,
    required this.quantity,
    required this.locationId,
    required this.source,
    required this.provenance,
    this.useByDate,
    this.estimatedBestBefore,
    this.packageDescription,
    this.receiptId,
    this.preparedFromRecipeId,
    this.needsReview = false,
  });

  /// The catalogue product. Created in the same transaction if new.
  final FoodProduct product;
  final Quantity quantity;
  final String locationId;
  final LotSource source;
  final Provenance provenance;
  final CalendarDate? useByDate;
  final CalendarDate? estimatedBestBefore;
  final String? packageDescription;
  final String? receiptId;
  final String? preparedFromRecipeId;
  final bool needsReview;
}

class ConsumeRequest {
  const ConsumeRequest({
    required this.productId,
    required this.productName,
    required this.quantity,
    this.lotId,
    this.bridge = UnitBridge.none,
  });

  final String productId;
  final String productName;
  final Quantity quantity;

  /// Draw from this lot first (e.g. the one the user tapped).
  final String? lotId;
  final UnitBridge bridge;
}

class OperationResult {
  const OperationResult(this.operation, {required this.alreadyApplied});

  final InventoryOperation operation;

  /// True when the idempotency key had already been processed (a retry or a
  /// double tap) and nothing was changed this time.
  final bool alreadyApplied;

  List<String> get discrepancies => operation.discrepancies;
}

class InventoryException implements Exception {
  InventoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Authoritative inventory mutations.
///
/// Every mutation:
///  * is keyed by an idempotency key (the operation id) so retries, double
///    taps and network replays never double-apply;
///  * runs in a single atomic transaction;
///  * writes immutable [InventoryAdjustment] ledger entries alongside the lot
///    projection, so any change can be audited and undone;
///  * never drives a lot below zero — excess is recorded as a discrepancy.
class InventoryRepository {
  InventoryRepository(this._store, {DateTime Function()? clock, this.planner = const ConsumptionPlanner()})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  final DocStore _store;
  final DateTime Function() _clock;
  final ConsumptionPlanner planner;

  // ---------------------------------------------------------------- reads

  Stream<List<InventoryLot>> watchLots(String householdId, {bool includeDepleted = false}) {
    final p = HouseholdPaths(householdId);
    final spec = includeDepleted
        ? QuerySpec.all
        : const QuerySpec(where: [Where.eq('depleted', false)]);
    return _store
        .watchQuery(p.lots, spec)
        .map((docs) => docs.map((d) => InventoryLot.fromMap(d.id, d.data)).toList());
  }

  Future<List<InventoryLot>> lotsForProduct(String householdId, String productId) async {
    final docs = await _store.query(
      HouseholdPaths(householdId).lots,
      QuerySpec(where: [Where.eq('productId', productId), const Where.eq('depleted', false)]),
    );
    return docs.map((d) => InventoryLot.fromMap(d.id, d.data)).toList();
  }

  Future<List<InventoryLot>> activeLots(String householdId) async {
    final docs = await _store.query(
      HouseholdPaths(householdId).lots,
      const QuerySpec(where: [Where.eq('depleted', false)]),
    );
    return docs.map((d) => InventoryLot.fromMap(d.id, d.data)).toList();
  }

  Stream<InventoryLot?> watchLot(String householdId, String lotId) => _store
      .watch(HouseholdPaths(householdId).lot(lotId))
      .map((d) => d == null ? null : InventoryLot.fromMap(d.id, d.data));

  Stream<List<InventoryAdjustment>> watchAdjustmentsForProduct(String householdId, String productId,
          {int limit = 50}) =>
      _store
          .watchQuery(
            HouseholdPaths(householdId).adjustments,
            QuerySpec(where: [Where.eq('productId', productId)], orderBy: 'createdAt', descending: true, limit: limit),
          )
          .map((docs) => docs.map((d) => InventoryAdjustment.fromMap(d.id, d.data)).toList());

  Stream<List<InventoryOperation>> watchRecentOperations(String householdId, {int limit = 20}) => _store
      .watchQuery(
        HouseholdPaths(householdId).operations,
        QuerySpec(orderBy: 'createdAt', descending: true, limit: limit),
      )
      .map((docs) => docs.map((d) => InventoryOperation.fromMap(d.id, d.data)).toList());

  Stream<List<FoodProduct>> watchProducts(String householdId) => _store
      .watchQuery(HouseholdPaths(householdId).products, const QuerySpec(orderBy: 'nameLower'))
      .map((docs) => docs.map((d) => FoodProduct.fromMap(d.id, d.data)).toList());

  // ---------------------------------------------------------------- locations

  /// The three built-in places plus any the household added, in display order.
  Stream<List<StorageLocation>> watchLocations(String householdId) => _store
      .watchQuery(HouseholdPaths(householdId).locations)
      .map((docs) => mergeLocations(docs.map((d) => StorageLocation.fromMap(d.id, d.data))));

  static List<StorageLocation> mergeLocations(Iterable<StorageLocation> custom) {
    final byId = {for (final l in StorageLocation.defaults) l.id: l};
    for (final l in custom) {
      if (!byId.containsKey(l.id)) byId[l.id] = l;
    }
    return byId.values.toList()..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.name.compareTo(b.name));
  }

  /// Adds a named place such as "Garage freezer". [kind] drives freshness
  /// estimates and FIFO (freezer stock is used last).
  Future<StorageLocation> addLocation(String householdId, {required String name, required StorageKind kind}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 30) throw InventoryException('Give the place a name of up to 30 characters.');
    final existing = await _store.query(HouseholdPaths(householdId).locations);
    final all = mergeLocations(existing.map((d) => StorageLocation.fromMap(d.id, d.data)));
    if (all.any((l) => l.name.toLowerCase() == trimmed.toLowerCase())) throw InventoryException('You already have a place called $trimmed.');
    if (all.length >= 12) throw InventoryException('You can have up to 12 places.');
    final slug = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    var id = 'loc_${slug.isEmpty ? 'place' : slug}';
    for (var n = 2; all.any((l) => l.id == id); n++) {
      id = 'loc_${slug}_$n';
    }
    final location = StorageLocation(id: id, name: trimmed, kind: kind, sortOrder: 10 + existing.length);
    await _store.set('${HouseholdPaths(householdId).locations}/$id', location.toMap());
    return location;
  }

  Future<void> renameLocation(String householdId, StorageLocation location, String name) async {
    if (StorageLocation.defaults.any((d) => d.id == location.id)) throw InventoryException('The built-in places can\'t be renamed.');
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 30) throw InventoryException('Give the place a name of up to 30 characters.');
    await _store.set('${HouseholdPaths(householdId).locations}/${location.id}', {'name': trimmed}, merge: true);
  }

  /// Removes a custom place. Refuses while anything is still stored there, so
  /// no stock is ever orphaned.
  Future<void> removeLocation(String householdId, String locationId) async {
    if (StorageLocation.defaults.any((d) => d.id == locationId)) throw InventoryException('The built-in places can\'t be removed.');
    final p = HouseholdPaths(householdId);
    final inUse = await _store.query(p.lots, QuerySpec(where: [const Where.eq('depleted', false), Where.eq('locationId', locationId)], limit: 1));
    if (inUse.isNotEmpty) throw InventoryException('Move or use up what\'s stored there first.');
    await _store.delete('${p.locations}/$locationId');
  }

  Future<List<FoodProduct>> products(String householdId) async {
    final docs = await _store.query(HouseholdPaths(householdId).products);
    return docs.map((d) => FoodProduct.fromMap(d.id, d.data)).toList();
  }

  Future<FoodProduct?> product(String householdId, String productId) async {
    final d = await _store.get(HouseholdPaths(householdId).product(productId));
    return d == null ? null : FoodProduct.fromMap(d.id, d.data);
  }

  Future<void> saveProduct(String householdId, FoodProduct product) =>
      _store.set(HouseholdPaths(householdId).product(product.id), product.toMap());

  // ------------------------------------------------------------ mutations

  /// Adds new lots (receipt import, manual add, scan, leftovers).
  Future<OperationResult> addLots({
    required String householdId,
    required String operationId,
    required String actorUid,
    required List<NewLotInput> inputs,
    OperationKind kind = OperationKind.manualAdd,
    String? summary,
  }) {
    if (inputs.isEmpty) throw InventoryException('Nothing to add.');
    for (final i in inputs) {
      if (i.quantity.isNegative || i.quantity.isZero) {
        throw InventoryException('${i.product.name}: quantity must be greater than zero.');
      }
    }
    final p = HouseholdPaths(householdId);
    return _store.transaction((tx) async {
      final existing = await tx.get(p.operation(operationId));
      if (existing != null) {
        return OperationResult(InventoryOperation.fromMap(existing.id, existing.data), alreadyApplied: true);
      }
      final productIds = inputs.map((i) => i.product.id).toSet();
      final missingProducts = <String>{};
      for (final id in productIds) {
        if (await tx.get(p.product(id)) == null) missingProducts.add(id);
      }

      final now = _clock();
      final lotIds = <String>[];
      final adjIds = <String>[];
      for (var i = 0; i < inputs.length; i++) {
        final input = inputs[i];
        if (missingProducts.remove(input.product.id)) {
          tx.set(p.product(input.product.id), input.product.toMap());
        }
        final lotId = '${operationId}_l$i';
        final adjId = '${operationId}_a$i';
        final lot = InventoryLot(
          id: lotId,
          householdId: householdId,
          productId: input.product.id,
          productName: input.product.name,
          category: input.product.category,
          quantity: input.quantity,
          initialQuantity: input.quantity,
          locationId: input.locationId,
          acquiredAt: now,
          source: input.source,
          provenance: input.provenance,
          updatedAt: now,
          packageDescription: input.packageDescription,
          useByDate: input.useByDate,
          estimatedBestBefore: input.estimatedBestBefore ??
              (input.product.typicalShelfLifeDays == null
                  ? null
                  : CalendarDate.fromDateTime(now.toLocal()).addDays(input.product.typicalShelfLifeDays!)),
          needsReview: input.needsReview,
          receiptId: input.receiptId,
          preparedFromRecipeId: input.preparedFromRecipeId,
        );
        tx.set(p.lot(lotId), lot.toMap());
        tx.set(
          p.adjustment(adjId),
          InventoryAdjustment(
            id: adjId,
            householdId: householdId,
            operationId: operationId,
            lotId: lotId,
            productId: input.product.id,
            productName: input.product.name,
            type: AdjustmentType.intake,
            delta: input.quantity,
            quantityBefore: Quantity(0, input.quantity.unit),
            quantityAfter: input.quantity,
            createdAt: now,
            createdBy: actorUid,
            reason: input.source.name,
          ).toMap(),
        );
        lotIds.add(lotId);
        adjIds.add(adjId);
      }
      final op = InventoryOperation(
        id: operationId,
        householdId: householdId,
        kind: kind,
        adjustmentIds: adjIds,
        lotIdsCreated: lotIds,
        createdAt: now,
        createdBy: actorUid,
        summary: summary ??
            (inputs.length == 1
                ? 'Added ${inputs.first.quantity.format()} ${inputs.first.product.name}'
                : 'Added ${inputs.length} items'),
      );
      tx.set(p.operation(operationId), op.toMap());
      return OperationResult(op, alreadyApplied: false);
    });
  }

  /// Deducts stock for one or more products (cooking, "I used two eggs",
  /// discarding). One call = one atomic, idempotent operation.
  Future<OperationResult> consume({
    required String householdId,
    required String operationId,
    required String actorUid,
    required List<ConsumeRequest> requests,
    OperationKind kind = OperationKind.consume,
    String? reason,
    String? summary,
  }) async {
    if (requests.isEmpty) throw InventoryException('Nothing to deduct.');
    final p = HouseholdPaths(householdId);
    // Queries cannot run inside client transactions; find candidates first,
    // then re-read each lot transactionally so we act on fresh values.
    final candidateIds = <String, List<String>>{};
    for (final r in requests) {
      final lots = await lotsForProduct(householdId, r.productId);
      candidateIds[r.productId] = lots.map((l) => l.id).toList();
      if (r.lotId != null && !candidateIds[r.productId]!.contains(r.lotId)) {
        candidateIds[r.productId]!.add(r.lotId!);
      }
    }
    final type = kind == OperationKind.discard ? AdjustmentType.discard : AdjustmentType.consume;
    // Every freezer-kind place (including "Garage freezer") is used last.
    final freezerIds = {
      'freezer',
      for (final d in await _store.query(p.locations))
        if (StorageLocation.fromMap(d.id, d.data).kind == StorageKind.freezer) d.id,
    };

    return _store.transaction((tx) async {
      final existing = await tx.get(p.operation(operationId));
      if (existing != null) {
        return OperationResult(InventoryOperation.fromMap(existing.id, existing.data), alreadyApplied: true);
      }
      final fresh = <String, InventoryLot>{};
      for (final ids in candidateIds.values) {
        for (final id in ids) {
          if (fresh.containsKey(id)) continue;
          final d = await tx.get(p.lot(id));
          if (d != null) fresh[id] = InventoryLot.fromMap(d.id, d.data);
        }
      }

      final now = _clock();
      final adjIds = <String>[];
      final discrepancies = <String>[];
      final changedLotIds = <String>{};
      var n = 0;
      for (final r in requests) {
        final lots = candidateIds[r.productId]!.map((id) => fresh[id]).whereType<InventoryLot>().toList();
        final plan = planner.plan(lots: lots, requested: r.quantity, bridge: r.bridge, preferLotId: r.lotId, deprioritizedLocationIds: freezerIds);
        for (final a in plan.allocations) {
          final current = fresh[a.lot.id]!;
          final after = current.quantity - a.take;
          final updated = current.copyWith(
            quantity: after.isNegative ? Quantity(0, after.unit) : after,
            updatedAt: now,
            version: current.version + 1,
            provenance: a.isEstimate
                ? Provenance(
                    source: current.provenance.source,
                    confidence: current.provenance.confidence.clamp(0, 0.8),
                    model: current.provenance.model,
                    raw: current.provenance.raw,
                  )
                : null,
          );
          fresh[a.lot.id] = updated;
          changedLotIds.add(current.id);
          final adjId = '${operationId}_a${n++}';
          tx.set(
            p.adjustment(adjId),
            InventoryAdjustment(
              id: adjId,
              householdId: householdId,
              operationId: operationId,
              lotId: current.id,
              productId: current.productId,
              productName: current.productName,
              type: type,
              delta: -a.take,
              quantityBefore: current.quantity,
              quantityAfter: updated.quantity,
              createdAt: now,
              createdBy: actorUid,
              reason: reason,
            ).toMap(),
          );
          adjIds.add(adjId);
        }
        if (!plan.isFullySatisfied) {
          discrepancies.add(plan.allocations.isEmpty
              ? '${r.productName}: no matching stock recorded'
              : '${r.productName}: ${plan.shortfall.format()} more than recorded');
        }
      }
      for (final id in changedLotIds) {
        tx.set(p.lot(id), fresh[id]!.toMap());
      }
      final op = InventoryOperation(
        id: operationId,
        householdId: householdId,
        kind: kind,
        adjustmentIds: adjIds,
        lotIdsCreated: const [],
        createdAt: now,
        createdBy: actorUid,
        summary: summary ?? _consumeSummary(type, requests),
        discrepancies: discrepancies,
      );
      tx.set(p.operation(operationId), op.toMap());
      return OperationResult(op, alreadyApplied: false);
    });
  }

  /// Sets a lot to an exact, user-verified count. Also confirms the lot.
  Future<OperationResult> correctCount({
    required String householdId,
    required String operationId,
    required String actorUid,
    required Map<String, Quantity> newQuantities,
    OperationKind kind = OperationKind.correction,
    String reason = 'Corrected count',
  }) {
    if (newQuantities.isEmpty) throw InventoryException('Nothing to correct.');
    for (final q in newQuantities.values) {
      if (q.isNegative) throw InventoryException('Counts cannot be negative.');
    }
    final p = HouseholdPaths(householdId);
    return _store.transaction((tx) async {
      final existing = await tx.get(p.operation(operationId));
      if (existing != null) {
        return OperationResult(InventoryOperation.fromMap(existing.id, existing.data), alreadyApplied: true);
      }
      final lots = <InventoryLot>[];
      for (final id in newQuantities.keys) {
        final d = await tx.get(p.lot(id));
        if (d == null) throw InventoryException('That item no longer exists.');
        lots.add(InventoryLot.fromMap(d.id, d.data));
      }
      final now = _clock();
      final adjIds = <String>[];
      var n = 0;
      for (final lot in lots) {
        final target = newQuantities[lot.id]!;
        final converted = target.tryConvert(lot.quantity.unit);
        if (converted == null) {
          throw InventoryException('${lot.productName}: use ${lot.quantity.unit.symbol} for this item.');
        }
        final after = converted.quantity;
        final delta = after - lot.quantity;
        final updated = lot.copyWith(
          quantity: after,
          needsReview: false,
          provenance: Provenance(
            source: lot.provenance.source,
            confidence: 1,
            model: lot.provenance.model,
            raw: lot.provenance.raw,
          ),
          updatedAt: now,
          version: lot.version + 1,
        );
        tx.set(p.lot(lot.id), updated.toMap());
        final adjId = '${operationId}_a${n++}';
        tx.set(
          p.adjustment(adjId),
          InventoryAdjustment(
            id: adjId,
            householdId: householdId,
            operationId: operationId,
            lotId: lot.id,
            productId: lot.productId,
            productName: lot.productName,
            type: AdjustmentType.correction,
            delta: delta,
            quantityBefore: lot.quantity,
            quantityAfter: after,
            createdAt: now,
            createdBy: actorUid,
            reason: reason,
          ).toMap(),
        );
        adjIds.add(adjId);
      }
      final op = InventoryOperation(
        id: operationId,
        householdId: householdId,
        kind: kind,
        adjustmentIds: adjIds,
        lotIdsCreated: const [],
        createdAt: now,
        createdBy: actorUid,
        summary: lots.length == 1
            ? '${lots.first.productName}: set to ${newQuantities.values.first.format()}'
            : 'Verified ${lots.length} items',
      );
      tx.set(p.operation(operationId), op.toMap());
      return OperationResult(op, alreadyApplied: false);
    });
  }

  /// Marks a single lot as finished (used up or discarded), whatever its
  /// current recorded amount is. Never touches other lots.
  Future<OperationResult> markEmpty({
    required String householdId,
    required String operationId,
    required String actorUid,
    required String lotId,
    bool discarded = false,
  }) {
    final p = HouseholdPaths(householdId);
    return _store.transaction((tx) async {
      final existing = await tx.get(p.operation(operationId));
      if (existing != null) {
        return OperationResult(InventoryOperation.fromMap(existing.id, existing.data), alreadyApplied: true);
      }
      final d = await tx.get(p.lot(lotId));
      if (d == null) throw InventoryException('That item no longer exists.');
      final lot = InventoryLot.fromMap(d.id, d.data);
      final now = _clock();
      final zero = Quantity(0, lot.quantity.unit);
      tx.set(p.lot(lotId), lot.copyWith(quantity: zero, updatedAt: now, version: lot.version + 1).toMap());
      final adjId = '${operationId}_a0';
      tx.set(
        p.adjustment(adjId),
        InventoryAdjustment(
          id: adjId,
          householdId: householdId,
          operationId: operationId,
          lotId: lotId,
          productId: lot.productId,
          productName: lot.productName,
          type: discarded ? AdjustmentType.discard : AdjustmentType.consume,
          delta: -lot.quantity,
          quantityBefore: lot.quantity,
          quantityAfter: zero,
          createdAt: now,
          createdBy: actorUid,
          reason: discarded ? 'Discarded' : 'Marked empty',
        ).toMap(),
      );
      final op = InventoryOperation(
        id: operationId,
        householdId: householdId,
        kind: discarded ? OperationKind.discard : OperationKind.consume,
        adjustmentIds: [adjId],
        lotIdsCreated: const [],
        createdAt: now,
        createdBy: actorUid,
        summary: discarded ? 'Discarded ${lot.productName}' : '${lot.productName} marked empty',
      );
      tx.set(p.operation(operationId), op.toMap());
      return OperationResult(op, alreadyApplied: false);
    });
  }

  /// Moves a lot between storage locations (no quantity change).
  Future<OperationResult> moveLot({
    required String householdId,
    required String operationId,
    required String actorUid,
    required String lotId,
    required String toLocationId,
    String? toLocationName,
  }) {
    final p = HouseholdPaths(householdId);
    return _store.transaction((tx) async {
      final existing = await tx.get(p.operation(operationId));
      if (existing != null) {
        return OperationResult(InventoryOperation.fromMap(existing.id, existing.data), alreadyApplied: true);
      }
      final d = await tx.get(p.lot(lotId));
      if (d == null) throw InventoryException('That item no longer exists.');
      final lot = InventoryLot.fromMap(d.id, d.data);
      final now = _clock();
      final from = lot.locationId;
      tx.set(p.lot(lotId), lot.copyWith(locationId: toLocationId, updatedAt: now, version: lot.version + 1).toMap());
      final adjId = '${operationId}_a0';
      tx.set(
        p.adjustment(adjId),
        InventoryAdjustment(
          id: adjId,
          householdId: householdId,
          operationId: operationId,
          lotId: lotId,
          productId: lot.productId,
          productName: lot.productName,
          type: AdjustmentType.transferIn,
          delta: Quantity(0, lot.quantity.unit),
          quantityBefore: lot.quantity,
          quantityAfter: lot.quantity,
          createdAt: now,
          createdBy: actorUid,
          reason: 'Moved from $from to $toLocationId',
        ).toMap(),
      );
      final op = InventoryOperation(
        id: operationId,
        householdId: householdId,
        kind: OperationKind.transfer,
        adjustmentIds: [adjId],
        lotIdsCreated: const [],
        createdAt: now,
        createdBy: actorUid,
        summary: 'Moved ${lot.productName} to ${toLocationName ?? toLocationId}',
      );
      tx.set(p.operation(operationId), op.toMap());
      return OperationResult(op, alreadyApplied: false);
    });
  }

  /// Reverses a previous operation by appending inverse ledger entries.
  /// Undoing twice is a no-op. Quantities are clamped at zero if the stock
  /// was used in the meantime, and that is reported as a discrepancy.
  Future<OperationResult> undo({
    required String householdId,
    required String targetOperationId,
    required String actorUid,
  }) {
    final p = HouseholdPaths(householdId);
    final undoId = 'undo_$targetOperationId';
    return _store.transaction((tx) async {
      final existing = await tx.get(p.operation(undoId));
      if (existing != null) {
        return OperationResult(InventoryOperation.fromMap(existing.id, existing.data), alreadyApplied: true);
      }
      final targetDoc = await tx.get(p.operation(targetOperationId));
      if (targetDoc == null) throw InventoryException('Nothing to undo.');
      final target = InventoryOperation.fromMap(targetDoc.id, targetDoc.data);
      if (target.isUndone) {
        throw InventoryException('This change has already been undone.');
      }
      if (target.kind == OperationKind.undo) {
        throw InventoryException('An undo cannot itself be undone.');
      }
      final adjustments = <InventoryAdjustment>[];
      for (final id in target.adjustmentIds) {
        final d = await tx.get(p.adjustment(id));
        if (d != null) adjustments.add(InventoryAdjustment.fromMap(d.id, d.data));
      }
      final lots = <String, InventoryLot>{};
      for (final a in adjustments) {
        if (lots.containsKey(a.lotId)) continue;
        final d = await tx.get(p.lot(a.lotId));
        if (d != null) lots[a.lotId] = InventoryLot.fromMap(d.id, d.data);
      }

      final now = _clock();
      final adjIds = <String>[];
      final discrepancies = <String>[];
      var n = 0;
      for (final a in adjustments.reversed) {
        final lot = lots[a.lotId];
        if (lot == null) continue;
        final isMove = a.type == AdjustmentType.transferIn;
        var after = lot.quantity - a.delta;
        if (after.isNegative) {
          discrepancies.add('${lot.productName}: some was already used, so it was set to zero');
          after = Quantity(0, after.unit);
        }
        var updated = lot.copyWith(quantity: after, updatedAt: now, version: lot.version + 1);
        if (isMove) {
          final from = a.reason?.split(' ').elementAtOrNull(2);
          if (from != null) updated = updated.copyWith(locationId: from);
        }
        lots[a.lotId] = updated;
        final adjId = '${undoId}_a${n++}';
        tx.set(
          p.adjustment(adjId),
          InventoryAdjustment(
            id: adjId,
            householdId: householdId,
            operationId: undoId,
            lotId: lot.id,
            productId: lot.productId,
            productName: lot.productName,
            type: AdjustmentType.reversal,
            delta: after - lot.quantity,
            quantityBefore: lot.quantity,
            quantityAfter: after,
            createdAt: now,
            createdBy: actorUid,
            reason: 'Undo: ${target.summary}',
            reversesAdjustmentId: a.id,
          ).toMap(),
        );
        adjIds.add(adjId);
      }
      for (final lot in lots.values) {
        tx.set(p.lot(lot.id), lot.toMap());
      }
      tx.set(p.operation(targetOperationId), {'undoneByOperationId': undoId}, merge: true);
      final op = InventoryOperation(
        id: undoId,
        householdId: householdId,
        kind: OperationKind.undo,
        adjustmentIds: adjIds,
        lotIdsCreated: const [],
        createdAt: now,
        createdBy: actorUid,
        summary: 'Undid: ${target.summary}',
        undoesOperationId: targetOperationId,
        discrepancies: discrepancies,
      );
      tx.set(p.operation(undoId), op.toMap());
      return OperationResult(op, alreadyApplied: false);
    });
  }

  static String _consumeSummary(AdjustmentType type, List<ConsumeRequest> rs) {
    final verb = type == AdjustmentType.discard ? 'Discarded' : 'Used';
    if (rs.length == 1) return '$verb ${rs.first.quantity.format()} ${rs.first.productName}';
    return '$verb ${rs.length} ingredients';
  }
}
