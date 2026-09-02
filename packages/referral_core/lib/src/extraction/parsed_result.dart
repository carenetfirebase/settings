import '../enums.dart';
import '../guardrail/guardrail.dart';
import '../tooth/location.dart';
import '../tooth/tooth.dart';

/// Why a field scored the way it did. Used to choose what to ask about, and to
/// explain the question in the UI.
enum ConfidenceReason {
  exactPhrase,
  quadrantOrRegion,

  /// A tooth code that is real in the professional's own notation.
  toothValidInConfiguredNotation,

  /// A tooth code that is not a tooth in the professional's notation but is one
  /// in another. Never rewritten — always asked about.
  toothValidOnlyInOtherNotation,

  /// A number that is not a tooth in any supported notation.
  toothUnknown,

  notStated,
}

/// Confidence in one extracted field. Internal: the professional sees a
/// question or nothing, never a percentage.
class FieldConfidence {
  const FieldConfidence(this.field, this.value, this.reason);

  final ReferralField field;
  final double value;
  final ConfidenceReason reason;

  /// Below this, a critical field is worth one question.
  static const double clarificationThreshold = 0.75;

  bool get needsClarification => value < clarificationThreshold;

  @override
  String toString() =>
      'FieldConfidence(${field.wire}, ${value.toStringAsFixed(2)})';
}

/// What the professional should be asked, if anything.
enum ClarificationKind {
  /// "Did you say tooth 36?" — the code is not a tooth in their notation.
  confirmToothAcrossNotation,

  /// The number is not a tooth anywhere.
  confirmUnknownTooth,

  /// A required field the template needs and the utterance did not supply.
  missingRequiredField,
}

class Clarification {
  const Clarification({
    required this.kind,
    required this.field,
    required this.prompt,
    this.candidate,
  });

  final ClarificationKind kind;
  final ReferralField field;

  /// Short enough to read at a glance while walking.
  final String prompt;

  /// The value in question, if there is one.
  final String? candidate;

  @override
  String toString() => 'Clarification(${kind.name}, ${field.wire})';
}

/// Structured output of one capture.
///
/// Holds no transcript. [unrecognisedSegments] carries the fragments that
/// matched nothing so the UI can offer them back to the professional; it is
/// transient and is never written to a draft or to storage.
class ParsedReferralResult {
  const ParsedReferralResult({
    this.identifierCategories = const {},
    this.specialty,
    this.locations = const [],
    this.toothInterpretations = const [],
    this.reasons = const [],
    this.findings = const [],
    this.symptoms = const [],
    this.urgency = Urgency.unspecified,
    this.useDefaultDestination = false,
    this.requestedRecords = const [],
    this.operatory,
    this.confidences = const [],
    this.missingRequiredFields = const {},
    this.unrecognisedSegments = const [],
    this.clarification,
  });

  /// A result produced when the guardrail tripped. Everything else is empty:
  /// the transcript was discarded rather than parsed.
  const ParsedReferralResult.blockedByGuardrail(
    Set<IdentifierCategory> categories,
  ) : this(identifierCategories: categories);

  final Set<IdentifierCategory> identifierCategories;
  final Specialty? specialty;
  final List<ReferralLocation> locations;

  /// One entry per spoken tooth code, including the ones that failed, so the UI
  /// can explain what it is asking about.
  final List<ToothInterpretation> toothInterpretations;

  final List<String> reasons;
  final List<String> findings;
  final List<String> symptoms;
  final Urgency urgency;

  /// The professional said "usual" or "default" — resolve against their
  /// configured destination for this specialty.
  final bool useDefaultDestination;

  final List<RecordType> requestedRecords;

  /// The room, when the professional named one ("op three"). Clinic
  /// infrastructure, not a patient identifier — it is what lets staff tell two
  /// drafts captured minutes apart from one another.
  final String? operatory;

  final List<FieldConfidence> confidences;
  final Set<ReferralField> missingRequiredFields;

  /// Fragments that mapped to nothing. Shown so clinical detail is never
  /// dropped in silence. Not persisted.
  final List<String> unrecognisedSegments;

  final Clarification? clarification;

  bool get blockedByIdentifier => identifierCategories.isNotEmpty;

  bool get needsClarification => clarification != null;

  /// True when nothing at all could be made of the utterance.
  bool get isEmpty =>
      specialty == null &&
      locations.isEmpty &&
      reasons.isEmpty &&
      findings.isEmpty &&
      symptoms.isEmpty &&
      urgency == Urgency.unspecified &&
      requestedRecords.isEmpty;

  FieldConfidence? confidenceFor(ReferralField field) {
    for (final c in confidences) {
      if (c.field == field) return c;
    }
    return null;
  }

  @override
  String toString() => 'ParsedReferralResult(${specialty?.wire ?? 'none'}, '
      '${locations.length} location(s))';
}
