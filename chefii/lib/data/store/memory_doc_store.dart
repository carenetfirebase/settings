import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'doc_store.dart';

/// In-memory [DocStore] used by tests and by the offline demo mode.
///
/// Transactions are serialised through a mutex, so they are genuinely atomic:
/// writes are buffered and applied together, or not at all if the body throws.
class MemoryDocStore implements DocStore {
  MemoryDocStore({Map<String, Map<String, dynamic>>? initial, this.onChanged}) {
    if (initial != null) {
      for (final e in initial.entries) {
        _docs[e.key] = _deepCopy(e.value);
      }
    }
  }

  /// Called after every committed change (used for demo-mode persistence).
  final void Function(MemoryDocStore store)? onChanged;

  final Map<String, Map<String, dynamic>> _docs = {};
  final _changes = StreamController<void>.broadcast(sync: true);
  final _rng = Random.secure();
  Future<void> _lock = Future.value();

  /// Test hook: number of committed transactions.
  int committedTransactions = 0;

  @override
  String newId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(20, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  @override
  Future<DocSnapshot?> get(String path) async => _read(path);

  DocSnapshot? _read(String path) {
    _checkDocPath(path);
    final d = _docs[path];
    return d == null ? null : DocSnapshot(path, _deepCopy(d));
  }

  @override
  Future<List<DocSnapshot>> query(String collectionPath, [QuerySpec spec = QuerySpec.all]) async =>
      _query(collectionPath, spec);

  List<DocSnapshot> _query(String collectionPath, QuerySpec spec) {
    final prefix = '$collectionPath/';
    final depth = '/'.allMatches(collectionPath).length + 1;
    var results = _docs.entries
        .where((e) => e.key.startsWith(prefix) && '/'.allMatches(e.key).length == depth)
        .where((e) => spec.where.every((w) => _matches(e.value, w)))
        .map((e) => DocSnapshot(e.key, _deepCopy(e.value)))
        .toList();
    if (spec.orderBy != null) {
      final f = spec.orderBy!;
      results = results.where((d) => _field(d.data, f) != null).toList()
        ..sort((a, b) {
          final c = _compare(_field(a.data, f), _field(b.data, f));
          return spec.descending ? -c : c;
        });
    } else {
      results.sort((a, b) => a.path.compareTo(b.path));
    }
    if (spec.limit != null && results.length > spec.limit!) {
      results = results.sublist(0, spec.limit!);
    }
    return results;
  }

  @override
  Stream<DocSnapshot?> watch(String path) {
    late StreamController<DocSnapshot?> c;
    StreamSubscription<void>? sub;
    c = StreamController<DocSnapshot?>(
      onListen: () {
        c.add(_read(path));
        sub = _changes.stream.listen((_) => c.add(_read(path)));
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  @override
  Stream<List<DocSnapshot>> watchQuery(String collectionPath, [QuerySpec spec = QuerySpec.all]) {
    late StreamController<List<DocSnapshot>> c;
    StreamSubscription<void>? sub;
    c = StreamController<List<DocSnapshot>>(
      onListen: () {
        c.add(_query(collectionPath, spec));
        sub = _changes.stream.listen((_) => c.add(_query(collectionPath, spec)));
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  @override
  Future<void> set(String path, Map<String, dynamic> data, {bool merge = false}) =>
      transaction((tx) async => tx.set(path, data, merge: merge));

  @override
  Future<void> delete(String path) => transaction((tx) async => tx.delete(path));

  @override
  Future<T> transaction<T>(Future<T> Function(DocTransaction tx) body) {
    final completer = Completer<T>();
    final previous = _lock;
    final done = Completer<void>();
    _lock = done.future;
    previous.then((_) async {
      final tx = _MemoryTransaction(this);
      try {
        final result = await body(tx);
        tx._commit();
        committedTransactions++;
        if (tx._writes.isNotEmpty) {
          _changes.add(null);
          onChanged?.call(this);
        }
        completer.complete(result);
      } catch (e, s) {
        completer.completeError(e, s);
      } finally {
        done.complete();
      }
    });
    return completer.future;
  }

  // ---- persistence helpers (demo mode) ----

  String exportJson() => jsonEncode(_encode(_docs));

  void importJson(String json) {
    final decoded = _decode(jsonDecode(json)) as Map<String, dynamic>;
    _docs
      ..clear()
      ..addAll(decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map))));
    _changes.add(null);
  }

  void clear() {
    _docs.clear();
    _changes.add(null);
    onChanged?.call(this);
  }

  int get documentCount => _docs.length;

  static Object? _encode(Object? v) {
    if (v is DateTime) return {r'$dt': v.toUtc().toIso8601String()};
    if (v is Map) return v.map((k, val) => MapEntry(k as String, _encode(val)));
    if (v is List) return v.map(_encode).toList();
    return v;
  }

  static Object? _decode(Object? v) {
    if (v is Map) {
      if (v.length == 1 && v.containsKey(r'$dt')) {
        return DateTime.parse(v[r'$dt'] as String).toUtc();
      }
      return v.map((k, val) => MapEntry(k as String, _decode(val)));
    }
    if (v is List) return v.map(_decode).toList();
    return v;
  }

  // ---- internals ----

  static void _checkDocPath(String path) {
    if (path.split('/').length.isOdd) {
      throw ArgumentError('Document paths need an even number of segments: $path');
    }
  }

  static Object? _field(Map<String, dynamic> data, String dotted) {
    Object? cur = data;
    for (final part in dotted.split('.')) {
      if (cur is Map) {
        cur = cur[part];
      } else {
        return null;
      }
    }
    return cur;
  }

  static bool _matches(Map<String, dynamic> data, Where w) {
    final v = _field(data, w.field);
    switch (w.op) {
      case WhereOp.eq:
        return _equals(v, w.value);
      case WhereOp.arrayContains:
        return v is List && v.any((e) => _equals(e, w.value));
      case WhereOp.whereIn:
        return (w.value as List).any((e) => _equals(e, v));
      case WhereOp.lt:
        return v != null && _compare(v, w.value) < 0;
      case WhereOp.lte:
        return v != null && _compare(v, w.value) <= 0;
      case WhereOp.gt:
        return v != null && _compare(v, w.value) > 0;
      case WhereOp.gte:
        return v != null && _compare(v, w.value) >= 0;
    }
  }

  static bool _equals(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    return a == b;
  }

  static int _compare(Object? a, Object? b) {
    if (a is num && b is num) return a.compareTo(b);
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    if (a is bool && b is bool) return (a ? 1 : 0) - (b ? 1 : 0);
    return 0;
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> m) =>
      m.map((k, v) => MapEntry(k, _copyValue(v)));

  static Object? _copyValue(Object? v) {
    if (v is Map) return _deepCopy(Map<String, dynamic>.from(v));
    if (v is List) return v.map(_copyValue).toList();
    return v;
  }

  static Map<String, dynamic> _merge(Map<String, dynamic> base, Map<String, dynamic> patch) {
    final out = _deepCopy(base);
    patch.forEach((k, v) {
      if (v is Map && out[k] is Map) {
        out[k] = _merge(Map<String, dynamic>.from(out[k] as Map), Map<String, dynamic>.from(v));
      } else {
        out[k] = _copyValue(v);
      }
    });
    return out;
  }
}

class _MemoryTransaction implements DocTransaction {
  _MemoryTransaction(this._store);

  final MemoryDocStore _store;
  final List<void Function()> _writes = [];

  @override
  Future<DocSnapshot?> get(String path) async {
    if (_writes.isNotEmpty) throw TransactionReadAfterWriteError();
    return _store._read(path);
  }

  @override
  void set(String path, Map<String, dynamic> data, {bool merge = false}) {
    MemoryDocStore._checkDocPath(path);
    final copy = MemoryDocStore._deepCopy(data);
    _writes.add(() {
      final existing = _store._docs[path];
      _store._docs[path] =
          merge && existing != null ? MemoryDocStore._merge(existing, copy) : copy;
    });
  }

  @override
  void delete(String path) {
    MemoryDocStore._checkDocPath(path);
    _writes.add(() => _store._docs.remove(path));
  }

  void _commit() {
    for (final w in _writes) {
      w();
    }
  }
}
