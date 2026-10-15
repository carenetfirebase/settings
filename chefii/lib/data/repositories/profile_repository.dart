import '../../domain/models/codec.dart';
import '../../domain/models/planning.dart';
import '../../domain/models/professional.dart';
import '../../domain/models/profile.dart';
import '../paths.dart';
import '../store/doc_store.dart';

/// Private per-user data: profile, dietary safety, wellness, settings,
/// consents, routine, notifications and audit trail.
class ProfileRepository {
  ProfileRepository(this._store, {DateTime Function()? clock}) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DocStore _store;
  final DateTime Function() _clock;

  Stream<UserProfile?> watchProfile(String uid) =>
      _store.watch(UserPaths(uid).root).map((d) => d == null ? null : UserProfile.fromMap(uid, d.data));

  Future<UserProfile?> profile(String uid) async {
    final d = await _store.get(UserPaths(uid).root);
    return d == null ? null : UserProfile.fromMap(uid, d.data);
  }

  Future<UserProfile> ensureProfile({required String uid, required String displayName, String? email}) async {
    return _store.transaction((tx) async {
      final d = await tx.get(UserPaths(uid).root);
      if (d != null) return UserProfile.fromMap(uid, d.data);
      final p = UserProfile(uid: uid, displayName: displayName, email: email, createdAt: _clock());
      tx.set(UserPaths(uid).root, p.toMap());
      return p;
    });
  }

  Future<void> saveProfile(UserProfile p) => _store.set(UserPaths(p.uid).root, p.toMap(), merge: true);

  Future<void> updateProfileFields(String uid, Map<String, dynamic> fields) =>
      _store.set(UserPaths(uid).root, fields, merge: true);

  // Dietary safety
  Stream<DietaryProfile> watchDietary(String uid) =>
      _store.watch(UserPaths(uid).dietary).map((d) => DietaryProfile.fromMap(d?.data));

  Future<DietaryProfile> dietary(String uid) async =>
      DietaryProfile.fromMap((await _store.get(UserPaths(uid).dietary))?.data);

  Future<void> saveDietary(String uid, DietaryProfile p) =>
      _store.set(UserPaths(uid).dietary, p.copyWith(updatedAt: _clock()).toMap());

  // Wellness
  Stream<WellnessPreferences> watchWellness(String uid) =>
      _store.watch(UserPaths(uid).wellness).map((d) => WellnessPreferences.fromMap(d?.data));

  Future<void> saveWellness(String uid, WellnessPreferences w) => _store.set(UserPaths(uid).wellness, w.toMap());

  // Settings
  Stream<AppSettings> watchSettings(String uid) =>
      _store.watch(UserPaths(uid).settings).map((d) => AppSettings.fromMap(d?.data));

  Future<void> saveSettings(String uid, AppSettings s) => _store.set(UserPaths(uid).settings, s.toMap());

  // Morning routine
  Stream<MorningRoutine> watchMorningRoutine(String uid) =>
      _store.watch(UserPaths(uid).morningRoutine).map((d) => MorningRoutine.fromMap(d?.data));

  Future<void> saveMorningRoutine(String uid, MorningRoutine r) => _store.set(UserPaths(uid).morningRoutine, r.toMap());

  // Consents: append-only history; latest per purpose wins.
  Future<void> recordConsent(String uid, {required String purpose, required bool granted, String version = '1', String? text}) {
    final id = _store.newId();
    return _store.set(
      '${UserPaths(uid).consents}/$id',
      ConsentRecord(id: id, purpose: purpose, granted: granted, version: version, recordedAt: _clock(), text: text).toMap(),
    );
  }

  Stream<List<ConsentRecord>> watchConsents(String uid) => _store
      .watchQuery(UserPaths(uid).consents, const QuerySpec(orderBy: 'recordedAt', descending: true))
      .map((ds) => ds.map((d) => ConsentRecord.fromMap(d.id, d.data)).toList());

  static bool hasConsent(List<ConsentRecord> history, String purpose) {
    for (final c in history) {
      if (c.purpose == purpose) return c.granted;
    }
    return false;
  }

  // Notifications
  Stream<List<AppNotification>> watchNotifications(String uid) => _store
      .watchQuery(UserPaths(uid).notifications, const QuerySpec(orderBy: 'createdAt', descending: true, limit: 50))
      .map((ds) => ds.map((d) => AppNotification.fromMap(d.id, d.data)).toList());

  Future<void> addNotification(String uid, AppNotification n) =>
      _store.set('${UserPaths(uid).notifications}/${n.id}', n.toMap());

  Future<void> markNotificationRead(String uid, String id) =>
      _store.set('${UserPaths(uid).notifications}/$id', {'read': true}, merge: true);

  Future<void> markAllNotificationsRead(String uid, Iterable<String> ids) => _store.transaction((tx) async {
        for (final id in ids) {
          tx.set('${UserPaths(uid).notifications}/$id', {'read': true}, merge: true);
        }
      });

  // Audit
  Future<void> audit(String uid, {required String action, required String target, String? detail}) {
    final id = _store.newId();
    return _store.set(
      '${UserPaths(uid).audit}/$id',
      AuditEvent(id: id, actorUid: uid, action: action, target: target, at: _clock(), detail: detail).toMap(),
    );
  }

  Stream<List<AuditEvent>> watchAudit(String uid) => _store
      .watchQuery(UserPaths(uid).audit, const QuerySpec(orderBy: 'at', descending: true, limit: 100))
      .map((ds) => ds.map((d) => AuditEvent.fromMap(d.id, d.data)).toList());

  // Favourites (recipe ids)
  Stream<Set<String>> watchFavourites(String uid) =>
      _store.watchQuery(UserPaths(uid).favourites).map((ds) => ds.map((d) => d.id).toSet());

  Future<void> setFavourite(String uid, String recipeId, bool fav) => fav
      ? _store.set('${UserPaths(uid).favourites}/$recipeId', {'at': _clock()})
      : _store.delete('${UserPaths(uid).favourites}/$recipeId');

  Future<void> submitFeedback(String uid, {required String kind, required String message}) {
    final id = _store.newId();
    return _store.set('${UserPaths(uid).feedback}/$id', {'kind': kind, 'message': message, 'createdAt': _clock()});
  }
}

class HouseholdRepository {
  HouseholdRepository(this._store, {DateTime Function()? clock}) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DocStore _store;
  final DateTime Function() _clock;

  Stream<Household?> watchHousehold(String id) =>
      _store.watch(HouseholdPaths(id).root).map((d) => d == null ? null : Household.fromMap(id, d.data));

  Stream<List<HouseholdMember>> watchMembers(String id) => _store
      .watchQuery(HouseholdPaths(id).members)
      .map((ds) => ds.map((d) => HouseholdMember.fromMap(d.id, d.data)).toList());

  /// Creates the household, the owner's membership and links the profile —
  /// atomically, so there is never a household without an owner.
  Future<Household> createHousehold({
    required String uid,
    required String ownerName,
    required String name,
    required HouseholdType type,
    required int portions,
  }) {
    final id = _store.newId();
    final p = HouseholdPaths(id);
    return _store.transaction((tx) async {
      final profile = await tx.get(UserPaths(uid).root);
      final existing = profile?.data['householdId'] as String?;
      if (existing != null) {
        final hd = await tx.get(HouseholdPaths(existing).root);
        if (hd != null) return Household.fromMap(existing, hd.data);
      }
      final now = _clock();
      final h = Household(
        id: id,
        name: name,
        type: type,
        portions: portions,
        ownerUid: uid,
        memberUids: [uid],
        createdAt: now,
      );
      tx.set(p.root, h.toMap());
      tx.set(p.member(uid), HouseholdMember(uid: uid, displayName: ownerName, role: HouseholdRole.owner, joinedAt: now).toMap());
      tx.set(UserPaths(uid).root, {'householdId': id}, merge: true);
      return h;
    });
  }

  Future<void> updateHousehold(Household h) => _store.set(HouseholdPaths(h.id).root, h.toMap(), merge: true);

  Future<void> setSharedAllergens(String householdId, String uid, List<String> allergens) =>
      _store.set(HouseholdPaths(householdId).member(uid), {'sharedAllergens': allergens}, merge: true);

  /// Creates a single-use invite code. Joining is performed server-side
  /// (functions: acceptHouseholdInvite) in production.
  Future<String> createInvite(String householdId, String createdBy, {String role = 'adult'}) async {
    final code = _store.newId().substring(0, 8).toUpperCase();
    await _store.set('${HouseholdPaths(householdId).invites}/$code', {
      'code': code,
      'createdBy': createdBy,
      'role': role,
      'createdAt': _clock(),
      'expiresAt': _clock().add(const Duration(days: 7)),
      'used': false,
    });
    return code;
  }

  Stream<List<Map<String, dynamic>>> watchInvites(String householdId) => _store
      .watchQuery(HouseholdPaths(householdId).invites, const QuerySpec(where: [Where.eq('used', false)]))
      .map((ds) => ds.map((d) => d.data).toList());

  Future<void> removeMember(String householdId, String memberUid) => _store.transaction((tx) async {
        final hd = await tx.get(HouseholdPaths(householdId).root);
        if (hd == null) return;
        final h = Household.fromMap(householdId, hd.data);
        if (memberUid == h.ownerUid) throw StateError('The owner cannot be removed.');
        tx.set(HouseholdPaths(householdId).root, {'memberUids': h.memberUids.where((u) => u != memberUid).toList()}, merge: true);
        tx.delete(HouseholdPaths(householdId).member(memberUid));
      });

  CalendarDate today() => CalendarDate.fromDateTime(_clock().toLocal());
}
