import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/catalog/catalog.dart';
import '../../domain/catalog/product_matcher.dart';
import '../../domain/models/codec.dart';
import '../../domain/models/inventory.dart';
import '../../domain/models/receipt.dart';
import '../errors.dart';
import '../paths.dart';
import '../store/doc_store.dart';
import 'inventory_repository.dart';

class ReceiptValidationException implements Exception, CodedError {
  ReceiptValidationException(this.message, {this.code, this.args = const {}});
  final String message;
  @override
  final AppErrorCode? code;
  @override
  final Map<String, Object?> args;
  @override
  String toString() => message;
}

/// Client-side guards before a receipt image leaves the device.
class ReceiptImageRules {
  static const maxBytes = 12 * 1024 * 1024;
  static const maxPages = 5;
  static const allowedMime = {'image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp'};

  /// English problem text, or null when the image is acceptable.
  /// UI code should translate [check]'s code instead.
  static String? validate(Uint8List bytes, String? mimeType) => switch (check(bytes, mimeType)) {
        AppErrorCode.receiptImageEmpty => 'That image appears to be empty.',
        AppErrorCode.receiptImageTooLarge => 'That image is too large (over 12 MB). Try a closer, single-page photo.',
        null => null,
        _ => 'Please use a JPEG, PNG, HEIC or WebP photo.',
      };

  /// The problem with an image as a translatable code, or null when it is acceptable.
  static AppErrorCode? check(Uint8List bytes, String? mimeType) {
    if (bytes.isEmpty) return AppErrorCode.receiptImageEmpty;
    if (bytes.length > maxBytes) return AppErrorCode.receiptImageTooLarge;
    final mime = mimeType ?? sniffMime(bytes);
    if (mime == null || !allowedMime.contains(mime)) return AppErrorCode.receiptImageFormat;
    return null;
  }

  /// Magic-number sniffing so we don't trust file extensions.
  static String? sniffMime(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
    if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45) {
      return 'image/webp';
    }
    if (b.length >= 12 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      final brand = String.fromCharCodes(b.sublist(8, 12));
      if (brand.startsWith('hei') || brand.startsWith('mif') || brand.startsWith('hev')) return 'image/heic';
    }
    return null;
  }

  static String hash(Uint8List bytes) => sha256.convert(bytes).toString();
}

class ReceiptRepository {
  ReceiptRepository(this._store, {DateTime Function()? clock}) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DocStore _store;
  final DateTime Function() _clock;

  Stream<PurchaseReceipt?> watch(String householdId, String id) => _store
      .watch(HouseholdPaths(householdId).receipt(id))
      .map((d) => d == null ? null : PurchaseReceipt.fromMap(d.id, d.data));

  Future<PurchaseReceipt?> get(String householdId, String id) async {
    final d = await _store.get(HouseholdPaths(householdId).receipt(id));
    return d == null ? null : PurchaseReceipt.fromMap(d.id, d.data);
  }

  Stream<List<PurchaseReceipt>> watchRecent(String householdId, {int limit = 30}) => _store
      .watchQuery(HouseholdPaths(householdId).receipts, QuerySpec(orderBy: 'createdAt', descending: true, limit: limit))
      .map((ds) => ds.map((d) => PurchaseReceipt.fromMap(d.id, d.data)).toList());

  /// Returns an earlier receipt that contained an identical image, if any.
  Future<PurchaseReceipt?> findByImageHash(String householdId, String hash) async {
    final ds = await _store.query(
      HouseholdPaths(householdId).receipts,
      QuerySpec(where: [Where('imageHashes', WhereOp.arrayContains, hash)], limit: 5),
    );
    for (final d in ds) {
      final r = PurchaseReceipt.fromMap(d.id, d.data);
      if (r.status != ReceiptStatus.cancelled && r.status != ReceiptStatus.failed) return r;
    }
    return null;
  }

  Future<String> createJob({required String householdId, required String uid, required List<String> imageHashes}) async {
    final id = _store.newId();
    final now = _clock();
    await _store.set(
      HouseholdPaths(householdId).receipt(id),
      PurchaseReceipt(
        id: id,
        householdId: householdId,
        createdBy: uid,
        status: ReceiptStatus.uploading,
        createdAt: now,
        updatedAt: now,
        imageHashes: imageHashes,
      ).toMap(),
    );
    return id;
  }

  Future<void> markUploaded(String householdId, String id, List<String> pagePaths) => _store.set(
        HouseholdPaths(householdId).receipt(id),
        {'status': ReceiptStatus.uploaded.name, 'pagePaths': pagePaths, 'updatedAt': _clock()},
        merge: true,
      );

  Future<void> cancel(String householdId, String id) => _store.transaction((tx) async {
        final d = await tx.get(HouseholdPaths(householdId).receipt(id));
        if (d == null) return;
        final r = PurchaseReceipt.fromMap(d.id, d.data);
        if (r.status == ReceiptStatus.imported) return; // never cancel after import
        tx.set(HouseholdPaths(householdId).receipt(id), {'status': ReceiptStatus.cancelled.name, 'updatedAt': _clock()},
            merge: true);
      });

  Future<void> markFailed(String householdId, String id, String code, String message) => _store.set(
        HouseholdPaths(householdId).receipt(id),
        {'status': ReceiptStatus.failed.name, 'errorCode': code, 'errorMessage': message, 'updatedAt': _clock()},
        merge: true,
      );

  /// Saves user corrections. Refused once the receipt has been imported.
  Future<void> saveLines(String householdId, String id, List<ReceiptLineItem> lines) => _store.transaction((tx) async {
        final d = await tx.get(HouseholdPaths(householdId).receipt(id));
        if (d == null) throw ReceiptValidationException('Receipt not found.', code: AppErrorCode.receiptNotFound);
        final r = PurchaseReceipt.fromMap(d.id, d.data);
        if (r.status != ReceiptStatus.needsReview) {
          throw ReceiptValidationException('This receipt can no longer be edited.', code: AppErrorCode.receiptNotEditable);
        }
        tx.set(HouseholdPaths(householdId).receipt(id), {'lines': lines.map((l) => l.toMap()).toList(), 'updatedAt': _clock()},
            merge: true);
      });

  /// Used by the demo extractor (the real one runs in Cloud Functions).
  /// Refuses to modify receipts in a terminal state (e.g. cancelled while
  /// processing), so late results can never resurrect them.
  Future<bool> writeExtraction(String householdId, String id, Map<String, dynamic> fields) =>
      _store.transaction((tx) async {
        final path = HouseholdPaths(householdId).receipt(id);
        final d = await tx.get(path);
        if (d == null) return false;
        final status = PurchaseReceipt.fromMap(d.id, d.data).status;
        if (status.isTerminal) return false;
        tx.set(path, {...fields, 'updatedAt': _clock()}, merge: true);
        return true;
      });
}

/// Turns a reviewed receipt into inventory. Safe to call repeatedly: the
/// inventory write is keyed by the receipt id, and the status update is
/// re-applied after a partial failure.
class ReceiptImportService {
  ReceiptImportService(this._store, this._inventory, {DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  final DocStore _store;
  final InventoryRepository _inventory;
  final DateTime Function() _clock;

  static String operationIdFor(String receiptId) => 'receipt_$receiptId';

  /// Lines that must be resolved before import (no name or no quantity).
  static List<ReceiptLineItem> blockingLines(PurchaseReceipt r) =>
      r.lines.where((l) => !l.excluded && l.isFood && (l.name.trim().isEmpty || l.quantity == null)).toList();

  Future<OperationResult> confirm({
    required PurchaseReceipt receipt,
    required String uid,
    required Map<StorageKind, String> locationIds,
  }) async {
    if (receipt.status == ReceiptStatus.imported && receipt.importOperationId != null) {
      final existing = await _store.get(HouseholdPaths(receipt.householdId).operation(receipt.importOperationId!));
      if (existing != null) {
        return OperationResult(InventoryOperation.fromMap(existing.id, existing.data), alreadyApplied: true);
      }
    }
    if (receipt.status != ReceiptStatus.needsReview && receipt.status != ReceiptStatus.imported) {
      throw ReceiptValidationException('This receipt is not ready to import.', code: AppErrorCode.receiptNotReady);
    }
    final blocking = blockingLines(receipt);
    if (blocking.isNotEmpty) {
      throw ReceiptValidationException(
          '${blocking.length} item${blocking.length == 1 ? ' needs' : 's need'} a name and quantity before importing.',
          code: AppErrorCode.receiptLinesIncomplete,
          args: {'count': blocking.length});
    }
    final lines = receipt.lines.where((l) => !l.excluded && l.isFood).toList();
    if (lines.isEmpty) throw ReceiptValidationException('There are no food items to add.', code: AppErrorCode.receiptNoFoodItems);

    final householdProducts = await _inventory.products(receipt.householdId);
    final matcher = ProductMatcher([...householdProducts, ...catalog.map((e) => e.product)]);
    final byId = {for (final p in [...catalog.map((e) => e.product), ...householdProducts]) p.id: p};

    final inputs = <NewLotInput>[];
    for (final l in lines) {
      FoodProduct? product = l.matchedProductId == null ? null : byId[l.matchedProductId];
      product ??= matcher.best(l.name, minScore: 0.75)?.product;
      product ??= FoodProduct(
        id: 'p_${_slug(l.name)}',
        name: l.name,
        category: l.category,
        defaultUnit: l.quantity!.unit,
        brand: l.brand,
        defaultStorage: l.storage,
        aliases: [l.rawText.toLowerCase()],
      );
      inputs.add(NewLotInput(
        product: product,
        quantity: l.quantity!,
        locationId: locationIds[l.storage] ?? locationIds[StorageKind.pantry] ?? 'pantry',
        source: LotSource.receipt,
        provenance: Provenance(
          source: receipt.isDemo ? ProvenanceSource.demo : ProvenanceSource.receiptAi,
          // A human reviewed the line: edited lines are confirmed, untouched
          // lines keep the model's confidence so they show as estimates.
          confidence: l.userEdited ? 1 : l.confidence,
          model: receipt.aiModel,
          raw: l.rawText,
        ),
        packageDescription: l.packageDescription,
        receiptId: receipt.id,
        needsReview: !l.userEdited && l.confidence < ReceiptLineItem.reviewThreshold,
      ));
    }

    final opId = operationIdFor(receipt.id);
    final result = await _inventory.addLots(
      householdId: receipt.householdId,
      operationId: opId,
      actorUid: uid,
      inputs: inputs,
      kind: OperationKind.receiptImport,
      summary: 'Imported ${inputs.length} item${inputs.length == 1 ? '' : 's'}${receipt.merchant == null ? '' : ' from ${receipt.merchant}'}',
    );
    await _store.transaction((tx) async {
      final p = HouseholdPaths(receipt.householdId);
      tx.set(p.receipt(receipt.id), {
        'status': ReceiptStatus.imported.name,
        'importOperationId': opId,
        'updatedAt': _clock(),
      }, merge: true);
      if (receipt.fingerprint != null) {
        tx.set(p.receiptFingerprint(receipt.fingerprint!), {'receiptId': receipt.id, 'at': _clock()});
      }
    });
    return result;
  }

  static String _slug(String s) {
    final slug = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    return slug.isEmpty ? 'item' : (slug.length > 40 ? slug.substring(0, 40) : slug);
  }
}

/// Summary for the Import Complete screen.
class ReceiptSummary {
  ReceiptSummary(this.receipt);
  final PurchaseReceipt receipt;

  int get imported => receipt.lines.where((l) => !l.excluded && l.isFood).length;
  int get excluded => receipt.lines.where((l) => l.excluded || !l.isFood).length;
  int get estimated => receipt.lines.where((l) => !l.excluded && l.isFood && !l.userEdited && l.confidence < ReceiptLineItem.reviewThreshold).length;
  Money? get total => receipt.total;
}
