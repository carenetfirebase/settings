import 'package:referral_core/referral_core.dart';

/// A repository that keeps drafts in memory, scoped by professional.
///
/// It mirrors the contract a Firestore implementation must honour: every read
/// is scoped by the owning account, so a draft cannot be reached by guessing
/// its id. In production that scoping is enforced by the security rule and the
/// collection layout, not by this class.
class InMemoryReferralDraftRepository implements ReferralDraftRepository {
  final Map<String, Map<String, ReferralDraft>> _byProfessional = {};

  int writeCount = 0;

  Map<String, ReferralDraft> _bucket(String professionalId) =>
      _byProfessional.putIfAbsent(professionalId, () => {});

  int countFor(String professionalId) => _bucket(professionalId).length;

  @override
  Future<void> save(ReferralDraft draft) async {
    writeCount++;
    // Keyed by the draft's own id, so a repeated save replaces rather than
    // appends. This is what makes a double tap harmless.
    _bucket(draft.professionalId)[draft.id] = draft;
  }

  @override
  Future<ReferralDraft?> byId(String professionalId, String id) async =>
      _bucket(professionalId)[id];

  @override
  Future<ReferralDraft?> byHumanCode(String professionalId, String code) async {
    final wanted = ReferralCode.normalise(code);
    for (final draft in _bucket(professionalId).values) {
      if (ReferralCode.normalise(draft.humanCode) == wanted) return draft;
    }
    return null;
  }

  @override
  Future<bool> isCodeTaken(String professionalId, String code) async =>
      await byHumanCode(professionalId, code) != null;

  @override
  Future<List<ReferralDraft>> list(
    String professionalId, {
    ReferralStatus? status,
    bool includeDeleted = false,
  }) async =>
      [
        for (final d in _bucket(professionalId).values)
          if ((includeDeleted || !d.isDeleted) &&
              (status == null || d.status == status))
            d,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<List<ReferralDraft>> near(
    String professionalId,
    DateTime around, {
    Duration window = const Duration(minutes: 15),
  }) async =>
      [
        for (final d in _bucket(professionalId).values)
          if (!d.isDeleted &&
              d.createdAt.difference(around.toUtc()).abs() <= window)
            d,
      ];

  @override
  Future<void> softDelete(String professionalId, String id, DateTime at) async {
    final draft = _bucket(professionalId)[id];
    if (draft == null) return;
    _bucket(professionalId)[id] =
        draft.copyWith(deletedAt: at.toUtc(), updatedAt: at.toUtc());
  }

  @override
  Future<void> restore(String professionalId, String id) async {
    final draft = _bucket(professionalId)[id];
    if (draft == null) return;
    _bucket(professionalId)[id] = draft.copyWith(clearDeletedAt: true);
  }

  @override
  Future<void> purge(String professionalId, String id) async {
    _bucket(professionalId).remove(id);
  }
}
