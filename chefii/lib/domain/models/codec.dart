/// Small, strict helpers shared by model (de)serialisation.
///
/// All timestamps are stored in UTC. The storage layer converts backend
/// specific timestamp types (e.g. Firestore `Timestamp`) to [DateTime]
/// before models see them, so models only deal with [DateTime].
library;

DateTime readDate(Object? v) {
  final d = readDateOrNull(v);
  if (d == null) throw FormatException('Expected a timestamp, got $v');
  return d;
}

DateTime? readDateOrNull(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toUtc();
  if (v is String) return DateTime.parse(v).toUtc();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
  throw FormatException('Unsupported timestamp value: $v');
}

String readString(Map<String, dynamic> m, String key, [String? fallback]) {
  final v = m[key];
  if (v is String) return v;
  if (v == null && fallback != null) return fallback;
  throw FormatException('Field "$key" must be a string, got $v');
}

double readDouble(Map<String, dynamic> m, String key, [double? fallback]) {
  final v = m[key];
  if (v is num) return v.toDouble();
  if (v == null && fallback != null) return fallback;
  throw FormatException('Field "$key" must be a number, got $v');
}

int readInt(Map<String, dynamic> m, String key, [int? fallback]) {
  final v = m[key];
  if (v is num) return v.toInt();
  if (v == null && fallback != null) return fallback;
  throw FormatException('Field "$key" must be an integer, got $v');
}

List<String> readStrings(Object? v) =>
    v == null ? const [] : List<String>.unmodifiable((v as List).cast<String>());

Map<String, dynamic> readMap(Object? v) =>
    v == null ? const {} : Map<String, dynamic>.from(v as Map);

List<Map<String, dynamic>> readMaps(Object? v) => v == null
    ? const []
    : (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

T readEnum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}

/// Calendar date (no time) stored as ISO `yyyy-MM-dd` to avoid time-zone drift
/// for things like use-by dates and meal plan days.
class CalendarDate implements Comparable<CalendarDate> {
  const CalendarDate(this.year, this.month, this.day);

  factory CalendarDate.fromDateTime(DateTime d) => CalendarDate(d.year, d.month, d.day);

  factory CalendarDate.parse(String s) {
    final p = s.split('-').map(int.parse).toList();
    return CalendarDate(p[0], p[1], p[2]);
  }

  static CalendarDate? tryParse(Object? s) =>
      s is String && s.isNotEmpty ? CalendarDate.parse(s) : null;

  final int year;
  final int month;
  final int day;

  DateTime toLocalDateTime() => DateTime(year, month, day);

  CalendarDate addDays(int days) =>
      CalendarDate.fromDateTime(DateTime(year, month, day + days));

  int daysUntil(CalendarDate other) =>
      DateTime.utc(other.year, other.month, other.day)
          .difference(DateTime.utc(year, month, day))
          .inDays;

  String toIso() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(CalendarDate o) => toIso().compareTo(o.toIso());

  bool isBefore(CalendarDate o) => compareTo(o) < 0;
  bool isAfter(CalendarDate o) => compareTo(o) > 0;

  @override
  bool operator ==(Object other) => other is CalendarDate && other.toIso() == toIso();

  @override
  int get hashCode => toIso().hashCode;

  @override
  String toString() => toIso();
}

/// Money in minor units (cents) with an ISO currency code. Never a double.
class Money {
  const Money(this.minorUnits, [this.currency = 'CAD']);
  final int minorUnits;
  final String currency;

  static const zero = Money(0);

  Money operator +(Money o) {
    assert(o.currency == currency, 'Currency mismatch');
    return Money(minorUnits + o.minorUnits, currency);
  }

  String format() {
    final sign = minorUnits < 0 ? '-' : '';
    final abs = minorUnits.abs();
    return '$sign\$${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() => {'minor': minorUnits, 'currency': currency};

  static Money? fromMap(Object? m) {
    if (m == null) return null;
    final map = m as Map;
    return Money((map['minor'] as num).toInt(), map['currency'] as String? ?? 'CAD');
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits && other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);
}

/// Where a piece of data came from and how much we trust it.
enum ProvenanceSource { user, receiptAi, scanAi, barcode, recipe, system, professional, import, demo }

class Provenance {
  const Provenance({required this.source, this.confidence = 1, this.model, this.raw});

  final ProvenanceSource source;

  /// 0..1. User-entered data is 1.
  final double confidence;

  /// AI model identifier when inferred.
  final String? model;

  /// Original raw text the value was derived from (e.g. receipt line).
  final String? raw;

  bool get isInferred =>
      source == ProvenanceSource.receiptAi || source == ProvenanceSource.scanAi;

  Map<String, dynamic> toMap() => {
        'source': source.name,
        'confidence': confidence,
        if (model != null) 'model': model,
        if (raw != null) 'raw': raw,
      };

  static Provenance fromMap(Object? m) {
    final map = readMap(m);
    return Provenance(
      source: readEnum(ProvenanceSource.values, map['source'], ProvenanceSource.user),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1,
      model: map['model'] as String?,
      raw: map['raw'] as String?,
    );
  }
}
