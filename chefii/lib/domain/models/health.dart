import 'codec.dart';

/// Glucose units. Canada uses mmol/L; mg/dL supported for travellers/devices.
enum GlucoseUnit {
  mmolL('mmol/L'),
  mgdL('mg/dL');

  const GlucoseUnit(this.label);
  final String label;

  /// Standard conversion factor for glucose: 1 mmol/L = 18.016 mg/dL.
  static const mgPerMmol = 18.016;
}

enum GlucoseSource { manual, healthIntegration, device }

enum GlucoseContext { fasting, beforeMeal, afterMeal, bedtime, other }

/// A user-recorded glucose reading. Stored in mmol/L with original unit kept.
/// Chefii never interprets readings diagnostically.
class GlucoseEntry {
  const GlucoseEntry({
    required this.id,
    required this.uid,
    required this.valueMmolL,
    required this.enteredUnit,
    required this.measuredAt,
    required this.source,
    required this.createdAt,
    this.context = GlucoseContext.other,
    this.note,
    this.deviceName,
  });

  final String id;
  final String uid;
  final double valueMmolL;
  final GlucoseUnit enteredUnit;
  final DateTime measuredAt;
  final GlucoseSource source;
  final DateTime createdAt;
  final GlucoseContext context;
  final String? note;
  final String? deviceName;

  double valueIn(GlucoseUnit u) =>
      u == GlucoseUnit.mmolL ? valueMmolL : valueMmolL * GlucoseUnit.mgPerMmol;

  static double toMmol(double value, GlucoseUnit unit) =>
      unit == GlucoseUnit.mmolL ? value : value / GlucoseUnit.mgPerMmol;

  /// Plausibility bounds to catch typos; not clinical thresholds.
  static String? validate(double value, GlucoseUnit unit) {
    final mmol = toMmol(value, unit);
    if (mmol <= 0) return 'Enter a positive value.';
    if (mmol < 1 || mmol > 35) {
      return 'That value looks outside what meters typically report. Please double-check it.';
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'valueMmolL': valueMmolL,
        'enteredUnit': enteredUnit.name,
        'measuredAt': measuredAt,
        'source': source.name,
        'createdAt': createdAt,
        'context': context.name,
        if (note != null) 'note': note,
        if (deviceName != null) 'deviceName': deviceName,
      };

  static GlucoseEntry fromMap(String id, Map<String, dynamic> m) => GlucoseEntry(
        id: id,
        uid: readString(m, 'uid'),
        valueMmolL: readDouble(m, 'valueMmolL'),
        enteredUnit: readEnum(GlucoseUnit.values, m['enteredUnit'], GlucoseUnit.mmolL),
        measuredAt: readDate(m['measuredAt']),
        source: readEnum(GlucoseSource.values, m['source'], GlucoseSource.manual),
        createdAt: readDate(m['createdAt'] ?? m['measuredAt']),
        context: readEnum(GlucoseContext.values, m['context'], GlucoseContext.other),
        note: m['note'] as String?,
        deviceName: m['deviceName'] as String?,
      );
}

enum OralExposureKind {
  sugaryDrink('Sugary drink'),
  sweetSnack('Sweet snack'),
  stickyFood('Sticky or slow-dissolving sweet'),
  acidicDrink('Acidic drink'),
  citrus('Citrus or acidic fruit'),
  sipping('Long sipping session'),
  water('Water after eating'),
  cheese('Cheese or dairy finish'),
  brushed('Brushed teeth');

  const OralExposureKind(this.label);
  final String label;

  bool get isProtective => this == water || this == cheese || this == brushed;
}

class OralExposureEvent {
  const OralExposureEvent({
    required this.id,
    required this.uid,
    required this.kind,
    required this.occurredAt,
    this.durationMinutes,
    this.note,
    this.mealId,
  });

  final String id;
  final String uid;
  final OralExposureKind kind;
  final DateTime occurredAt;
  final int? durationMinutes;
  final String? note;
  final String? mealId;

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'kind': kind.name,
        'occurredAt': occurredAt,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        if (note != null) 'note': note,
        if (mealId != null) 'mealId': mealId,
      };

  static OralExposureEvent fromMap(String id, Map<String, dynamic> m) => OralExposureEvent(
        id: id,
        uid: readString(m, 'uid'),
        kind: readEnum(OralExposureKind.values, m['kind'], OralExposureKind.sweetSnack),
        occurredAt: readDate(m['occurredAt']),
        durationMinutes: (m['durationMinutes'] as num?)?.toInt(),
        note: m['note'] as String?,
        mealId: m['mealId'] as String?,
      );
}

enum ConcernArea { hair, skin, nails, energy, digestion, other }

class UserConcern {
  const UserConcern({
    required this.id,
    required this.uid,
    required this.area,
    required this.description,
    required this.recordedAt,
    this.severity = 2,
  });

  final String id;
  final String uid;
  final ConcernArea area;
  final String description;
  final DateTime recordedAt;

  /// Self-reported 1..5.
  final int severity;

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'area': area.name,
        'description': description,
        'recordedAt': recordedAt,
        'severity': severity,
      };

  static UserConcern fromMap(String id, Map<String, dynamic> m) => UserConcern(
        id: id,
        uid: readString(m, 'uid'),
        area: readEnum(ConcernArea.values, m['area'], ConcernArea.other),
        description: readString(m, 'description', ''),
        recordedAt: readDate(m['recordedAt']),
        severity: readInt(m, 'severity', 2),
      );
}

enum StudyType {
  guideline('Clinical/public-health guideline'),
  systematicReview('Systematic review / meta-analysis'),
  rct('Randomised controlled trial'),
  cohort('Observational cohort'),
  reference('Reference values / authoritative body');

  const StudyType(this.label);
  final String label;
}

enum EvidenceStrength {
  strong('Strong'),
  moderate('Moderate'),
  limited('Limited'),
  insufficient('Insufficient');

  const EvidenceStrength(this.label);
  final String label;
}

class EvidenceSource {
  const EvidenceSource({
    required this.id,
    required this.title,
    required this.publisher,
    required this.studyType,
    required this.year,
    required this.url,
  });

  final String id;
  final String title;
  final String publisher;
  final StudyType studyType;
  final int year;
  final String url;
}

/// A reviewed educational statement. Only claims with status 'approved' may
/// be phrased by AI; AI may not add new claims.
class EvidenceClaim {
  const EvidenceClaim({
    required this.id,
    required this.topic,
    required this.statement,
    required this.strength,
    required this.sourceIds,
    required this.limitations,
    required this.reviewedOn,
    required this.reviewStatus,
    this.foodSources = const [],
  });

  final String id;
  final String topic;
  final String statement;
  final EvidenceStrength strength;
  final List<String> sourceIds;
  final String limitations;
  final CalendarDate reviewedOn;

  /// 'internal_draft' until a qualified professional signs off.
  final String reviewStatus;
  final List<String> foodSources;

  bool get professionallyReviewed => reviewStatus == 'professionally_reviewed';
}
