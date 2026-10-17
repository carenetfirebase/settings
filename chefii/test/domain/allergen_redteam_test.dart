import 'dart:convert';
import 'dart:io';

import 'package:chefii/domain/models/profile.dart';
import 'package:chefii/domain/safety/allergen_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared red-team set (also run server-side). Recall must be 100%.
void main() {
  final fixture = jsonDecode(File('test/fixtures/allergen_redteam.json').readAsStringSync()) as Map<String, dynamic>;
  const guard = AllergenGuard();

  group('must detect', () {
    for (final c in (fixture['mustDetect'] as List).cast<Map<String, dynamic>>()) {
      test(c['text'], () {
        final found = guard.detect(c['text'] as String);
        for (final a in (c['allergens'] as List).cast<String>()) {
          expect(found, contains(a), reason: '"${c['text']}" should contain $a, found $found');
        }
      });
    }
  });

  group('must not detect', () {
    for (final c in (fixture['mustNotDetect'] as List).cast<Map<String, dynamic>>()) {
      test(c['text'], () {
        final found = guard.detect(c['text'] as String);
        for (final a in (c['allergens'] as List).cast<String>()) {
          expect(found, isNot(contains(a)), reason: '"${c['text']}" flagged as $a');
        }
      });
    }
  });

  group('restrictions', () {
    for (final c in (fixture['restrictions'] as List).cast<Map<String, dynamic>>()) {
      test('${c['text']} / ${c['restriction']}', () {
        final profile = DietaryProfile(restrictions: [c['restriction'] as String]);
        final report = guard.checkIngredients([(c['text'] as String, const <String>[])], profile);
        expect(report.isBlocked, c['blocked'], reason: report.conflicts.map((x) => x.reason).join(', '));
      });
    }
  });
}
