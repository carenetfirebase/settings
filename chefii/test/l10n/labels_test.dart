import 'package:chefii/domain/safety/allergen_guard.dart';
import 'package:chefii/domain/inventory/inventory_command_parser.dart';
import 'package:chefii/domain/models/health.dart';
import 'package:chefii/domain/models/inventory.dart';
import 'package:chefii/domain/models/nutrition.dart';
import 'package:chefii/domain/models/professional.dart';
import 'package:chefii/domain/models/profile.dart';
import 'package:chefii/domain/models/receipt.dart';
import 'package:chefii/domain/models/recipe.dart';
import 'package:chefii/domain/units/units.dart';
import 'package:chefii/l10n/gen/app_localizations_en.dart';
import 'package:chefii/l10n/gen/app_localizations_fr.dart';
import 'package:chefii/l10n/labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final values = <Object>[
    ...InventoryCommandAction.values,
    ...GlucoseUnit.values,
    ...OralExposureKind.values,
    ...StudyType.values,
    ...EvidenceStrength.values,
    ...FoodCategory.values,
    ...StorageKind.values,
    ...InventoryStatus.values,
    ...AdjustmentType.values,
    ...Nutrient.values,
    ...ProfessionalKind.values,
    ...ShareCategory.values,
    ...DisclosureStatus.values,
    ...CookingConfidence.values,
    ...HouseholdType.values,
    ...ReceiptStatus.values,
    ...MealType.values,
    ...Difficulty.values,
    ...RecipeOrigin.values,
    ...Unit.values,
  ];

  for (final l in [AppLocalizationsEn(), AppLocalizationsFr()]) {
    test('every domain value has a ${l.localeName} label', () {
      for (final v in values) {
        expect(localizedLabel(l, v), isNotEmpty, reason: '$v');
      }
      for (final a in allergens) {
        expect(localizedAllergen(l, a.key), isNot(a.key), reason: a.key);
      }
      for (final r in restrictions) {
        expect(localizedRestriction(l, r.key), isNot(r.key), reason: r.key);
      }
      for (final k in intoleranceToAllergen.keys) {
        expect(localizedIntolerance(l, k), isNotEmpty, reason: k);
      }
    });
  }

  test('counted items use kitchen fractions', () {
    expect(const Quantity(0.5, Unit.piece).format(), '½ pc');
    expect(const Quantity(1.5, Unit.piece).format(), '1½ pc');
    expect(const Quantity(2, Unit.piece).format(), '2 pc');
    expect(const Quantity(0.4, Unit.piece).format(), '0.4 pc');
    expect(const Quantity(1.5, Unit.kg).format(), '1.5 kg');
  });

  test('French labels are actually French for common values', () {
    final fr = AppLocalizationsFr();
    expect(localizedLabel(fr, MealType.dinner), 'Souper');
    expect(localizedLabel(fr, Unit.tsp), 'c. à thé');
    expect(localizedAllergen(fr, 'peanut'), 'Arachides');
    expect(const Quantity(1.5, Unit.kg).format(unitLabel: (u) => localizedLabel(fr, u), decimalSeparator: ','), '1,5 kg');
  });
}
