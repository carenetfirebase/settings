import 'codec.dart';

enum ProfessionalKind {
  dietitian('Registered Dietitian'),
  dentist('Dentist'),
  dentalHygienist('Dental Hygienist'),
  physician('Physician'),
  nurse('Nurse / Diabetes Educator');

  const ProfessionalKind(this.label);
  final String label;
}

enum VerificationStatus { pending, verified, rejected, suspended }

class ProfessionalProfile {
  const ProfessionalProfile({
    required this.uid,
    required this.displayName,
    required this.kind,
    required this.regulatoryBody,
    required this.registrationNumber,
    required this.province,
    required this.status,
    this.email,
    this.verifiedAt,
  });

  final String uid;
  final String displayName;
  final ProfessionalKind kind;

  /// e.g. "College of Dietitians of Ontario".
  final String regulatoryBody;
  final String registrationNumber;
  final String province;
  final VerificationStatus status;
  final String? email;
  final DateTime? verifiedAt;

  bool get isVerified => status == VerificationStatus.verified;

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'kind': kind.name,
        'regulatoryBody': regulatoryBody,
        'registrationNumber': registrationNumber,
        'province': province,
        'status': status.name,
        if (email != null) 'email': email,
        if (verifiedAt != null) 'verifiedAt': verifiedAt,
      };

  static ProfessionalProfile fromMap(String uid, Map<String, dynamic> m) => ProfessionalProfile(
        uid: uid,
        displayName: readString(m, 'displayName'),
        kind: readEnum(ProfessionalKind.values, m['kind'], ProfessionalKind.dietitian),
        regulatoryBody: readString(m, 'regulatoryBody', ''),
        registrationNumber: readString(m, 'registrationNumber', ''),
        province: readString(m, 'province', ''),
        status: readEnum(VerificationStatus.values, m['status'], VerificationStatus.pending),
        email: m['email'] as String?,
        verifiedAt: readDateOrNull(m['verifiedAt']),
      );
}

/// Data a client can choose to share. Each maps to a private collection.
enum ShareCategory {
  journal('Food journal', 'journal'),
  nutrition('Nutrition estimates', 'journal'),
  glucose('Glucose journal', 'glucose'),
  oral('Smile & Food log', 'oralExposures'),
  concerns('Hair, skin & nails notes', 'concerns'),
  dietary('Allergies & preferences', 'private');

  const ShareCategory(this.label, this.collection);
  final String label;
  final String collection;
}

enum GrantStatus { invited, active, revoked, expired }

/// Explicit, time-bounded, revocable permission for one professional to read
/// selected categories of one client's private records.
/// Document id is deterministic: `{ownerUid}__{professionalUid}`.
class ShareGrant {
  const ShareGrant({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.professionalUid,
    required this.professionalName,
    required this.categories,
    required this.rangeStart,
    required this.expiresAt,
    required this.status,
    required this.createdAt,
    this.revokedAt,
    this.inviteCode,
  });

  final String id;
  final String ownerUid;
  final String ownerName;
  final String professionalUid;
  final String professionalName;
  final List<ShareCategory> categories;

  /// Only records on/after this instant are visible.
  final DateTime rangeStart;
  final DateTime expiresAt;
  final GrantStatus status;
  final DateTime createdAt;
  final DateTime? revokedAt;
  final String? inviteCode;

  bool isActiveAt(DateTime now) => status == GrantStatus.active && now.isBefore(expiresAt);

  ShareGrant copyWith({GrantStatus? status, DateTime? revokedAt, List<ShareCategory>? categories, DateTime? expiresAt}) =>
      ShareGrant(
        id: id,
        ownerUid: ownerUid,
        ownerName: ownerName,
        professionalUid: professionalUid,
        professionalName: professionalName,
        categories: categories ?? this.categories,
        rangeStart: rangeStart,
        expiresAt: expiresAt ?? this.expiresAt,
        status: status ?? this.status,
        createdAt: createdAt,
        revokedAt: revokedAt ?? this.revokedAt,
        inviteCode: inviteCode,
      );

  Map<String, dynamic> toMap() => {
        'ownerUid': ownerUid,
        'ownerName': ownerName,
        'professionalUid': professionalUid,
        'professionalName': professionalName,
        'categories': categories.map((c) => c.name).toList(),
        'rangeStart': rangeStart,
        'expiresAt': expiresAt,
        'status': status.name,
        'createdAt': createdAt,
        if (revokedAt != null) 'revokedAt': revokedAt,
        if (inviteCode != null) 'inviteCode': inviteCode,
      };

  static ShareGrant fromMap(String id, Map<String, dynamic> m) => ShareGrant(
        id: id,
        ownerUid: readString(m, 'ownerUid'),
        ownerName: readString(m, 'ownerName', ''),
        professionalUid: readString(m, 'professionalUid'),
        professionalName: readString(m, 'professionalName', ''),
        categories: readStrings(m['categories']).map((s) => readEnum(ShareCategory.values, s, ShareCategory.journal)).toList(),
        rangeStart: readDate(m['rangeStart']),
        expiresAt: readDate(m['expiresAt']),
        status: readEnum(GrantStatus.values, m['status'], GrantStatus.invited),
        createdAt: readDate(m['createdAt']),
        revokedAt: readDateOrNull(m['revokedAt']),
        inviteCode: m['inviteCode'] as String?,
      );
}

enum AssessmentStatus { draft, sharedWithClient, acknowledged, accepted, declined }

/// Written professional feedback. Suggestions never change a meal plan until
/// the client explicitly accepts them.
class ProfessionalAssessment {
  const ProfessionalAssessment({
    required this.id,
    required this.grantId,
    required this.clientUid,
    required this.professionalUid,
    required this.professionalName,
    required this.professionalCredentials,
    required this.summary,
    required this.recommendations,
    required this.status,
    required this.createdAt,
    this.reviewedRangeStart,
    this.reviewedRangeEnd,
    this.clientRespondedAt,
  });

  final String id;
  final String grantId;
  final String clientUid;
  final String professionalUid;
  final String professionalName;
  final String professionalCredentials;
  final String summary;
  final List<String> recommendations;
  final AssessmentStatus status;
  final DateTime createdAt;
  final DateTime? reviewedRangeStart;
  final DateTime? reviewedRangeEnd;
  final DateTime? clientRespondedAt;

  ProfessionalAssessment copyWith({AssessmentStatus? status, DateTime? clientRespondedAt}) => ProfessionalAssessment(
        id: id,
        grantId: grantId,
        clientUid: clientUid,
        professionalUid: professionalUid,
        professionalName: professionalName,
        professionalCredentials: professionalCredentials,
        summary: summary,
        recommendations: recommendations,
        status: status ?? this.status,
        createdAt: createdAt,
        reviewedRangeStart: reviewedRangeStart,
        reviewedRangeEnd: reviewedRangeEnd,
        clientRespondedAt: clientRespondedAt ?? this.clientRespondedAt,
      );

  Map<String, dynamic> toMap() => {
        'grantId': grantId,
        'clientUid': clientUid,
        'professionalUid': professionalUid,
        'professionalName': professionalName,
        'professionalCredentials': professionalCredentials,
        'summary': summary,
        'recommendations': recommendations,
        'status': status.name,
        'createdAt': createdAt,
        if (reviewedRangeStart != null) 'reviewedRangeStart': reviewedRangeStart,
        if (reviewedRangeEnd != null) 'reviewedRangeEnd': reviewedRangeEnd,
        if (clientRespondedAt != null) 'clientRespondedAt': clientRespondedAt,
      };

  static ProfessionalAssessment fromMap(String id, Map<String, dynamic> m) => ProfessionalAssessment(
        id: id,
        grantId: readString(m, 'grantId'),
        clientUid: readString(m, 'clientUid'),
        professionalUid: readString(m, 'professionalUid'),
        professionalName: readString(m, 'professionalName', ''),
        professionalCredentials: readString(m, 'professionalCredentials', ''),
        summary: readString(m, 'summary', ''),
        recommendations: readStrings(m['recommendations']),
        status: readEnum(AssessmentStatus.values, m['status'], AssessmentStatus.draft),
        createdAt: readDate(m['createdAt']),
        reviewedRangeStart: readDateOrNull(m['reviewedRangeStart']),
        reviewedRangeEnd: readDateOrNull(m['reviewedRangeEnd']),
        clientRespondedAt: readDateOrNull(m['clientRespondedAt']),
      );
}

/// Append-only audit trail entry (who accessed / changed what).
class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.actorUid,
    required this.action,
    required this.target,
    required this.at,
    this.detail,
  });

  final String id;
  final String actorUid;

  /// e.g. 'share.granted', 'share.revoked', 'pro.viewed:journal', 'export.requested'.
  final String action;
  final String target;
  final DateTime at;
  final String? detail;

  Map<String, dynamic> toMap() => {
        'actorUid': actorUid,
        'action': action,
        'target': target,
        'at': at,
        if (detail != null) 'detail': detail,
      };

  static AuditEvent fromMap(String id, Map<String, dynamic> m) => AuditEvent(
        id: id,
        actorUid: readString(m, 'actorUid'),
        action: readString(m, 'action'),
        target: readString(m, 'target', ''),
        at: readDate(m['at']),
        detail: m['detail'] as String?,
      );
}
