import '../enums.dart';
import '../guardrail/guardrail.dart';
import '../models/preferences.dart';
import '../templates/templates.dart';
import '../tooth/location.dart';
import '../tooth/tooth.dart';
import 'normaliser.dart';
import 'parsed_result.dart';

/// Turns a transcript into structured referral fields.
///
/// The interface exists so the rule-based implementation can be replaced later
/// — by a model-backed one, for instance — behind an explicit decision rather
/// than by default. Nothing outside this package should depend on the
/// implementation type.
abstract class ReferralExtractionService {
  /// [transcript] is transient. Implementations must not retain, log or
  /// transmit it.
  ParsedReferralResult extract(
    String transcript,
    ProfessionalReferralPreferences preferences,
  );
}

class _Occurrence {
  const _Occurrence(this.start, this.end);
  final int start;
  final int end;
}

/// Deterministic extraction over the dental vocabulary.
///
/// Chosen over a model for the MVP because the grammar is narrow, the result is
/// testable against fixed phrases, it runs offline in milliseconds, and it
/// introduces no third-party processor for clinical speech.
class RuleBasedExtractionService implements ReferralExtractionService {
  const RuleBasedExtractionService();

  static const Map<Urgency, List<String>> _urgencyPhrases = {
    Urgency.urgent: [
      'as soon as possible',
      'right away',
      'immediately',
      'emergency',
      'emergent',
      'urgently',
      'urgent',
      'asap',
    ],
    Urgency.soon: [
      'this week',
      'expedited',
      'expedite',
      'promptly',
      'prompt',
      'shortly',
      'soon',
    ],
    Urgency.routine: [
      'when convenient',
      'non urgent',
      'not urgent',
      'no rush',
      'routinely',
      'elective',
      'routine',
    ],
  };

  static const Map<RecordType, List<String>> _recordPhrases = {
    RecordType.periodontalChart: [
      'periodontal charting',
      'periodontal chart',
      'perio chart',
    ],
    RecordType.panoramic: ['panoramic', 'panorex', 'opg', 'pan'],
    RecordType.cbct: ['cone beam', 'cbct'],
    RecordType.bitewing: ['bitewings', 'bitewing', 'bws', 'bw'],
    RecordType.periapical: ['periapicals', 'periapical', 'pas', 'pa'],
    RecordType.photographs: [
      'clinical photographs',
      'clinical photos',
      'photographs',
      'photograph',
      'pictures',
      'photos',
      'photo',
    ],
  };

  static const List<String> _defaultDestinationPhrases = [
    'my usual',
    'the usual',
    'as usual',
    'my regular',
    'my default',
    'default',
    'regular',
    'usual',
  ];

  static const Map<OralRegion, List<String>> _regionPhrases = {
    OralRegion.upperAnterior: ['upper anterior', 'maxillary anterior'],
    OralRegion.lowerAnterior: ['lower anterior', 'mandibular anterior'],
    OralRegion.upperPosterior: ['upper posterior', 'maxillary posterior'],
    OralRegion.lowerPosterior: ['lower posterior', 'mandibular posterior'],
    OralRegion.anterior: ['anterior'],
    OralRegion.posterior: ['posterior'],
  };

  static const Map<Quadrant, List<String>> _quadrantPhrases = {
    Quadrant.upperRight: ['upper right'],
    Quadrant.upperLeft: ['upper left'],
    Quadrant.lowerLeft: ['lower left'],
    Quadrant.lowerRight: ['lower right'],
  };

  static const List<String> _generalisedPhrases = [
    'generalised',
    'generalized',
    'general',
  ];

  static const List<String> _fullMouthPhrases = [
    'full mouth',
    'whole mouth',
    'full arch',
  ];

  /// Words that carry no clinical content, so a segment made only of these is
  /// not reported as unrecognised.
  static const Set<String> _filler = {
    'a',
    'an',
    'the',
    'and',
    'with',
    'for',
    'of',
    'to',
    'is',
    'are',
    'has',
    'have',
    'please',
    'i',
    'my',
    'need',
    'needs',
    'needed',
    'required',
    'require',
    'requires',
    'request',
    'requested',
    'referral',
    'refer',
    'referred',
    'send',
    'sending',
    'tooth',
    'teeth',
    'number',
    'op',
    'operatory',
    'room',
    'chair',
    'also',
    'plus',
    'some',
    'this',
    'that',
    'them',
    'they',
    'get',
    'seen',
    'out',
    'on',
    'in',
    'at',
    'it',
  };

  @override
  ParsedReferralResult extract(
    String transcript,
    ProfessionalReferralPreferences preferences,
  ) {
    // The guardrail runs first and its verdict is absolute: a tripped
    // transcript is discarded whole rather than partially salvaged.
    final screen = IdentifierGuardrail.screen(transcript);
    if (screen.tripped) {
      return ParsedReferralResult.blockedByGuardrail(screen.categories);
    }

    final text = Normaliser.normalise(transcript);
    if (text.isEmpty) return const ParsedReferralResult();

    final consumed = List<bool>.filled(text.length, false);
    final confidences = <FieldConfidence>[];

    // --- specialty -------------------------------------------------------
    Specialty? specialty;
    var specialtyStart = 1 << 30;
    for (final template in ReferralTemplates.active) {
      final hits = _consumeAll(text, template.synonyms, consumed);
      if (hits.isEmpty) continue;
      final earliest = hits.first.start;
      if (earliest < specialtyStart) {
        specialtyStart = earliest;
        specialty = template.specialty;
      }
    }
    if (specialty != null) {
      confidences.add(const FieldConfidence(
        ReferralField.specialty,
        0.99,
        ConfidenceReason.exactPhrase,
      ));
    }

    final template =
        specialty == null ? null : ReferralTemplates.forSpecialty(specialty);

    // --- default destination hint ----------------------------------------
    final useDefault =
        _consumeAll(text, _defaultDestinationPhrases, consumed).isNotEmpty;

    // --- clinical concepts ------------------------------------------------
    // Ahead of records on purpose: "periapical lesion" is a finding, and the
    // PA record matcher would otherwise claim the word "periapical" from it.
    final reasons = <String>[];
    final findings = <String>[];
    final symptoms = <String>[];
    if (template != null) {
      _collectConcepts(text, template.reasons, consumed, reasons);
      _collectConcepts(text, template.findings, consumed, findings);
      _collectConcepts(text, template.symptoms, consumed, symptoms);
    }

    // --- records ---------------------------------------------------------
    final records = <RecordType>[];
    for (final entry in _recordPhrases.entries) {
      if (_consumeAll(text, entry.value, consumed).isNotEmpty) {
        records.add(entry.key);
      }
    }

    // --- urgency ---------------------------------------------------------
    // After concepts: "routine" is an urgency, but "routine assessment" is a
    // periodontal reason, and the concept has to claim it first.
    var urgency = Urgency.unspecified;
    for (final entry in _urgencyPhrases.entries) {
      if (_consumeAll(text, entry.value, consumed).isNotEmpty) {
        // First stated urgency wins; nothing is inferred when none is stated.
        urgency = entry.key;
        break;
      }
    }
    if (urgency != Urgency.unspecified) {
      confidences.add(const FieldConfidence(
        ReferralField.urgency,
        0.97,
        ConfidenceReason.exactPhrase,
      ));
    }

    // --- operatory --------------------------------------------------------
    final operatory = _consumeOperatory(text, consumed);

    // --- locations --------------------------------------------------------
    final locations = <ReferralLocation>[];
    final interpretations = <ToothInterpretation>[];
    final notation = preferences.toothNotation;

    if (notation == ToothNotation.palmer) {
      _consumePalmerTeeth(text, consumed, locations, interpretations);
    }

    if (_consumeAll(text, _fullMouthPhrases, consumed).isNotEmpty) {
      locations.add(const ReferralLocation.fullMouth());
    }
    if (_consumeAll(text, _generalisedPhrases, consumed).isNotEmpty) {
      locations.add(const ReferralLocation.generalized());
    }
    for (final entry in _regionPhrases.entries) {
      if (_consumeAll(text, entry.value, consumed).isNotEmpty) {
        locations.add(ReferralLocation.region(entry.key));
      }
    }
    for (final entry in _quadrantPhrases.entries) {
      if (_consumeAll(text, entry.value, consumed).isNotEmpty) {
        locations.add(ReferralLocation.quadrant(entry.key));
      }
    }

    _consumeNumericTeeth(text, consumed, notation, locations, interpretations);
    _consumeLetterTeeth(text, consumed, notation, locations, interpretations);

    if (locations.isNotEmpty) {
      confidences.add(_locationConfidence(interpretations, locations));
    }

    // --- what was not understood -----------------------------------------
    final unrecognised = _unrecognisedSegments(text, consumed);

    // --- required fields ---------------------------------------------------
    final missing = <ReferralField>{};
    final required =
        template?.requiredFields ?? const {ReferralField.specialty};
    for (final field in required) {
      final satisfied = switch (field) {
        ReferralField.specialty => specialty != null,
        ReferralField.location => locations.isNotEmpty,
        ReferralField.reason => reasons.isNotEmpty,
        ReferralField.finding => findings.isNotEmpty,
        ReferralField.symptom => symptoms.isNotEmpty,
        ReferralField.urgency => urgency != Urgency.unspecified,
        ReferralField.destination => useDefault,
        ReferralField.records => records.isNotEmpty,
      };
      if (!satisfied) missing.add(field);
    }

    return ParsedReferralResult(
      specialty: specialty,
      locations: locations,
      toothInterpretations: interpretations,
      reasons: reasons,
      findings: findings,
      symptoms: symptoms,
      urgency: urgency,
      useDefaultDestination: useDefault,
      requestedRecords: records,
      operatory: operatory,
      confidences: confidences,
      missingRequiredFields: missing,
      unrecognisedSegments: unrecognised,
      clarification: _chooseClarification(interpretations, missing),
    );
  }

  // ---------------------------------------------------------------------
  // phrase matching
  // ---------------------------------------------------------------------

  /// Marks every occurrence of any phrase in [phrases], longest first so that
  /// "impacted third molars" wins over "impacted".
  static List<_Occurrence> _consumeAll(
    String text,
    List<String> phrases,
    List<bool> consumed,
  ) {
    final ordered = [...phrases]..sort((a, b) => b.length.compareTo(a.length));
    final hits = <_Occurrence>[];
    for (final phrase in ordered) {
      if (phrase.isEmpty) continue;
      final pattern = RegExp('\\b${_escape(phrase)}\\b');
      for (final match in pattern.allMatches(text)) {
        if (_isFree(consumed, match.start, match.end)) {
          _mark(consumed, match.start, match.end);
          hits.add(_Occurrence(match.start, match.end));
        }
      }
    }
    hits.sort((a, b) => a.start.compareTo(b.start));
    return hits;
  }

  static void _collectConcepts(
    String text,
    List<ClinicalConcept> concepts,
    List<bool> consumed,
    List<String> into,
  ) {
    // Longest synonym across the whole group first, so a concept with a more
    // specific phrase claims the text before a shorter one can.
    final ordered = [...concepts]..sort((a, b) {
        final aMax =
            a.synonyms.fold<int>(0, (m, s) => s.length > m ? s.length : m);
        final bMax =
            b.synonyms.fold<int>(0, (m, s) => s.length > m ? s.length : m);
        return bMax.compareTo(aMax);
      });
    for (final concept in ordered) {
      if (_consumeAll(text, concept.synonyms, consumed).isNotEmpty) {
        if (!into.contains(concept.id)) into.add(concept.id);
      }
    }
  }

  static String _escape(String value) =>
      value.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');

  static bool _isFree(List<bool> consumed, int start, int end) {
    for (var i = start; i < end; i++) {
      if (consumed[i]) return false;
    }
    return true;
  }

  static void _mark(List<bool> consumed, int start, int end) {
    for (var i = start; i < end; i++) {
      consumed[i] = true;
    }
  }

  /// The text with consumed spans blanked, so later passes only see what is
  /// still unclaimed.
  static String _remaining(String text, List<bool> consumed) {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      buffer.write(consumed[i] ? ' ' : text[i]);
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------
  // locations
  // ---------------------------------------------------------------------

  static String? _consumeOperatory(String text, List<bool> consumed) {
    final pattern = RegExp(r'\b(?:op|operatory|room|chair)\s+(\d{1,2})\b');
    for (final match in pattern.allMatches(text)) {
      if (!_isFree(consumed, match.start, match.end)) continue;
      _mark(consumed, match.start, match.end);
      return match.group(1);
    }
    return null;
  }

  static void _consumePalmerTeeth(
    String text,
    List<bool> consumed,
    List<ReferralLocation> locations,
    List<ToothInterpretation> interpretations,
  ) {
    final pattern = RegExp(
      r'\b(upper right|upper left|lower left|lower right)\s+([1-8])\b',
    );
    for (final match in pattern.allMatches(_remaining(text, consumed))) {
      if (!_isFree(consumed, match.start, match.end)) continue;
      _mark(consumed, match.start, match.end);
      final quadrant = switch (match.group(1)) {
        'upper right' => Quadrant.upperRight,
        'upper left' => Quadrant.upperLeft,
        'lower left' => Quadrant.lowerLeft,
        _ => Quadrant.lowerRight,
      };
      final code = '${quadrant.wire}${match.group(2)}';
      final interp = ToothInterpretation.of(code, ToothNotation.palmer);
      interpretations.add(interp);
      locations.add(ReferralLocation.tooth(
        code: code,
        notation: ToothNotation.palmer,
        canonicalFdi: interp.canonicalFdi,
      ));
    }
  }

  static void _consumeNumericTeeth(
    String text,
    List<bool> consumed,
    ToothNotation notation,
    List<ReferralLocation> locations,
    List<ToothInterpretation> interpretations,
  ) {
    for (final match
        in RegExp(r'\b\d{1,2}\b').allMatches(_remaining(text, consumed))) {
      if (!_isFree(consumed, match.start, match.end)) continue;
      _mark(consumed, match.start, match.end);
      final raw = match.group(0)!;
      final interp = ToothInterpretation.of(raw, notation);
      interpretations.add(interp);
      locations.add(ReferralLocation.tooth(
        code: raw,
        notation: notation,
        // Null unless it is a real tooth in the professional's own system.
        // Nothing is translated across notations without being asked.
        canonicalFdi: interp.canonicalFdi,
      ));
    }
  }

  static void _consumeLetterTeeth(
    String text,
    List<bool> consumed,
    ToothNotation notation,
    List<ReferralLocation> locations,
    List<ToothInterpretation> interpretations,
  ) {
    if (notation != ToothNotation.universal) return;
    // A bare letter is too weak a signal; require an explicit tooth cue.
    final pattern = RegExp(r'\b(?:tooth|teeth)\s+([a-t])\b');
    for (final match in pattern.allMatches(_remaining(text, consumed))) {
      final letterStart =
          match.start + match.group(0)!.indexOf(match.group(1)!);
      if (!_isFree(consumed, letterStart, match.end)) continue;
      _mark(consumed, letterStart, match.end);
      final raw = match.group(1)!.toUpperCase();
      final interp = ToothInterpretation.of(raw, notation);
      interpretations.add(interp);
      locations.add(ReferralLocation.tooth(
        code: raw,
        notation: notation,
        canonicalFdi: interp.canonicalFdi,
      ));
    }
  }

  static FieldConfidence _locationConfidence(
    List<ToothInterpretation> interpretations,
    List<ReferralLocation> locations,
  ) {
    if (interpretations.isEmpty) {
      return const FieldConfidence(
        ReferralField.location,
        0.90,
        ConfidenceReason.quadrantOrRegion,
      );
    }
    if (interpretations.any((i) => i.isUnknownEverywhere)) {
      return const FieldConfidence(
        ReferralField.location,
        0.20,
        ConfidenceReason.toothUnknown,
      );
    }
    if (interpretations.any((i) => i.isCrossNotationCandidate)) {
      return const FieldConfidence(
        ReferralField.location,
        0.45,
        ConfidenceReason.toothValidOnlyInOtherNotation,
      );
    }
    return const FieldConfidence(
      ReferralField.location,
      0.96,
      ConfidenceReason.toothValidInConfiguredNotation,
    );
  }

  // ---------------------------------------------------------------------
  // clarification and leftovers
  // ---------------------------------------------------------------------

  /// At most one question. Two in a row is a questionnaire, which is the thing
  /// this flow exists to avoid.
  static Clarification? _chooseClarification(
    List<ToothInterpretation> interpretations,
    Set<ReferralField> missing,
  ) {
    for (final i in interpretations) {
      if (i.isCrossNotationCandidate) {
        final others = i.alsoValidIn.map((n) => n.displayName).join(' or ');
        return Clarification(
          kind: ClarificationKind.confirmToothAcrossNotation,
          field: ReferralField.location,
          prompt: 'Did you say tooth ${i.raw}? '
              'That is not a ${i.configured.displayName} tooth — '
              'it is $others.',
          candidate: i.raw,
        );
      }
    }
    for (final i in interpretations) {
      if (i.isUnknownEverywhere) {
        return Clarification(
          kind: ClarificationKind.confirmUnknownTooth,
          field: ReferralField.location,
          prompt: 'Did you say tooth ${i.raw}?',
          candidate: i.raw,
        );
      }
    }
    for (final field in [
      ReferralField.specialty,
      ReferralField.location,
      ReferralField.reason,
    ]) {
      if (!missing.contains(field)) continue;
      return Clarification(
        kind: ClarificationKind.missingRequiredField,
        field: field,
        prompt: switch (field) {
          ReferralField.specialty => 'Which specialty?',
          ReferralField.location => 'Which tooth or area?',
          _ => 'Reason?',
        },
      );
    }
    return null;
  }

  /// Segments in which nothing at all was recognised.
  ///
  /// Surfaced so the professional can see what was not understood instead of
  /// it being dropped silently.
  static List<String> _unrecognisedSegments(
    String text,
    List<bool> consumed,
  ) {
    final out = <String>[];
    var offset = 0;
    for (final segment in text.split(',')) {
      final start = offset;
      final end = offset + segment.length;
      offset = end + 1;

      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;

      var anyConsumed = false;
      for (var i = start; i < end && i < consumed.length; i++) {
        if (consumed[i]) {
          anyConsumed = true;
          break;
        }
      }
      if (anyConsumed) continue;

      final meaningful = trimmed
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty && !_filler.contains(w))
          .toList();
      if (meaningful.isEmpty) continue;

      out.add(meaningful.join(' '));
    }
    return out;
  }
}
