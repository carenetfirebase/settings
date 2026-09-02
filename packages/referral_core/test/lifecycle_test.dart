import 'package:referral_core/referral_core.dart';
import 'package:test/test.dart';

import 'support/in_memory_repository.dart';

const extractor = RuleBasedExtractionService();

const prefs = ProfessionalReferralPreferences(
  professionalId: 'prof-1',
  timezone: 'America/Edmonton',
);

const destinations = [
  ReferralDestination(
    id: 'dest-endo',
    professionalId: 'prof-1',
    specialty: Specialty.endodontics,
    providerName: 'Dr Michael Smith',
    clinicName: 'Calgary Endodontics',
    isDefault: true,
  ),
  ReferralDestination(
    id: 'dest-endo-2',
    professionalId: 'prof-1',
    specialty: Specialty.endodontics,
    providerName: 'Dr Other',
    clinicName: 'Elsewhere Endo',
  ),
];

ReferralDraft build(
  String phrase, {
  DateTime? at,
  String? operatory,
  ProfessionalReferralPreferences? preferences,
}) {
  final p = preferences ?? prefs;
  return DraftFactory.fromParsed(
    parsed: extractor.extract(phrase, p),
    preferences: p,
    clock: FixedClock(at ?? DateTime.utc(2026, 9, 2, 16, 42)),
    isCodeTaken: (_) => false,
    destinations: destinations,
    operatory: operatory,
  );
}

void main() {
  group('saving is idempotent', () {
    test('saving the same draft twice creates one record', () async {
      final repo = InMemoryReferralDraftRepository();
      final draft = build('Endo, 36, necrotic.');

      await repo.save(draft);
      await repo.save(draft); // double tap
      await repo.save(draft.copyWith(syncState: SyncState.synced)); // replay

      expect(repo.writeCount, 3, reason: 'three writes were attempted');
      expect(repo.countFor('prof-1'), 1, reason: 'but one draft exists');
    });

    test('the id is generated before the first write', () {
      final draft = build('Endo, 36, necrotic.');
      expect(Uuid.isValid(draft.id), isTrue);
      expect(draft.syncState, SyncState.pending);
    });
  });

  group('authorisation', () {
    test('a draft is not reachable from another account', () async {
      final repo = InMemoryReferralDraftRepository();
      final draft = build('Endo, 36, necrotic.');
      await repo.save(draft);

      expect(await repo.byId('prof-1', draft.id), isNotNull);
      expect(await repo.byId('prof-2', draft.id), isNull);
      expect(await repo.list('prof-2'), isEmpty);
      expect(await repo.byHumanCode('prof-2', draft.humanCode), isNull);
    });
  });

  group('undo', () {
    test('soft delete hides the draft and restore brings it back', () async {
      final repo = InMemoryReferralDraftRepository();
      final draft = build('Endo, 36, necrotic.');
      await repo.save(draft);

      await repo.softDelete(
          'prof-1', draft.id, DateTime.utc(2026, 9, 2, 16, 43));
      expect(await repo.list('prof-1'), isEmpty);
      expect((await repo.byId('prof-1', draft.id))!.isDeleted, isTrue);

      await repo.restore('prof-1', draft.id);
      expect(await repo.list('prof-1'), hasLength(1));
      expect((await repo.byId('prof-1', draft.id))!.isDeleted, isFalse);
    });
  });

  group('retention', () {
    test('an expiry is set from the professional preference', () {
      final draft = build('Endo, 36, necrotic.');
      expect(draft.expiresAt, DateTime.utc(2026, 12, 1, 16, 42));
    });

    test('expiry is evaluated, not assumed', () {
      final draft = build('Endo, 36, necrotic.');
      expect(draft.isExpiredAt(DateTime.utc(2026, 11, 30)), isFalse);
      expect(draft.isExpiredAt(DateTime.utc(2027, 1, 1)), isTrue);
    });
  });

  group('default destination', () {
    test('"usual" resolves to the configured default', () {
      final draft = build('Endo, 36, necrotic, my usual endodontist.');
      expect(draft.referralDestinationId, 'dest-endo');
    });

    test('nothing is chosen when the professional did not ask for it', () {
      final draft = build('Endo, 36, necrotic.');
      expect(draft.referralDestinationId, isNull);
    });

    test('falls back to the only active destination when none is flagged', () {
      final resolved = DestinationResolver.defaultFor(
        const [
          ReferralDestination(
            id: 'only',
            professionalId: 'prof-1',
            specialty: Specialty.periodontics,
            providerName: 'Dr Jones',
          ),
        ],
        Specialty.periodontics,
      );
      expect(resolved!.id, 'only');
    });

    test('never borrows a destination from another specialty', () {
      final resolved =
          DestinationResolver.defaultFor(destinations, Specialty.oralSurgery);
      expect(resolved, isNull);
    });
  });

  group('operatory', () {
    test('a spoken room is recorded', () {
      final draft = build('Endo, op 3, tooth 36, necrotic.');
      expect(draft.operatory, '3');
    });

    test('a remembered room is offered inside the window', () {
      final p = prefs.copyWith(
        lastOperatory: '4',
        lastOperatoryAt: DateTime.utc(2026, 9, 2, 16, 0),
      );
      final draft = build('Endo, 36, necrotic.', preferences: p);
      expect(draft.operatory, '4');
    });

    test('a stale room is dropped rather than guessed', () {
      final p = prefs.copyWith(
        lastOperatory: '4',
        lastOperatoryAt: DateTime.utc(2026, 9, 1, 9, 0), // yesterday
      );
      final draft = build('Endo, 36, necrotic.', preferences: p);
      expect(draft.operatory, isNull,
          reason: 'a wrong room is worse than no room');
    });

    test('what was spoken beats what was remembered', () {
      final p = prefs.copyWith(
        lastOperatory: '4',
        lastOperatoryAt: DateTime.utc(2026, 9, 2, 16, 0),
      );
      final draft = build('Endo, op 7, tooth 36, necrotic.', preferences: p);
      expect(draft.operatory, '7');
    });
  });

  group('ambiguity', () {
    ReferralDraft at(int minute, {String? operatory}) => build(
          'Endo, 36, necrotic.',
          at: DateTime.utc(2026, 9, 2, 16, minute),
          operatory: operatory,
        );

    test('two drafts minutes apart with no room cannot be told apart', () {
      final a = at(42);
      final b = at(45);
      final assessment = AmbiguityDetector.assess(a, [b]);
      expect(assessment.isAmbiguous, isTrue);
      expect(assessment.collidingCodes, [b.humanCode]);
      expect(assessment.bannerText, contains('2 drafts'));
    });

    test('different rooms resolve it', () {
      final a = at(42, operatory: '3');
      final b = at(45, operatory: '5');
      expect(AmbiguityDetector.assess(a, [b]).isAmbiguous, isFalse);
    });

    test('the same room does not resolve it', () {
      final a = at(42, operatory: '3');
      final b = at(45, operatory: '3');
      expect(AmbiguityDetector.assess(a, [b]).isAmbiguous, isTrue);
    });

    test('drafts far apart in time do not collide', () {
      final a = at(0);
      final b = at(59);
      expect(AmbiguityDetector.assess(a, [b]).isAmbiguous, isFalse);
    });

    test('another professional draft is never a collision', () {
      final a = at(42);
      final b = at(45).copyWith();
      final other = ReferralDraft.fromMap(
        b.toMap()..['professionalId'] = 'prof-2',
      );
      expect(AmbiguityDetector.assess(a, [other]).isAmbiguous, isFalse);
    });

    test('prompts for a room only when a collision is likely', () {
      final alone = at(42);
      expect(AmbiguityDetector.shouldPromptForOperatory(alone, []), isFalse);

      final colliding = at(45);
      expect(
        AmbiguityDetector.shouldPromptForOperatory(alone, [colliding]),
        isTrue,
      );

      final withRoom = at(42, operatory: '3');
      expect(
        AmbiguityDetector.shouldPromptForOperatory(withRoom, [colliding]),
        isFalse,
      );
    });
  });

  group('serialisation', () {
    test('round-trips through a plain map', () {
      final draft = build(
        'Endo, op 3, tooth 36, suspected necrosis with apical pathology, '
        'spontaneous pain, soon, usual endodontist, PA required.',
      );
      final restored = ReferralDraft.fromMap(draft.toMap());

      expect(restored.id, draft.id);
      expect(restored.humanCode, draft.humanCode);
      expect(restored.specialty, draft.specialty);
      expect(restored.toothNotation, draft.toothNotation);
      expect(restored.locations, draft.locations);
      expect(restored.reasons, draft.reasons);
      expect(restored.findings, draft.findings);
      expect(restored.symptoms, draft.symptoms);
      expect(restored.urgency, draft.urgency);
      expect(restored.requestedRecords, draft.requestedRecords);
      expect(restored.operatory, draft.operatory);
      expect(restored.createdAt, draft.createdAt);
      expect(restored.expiresAt, draft.expiresAt);
      expect(restored.referralDestinationId, draft.referralDestinationId);
    });

    test('an unstated urgency survives a round trip as unspecified', () {
      final draft = build('Endo, 36, necrotic.');
      final restored = ReferralDraft.fromMap(draft.toMap());
      expect(restored.urgency, Urgency.unspecified);
    });

    test('preferences round-trip', () {
      final p = prefs.copyWith(
        toothNotation: ToothNotation.universal,
        lastOperatory: '3',
        lastOperatoryAt: DateTime.utc(2026, 9, 2, 16, 0),
      );
      final restored = ProfessionalReferralPreferences.fromMap(p.toMap());
      expect(restored.toothNotation, ToothNotation.universal);
      expect(restored.timezone, 'America/Edmonton');
      expect(restored.lastOperatory, '3');
    });
  });

  group('handoff', () {
    test('produces a block with no patient information', () {
      final draft = build(
        'Endo, op 3, tooth 36, suspected necrosis with apical pathology, '
        'spontaneous pain, soon, usual endodontist, PA required.',
      );
      final text = HandoffFormatter.format(
        draft,
        utcOffset: const Duration(hours: -6),
        destination: destinations.first,
      );

      expect(text, contains('Endodontics referral'));
      expect(text, contains('Reference: ${draft.humanCode}'));
      expect(text, contains('Captured: 10:42 AM · September 2, 2026'));
      expect(text, contains('Operatory: 3'));
      expect(text, contains('Location: 36 · FDI'));
      expect(text, contains('Reason: Suspected pulp necrosis'));
      expect(text, contains('Findings: Apical pathology'));
      expect(text, contains('Urgency: Soon'));
      expect(text, contains('Records to attach: PA'));
      expect(text, contains('Preferred destination: Dr Michael Smith'));
      expect(text, contains('Patient information is not stored'));
    });

    test('states an unspecified urgency rather than omitting it', () {
      final draft = build('Endo, 36, necrotic.');
      final text =
          HandoffFormatter.format(draft, utcOffset: const Duration(hours: -6));
      expect(text, contains('Urgency: Not specified'));
      expect(text, isNot(contains('Routine')));
    });

    test('the inbox summary invents no urgency', () {
      final draft = build('Endo, 36, necrotic.');
      expect(HandoffFormatter.inboxSummary(draft), 'ENDO · 36 · FDI');
    });
  });
}
