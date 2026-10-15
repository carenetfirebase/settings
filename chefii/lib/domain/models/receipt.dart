import '../units/units.dart';
import 'codec.dart';
import 'inventory.dart';

enum ReceiptStatus {
  uploading('Uploading'),
  uploaded('Waiting to analyze'),
  processing('Reading your receipt'),
  needsReview('Ready for review'),
  imported('Added to your kitchen'),
  failed('Could not read'),
  duplicate('Already imported'),
  cancelled('Cancelled');

  const ReceiptStatus(this.label);
  final String label;

  bool get isTerminal => this == imported || this == failed || this == duplicate || this == cancelled;
}

/// Server-produced extraction problems, plus deterministic validation output.
class ReceiptIssue {
  const ReceiptIssue(this.code, this.message, {this.lineId});
  final String code;
  final String message;
  final String? lineId;

  Map<String, dynamic> toMap() => {'code': code, 'message': message, if (lineId != null) 'lineId': lineId};
  static ReceiptIssue fromMap(Map<String, dynamic> m) =>
      ReceiptIssue(readString(m, 'code'), readString(m, 'message', ''), lineId: m['lineId'] as String?);
}

class ReceiptLineItem {
  const ReceiptLineItem({
    required this.id,
    required this.rawText,
    required this.name,
    required this.category,
    required this.confidence,
    this.brand,
    this.quantity,
    this.packageDescription,
    this.unitPrice,
    this.totalPrice,
    this.matchedProductId,
    this.isFood = true,
    this.excluded = false,
    this.storage = StorageKind.pantry,
    this.userEdited = false,
    this.issues = const [],
  });

  final String id;

  /// Exactly as printed on the receipt; never overwritten.
  final String rawText;

  /// Normalised product name (AI or user).
  final String name;
  final FoodCategory category;

  /// 0..1 overall extraction confidence from the model + validation.
  final double confidence;
  final String? brand;
  final Quantity? quantity;
  final String? packageDescription;
  final Money? unitPrice;
  final Money? totalPrice;
  final String? matchedProductId;
  final bool isFood;
  final bool excluded;
  final StorageKind storage;
  final bool userEdited;
  final List<String> issues;

  static const reviewThreshold = 0.75;

  bool get needsReview =>
      !excluded && !userEdited && (confidence < reviewThreshold || quantity == null || issues.isNotEmpty);

  bool get isUnknown => !excluded && (name.trim().isEmpty || category == FoodCategory.other && confidence < 0.5);

  ReceiptLineItem copyWith({
    String? name,
    FoodCategory? category,
    String? brand,
    Quantity? quantity,
    String? packageDescription,
    bool? isFood,
    bool? excluded,
    StorageKind? storage,
    bool? userEdited,
    String? matchedProductId,
    List<String>? issues,
  }) =>
      ReceiptLineItem(
        id: id,
        rawText: rawText,
        name: name ?? this.name,
        category: category ?? this.category,
        confidence: confidence,
        brand: brand ?? this.brand,
        quantity: quantity ?? this.quantity,
        packageDescription: packageDescription ?? this.packageDescription,
        unitPrice: unitPrice,
        totalPrice: totalPrice,
        matchedProductId: matchedProductId ?? this.matchedProductId,
        isFood: isFood ?? this.isFood,
        excluded: excluded ?? this.excluded,
        storage: storage ?? this.storage,
        userEdited: userEdited ?? this.userEdited,
        issues: issues ?? this.issues,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'rawText': rawText,
        'name': name,
        'category': category.name,
        'confidence': confidence,
        if (brand != null) 'brand': brand,
        if (quantity != null) 'quantity': quantity!.toMap(),
        if (packageDescription != null) 'packageDescription': packageDescription,
        if (unitPrice != null) 'unitPrice': unitPrice!.toMap(),
        if (totalPrice != null) 'totalPrice': totalPrice!.toMap(),
        if (matchedProductId != null) 'matchedProductId': matchedProductId,
        'isFood': isFood,
        'excluded': excluded,
        'storage': storage.name,
        'userEdited': userEdited,
        'issues': issues,
      };

  static ReceiptLineItem fromMap(Map<String, dynamic> m) => ReceiptLineItem(
        id: readString(m, 'id'),
        rawText: readString(m, 'rawText', ''),
        name: readString(m, 'name', ''),
        category: readEnum(FoodCategory.values, m['category'], FoodCategory.other),
        confidence: readDouble(m, 'confidence', 0),
        brand: m['brand'] as String?,
        quantity: m['quantity'] == null ? null : Quantity.fromMap(readMap(m['quantity'])),
        packageDescription: m['packageDescription'] as String?,
        unitPrice: Money.fromMap(m['unitPrice']),
        totalPrice: Money.fromMap(m['totalPrice']),
        matchedProductId: m['matchedProductId'] as String?,
        isFood: m['isFood'] as bool? ?? true,
        excluded: m['excluded'] as bool? ?? false,
        storage: readEnum(StorageKind.values, m['storage'], StorageKind.pantry),
        userEdited: m['userEdited'] as bool? ?? false,
        issues: readStrings(m['issues']),
      );
}

class PurchaseReceipt {
  const PurchaseReceipt({
    required this.id,
    required this.householdId,
    required this.createdBy,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.pagePaths = const [],
    this.imageHashes = const [],
    this.merchant,
    this.purchaseDate,
    this.subtotal,
    this.tax,
    this.total,
    this.lines = const [],
    this.issues = const [],
    this.errorCode,
    this.errorMessage,
    this.duplicateOfReceiptId,
    this.aiModel,
    this.fingerprint,
    this.importOperationId,
    this.isDemo = false,
    this.progress = 0,
  });

  final String id;
  final String householdId;
  final String createdBy;
  final ReceiptStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> pagePaths;
  final List<String> imageHashes;
  final String? merchant;
  final CalendarDate? purchaseDate;
  final Money? subtotal;
  final Money? tax;
  final Money? total;
  final List<ReceiptLineItem> lines;
  final List<ReceiptIssue> issues;
  final String? errorCode;
  final String? errorMessage;
  final String? duplicateOfReceiptId;
  final String? aiModel;
  final String? fingerprint;
  final String? importOperationId;

  /// Produced by the offline demo extractor, not by real AI.
  final bool isDemo;

  /// 0..1 server-reported progress for the processing screen.
  final double progress;

  Iterable<ReceiptLineItem> get activeLines => lines.where((l) => !l.excluded);
  int get reviewCount => lines.where((l) => l.needsReview).length;

  Money get linesTotal => lines
      .where((l) => l.totalPrice != null)
      .fold(Money(0, total?.currency ?? 'CAD'), (s, l) => s + l.totalPrice!);

  PurchaseReceipt copyWith({
    ReceiptStatus? status,
    List<ReceiptLineItem>? lines,
    DateTime? updatedAt,
    String? importOperationId,
    String? merchant,
  }) =>
      PurchaseReceipt(
        id: id,
        householdId: householdId,
        createdBy: createdBy,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        pagePaths: pagePaths,
        imageHashes: imageHashes,
        merchant: merchant ?? this.merchant,
        purchaseDate: purchaseDate,
        subtotal: subtotal,
        tax: tax,
        total: total,
        lines: lines ?? this.lines,
        issues: issues,
        errorCode: errorCode,
        errorMessage: errorMessage,
        duplicateOfReceiptId: duplicateOfReceiptId,
        aiModel: aiModel,
        fingerprint: fingerprint,
        importOperationId: importOperationId ?? this.importOperationId,
        isDemo: isDemo,
        progress: progress,
      );

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'createdBy': createdBy,
        'status': status.name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'pagePaths': pagePaths,
        'imageHashes': imageHashes,
        if (merchant != null) 'merchant': merchant,
        if (purchaseDate != null) 'purchaseDate': purchaseDate!.toIso(),
        if (subtotal != null) 'subtotal': subtotal!.toMap(),
        if (tax != null) 'tax': tax!.toMap(),
        if (total != null) 'total': total!.toMap(),
        'lines': lines.map((l) => l.toMap()).toList(),
        'issues': issues.map((i) => i.toMap()).toList(),
        if (errorCode != null) 'errorCode': errorCode,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (duplicateOfReceiptId != null) 'duplicateOfReceiptId': duplicateOfReceiptId,
        if (aiModel != null) 'aiModel': aiModel,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (importOperationId != null) 'importOperationId': importOperationId,
        'isDemo': isDemo,
        'progress': progress,
      };

  static PurchaseReceipt fromMap(String id, Map<String, dynamic> m) => PurchaseReceipt(
        id: id,
        householdId: readString(m, 'householdId'),
        createdBy: readString(m, 'createdBy'),
        status: readEnum(ReceiptStatus.values, m['status'], ReceiptStatus.uploaded),
        createdAt: readDate(m['createdAt']),
        updatedAt: readDate(m['updatedAt'] ?? m['createdAt']),
        pagePaths: readStrings(m['pagePaths']),
        imageHashes: readStrings(m['imageHashes']),
        merchant: m['merchant'] as String?,
        purchaseDate: CalendarDate.tryParse(m['purchaseDate']),
        subtotal: Money.fromMap(m['subtotal']),
        tax: Money.fromMap(m['tax']),
        total: Money.fromMap(m['total']),
        lines: readMaps(m['lines']).map(ReceiptLineItem.fromMap).toList(),
        issues: readMaps(m['issues']).map(ReceiptIssue.fromMap).toList(),
        errorCode: m['errorCode'] as String?,
        errorMessage: m['errorMessage'] as String?,
        duplicateOfReceiptId: m['duplicateOfReceiptId'] as String?,
        aiModel: m['aiModel'] as String?,
        fingerprint: m['fingerprint'] as String?,
        importOperationId: m['importOperationId'] as String?,
        isDemo: m['isDemo'] as bool? ?? false,
        progress: (m['progress'] as num?)?.toDouble() ?? 0,
      );
}
