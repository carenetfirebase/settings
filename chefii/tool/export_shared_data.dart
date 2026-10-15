// Exports the catalogue and allergen lexicon used by the Flutter app as JSON
// for Cloud Functions, so client and server screen and match identically.
//
//   dart run tool/export_shared_data.dart
//
// CI runs this and fails if functions/src/data/*.json is out of date.
import 'dart:convert';
import 'dart:io';

import 'package:chefii/domain/catalog/catalog.dart';
import 'package:chefii/domain/models/nutrition.dart';
import 'package:chefii/domain/safety/allergen_guard.dart';

void main(List<String> args) {
  final check = args.contains('--check');
  const encoder = JsonEncoder.withIndent('  ');
  final catalogJson = encoder.convert([
    for (final e in catalog)
      {
        'id': e.product.id,
        'name': e.product.name,
        'category': e.product.category.name,
        'defaultUnit': e.product.defaultUnit.name,
        'defaultStorage': e.product.defaultStorage.name,
        'aliases': e.product.aliases,
        'allergens': e.product.allergens,
        'gramsPerPiece': e.product.bridge.gramsPerPiece,
        'gramsPerMl': e.product.bridge.gramsPerMl,
        'per100g': {for (final n in Nutrient.values) if (e.reference.per100g.has(n)) n.name: e.reference.per100g[n]},
      },
  ]);
  final allergenJson = encoder.convert({
    'allergens': [
      for (final a in allergens) {'key': a.key, 'label': a.label, 'terms': a.terms, 'exclusions': a.exclusions},
    ],
    'intolerances': intoleranceToAllergen,
    'restrictions': [
      for (final r in restrictions)
        {'key': r.key, 'label': r.label, 'excludedAllergens': r.excludedAllergens, 'excludedTerms': r.excludedTerms, 'exclusions': r.exclusions},
    ],
  });
  final outputs = {'functions/src/data/catalog.json': '$catalogJson\n', 'functions/src/data/allergens.json': '$allergenJson\n'};
  var stale = false;
  outputs.forEach((path, content) {
    final f = File(path);
    if (check) {
      if (!f.existsSync() || f.readAsStringSync() != content) {
        stderr.writeln('$path is out of date. Run: dart run tool/export_shared_data.dart');
        stale = true;
      }
    } else {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
      stdout.writeln('wrote $path');
    }
  });
  if (stale) exit(1);
}
