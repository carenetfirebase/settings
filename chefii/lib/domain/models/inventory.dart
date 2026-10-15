import '../units/units.dart';
import 'codec.dart';

enum FoodCategory {
  produce('Produce'),
  dairy('Dairy & eggs'),
  meat('Meat'),
  seafood('Fish & seafood'),
  bakery('Bakery'),
  grains('Grains & pasta'),
  pantry('Pantry staples'),
  spices('Herbs & spices'),
  condiments('Sauces & condiments'),
  frozen('Frozen'),
  beverages('Beverages'),
  snacks('Snacks'),
  prepared('Prepared & leftovers'),
  other('Other'),
  nonFood('Non-food');

  const FoodCategory(this.label);
  final String label;
}

enum StorageKind {
  fridge('Fridge'),
  freezer('Freezer'),
  pantry('Pantry'),
  custom('Other');

  const StorageKind(this.label);
  final String label;
}

class StorageLocation {
  const StorageLocation({required this.id, required this.name, required this.kind, this.sortOrder = 0});

  final String id;
  final String name;
  final StorageKind kind;
  final int sortOrder;

  static const defaults = [
    StorageLocation(id: 'fridge', name: 'Fridge', kind: StorageKind.fridge, sortOrder: 0),
    StorageLocation(id: 'freezer', name: 'Freezer', kind: StorageKind.freezer, sortOrder: 1),
    StorageLocation(id: 'pantry', name: 'Pantry', kind: StorageKind.pantry, sortOrder: 2),
  ];

  Map<String, dynamic> toMap() => {'name': name, 'kind': kind.name, 'sortOrder': sortOrder};

  static StorageLocation fromMap(String id, Map<String, dynamic> m) => StorageLocation(
        id: id,
        name: readString(m, 'name'),
        kind: readEnum(StorageKind.values, m['kind'], StorageKind.custom),
        sortOrder: readInt(m, 'sortOrder', 0),
      );
}

/// A catalogue entry: what something *is*, independent of how much we have.
class FoodProduct {
  const FoodProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.defaultUnit,
    this.brand,
    this.barcode,
    this.aliases = const [],
    this.bridge = UnitBridge.none,
    this.defaultStorage = StorageKind.pantry,
    this.typicalShelfLifeDays,
    this.nutrientRefId,
    this.allergens = const [],
    this.lowStockThreshold,
  });

  final String id;
  final String name;
  final FoodCategory category;
  final Unit defaultUnit;
  final String? brand;
  final String? barcode;

  /// Alternative names (receipt abbreviations, plurals) used for matching.
  final List<String> aliases;
  final UnitBridge bridge;
  final StorageKind defaultStorage;

  /// Typical days of quality once purchased (estimate, never a safety claim).
  final int? typicalShelfLifeDays;
  final String? nutrientRefId;

  /// Allergen tags (see AllergenGuard), e.g. ['milk'].
  final List<String> allergens;
  final Quantity? lowStockThreshold;

  FoodProduct copyWith({
    String? name,
    FoodCategory? category,
    Unit? defaultUnit,
    String? brand,
    List<String>? aliases,
    StorageKind? defaultStorage,
  }) =>
      FoodProduct(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        defaultUnit: defaultUnit ?? this.defaultUnit,
        brand: brand ?? this.brand,
        barcode: barcode,
        aliases: aliases ?? this.aliases,
        bridge: bridge,
        defaultStorage: defaultStorage ?? this.defaultStorage,
        typicalShelfLifeDays: typicalShelfLifeDays,
        nutrientRefId: nutrientRefId,
        allergens: allergens,
        lowStockThreshold: lowStockThreshold,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'nameLower': name.toLowerCase(),
        'category': category.name,
        'defaultUnit': defaultUnit.name,
        if (brand != null) 'brand': brand,
        if (barcode != null) 'barcode': barcode,
        'aliases': aliases,
        'bridge': bridge.toMap(),
        'defaultStorage': defaultStorage.name,
        if (typicalShelfLifeDays != null) 'typicalShelfLifeDays': typicalShelfLifeDays,
        if (nutrientRefId != null) 'nutrientRefId': nutrientRefId,
        'allergens': allergens,
        if (lowStockThreshold != null) 'lowStockThreshold': lowStockThreshold!.toMap(),
      };

  static FoodProduct fromMap(String id, Map<String, dynamic> m) => FoodProduct(
        id: id,
        name: readString(m, 'name'),
        category: readEnum(FoodCategory.values, m['category'], FoodCategory.other),
        defaultUnit: readEnum(Unit.values, m['defaultUnit'], Unit.piece),
        brand: m['brand'] as String?,
        barcode: m['barcode'] as String?,
        aliases: readStrings(m['aliases']),
        bridge: UnitBridge.fromMap(m['bridge'] == null ? null : readMap(m['bridge'])),
        defaultStorage: readEnum(StorageKind.values, m['defaultStorage'], StorageKind.pantry),
        typicalShelfLifeDays: (m['typicalShelfLifeDays'] as num?)?.toInt(),
        nutrientRefId: m['nutrientRefId'] as String?,
        allergens: readStrings(m['allergens']),
        lowStockThreshold: m['lowStockThreshold'] == null
            ? null
            : Quantity.fromMap(readMap(m['lowStockThreshold'])),
      );
}

enum LotSource { receipt, manual, barcode, scan, correction, transfer, leftover, returned, demo }

/// Displayed inventory states. None of these is a food-safety guarantee.
enum InventoryStatus {
  confirmed('Confirmed'),
  estimated('Estimated'),
  needsReview('Needs review'),
  depleted('Used up'),
  pastRecordedDate('Past recorded date');

  const InventoryStatus(this.label);
  final String label;
}

/// A physical batch of a product: one purchase, one leftover container, etc.
class InventoryLot {
  const InventoryLot({
    required this.id,
    required this.householdId,
    required this.productId,
    required this.productName,
    required this.category,
    required this.quantity,
    required this.initialQuantity,
    required this.locationId,
    required this.acquiredAt,
    required this.source,
    required this.provenance,
    required this.updatedAt,
    this.packageDescription,
    this.useByDate,
    this.estimatedBestBefore,
    this.needsReview = false,
    this.receiptId,
    this.preparedFromRecipeId,
    this.version = 0,
  });

  final String id;
  final String householdId;
  final String productId;
  final String productName;
  final FoodCategory category;
  final Quantity quantity;
  final Quantity initialQuantity;
  final String locationId;
  final DateTime acquiredAt;
  final LotSource source;
  final Provenance provenance;
  final DateTime updatedAt;
  final String? packageDescription;

  /// A date actually printed on / confirmed for the package.
  final CalendarDate? useByDate;

  /// Our estimate of quality, kept separate from confirmed dates.
  final CalendarDate? estimatedBestBefore;
  final bool needsReview;
  final String? receiptId;
  final String? preparedFromRecipeId;

  /// Incremented on every mutation; used for optimistic UI and audit.
  final int version;

  bool get isDepleted => quantity.amount <= Quantity.epsilon;

  InventoryStatus statusOn(CalendarDate today) {
    if (isDepleted) return InventoryStatus.depleted;
    if (useByDate != null && useByDate!.isBefore(today)) return InventoryStatus.pastRecordedDate;
    if (needsReview || provenance.confidence < 0.6) return InventoryStatus.needsReview;
    // Quantities derived from estimates (unconfirmed AI output, density or
    // per-piece conversions) are shown as estimated until the user verifies.
    if (provenance.confidence < 0.95) return InventoryStatus.estimated;
    return InventoryStatus.confirmed;
  }

  /// Days until the confirmed date or (fallback) the estimate. Null if unknown.
  int? daysLeft(CalendarDate today) {
    final d = useByDate ?? estimatedBestBefore;
    return d == null ? null : today.daysUntil(d);
  }

  bool get daysLeftIsEstimate => useByDate == null && estimatedBestBefore != null;

  InventoryLot copyWith({
    Quantity? quantity,
    String? locationId,
    CalendarDate? useByDate,
    bool clearUseBy = false,
    CalendarDate? estimatedBestBefore,
    bool? needsReview,
    Provenance? provenance,
    DateTime? updatedAt,
    String? productName,
    int? version,
  }) =>
      InventoryLot(
        id: id,
        householdId: householdId,
        productId: productId,
        productName: productName ?? this.productName,
        category: category,
        quantity: quantity ?? this.quantity,
        initialQuantity: initialQuantity,
        locationId: locationId ?? this.locationId,
        acquiredAt: acquiredAt,
        source: source,
        provenance: provenance ?? this.provenance,
        updatedAt: updatedAt ?? this.updatedAt,
        packageDescription: packageDescription,
        useByDate: clearUseBy ? null : (useByDate ?? this.useByDate),
        estimatedBestBefore: estimatedBestBefore ?? this.estimatedBestBefore,
        needsReview: needsReview ?? this.needsReview,
        receiptId: receiptId,
        preparedFromRecipeId: preparedFromRecipeId,
        version: version ?? this.version,
      );

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'productId': productId,
        'productName': productName,
        'category': category.name,
        'quantity': quantity.toMap(),
        'initialQuantity': initialQuantity.toMap(),
        'locationId': locationId,
        'acquiredAt': acquiredAt,
        'source': source.name,
        'provenance': provenance.toMap(),
        'updatedAt': updatedAt,
        if (packageDescription != null) 'packageDescription': packageDescription,
        if (useByDate != null) 'useByDate': useByDate!.toIso(),
        if (estimatedBestBefore != null) 'estimatedBestBefore': estimatedBestBefore!.toIso(),
        'needsReview': needsReview,
        'depleted': isDepleted,
        if (receiptId != null) 'receiptId': receiptId,
        if (preparedFromRecipeId != null) 'preparedFromRecipeId': preparedFromRecipeId,
        'version': version,
      };

  static InventoryLot fromMap(String id, Map<String, dynamic> m) => InventoryLot(
        id: id,
        householdId: readString(m, 'householdId'),
        productId: readString(m, 'productId'),
        productName: readString(m, 'productName'),
        category: readEnum(FoodCategory.values, m['category'], FoodCategory.other),
        quantity: Quantity.fromMap(readMap(m['quantity'])),
        initialQuantity: Quantity.fromMap(readMap(m['initialQuantity'] ?? m['quantity'])),
        locationId: readString(m, 'locationId'),
        acquiredAt: readDate(m['acquiredAt']),
        source: readEnum(LotSource.values, m['source'], LotSource.manual),
        provenance: Provenance.fromMap(m['provenance']),
        updatedAt: readDate(m['updatedAt'] ?? m['acquiredAt']),
        packageDescription: m['packageDescription'] as String?,
        useByDate: CalendarDate.tryParse(m['useByDate']),
        estimatedBestBefore: CalendarDate.tryParse(m['estimatedBestBefore']),
        needsReview: m['needsReview'] as bool? ?? false,
        receiptId: m['receiptId'] as String?,
        preparedFromRecipeId: m['preparedFromRecipeId'] as String?,
        version: readInt(m, 'version', 0),
      );
}

enum AdjustmentType {
  intake('Added'),
  consume('Used'),
  discard('Discarded'),
  correction('Corrected'),
  transferOut('Moved out'),
  transferIn('Moved in'),
  reversal('Undone');

  const AdjustmentType(this.label);
  final String label;
}

/// Immutable ledger entry. Lots are a projection of these entries.
class InventoryAdjustment {
  const InventoryAdjustment({
    required this.id,
    required this.householdId,
    required this.operationId,
    required this.lotId,
    required this.productId,
    required this.productName,
    required this.type,
    required this.delta,
    required this.quantityBefore,
    required this.quantityAfter,
    required this.createdAt,
    required this.createdBy,
    this.reason,
    this.reversesAdjustmentId,
  });

  final String id;
  final String householdId;
  final String operationId;
  final String lotId;
  final String productId;
  final String productName;
  final AdjustmentType type;

  /// Signed change in the lot's unit.
  final Quantity delta;
  final Quantity quantityBefore;
  final Quantity quantityAfter;
  final DateTime createdAt;
  final String createdBy;
  final String? reason;
  final String? reversesAdjustmentId;

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'operationId': operationId,
        'lotId': lotId,
        'productId': productId,
        'productName': productName,
        'type': type.name,
        'delta': delta.toMap(),
        'quantityBefore': quantityBefore.toMap(),
        'quantityAfter': quantityAfter.toMap(),
        'createdAt': createdAt,
        'createdBy': createdBy,
        if (reason != null) 'reason': reason,
        if (reversesAdjustmentId != null) 'reversesAdjustmentId': reversesAdjustmentId,
      };

  static InventoryAdjustment fromMap(String id, Map<String, dynamic> m) => InventoryAdjustment(
        id: id,
        householdId: readString(m, 'householdId'),
        operationId: readString(m, 'operationId'),
        lotId: readString(m, 'lotId'),
        productId: readString(m, 'productId'),
        productName: readString(m, 'productName'),
        type: readEnum(AdjustmentType.values, m['type'], AdjustmentType.correction),
        delta: Quantity.fromMap(readMap(m['delta'])),
        quantityBefore: Quantity.fromMap(readMap(m['quantityBefore'])),
        quantityAfter: Quantity.fromMap(readMap(m['quantityAfter'])),
        createdAt: readDate(m['createdAt']),
        createdBy: readString(m, 'createdBy'),
        reason: m['reason'] as String?,
        reversesAdjustmentId: m['reversesAdjustmentId'] as String?,
      );
}

enum OperationKind { receiptImport, manualAdd, consume, discard, correction, transfer, cook, undo, scanImport, leftover }

/// One user-level action (idempotency unit). Its id is the idempotency key.
class InventoryOperation {
  const InventoryOperation({
    required this.id,
    required this.householdId,
    required this.kind,
    required this.adjustmentIds,
    required this.lotIdsCreated,
    required this.createdAt,
    required this.createdBy,
    required this.summary,
    this.undoneByOperationId,
    this.undoesOperationId,
    this.discrepancies = const [],
  });

  final String id;
  final String householdId;
  final OperationKind kind;
  final List<String> adjustmentIds;
  final List<String> lotIdsCreated;
  final DateTime createdAt;
  final String createdBy;
  final String summary;
  final String? undoneByOperationId;
  final String? undoesOperationId;

  /// Human-readable notes where requested amounts exceeded recorded stock.
  final List<String> discrepancies;

  bool get isUndone => undoneByOperationId != null;

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'kind': kind.name,
        'adjustmentIds': adjustmentIds,
        'lotIdsCreated': lotIdsCreated,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'summary': summary,
        if (undoneByOperationId != null) 'undoneByOperationId': undoneByOperationId,
        if (undoesOperationId != null) 'undoesOperationId': undoesOperationId,
        'discrepancies': discrepancies,
      };

  static InventoryOperation fromMap(String id, Map<String, dynamic> m) => InventoryOperation(
        id: id,
        householdId: readString(m, 'householdId'),
        kind: readEnum(OperationKind.values, m['kind'], OperationKind.correction),
        adjustmentIds: readStrings(m['adjustmentIds']),
        lotIdsCreated: readStrings(m['lotIdsCreated']),
        createdAt: readDate(m['createdAt']),
        createdBy: readString(m, 'createdBy'),
        summary: readString(m, 'summary', ''),
        undoneByOperationId: m['undoneByOperationId'] as String?,
        undoesOperationId: m['undoesOperationId'] as String?,
        discrepancies: readStrings(m['discrepancies']),
      );
}
