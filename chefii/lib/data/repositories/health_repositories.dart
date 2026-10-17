import '../../domain/models/health.dart';
import '../../domain/models/professional.dart';
import '../errors.dart';
import '../paths.dart';
import '../store/doc_store.dart';

/// Private health records. Never stored under the household.
class HealthRepository {
  HealthRepository(this._store, {DateTime Function()? clock}) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DocStore _store;
  final DateTime Function() _clock;

  Stream<List<GlucoseEntry>> watchGlucose(String uid, {DateTime? since}) => _store
      .watchQuery(
        UserPaths(uid).glucose,
        QuerySpec(where: [if (since != null) Where('measuredAt', WhereOp.gte, since)], orderBy: 'measuredAt', descending: true, limit: 500),
      )
      .map((ds) => ds.map((d) => GlucoseEntry.fromMap(d.id, d.data)).toList());

  Future<GlucoseEntry> addGlucose({
    required String uid,
    required double value,
    required GlucoseUnit unit,
    required DateTime measuredAt,
    GlucoseContext context = GlucoseContext.other,
    String? note,
  }) async {
    final err = GlucoseEntry.validate(value, unit);
    if (err != null) throw ArgumentError(err);
    final e = GlucoseEntry(
      id: _store.newId(),
      uid: uid,
      valueMmolL: double.parse(GlucoseEntry.toMmol(value, unit).toStringAsFixed(2)),
      enteredUnit: unit,
      measuredAt: measuredAt.toUtc(),
      source: GlucoseSource.manual,
      createdAt: _clock(),
      context: context,
      note: note,
    );
    await _store.set('${UserPaths(uid).glucose}/${e.id}', e.toMap());
    return e;
  }

  Future<void> deleteGlucose(String uid, String id) => _store.delete('${UserPaths(uid).glucose}/$id');

  Stream<List<OralExposureEvent>> watchOral(String uid, {DateTime? since}) => _store
      .watchQuery(
        UserPaths(uid).oralExposures,
        QuerySpec(where: [if (since != null) Where('occurredAt', WhereOp.gte, since)], orderBy: 'occurredAt', descending: true, limit: 300),
      )
      .map((ds) => ds.map((d) => OralExposureEvent.fromMap(d.id, d.data)).toList());

  Future<void> addOral(String uid, OralExposureKind kind, DateTime at, {int? durationMinutes, String? note}) {
    final id = _store.newId();
    return _store.set(
      '${UserPaths(uid).oralExposures}/$id',
      OralExposureEvent(id: id, uid: uid, kind: kind, occurredAt: at.toUtc(), durationMinutes: durationMinutes, note: note).toMap(),
    );
  }

  Future<void> deleteOral(String uid, String id) => _store.delete('${UserPaths(uid).oralExposures}/$id');

  Stream<List<UserConcern>> watchConcerns(String uid) => _store
      .watchQuery(UserPaths(uid).concerns, const QuerySpec(orderBy: 'recordedAt', descending: true))
      .map((ds) => ds.map((d) => UserConcern.fromMap(d.id, d.data)).toList());

  Future<void> addConcern(String uid, ConcernArea area, String description, int severity) {
    final id = _store.newId();
    return _store.set(
      '${UserPaths(uid).concerns}/$id',
      UserConcern(id: id, uid: uid, area: area, description: description, recordedAt: _clock(), severity: severity).toMap(),
    );
  }

  Future<void> deleteConcern(String uid, String id) => _store.delete('${UserPaths(uid).concerns}/$id');
}

/// Client <-> professional sharing. Grant ids are deterministic so security
/// rules can authorise reads with a single `get()`.
class SharingRepository {
  SharingRepository(this._store, {DateTime Function()? clock}) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DocStore _store;
  final DateTime Function() _clock;

  Stream<List<ShareGrant>> watchMyGrants(String ownerUid) => _store
      .watchQuery(shareGrantsCollection, QuerySpec(where: [Where.eq('ownerUid', ownerUid)], orderBy: 'createdAt', descending: true))
      .map((ds) => ds.map((d) => ShareGrant.fromMap(d.id, d.data)).toList());

  Stream<List<ShareGrant>> watchGrantsForProfessional(String proUid) => _store
      .watchQuery(shareGrantsCollection, QuerySpec(where: [Where.eq('professionalUid', proUid)]))
      .map((ds) => ds.map((d) => ShareGrant.fromMap(d.id, d.data)).toList());

  Stream<ShareGrant?> watchGrant(String id) =>
      _store.watch('$shareGrantsCollection/$id').map((d) => d == null ? null : ShareGrant.fromMap(d.id, d.data));

  Future<ProfessionalProfile?> professional(String uid) async {
    final d = await _store.get('$professionalsCollection/$uid');
    return d == null ? null : ProfessionalProfile.fromMap(uid, d.data);
  }

  Stream<ProfessionalProfile?> watchProfessional(String uid) => _store
      .watch('$professionalsCollection/$uid')
      .map((d) => d == null ? null : ProfessionalProfile.fromMap(uid, d.data));

  /// Looks up a verified professional by the invite code they share with
  /// clients (stored on their profile as `inviteCode`).
  Future<ProfessionalProfile?> findProfessionalByCode(String code) async {
    final ds = await _store.query(
      professionalsCollection,
      QuerySpec(where: [Where.eq('inviteCode', code.trim().toUpperCase()), const Where.eq('status', 'verified')], limit: 1),
    );
    return ds.isEmpty ? null : ProfessionalProfile.fromMap(ds.first.id, ds.first.data);
  }

  Future<ShareGrant> grant({
    required String ownerUid,
    required String ownerName,
    required ProfessionalProfile professional,
    required List<ShareCategory> categories,
    required DateTime rangeStart,
    required Duration duration,
  }) async {
    if (!professional.isVerified) throw CodedStateError('Only verified professionals can be granted access.', AppErrorCode.sharingProfessionalNotVerified);
    if (categories.isEmpty) throw CodedArgumentError('Choose at least one category to share.', AppErrorCode.sharingNoCategories);
    final now = _clock();
    final g = ShareGrant(
      id: shareGrantId(ownerUid, professional.uid),
      ownerUid: ownerUid,
      ownerName: ownerName,
      professionalUid: professional.uid,
      professionalName: professional.displayName,
      categories: categories,
      rangeStart: rangeStart.toUtc(),
      expiresAt: now.add(duration),
      status: GrantStatus.active,
      createdAt: now,
    );
    await _store.transaction((tx) async {
      tx.set('$shareGrantsCollection/${g.id}', g.toMap());
      final auditId = _store.newId();
      tx.set('${UserPaths(ownerUid).audit}/$auditId', AuditEvent(
        id: auditId,
        actorUid: ownerUid,
        action: 'share.granted',
        target: professional.uid,
        at: now,
        detail: '${categories.map((c) => c.label).join(', ')} until ${g.expiresAt.toIso8601String().substring(0, 10)}',
      ).toMap());
    });
    return g;
  }

  Future<void> revoke(ShareGrant g) async {
    final now = _clock();
    await _store.transaction((tx) async {
      tx.set('$shareGrantsCollection/${g.id}', {'status': GrantStatus.revoked.name, 'revokedAt': now}, merge: true);
      final auditId = _store.newId();
      tx.set('${UserPaths(g.ownerUid).audit}/$auditId',
          AuditEvent(id: auditId, actorUid: g.ownerUid, action: 'share.revoked', target: g.professionalUid, at: now).toMap());
    });
  }

  Stream<List<ProfessionalAssessment>> watchAssessmentsForClient(String uid) => _store
      .watchQuery(assessmentsCollection, QuerySpec(where: [Where.eq('clientUid', uid), clientVisibleAssessments], orderBy: 'createdAt', descending: true))
      .map((ds) => ds.map((d) => ProfessionalAssessment.fromMap(d.id, d.data)).where((a) => a.status != AssessmentStatus.draft).toList());

  Stream<List<ProfessionalAssessment>> watchAssessmentsByProfessional(String proUid) => _store
      .watchQuery(assessmentsCollection, QuerySpec(where: [Where.eq('professionalUid', proUid)], orderBy: 'createdAt', descending: true))
      .map((ds) => ds.map((d) => ProfessionalAssessment.fromMap(d.id, d.data)).toList());

  Future<void> saveAssessment(ProfessionalAssessment a) => _store.set('$assessmentsCollection/${a.id}', a.toMap());

  String newAssessmentId() => _store.newId();

  /// Client response. Accepting never edits the meal plan automatically; the
  /// UI then offers explicit, individual actions.
  Future<void> respond(ProfessionalAssessment a, bool accept) => _store.set(
        '$assessmentsCollection/${a.id}',
        {'status': (accept ? AssessmentStatus.accepted : AssessmentStatus.declined).name, 'clientRespondedAt': _clock()},
        merge: true,
      );

  /// Append-only access log under the grant (readable by the client).
  Future<void> logAccess(ShareGrant g, {required String viewerUid, required String what}) {
    final id = _store.newId();
    return _store.set('$shareGrantsCollection/${g.id}/accessLog/$id', {
      'viewerUid': viewerUid,
      'what': what,
      'at': _clock(),
    });
  }

  Stream<List<Map<String, dynamic>>> watchAccessLog(String grantId) => _store
      .watchQuery('$shareGrantsCollection/$grantId/accessLog', const QuerySpec(orderBy: 'at', descending: true, limit: 50))
      .map((ds) => ds.map((d) => d.data).toList());

  /// Applies to become a professional reviewer. Verification of the
  /// registration happens out-of-band (functions: verifyProfessional).
  Future<void> applyAsProfessional(ProfessionalProfile p) =>
      _store.set('$professionalsCollection/${p.uid}', {...p.toMap(), 'status': VerificationStatus.pending.name});

  /// Professional-side read of a client's records, only within an active
  /// grant. Firestore rules enforce the same constraints server-side.
  Future<List<Map<String, dynamic>>> readClientCategory(ShareGrant g, ShareCategory c, {required String viewerUid}) async {
    final now = _clock();
    if (!g.isActiveAt(now) || !g.categories.contains(c) || g.professionalUid != viewerUid) {
      throw CodedStateError('No active permission for ${c.label}.', AppErrorCode.sharingNoActivePermission, {'category': c});
    }
    final base = UserPaths(g.ownerUid);
    final (String path, String timeField) = switch (c) {
      ShareCategory.journal || ShareCategory.nutrition => (base.journal, 'eatenAt'),
      ShareCategory.glucose => (base.glucose, 'measuredAt'),
      ShareCategory.oral => (base.oralExposures, 'occurredAt'),
      ShareCategory.concerns => (base.concerns, 'recordedAt'),
      ShareCategory.dietary => ('', ''),
    };
    if (c == ShareCategory.dietary) {
      final d = await _store.get(base.dietary);
      return d == null ? const [] : [d.data];
    }
    final ds = await _store.query(
      path,
      QuerySpec(where: [Where(timeField, WhereOp.gte, g.rangeStart)], orderBy: timeField, descending: true, limit: 200),
    );
    return ds.map((d) => {'id': d.id, ...d.data}).toList();
  }
}
