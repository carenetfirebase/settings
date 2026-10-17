import 'dart:convert';

import '../paths.dart';
import '../store/doc_store.dart';

/// Builds a portable JSON export of everything Chefii stores about a user
/// (PIPEDA right of access). Shared household inventory is included only
/// for the household the user belongs to.
class DataExportService {
  DataExportService(this._store);
  final DocStore _store;

  Future<Map<String, dynamic>> collect(String uid, {String? householdId}) async {
    final u = UserPaths(uid);
    Future<Map<String, dynamic>?> doc(String p) async => (await _store.get(p))?.data;
    Future<List<Map<String, dynamic>>> col(String p) async =>
        (await _store.query(p)).map((d) => {'id': d.id, ...d.data}).toList();

    final out = <String, dynamic>{
      'format': 'chefii-export-v1',
      'exportedAt': DateTime.now().toUtc(),
      'profile': await doc(u.root),
      'dietary': await doc(u.dietary),
      'wellness': await doc(u.wellness),
      'settings': await doc(u.settings),
      'morningRoutine': await doc(u.morningRoutine),
      'journal': await col(u.journal),
      'glucose': await col(u.glucose),
      'oralExposures': await col(u.oralExposures),
      'concerns': await col(u.concerns),
      'consents': await col(u.consents),
      'audit': await col(u.audit),
      'favourites': await col(u.favourites),
      'shareGrants': (await _store.query(shareGrantsCollection, QuerySpec(where: [Where.eq('ownerUid', uid)]))).map((d) => {'id': d.id, ...d.data}).toList(),
      'assessments': (await _store.query(assessmentsCollection, QuerySpec(where: [Where.eq('clientUid', uid), clientVisibleAssessments]))).map((d) => {'id': d.id, ...d.data}).toList(),
    };
    if (householdId != null) {
      final h = HouseholdPaths(householdId);
      out['household'] = {
        'household': await doc(h.root),
        'lots': await col(h.lots),
        'adjustments': await col(h.adjustments),
        'products': await col(h.products),
        'receipts': await col(h.receipts),
        'recipes': await col(h.recipes),
        'mealPlan': await col(h.mealPlan),
        'shoppingItems': await col(h.shoppingItems),
      };
    }
    return out;
  }

  Future<String> toJson(String uid, {String? householdId}) async =>
      const JsonEncoder.withIndent('  ', _encode).convert(await collect(uid, householdId: householdId));

  static Object? _encode(Object? v) => v is DateTime ? v.toUtc().toIso8601String() : v.toString();
}
