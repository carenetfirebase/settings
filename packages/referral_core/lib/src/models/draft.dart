import '../enums.dart';
import '../tooth/location.dart';

/// A captured referral decision.
///
/// There is deliberately no patient identity here — no name, date of birth,
/// contact detail, chart number or appointment reference — and
/// [forbiddenKeyFragments] exists so a test can assert that stays true as the
/// model changes.
///
/// The clinical content is still sensitive: a timestamp, an operatory and a
/// diagnosis may be re-identifiable against a clinic's own records. Handle
/// accordingly.
class ReferralDraft {
  const ReferralDraft({
    required this.id,
    required this.humanCode,
    required this.professionalId,
    required this.createdAt,
    required this.updatedAt,
    required this.timezone,
    required this.specialty,
    required this.toothNotation,
    this.locations = const [],
    this.reasons = const [],
    this.findings = const [],
    this.symptoms = const [],
    this.urgency = Urgency.unspecified,
    this.referralDestinationId,
    this.requestedRecords = const [],
    this.operatory,
    this.status = ReferralStatus.needsCompletion,
    this.syncState = SyncState.pending,
    this.deletedAt,
    this.expiresAt,
  });

  /// Client-generated UUID, created before the first write so that saving is
  /// idempotent under double taps, retries and offline replay.
  final String id;

  /// The short code a human reads and transcribes. Random; encodes nothing.
  final String humanCode;

  /// The owning account's uid.
  final String professionalId;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// The zone the professional was working in, recorded so the instant can be
  /// rendered the way they experienced it.
  final String timezone;

  final Specialty specialty;

  /// The notation the professional works in. Tooth codes are stored as spoken
  /// in this system and never silently rewritten into another.
  final ToothNotation toothNotation;

  final List<ReferralLocation> locations;

  /// Standardised concept ids from the specialty's template.
  final List<String> reasons;
  final List<String> findings;
  final List<String> symptoms;

  final Urgency urgency;
  final String? referralDestinationId;
  final List<RecordType> requestedRecords;

  /// The room the referral was captured for. Clinic infrastructure, not a
  /// patient identifier — it lets staff resolve which patient a draft belongs
  /// to from their own schedule when several chairs run in parallel.
  final String? operatory;

  final ReferralStatus status;
  final SyncState syncState;

  /// Soft delete, so an undo has something to restore.
  final DateTime? deletedAt;

  /// When retention should remove this draft.
  final DateTime? expiresAt;

  bool get isDeleted => deletedAt != null;

  bool isExpiredAt(DateTime now) {
    final expiry = expiresAt;
    return expiry != null && !now.toUtc().isBefore(expiry.toUtc());
  }

  ReferralDraft copyWith({
    DateTime? updatedAt,
    Specialty? specialty,
    ToothNotation? toothNotation,
    List<ReferralLocation>? locations,
    List<String>? reasons,
    List<String>? findings,
    List<String>? symptoms,
    Urgency? urgency,
    String? referralDestinationId,
    List<RecordType>? requestedRecords,
    String? operatory,
    ReferralStatus? status,
    SyncState? syncState,
    DateTime? deletedAt,
    DateTime? expiresAt,
    bool clearDeletedAt = false,
    bool clearDestination = false,
    bool clearOperatory = false,
  }) =>
      ReferralDraft(
        id: id,
        humanCode: humanCode,
        professionalId: professionalId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        timezone: timezone,
        specialty: specialty ?? this.specialty,
        toothNotation: toothNotation ?? this.toothNotation,
        locations: locations ?? this.locations,
        reasons: reasons ?? this.reasons,
        findings: findings ?? this.findings,
        symptoms: symptoms ?? this.symptoms,
        urgency: urgency ?? this.urgency,
        referralDestinationId: clearDestination
            ? null
            : (referralDestinationId ?? this.referralDestinationId),
        requestedRecords: requestedRecords ?? this.requestedRecords,
        operatory: clearOperatory ? null : (operatory ?? this.operatory),
        status: status ?? this.status,
        syncState: syncState ?? this.syncState,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
        expiresAt: expiresAt ?? this.expiresAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'humanCode': humanCode,
        'professionalId': professionalId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'timezone': timezone,
        'specialty': specialty.wire,
        'toothNotation': toothNotation.wire,
        'locations': [for (final l in locations) l.toMap()],
        'reasons': reasons,
        'findings': findings,
        'symptoms': symptoms,
        'urgency': urgency.wire,
        if (referralDestinationId != null)
          'referralDestinationId': referralDestinationId,
        'requestedRecords': [for (final r in requestedRecords) r.wire],
        if (operatory != null) 'operatory': operatory,
        'status': status.wire,
        'syncState': syncState.wire,
        if (deletedAt != null)
          'deletedAt': deletedAt!.toUtc().toIso8601String(),
        if (expiresAt != null)
          'expiresAt': expiresAt!.toUtc().toIso8601String(),
      };

  static ReferralDraft fromMap(Map<String, dynamic> map) {
    DateTime parse(Object? value, {DateTime? fallback}) => switch (value) {
          final String s =>
            DateTime.tryParse(s)?.toUtc() ?? fallback ?? DateTime.utc(1970),
          _ => fallback ?? DateTime.utc(1970),
        };

    final created = parse(map['createdAt']);
    return ReferralDraft(
      id: (map['id'] as String?) ?? '',
      humanCode: (map['humanCode'] as String?) ?? '',
      professionalId: (map['professionalId'] as String?) ?? '',
      createdAt: created,
      updatedAt: parse(map['updatedAt'], fallback: created),
      timezone: (map['timezone'] as String?) ?? 'UTC',
      specialty:
          Specialty.fromWire(map['specialty'] as String?) ?? Specialty.other,
      toothNotation: ToothNotation.fromWire(map['toothNotation'] as String?),
      locations: [
        for (final raw in (map['locations'] as List?) ?? const [])
          if (ReferralLocation.fromMap((raw as Map).cast<String, dynamic>())
              case final l?)
            l,
      ],
      reasons: ((map['reasons'] as List?) ?? const []).cast<String>(),
      findings: ((map['findings'] as List?) ?? const []).cast<String>(),
      symptoms: ((map['symptoms'] as List?) ?? const []).cast<String>(),
      urgency: Urgency.fromWire(map['urgency'] as String?),
      referralDestinationId: map['referralDestinationId'] as String?,
      requestedRecords: [
        for (final raw in (map['requestedRecords'] as List?) ?? const [])
          if (RecordType.fromWire(raw as String?) case final r?) r,
      ],
      operatory: map['operatory'] as String?,
      status: ReferralStatus.fromWire(map['status'] as String?),
      syncState: SyncState.fromWire(map['syncState'] as String?),
      deletedAt: switch (map['deletedAt']) {
        final String s => DateTime.tryParse(s)?.toUtc(),
        _ => null,
      },
      expiresAt: switch (map['expiresAt']) {
        final String s => DateTime.tryParse(s)?.toUtc(),
        _ => null,
      },
    );
  }

  /// Key fragments that must never appear in [toMap].
  ///
  /// Enforced by test rather than convention, so a future field called
  /// `patientChartNumber` fails the build instead of shipping.
  static const List<String> forbiddenKeyFragments = [
    'patient',
    'name',
    'dob',
    'birth',
    'chart',
    'insurance',
    'phone',
    'email',
    'address',
    'appointment',
    'transcript',
    'audio',
    'mrn',
    'health',
  ];

  /// Redacted on purpose.
  ///
  /// An accidental interpolation into a log line or an exception message is the
  /// most common way clinical detail escapes, so the default rendering carries
  /// none.
  @override
  String toString() => 'ReferralDraft($humanCode, ${status.wire})';
}
