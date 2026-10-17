import 'package:chefii/domain/models/nutrition.dart';
import 'package:chefii/domain/nutrition/evidence_library.dart';
import 'package:chefii/domain/nutrition/evidence_library_fr.dart';
import 'package:flutter_test/flutter_test.dart';

/// French evidence text must exist for every claim and source, and
/// localizing must change display text only.
void main() {
  final numbers = RegExp(r'\d+(?:[.,]\d+)?');

  test('every claim has French text', () {
    expect(evidenceClaimsFr.keys.toSet(), {for (final c in evidenceClaims) c.id});
    for (final fr in evidenceClaimsFr.values) {
      expect(fr.topic.trim(), isNotEmpty);
      expect(fr.statement.trim(), isNotEmpty);
      expect(fr.limitations.trim(), isNotEmpty);
    }
  });

  test('every source has French text', () {
    expect(evidenceSourcesFr.keys.toSet(), evidenceSources.keys.toSet());
    for (final fr in evidenceSourcesFr.values) {
      expect(fr.title.trim(), isNotEmpty);
      expect(fr.publisher.trim(), isNotEmpty);
      expect(Uri.parse(fr.url).isScheme('https'), isTrue);
    }
  });

  for (final c in evidenceClaims) {
    test('${c.id}: localizeClaim changes display text only', () {
      final fr = localizeClaim(c, true);
      expect(fr.id, c.id);
      expect(fr.strength, c.strength);
      expect(fr.sourceIds, c.sourceIds);
      expect(fr.foodSources, c.foodSources);
      expect(fr.reviewStatus, c.reviewStatus);
      expect(fr.reviewedOn, c.reviewedOn);
      expect(fr.professionallyReviewed, c.professionallyReviewed);
      expect(fr.statement, evidenceClaimsFr[c.id]!.statement);
      expect(fr.statement, isNot(c.statement));
      // Numbers and thresholds are carried over exactly.
      expect(numbers.allMatches(fr.statement).map((m) => m[0]).toList(), numbers.allMatches(c.statement).map((m) => m[0]).toList());
      expect(numbers.allMatches(fr.limitations).map((m) => m[0]).toList(), numbers.allMatches(c.limitations).map((m) => m[0]).toList());
      expect(identical(localizeClaim(c, false), c), isTrue);
    });
  }

  for (final s in evidenceSources.values) {
    test('${s.id}: localizeSource keeps id, type and year', () {
      final fr = localizeSource(s, true);
      expect(fr.id, s.id);
      expect(fr.studyType, s.studyType);
      expect(fr.year, s.year);
      expect(identical(localizeSource(s, false), s), isTrue);
    });
  }

  test('French typography: no plain space before high punctuation or %', () {
    final bad = RegExp(r' [:;?!%»]|« ');
    for (final fr in evidenceClaimsFr.values) {
      for (final t in [fr.topic, fr.statement, fr.limitations]) {
        expect(bad.hasMatch(t), isFalse, reason: t);
      }
    }
    for (final fr in evidenceSourcesFr.values) {
      expect(bad.hasMatch(fr.title), isFalse, reason: fr.title);
    }
  });

  test('daily reference kinds and sources have French text', () {
    for (final dv in dailyReferences.values) {
      expect(localizeReferenceTerm(dv.kind, true), isNot(dv.kind));
      expect(localizeReferenceTerm(dv.source, true), isNot(dv.source));
      expect(localizeReferenceTerm(dv.kind, false), dv.kind);
    }
  });
}
