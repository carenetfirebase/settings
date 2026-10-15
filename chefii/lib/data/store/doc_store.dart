/// A minimal document-store abstraction shaped after Cloud Firestore.
///
/// Repositories are written once against this interface and run unchanged on
/// Firestore (production) and on [MemoryDocStore] (tests and demo mode).
/// Paths are slash-separated, e.g. `households/h1/lots/l1`.
library;

class DocSnapshot {
  const DocSnapshot(this.path, this.data);

  final String path;
  final Map<String, dynamic> data;

  String get id => path.substring(path.lastIndexOf('/') + 1);
}

enum WhereOp { eq, lt, lte, gt, gte, arrayContains, whereIn }

class Where {
  const Where(this.field, this.op, this.value);
  const Where.eq(this.field, this.value) : op = WhereOp.eq;

  final String field;
  final WhereOp op;
  final Object? value;
}

class QuerySpec {
  const QuerySpec({this.where = const [], this.orderBy, this.descending = false, this.limit});

  final List<Where> where;
  final String? orderBy;
  final bool descending;
  final int? limit;

  static const all = QuerySpec();
}

/// Reads inside a transaction must all happen before the first write
/// (a Firestore constraint the memory store also enforces).
abstract class DocTransaction {
  Future<DocSnapshot?> get(String path);
  void set(String path, Map<String, dynamic> data, {bool merge = false});
  void delete(String path);
}

class TransactionReadAfterWriteError extends StateError {
  TransactionReadAfterWriteError()
      : super('All transaction reads must happen before writes.');
}

abstract class DocStore {
  String newId();

  Future<DocSnapshot?> get(String path);
  Future<List<DocSnapshot>> query(String collectionPath, [QuerySpec spec = QuerySpec.all]);
  Stream<DocSnapshot?> watch(String path);
  Stream<List<DocSnapshot>> watchQuery(String collectionPath, [QuerySpec spec = QuerySpec.all]);

  Future<void> set(String path, Map<String, dynamic> data, {bool merge = false});
  Future<void> delete(String path);

  /// Runs [body] atomically. The body may be retried on contention, so it
  /// must not have side effects outside the transaction.
  Future<T> transaction<T>(Future<T> Function(DocTransaction tx) body);
}
