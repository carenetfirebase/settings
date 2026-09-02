import 'codes/codes.dart';
import 'enums.dart';
import 'extraction/parsed_result.dart';
import 'models/destination.dart';
import 'models/draft.dart';
import 'models/preferences.dart';

/// Assembles a saveable draft from an extraction result.
///
/// The id and code are created here, before any write, which is what makes
/// saving idempotent: a double tap, a retry and an offline replay all address
/// the same document.
abstract final class DraftFactory {
  static ReferralDraft fromParsed({
    required ParsedReferralResult parsed,
    required ProfessionalReferralPreferences preferences,
    required Clock clock,
    required bool Function(String code) isCodeTaken,
    Iterable<ReferralDestination> destinations = const [],
    String? operatory,
    String? id,
    String? humanCode,
  }) {
    if (parsed.blockedByIdentifier) {
      throw StateError(
        'Refusing to build a draft from a transcript the guardrail rejected.',
      );
    }
    final specialty = parsed.specialty;
    if (specialty == null) {
      throw StateError('Refusing to build a draft without a specialty.');
    }

    final now = clock.nowUtc();

    ReferralDestination? destination;
    if (parsed.useDefaultDestination) {
      destination = DestinationResolver.defaultFor(destinations, specialty);
    }

    final retention = Duration(days: preferences.draftRetentionDays);

    return ReferralDraft(
      id: id ?? Uuid.v4(),
      humanCode: humanCode ?? ReferralCode.generateUnique(isCodeTaken),
      professionalId: preferences.professionalId,
      createdAt: now,
      updatedAt: now,
      timezone: preferences.timezone,
      specialty: specialty,
      toothNotation: preferences.toothNotation,
      locations: parsed.locations,
      reasons: parsed.reasons,
      findings: parsed.findings,
      symptoms: parsed.symptoms,
      // Carried across verbatim. Nothing here promotes an unstated urgency to
      // routine, or fills an empty clinical list with a plausible default.
      urgency: parsed.urgency,
      referralDestinationId: destination?.id,
      requestedRecords: parsed.requestedRecords,
      // Spoken room wins; then an explicit choice from the chip; then the
      // remembered one, which expires so a stale value cannot silently
      // attribute a draft to the wrong room.
      operatory: _firstNonEmpty([
        parsed.operatory,
        operatory,
        preferences.stickyOperatoryAt(now),
      ]),
      status: ReferralStatus.needsCompletion,
      syncState: SyncState.pending,
      expiresAt: now.add(retention),
    );
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final value in candidates) {
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
