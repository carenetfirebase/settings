import '../enums.dart';
import '../models/destination.dart';
import '../models/draft.dart';
import '../referral_time.dart';
import '../templates/templates.dart';

/// Builds the plain-text block staff paste into the clinic's own system.
///
/// This is the entire staff-side deliverable in the MVP, so it carries
/// everything needed to act — including the code, the time and the operatory,
/// which are what let staff work out which patient it belongs to from their
/// own schedule.
///
/// It contains no patient information, because the application holds none.
abstract final class HandoffFormatter {
  static String format(
    ReferralDraft draft, {
    required Duration utcOffset,
    ReferralDestination? destination,
  }) {
    final template = ReferralTemplates.forSpecialty(draft.specialty);
    final lines = <String>[
      '${draft.specialty.displayName} referral',
      'Reference: ${draft.humanCode}',
      'Captured: ${ReferralTime.formatStamp(draft.createdAt, utcOffset)}',
    ];

    if (draft.operatory case final op? when op.isNotEmpty) {
      lines.add('Operatory: $op');
    }

    if (draft.locations.isNotEmpty) {
      final where = draft.locations.map((l) => l.display()).join(', ');
      lines.add('Location: $where');
    }

    void addConcepts(String label, List<String> ids) {
      if (ids.isEmpty) return;
      final names = [
        for (final id in ids) template?.conceptById(id)?.display ?? id,
      ];
      lines.add('$label: ${names.join(', ')}');
    }

    addConcepts('Reason', draft.reasons);
    addConcepts('Findings', draft.findings);
    addConcepts('Symptoms', draft.symptoms);

    // Stated plainly rather than omitted: an urgency that was not given is
    // information, and leaving the line out invites someone to assume routine.
    lines.add('Urgency: ${draft.urgency.displayName}');

    if (destination != null) {
      lines.add('Preferred destination: ${destination.display}');
    }

    if (draft.requestedRecords.isNotEmpty) {
      final records =
          draft.requestedRecords.map((r) => r.displayName).join(', ');
      lines.add('Records to attach: $records');
    }

    lines
      ..add('')
      ..add(
        'Patient information is not stored in this application. '
        'Complete the referral using the clinic\'s approved system.',
      );

    return lines.join('\n');
  }

  /// One-line summary for an inbox row. No patient information, and no
  /// urgency invented when none was stated.
  static String inboxSummary(ReferralDraft draft) {
    final parts = <String>[draft.specialty.shortName];
    if (draft.locations.isNotEmpty) {
      parts.add(draft.locations.map((l) => l.display()).join(' / '));
    }
    if (draft.urgency != Urgency.unspecified) {
      parts.add(draft.urgency.displayName);
    }
    return parts.join(' · ');
  }
}
