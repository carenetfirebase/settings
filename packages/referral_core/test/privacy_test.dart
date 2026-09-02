import 'package:referral_core/referral_core.dart';
import 'package:test/test.dart';

ReferralDraft sampleDraft() => ReferralDraft(
      id: Uuid.v4(),
      humanCode: 'R7K4P',
      professionalId: 'prof-1',
      createdAt: DateTime.utc(2026, 9, 2, 16, 42),
      updatedAt: DateTime.utc(2026, 9, 2, 16, 42),
      timezone: 'America/Edmonton',
      specialty: Specialty.endodontics,
      toothNotation: ToothNotation.fdi,
      locations: [
        ReferralLocation.tooth(
          code: '36',
          notation: ToothNotation.fdi,
          canonicalFdi: '36',
        ),
      ],
      reasons: const ['suspected_pulp_necrosis'],
      findings: const ['apical_pathology'],
      symptoms: const ['spontaneous_pain'],
      urgency: Urgency.soon,
      requestedRecords: const [RecordType.periapical],
      operatory: '3',
    );

void main() {
  group('the draft cannot hold patient identity', () {
    test('no serialised key looks like an identifier', () {
      final keys = sampleDraft().toMap().keys.map((k) => k.toLowerCase());
      for (final key in keys) {
        for (final banned in ReferralDraft.forbiddenKeyFragments) {
          expect(
            key.contains(banned),
            isFalse,
            reason: 'ReferralDraft serialises "$key", which contains '
                '"$banned". Patient identity and raw capture data must not be '
                'stored on a draft.',
          );
        }
      }
    });

    test('the forbidden list actually covers what it claims', () {
      // Guards the guard: if someone empties the list, this fails.
      expect(ReferralDraft.forbiddenKeyFragments, contains('patient'));
      expect(ReferralDraft.forbiddenKeyFragments, contains('transcript'));
      expect(ReferralDraft.forbiddenKeyFragments, contains('audio'));
      expect(ReferralDraft.forbiddenKeyFragments, contains('dob'));
    });

    test('no transcript or audio survives extraction', () {
      const extractor = RuleBasedExtractionService();
      const prefs = ProfessionalReferralPreferences(professionalId: 'prof-1');
      final parsed = extractor.extract(
        'Endo, tooth 36, suspected necrosis, soon, PA required.',
        prefs,
      );
      final draft = DraftFactory.fromParsed(
        parsed: parsed,
        preferences: prefs,
        clock: FixedClock(DateTime.utc(2026, 9, 2, 16, 42)),
        isCodeTaken: (_) => false,
      );
      final serialised = draft.toMap().toString().toLowerCase();
      expect(serialised, isNot(contains('suspected necrosis')));
      expect(serialised, isNot(contains('required')));
      expect(serialised, isNot(contains('tooth 36')));
      // Only the standardised concept id survives.
      expect(draft.reasons, ['suspected_pulp_necrosis']);
    });
  });

  group('redaction', () {
    test('a draft renders without clinical detail', () {
      final s = sampleDraft().toString();
      expect(s, 'ReferralDraft(R7K4P, needs_completion)');
      expect(s, isNot(contains('36')));
      expect(s, isNot(contains('necrosis')));
    });

    test('preferences and destinations render without content', () {
      const prefs = ProfessionalReferralPreferences(professionalId: 'prof-1');
      expect(prefs.toString(), isNot(contains('America')));

      const dest = ReferralDestination(
        id: 'd1',
        professionalId: 'prof-1',
        specialty: Specialty.endodontics,
        providerName: 'Dr Michael Smith',
        clinicName: 'Calgary Endodontics',
      );
      expect(dest.toString(), isNot(contains('Michael')));
    });
  });

  group('analytics carries no clinical payload', () {
    test('clinical keys are stripped', () {
      final sanitised = ReferralAnalyticsParams.sanitise({
        'launch_source': 'menu',
        'latency_ms': 820,
        'specialty': 'endodontics',
        'tooth': '36',
        'urgency': 'soon',
        'reason': 'suspected_pulp_necrosis',
        'human_code': 'R7K4P',
        'transcript': 'endo 36 necrotic',
      });
      expect(sanitised.keys, ['launch_source', 'latency_ms']);
      expect(sanitised.containsKey('specialty'), isFalse);
      expect(sanitised.containsKey('human_code'), isFalse);
      expect(sanitised.containsKey('transcript'), isFalse);
    });

    test('the allow list contains nothing clinical', () {
      const clinical = [
        'specialty',
        'tooth',
        'reason',
        'finding',
        'symptom',
        'urgency',
        'transcript',
        'human_code',
        'operatory',
        'destination',
      ];
      for (final key in clinical) {
        expect(ReferralAnalyticsParams.allowed, isNot(contains(key)));
      }
    });

    test('event names are a fixed vocabulary', () {
      final wires = ReferralAnalyticsEvent.values.map((e) => e.wire).toList();
      expect(wires, contains('quick_referral_opened'));
      expect(wires, contains('referral_saved'));
      for (final wire in wires) {
        expect(wire, matches(RegExp(r'^[a-z_]+$')));
      }
    });
  });

  test('a rejected transcript produces nothing to store', () {
    const extractor = RuleBasedExtractionService();
    const prefs = ProfessionalReferralPreferences(professionalId: 'prof-1');
    final parsed = extractor.extract(
      'Endo 36 for Mr Smith, phone 403-555-0199',
      prefs,
    );
    expect(parsed.blockedByIdentifier, isTrue);
    expect(
      () => DraftFactory.fromParsed(
        parsed: parsed,
        preferences: prefs,
        clock: const SystemClock(),
        isCodeTaken: (_) => false,
      ),
      throwsStateError,
      reason: 'a blocked result must never become a saveable draft',
    );
  });
}
