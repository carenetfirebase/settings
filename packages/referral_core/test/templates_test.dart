import 'package:referral_core/referral_core.dart';
import 'package:test/test.dart';

/// Invariants that keep the promise that adding a specialty, a reason or a
/// phrase is a data change and nothing more.
void main() {
  final templates = ReferralTemplates.active;

  test('every specialty has a template', () {
    for (final specialty in Specialty.values) {
      expect(
        ReferralTemplates.forSpecialty(specialty),
        isNotNull,
        reason: '${specialty.wire} has no template',
      );
    }
  });

  test('every template can satisfy its own required fields', () {
    for (final t in templates) {
      if (t.requiredFields.contains(ReferralField.reason)) {
        expect(t.reasons, isNotEmpty,
            reason: '${t.specialty.wire} requires a reason but offers none');
      }
    }
  });

  test('concept ids are unique within a template', () {
    for (final t in templates) {
      final ids = [
        ...t.reasons.map((c) => c.id),
        ...t.findings.map((c) => c.id),
        ...t.symptoms.map((c) => c.id),
      ];
      expect(ids.toSet().length, ids.length,
          reason: '${t.specialty.wire} repeats a concept id: $ids');
    }
  });

  test('every synonym survives normalisation, or it can never match', () {
    // The matcher runs against normalised text, so a synonym containing a
    // hyphen, capital or punctuation would be unreachable — silently.
    final unreachable = <String>[];

    void check(String phrase, String where) {
      if (Normaliser.normalise(phrase) != phrase) {
        unreachable.add('$where: "$phrase" '
            '-> "${Normaliser.normalise(phrase)}"');
      }
    }

    for (final t in templates) {
      for (final s in t.synonyms) {
        check(s, 'specialty ${t.specialty.wire}');
      }
      for (final group in [t.reasons, t.findings, t.symptoms]) {
        for (final concept in group) {
          for (final s in concept.synonyms) {
            check(s, 'concept ${concept.id}');
          }
        }
      }
    }

    expect(unreachable, isEmpty,
        reason: 'these phrases can never be matched:\n'
            '${unreachable.join('\n')}');
  });

  test('concept display names are human, not ids', () {
    for (final t in templates) {
      for (final group in [t.reasons, t.findings, t.symptoms]) {
        for (final c in group) {
          expect(c.display, isNot(contains('_')));
          expect(c.display.trim(), isNotEmpty);
          expect(c.id, matches(RegExp(r'^[a-z0-9_]+$')));
        }
      }
    }
  });

  test('conceptById finds concepts in every group', () {
    final endo = ReferralTemplates.forSpecialty(Specialty.endodontics)!;
    expect(endo.conceptById('suspected_pulp_necrosis')?.display,
        'Suspected pulp necrosis');
    expect(endo.conceptById('apical_pathology')?.display, 'Apical pathology');
    expect(endo.conceptById('spontaneous_pain')?.display, 'Spontaneous pain');
    expect(endo.conceptById('nonsense'), isNull);
  });

  test('short specialty labels are set for the compact confirmation', () {
    for (final s in Specialty.values) {
      expect(s.shortName.trim(), isNotEmpty);
      expect(s.shortName, s.shortName.toUpperCase());
    }
  });

  test('wire values are unique across each enum', () {
    void unique(List<String> wires, String name) {
      expect(wires.toSet().length, wires.length,
          reason: '$name repeats a wire');
    }

    unique([for (final v in Specialty.values) v.wire], 'Specialty');
    unique([for (final v in Urgency.values) v.wire], 'Urgency');
    unique([for (final v in ReferralStatus.values) v.wire], 'ReferralStatus');
    unique([for (final v in RecordType.values) v.wire], 'RecordType');
    unique([for (final v in ToothNotation.values) v.wire], 'ToothNotation');
  });

  test('no status implies the referral was transmitted', () {
    final wires = ReferralStatus.values.map((s) => s.wire).join(' ');
    for (final forbidden in ['sent', 'transmitted', 'delivered', 'faxed']) {
      expect(wires, isNot(contains(forbidden)));
    }
  });
}
