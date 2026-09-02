import 'enums.dart';
import 'models/destination.dart';
import 'models/draft.dart';
import 'models/preferences.dart';

/// Storage contract for referral drafts.
///
/// Every method is scoped by [professionalId] deliberately. Implementations
/// must enforce that scope at the datastore — with Firestore, by nesting under
/// the account's uid and matching it in a security rule — and never rely on
/// this signature or on UI filtering. One professional must not be able to
/// read another's drafts by guessing an id.
abstract class ReferralDraftRepository {
  /// Writes at the draft's own id, so a repeated save is the same write.
  Future<void> save(ReferralDraft draft);

  Future<ReferralDraft?> byId(String professionalId, String id);

  /// Resolves a code a human typed, tolerant of transcription slips.
  Future<ReferralDraft?> byHumanCode(String professionalId, String code);

  Future<bool> isCodeTaken(String professionalId, String code);

  Future<List<ReferralDraft>> list(
    String professionalId, {
    ReferralStatus? status,
    bool includeDeleted = false,
  });

  /// Drafts created within [window] of [around], for ambiguity detection.
  Future<List<ReferralDraft>> near(
    String professionalId,
    DateTime around, {
    Duration window,
  });

  /// Soft delete, so an undo has something to restore.
  Future<void> softDelete(String professionalId, String id, DateTime at);

  Future<void> restore(String professionalId, String id);

  /// Permanent removal, used by retention and by an explicit delete.
  Future<void> purge(String professionalId, String id);
}

abstract class ReferralDestinationRepository {
  Future<List<ReferralDestination>> list(String professionalId);
  Future<void> save(ReferralDestination destination);
  Future<void> delete(String professionalId, String id);
}

abstract class ReferralPreferencesRepository {
  Future<ProfessionalReferralPreferences?> load(String professionalId);
  Future<void> save(ProfessionalReferralPreferences preferences);
}

/// Product events safe to send to a general analytics provider.
///
/// The enum is the whole vocabulary: there is no free-form event name, and no
/// parameter carries clinical content. Specialty, tooth, findings, urgency,
/// referral codes and transcripts are all absent by construction rather than
/// by reviewer discipline.
enum ReferralAnalyticsEvent {
  quickReferralOpened('quick_referral_opened'),
  dictationStarted('dictation_started'),
  dictationFinished('dictation_finished'),
  clarificationRequired('clarification_required'),
  identifierGuardrailTripped('identifier_guardrail_tripped'),
  referralSaved('referral_saved'),
  referralUndone('referral_undone'),
  referralCompleted('referral_completed'),
  syncSucceeded('sync_succeeded'),
  syncFailed('sync_failed');

  const ReferralAnalyticsEvent(this.wire);

  final String wire;
}

/// Parameter keys permitted alongside an event.
///
/// Anything not on this list is dropped by the sink rather than passed through.
abstract final class ReferralAnalyticsParams {
  static const Set<String> allowed = {
    'launch_source',
    'input_mode',
    'latency_ms',
    'clarification_kind',
    'identifier_category_count',
    'error_code',
    'retry_count',
  };

  /// Strips anything outside [allowed].
  static Map<String, Object?> sanitise(Map<String, Object?> params) => {
        for (final entry in params.entries)
          if (allowed.contains(entry.key)) entry.key: entry.value,
      };
}
