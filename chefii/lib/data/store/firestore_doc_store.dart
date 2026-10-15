import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import 'doc_store.dart';

/// Production [DocStore] backed by Cloud Firestore.
///
/// Converts [DateTime] <-> [fs.Timestamp] at the boundary so domain models
/// only ever see UTC [DateTime]s.
class FirestoreDocStore implements DocStore {
  FirestoreDocStore(this._db);

  final fs.FirebaseFirestore _db;

  @override
  String newId() => _db.collection('_ids').doc().id;

  @override
  Future<DocSnapshot?> get(String path) async => _snap(await _db.doc(path).get());

  @override
  Future<List<DocSnapshot>> query(String collectionPath, [QuerySpec spec = QuerySpec.all]) async {
    final q = await _build(collectionPath, spec).get();
    return q.docs.map((d) => _snap(d)!).toList();
  }

  @override
  Stream<DocSnapshot?> watch(String path) => _db.doc(path).snapshots().map(_snap);

  @override
  Stream<List<DocSnapshot>> watchQuery(String collectionPath, [QuerySpec spec = QuerySpec.all]) =>
      _build(collectionPath, spec).snapshots().map((q) => q.docs.map((d) => _snap(d)!).toList());

  @override
  Future<void> set(String path, Map<String, dynamic> data, {bool merge = false}) =>
      _db.doc(path).set(_toFs(data) as Map<String, dynamic>, fs.SetOptions(merge: merge));

  @override
  Future<void> delete(String path) => _db.doc(path).delete();

  @override
  Future<T> transaction<T>(Future<T> Function(DocTransaction tx) body) =>
      _db.runTransaction((t) => body(_FsTransaction(_db, t)));

  fs.Query<Map<String, dynamic>> _build(String collectionPath, QuerySpec spec) {
    fs.Query<Map<String, dynamic>> q = _db.collection(collectionPath);
    for (final w in spec.where) {
      final v = _toFs(w.value);
      q = switch (w.op) {
        WhereOp.eq => q.where(w.field, isEqualTo: v),
        WhereOp.lt => q.where(w.field, isLessThan: v),
        WhereOp.lte => q.where(w.field, isLessThanOrEqualTo: v),
        WhereOp.gt => q.where(w.field, isGreaterThan: v),
        WhereOp.gte => q.where(w.field, isGreaterThanOrEqualTo: v),
        WhereOp.arrayContains => q.where(w.field, arrayContains: v),
        WhereOp.whereIn => q.where(w.field, whereIn: v as List),
      };
    }
    if (spec.orderBy != null) q = q.orderBy(spec.orderBy!, descending: spec.descending);
    if (spec.limit != null) q = q.limit(spec.limit!);
    return q;
  }

  static DocSnapshot? _snap(fs.DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    if (!d.exists || data == null) return null;
    return DocSnapshot(d.reference.path, _fromFs(data) as Map<String, dynamic>);
  }

  static Object? _toFs(Object? v) {
    if (v is DateTime) return fs.Timestamp.fromDate(v.toUtc());
    if (v is Map) return v.map((k, val) => MapEntry(k as String, _toFs(val)));
    if (v is List) return v.map(_toFs).toList();
    return v;
  }

  static Object? _fromFs(Object? v) {
    if (v is fs.Timestamp) return v.toDate().toUtc();
    if (v is Map) return v.map((k, val) => MapEntry(k as String, _fromFs(val)));
    if (v is List) return v.map(_fromFs).toList();
    return v;
  }
}

class _FsTransaction implements DocTransaction {
  _FsTransaction(this._db, this._t);

  final fs.FirebaseFirestore _db;
  final fs.Transaction _t;
  bool _wrote = false;

  @override
  Future<DocSnapshot?> get(String path) async {
    if (_wrote) throw TransactionReadAfterWriteError();
    return FirestoreDocStore._snap(await _t.get(_db.doc(path)));
  }

  @override
  void set(String path, Map<String, dynamic> data, {bool merge = false}) {
    _wrote = true;
    _t.set(_db.doc(path), FirestoreDocStore._toFs(data) as Map<String, dynamic>,
        fs.SetOptions(merge: merge));
  }

  @override
  void delete(String path) {
    _wrote = true;
    _t.delete(_db.doc(path));
  }
}
