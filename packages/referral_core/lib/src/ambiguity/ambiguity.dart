import '../models/draft.dart';

/// Whether a draft can be told apart from its neighbours.
class AmbiguityAssessment {
  const AmbiguityAssessment({
    required this.isAmbiguous,
    required this.collidingCodes,
  });

  const AmbiguityAssessment.clear()
      : isAmbiguous = false,
        collidingCodes = const [];

  final bool isAmbiguous;

  /// Human codes of the drafts this one cannot be distinguished from.
  final List<String> collidingCodes;

  /// Wording for the inbox banner. Names no clinical detail.
  String get bannerText {
    final n = collidingCodes.length + 1;
    return '$n drafts captured close together · confirm carefully';
  }
}

/// Detects drafts that a timestamp alone cannot separate.
///
/// This exists because attribution is done by a human comparing a draft
/// against the clinic's own schedule, and that comparison silently fails when
/// two drafts fall minutes apart with nothing to tell them apart. Surfacing
/// the collision turns a silent misattribution risk into a visible warning.
///
/// An operatory resolves it: two drafts from different rooms are distinct
/// however close together they were captured.
abstract final class AmbiguityDetector {
  static const Duration defaultWindow = Duration(minutes: 15);

  static AmbiguityAssessment assess(
    ReferralDraft draft,
    Iterable<ReferralDraft> others, {
    Duration window = defaultWindow,
  }) {
    final colliding = <String>[];
    for (final other in others) {
      if (other.id == draft.id) continue;
      if (other.isDeleted || draft.isDeleted) continue;
      if (other.professionalId != draft.professionalId) continue;

      final gap =
          other.createdAt.toUtc().difference(draft.createdAt.toUtc()).abs();
      if (gap > window) continue;

      final a = draft.operatory;
      final b = other.operatory;
      // Different rooms tell them apart. A missing room on either side does
      // not, so that case stays ambiguous.
      if (a != null && b != null && a.isNotEmpty && b.isNotEmpty && a != b) {
        continue;
      }
      colliding.add(other.humanCode);
    }

    if (colliding.isEmpty) return const AmbiguityAssessment.clear();
    return AmbiguityAssessment(
      isAmbiguous: true,
      collidingCodes: colliding..sort(),
    );
  }

  /// Whether the capture flow should ask for an operatory on this save.
  ///
  /// Only when a collision is actually likely, so the question stays rare.
  static bool shouldPromptForOperatory(
    ReferralDraft draft,
    Iterable<ReferralDraft> recent, {
    Duration window = defaultWindow,
  }) {
    if (draft.operatory != null && draft.operatory!.isNotEmpty) return false;
    return assess(draft, recent, window: window).isAmbiguous;
  }
}
