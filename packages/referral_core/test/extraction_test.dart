import 'package:referral_core/referral_core.dart';
import 'package:test/test.dart';

const extractor = RuleBasedExtractionService();

ProfessionalReferralPreferences prefs({
  ToothNotation notation = ToothNotation.fdi,
}) =>
    ProfessionalReferralPreferences(
      professionalId: 'prof-1',
      toothNotation: notation,
      timezone: 'America/Edmonton',
    );

ParsedReferralResult parse(
  String phrase, {
  ToothNotation notation = ToothNotation.fdi,
}) =>
    extractor.extract(phrase, prefs(notation: notation));

List<String> toothCodes(ParsedReferralResult r) => [
      for (final l in r.locations)
        if (l.kind == LocationKind.tooth) l.toothCode!,
    ];

void main() {
  group('canonical phrases', () {
    test('"Endo, 36, necrotic."', () {
      final r = parse('Endo, 36, necrotic.');
      expect(r.specialty, Specialty.endodontics);
      expect(toothCodes(r), ['36']);
      expect(r.reasons, ['suspected_pulp_necrosis']);
      expect(r.needsClarification, isFalse);
    });

    test('the full success-criteria utterance', () {
      final r = parse(
        'Endo, tooth 36, suspected necrosis with apical pathology, '
        'spontaneous pain, soon, usual endodontist, PA required.',
      );
      expect(r.specialty, Specialty.endodontics);
      expect(toothCodes(r), ['36']);
      expect(r.reasons, ['suspected_pulp_necrosis']);
      expect(r.findings, ['apical_pathology']);
      expect(r.symptoms, ['spontaneous_pain']);
      expect(r.urgency, Urgency.soon);
      expect(r.useDefaultDestination, isTrue);
      expect(r.requestedRecords, [RecordType.periapical]);
      expect(r.missingRequiredFields, isEmpty);
      expect(r.needsClarification, isFalse);
      expect(r.unrecognisedSegments, isEmpty);
    });

    test('"Oral surgery, 18 and 28, impacted thirds, panoramic."', () {
      final r = parse('Oral surgery, 18 and 28, impacted thirds, panoramic.');
      expect(r.specialty, Specialty.oralSurgery);
      expect(toothCodes(r), ['18', '28']);
      expect(r.reasons, ['impacted_third_molars']);
      expect(r.requestedRecords, [RecordType.panoramic]);
    });

    test('"Perio, generalized bone loss."', () {
      final r = parse('Perio, generalized bone loss.');
      expect(r.specialty, Specialty.periodontics);
      expect(r.reasons, ['bone_loss']);
      expect(
        r.locations.single.kind,
        LocationKind.generalized,
      );
    });

    test('"Perio, lower anterior, severe recession and mobility."', () {
      final r = parse('Perio, lower anterior, severe recession and mobility.');
      expect(r.specialty, Specialty.periodontics);
      expect(r.locations.single.region, OralRegion.lowerAnterior);
      expect(r.reasons, containsAll(['recession', 'mobility']));
      expect(r.missingRequiredFields, isEmpty);
    });

    test(
        '"Endo, 46, cracked tooth, lingering cold and percussion '
        'sensitive, urgent."', () {
      final r = parse(
        'Endo, 46, cracked tooth, lingering cold and percussion sensitive, '
        'urgent.',
      );
      expect(r.specialty, Specialty.endodontics);
      expect(toothCodes(r), ['46']);
      expect(r.reasons, ['cracked_tooth']);
      expect(
        r.symptoms,
        containsAll(['lingering_cold', 'percussion_sensitivity']),
      );
      expect(r.urgency, Urgency.urgent);
    });

    test('"Perio, generalized, routine assessment." keeps both meanings', () {
      // "routine" is an urgency and "routine assessment" is a reason. The
      // concept has to win, or the reason disappears.
      final r = parse('Perio, generalized, routine assessment.');
      expect(r.reasons, ['periodontal_assessment']);
      expect(r.urgency, Urgency.unspecified);
    });

    test('spoken number words become tooth numbers', () {
      final r = parse('Endo, tooth thirty six, necrotic.');
      expect(toothCodes(r), ['36']);
    });

    test('digit-by-digit speech after a tooth cue is joined', () {
      final r = parse('Endo, tooth three six, necrotic.');
      expect(toothCodes(r), ['36']);
    });
  });

  group('never invents', () {
    test('unstated urgency stays unspecified, not routine', () {
      final r = parse('Endo, 36, necrotic.');
      expect(r.urgency, Urgency.unspecified);
      expect(r.urgency, isNot(Urgency.routine));
    });

    test('unstated clinical fields stay empty', () {
      final r = parse('Endo, 36, necrotic.');
      expect(r.findings, isEmpty);
      expect(r.symptoms, isEmpty);
      expect(r.requestedRecords, isEmpty);
      expect(r.useDefaultDestination, isFalse);
    });
  });

  group('clarification', () {
    test('asks once for a missing required reason', () {
      final r = parse('Endo referral, 36.');
      expect(r.specialty, Specialty.endodontics);
      expect(r.missingRequiredFields, contains(ReferralField.reason));
      expect(r.clarification!.kind, ClarificationKind.missingRequiredField);
      expect(r.clarification!.prompt, 'Reason?');
    });

    test('asks about a tooth that is not valid in the configured notation', () {
      final r = parse('Endo, 36, necrotic.', notation: ToothNotation.universal);
      final c = r.clarification!;
      expect(c.kind, ClarificationKind.confirmToothAcrossNotation);
      expect(c.candidate, '36');
      expect(c.prompt, contains('36'));
      // The location is kept as spoken, with no canonical translation.
      expect(r.locations.single.canonicalFdi, isNull);
    });

    test('a valid Universal tooth raises no question', () {
      final r = parse('Endo, 19, necrotic.', notation: ToothNotation.universal);
      expect(r.needsClarification, isFalse);
      expect(r.locations.single.canonicalFdi, '36');
    });

    test('asks about a number that is not a tooth anywhere', () {
      final r = parse('Endo, 99, necrotic.');
      expect(r.clarification!.kind, ClarificationKind.confirmUnknownTooth);
    });

    test('only ever asks one question', () {
      final r = parse('Endo, 99.');
      expect(r.clarification, isNotNull);
      expect(r.missingRequiredFields, contains(ReferralField.reason));
      // Tooth trouble outranks the missing reason; the second question waits.
      expect(r.clarification!.field, ReferralField.location);
    });
  });

  group('does not lose what it did not understand', () {
    test('reports an unmapped segment instead of dropping it', () {
      final r = parse('Endo, 36, necrotic, weird periapical thing, not sure.');
      expect(r.reasons, ['suspected_pulp_necrosis']);
      expect(r.unrecognisedSegments, isNotEmpty);
      expect(r.unrecognisedSegments.join(' '), contains('not sure'));
    });

    test('filler-only segments are not reported as unrecognised', () {
      final r = parse('Endo, 36, necrotic, please.');
      expect(r.unrecognisedSegments, isEmpty);
    });
  });

  group('locations', () {
    test('quadrants', () {
      final r = parse('Perio, upper right, bone loss.');
      expect(r.locations.single.quadrant, Quadrant.upperRight);
    });

    test('full mouth', () {
      final r = parse('Perio, full mouth, bone loss.');
      expect(r.locations.single.kind, LocationKind.fullMouth);
    });

    test('Palmer speech combines quadrant and tooth', () {
      final r = parse('Endo, lower left six, necrotic.',
          notation: ToothNotation.palmer);
      expect(toothCodes(r), ['LL6']);
      expect(r.locations.single.canonicalFdi, '36');
    });
  });

  group('operatory', () {
    test('is captured when spoken and never treated as a tooth', () {
      final r = parse('Endo, op 3, tooth 36, necrotic.');
      expect(toothCodes(r), ['36'], reason: '3 is a room, not a tooth');
    });
  });

  group('robustness', () {
    test('an empty transcript yields nothing and does not throw', () {
      final r = parse('');
      expect(r.isEmpty, isTrue);
      expect(r.specialty, isNull);
      expect(r.blockedByIdentifier, isFalse);
    });

    test('punctuation alone yields nothing', () {
      expect(parse('... , , .').isEmpty, isTrue);
    });

    test('unrecognised speech asks which specialty', () {
      final r = parse('something completely unrelated');
      expect(r.specialty, isNull);
      expect(r.clarification!.field, ReferralField.specialty);
      expect(r.clarification!.prompt, 'Which specialty?');
    });

    test('is case insensitive', () {
      final r = parse('ENDO, 36, NECROTIC.');
      expect(r.specialty, Specialty.endodontics);
      expect(r.reasons, ['suspected_pulp_necrosis']);
    });

    test('handles a long rambling utterance without throwing', () {
      final r = parse(
        'so endo referral please for tooth 36 which I think is necrotic '
        'with apical pathology and spontaneous pain, soon if possible, '
        'my usual endodontist, and a PA would be helpful, thanks',
      );
      expect(r.specialty, Specialty.endodontics);
      expect(toothCodes(r), ['36']);
      expect(r.urgency, Urgency.soon);
    });

    test('repeated concepts are recorded once', () {
      final r = parse('Endo, 36, necrotic, necrotic, necrosis.');
      expect(r.reasons, ['suspected_pulp_necrosis']);
    });
  });

  test('the guardrail blocks before anything is extracted', () {
    final r = parse('Endo for John Smith, phone 403-555-0199, tooth 36.');
    expect(r.blockedByIdentifier, isTrue);
    expect(r.specialty, isNull);
    expect(r.locations, isEmpty);
    expect(r.reasons, isEmpty);
    expect(r.isEmpty, isTrue);
  });
}
