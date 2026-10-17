// Translated names for domain values. Wording lives in
// lib/l10n/parts/labels_{en,fr}.arb; when a domain enum gains a value, add
// its key to both parts and a case here (test/l10n/labels_test.dart checks
// every value is covered).
import 'package:flutter/widgets.dart';

import '../domain/inventory/inventory_command_parser.dart';
import '../domain/models/health.dart';
import '../domain/models/inventory.dart';
import '../domain/models/nutrition.dart';
import '../domain/models/professional.dart';
import '../domain/models/profile.dart';
import '../domain/models/receipt.dart';
import '../domain/models/recipe.dart';
import '../domain/units/units.dart';
import '../domain/catalog/catalog.dart';
import '../domain/catalog/catalog_fr.dart';
import '../domain/recipes/recipe_availability.dart';
import 'l10n.dart';

/// Translated display names for domain values. Use `context.labelOf(x)`
/// instead of `x.label` in UI code.
extension LocalizedLabels on BuildContext {
  String labelOf(Object value) => localizedLabel(l10n, value);

  /// Display name for a food. Catalogue foods show their French name in
  /// French, but only while the stored name is still the catalogue's English
  /// name — anything a person typed is shown exactly as typed.
  String productName(String productId, String storedName) {
    if (Localizations.localeOf(this).languageCode != 'fr') return storedName;
    final fr = catalogFrench[productId];
    final en = catalogById[productId]?.product.name;
    return fr != null && en != null && en.toLowerCase() == storedName.toLowerCase() ? fr.name : storedName;
  }

  /// Display name for a recipe tag key ('vegan', 'make-ahead'); unknown tags
  /// (for example from AI recipes) are shown as they are.
  String recipeTag(String key) => switch (key) {
        '15-minute' => l10n.tag15Minute,
        'high-protein' => l10n.tagHighProtein,
        'vegan' => l10n.tagVegan,
        'vegetarian' => l10n.tagVegetarian,
        'batch' => l10n.tagBatch,
        'comfort' => l10n.tagComfort,
        'make-ahead' => l10n.tagMakeAhead,
        'no-cook' => l10n.tagNoCook,
        _ => key,
      };

  /// "Everything on hand" / "2 ingredients to buy".
  String availabilityLabel(AvailabilityReport report) =>
      report.missing.isEmpty ? l10n.availabilityAllOnHand : l10n.availabilityToBuy(report.missing.length);

  /// Allergen key from AllergenGuard ('peanut', 'tree_nut', ...).
  String allergenLabel(String key) => localizedAllergen(l10n, key);
  String restrictionLabel(String key) => localizedRestriction(l10n, key);
  String intoleranceLabel(String key) => localizedIntolerance(l10n, key);

  /// "1,5 kg" in French, "1.5 kg" in English, with translated unit names.
  String formatQty(Quantity q) => q.format(
        unitLabel: (u) => localizedLabel(l10n, u),
        decimalSeparator: Localizations.localeOf(this).languageCode == 'fr' ? ',' : '.',
      );
}

String localizedLabel(AppLocalizations l, Object value) => switch (value) {
      InventoryCommandAction.consume => l.labelInventoryCommandActionConsume,
      InventoryCommandAction.add => l.labelInventoryCommandActionAdd,
      InventoryCommandAction.discard => l.labelInventoryCommandActionDiscard,
      InventoryCommandAction.markEmpty => l.labelInventoryCommandActionMarkEmpty,
      InventoryCommandAction.setCount => l.labelInventoryCommandActionSetCount,
      GlucoseUnit.mmolL => l.labelGlucoseUnitMmolL,
      GlucoseUnit.mgdL => l.labelGlucoseUnitMgdL,
      OralExposureKind.sugaryDrink => l.labelOralExposureKindSugaryDrink,
      OralExposureKind.sweetSnack => l.labelOralExposureKindSweetSnack,
      OralExposureKind.stickyFood => l.labelOralExposureKindStickyFood,
      OralExposureKind.acidicDrink => l.labelOralExposureKindAcidicDrink,
      OralExposureKind.citrus => l.labelOralExposureKindCitrus,
      OralExposureKind.sipping => l.labelOralExposureKindSipping,
      OralExposureKind.water => l.labelOralExposureKindWater,
      OralExposureKind.cheese => l.labelOralExposureKindCheese,
      OralExposureKind.brushed => l.labelOralExposureKindBrushed,
      StudyType.guideline => l.labelStudyTypeGuideline,
      StudyType.systematicReview => l.labelStudyTypeSystematicReview,
      StudyType.rct => l.labelStudyTypeRct,
      StudyType.cohort => l.labelStudyTypeCohort,
      StudyType.reference => l.labelStudyTypeReference,
      EvidenceStrength.strong => l.labelEvidenceStrengthStrong,
      EvidenceStrength.moderate => l.labelEvidenceStrengthModerate,
      EvidenceStrength.limited => l.labelEvidenceStrengthLimited,
      EvidenceStrength.insufficient => l.labelEvidenceStrengthInsufficient,
      FoodCategory.produce => l.labelFoodCategoryProduce,
      FoodCategory.dairy => l.labelFoodCategoryDairy,
      FoodCategory.meat => l.labelFoodCategoryMeat,
      FoodCategory.seafood => l.labelFoodCategorySeafood,
      FoodCategory.bakery => l.labelFoodCategoryBakery,
      FoodCategory.grains => l.labelFoodCategoryGrains,
      FoodCategory.pantry => l.labelFoodCategoryPantry,
      FoodCategory.spices => l.labelFoodCategorySpices,
      FoodCategory.condiments => l.labelFoodCategoryCondiments,
      FoodCategory.frozen => l.labelFoodCategoryFrozen,
      FoodCategory.beverages => l.labelFoodCategoryBeverages,
      FoodCategory.snacks => l.labelFoodCategorySnacks,
      FoodCategory.prepared => l.labelFoodCategoryPrepared,
      FoodCategory.other => l.labelFoodCategoryOther,
      FoodCategory.nonFood => l.labelFoodCategoryNonFood,
      StorageKind.fridge => l.labelStorageKindFridge,
      StorageKind.freezer => l.labelStorageKindFreezer,
      StorageKind.pantry => l.labelStorageKindPantry,
      StorageKind.custom => l.labelStorageKindCustom,
      InventoryStatus.confirmed => l.labelInventoryStatusConfirmed,
      InventoryStatus.estimated => l.labelInventoryStatusEstimated,
      InventoryStatus.needsReview => l.labelInventoryStatusNeedsReview,
      InventoryStatus.depleted => l.labelInventoryStatusDepleted,
      InventoryStatus.pastRecordedDate => l.labelInventoryStatusPastRecordedDate,
      AdjustmentType.intake => l.labelAdjustmentTypeIntake,
      AdjustmentType.consume => l.labelAdjustmentTypeConsume,
      AdjustmentType.discard => l.labelAdjustmentTypeDiscard,
      AdjustmentType.correction => l.labelAdjustmentTypeCorrection,
      AdjustmentType.transferOut => l.labelAdjustmentTypeTransferOut,
      AdjustmentType.transferIn => l.labelAdjustmentTypeTransferIn,
      AdjustmentType.reversal => l.labelAdjustmentTypeReversal,
      Nutrient.energyKcal => l.labelNutrientEnergyKcal,
      Nutrient.protein => l.labelNutrientProtein,
      Nutrient.carbohydrate => l.labelNutrientCarbohydrate,
      Nutrient.fat => l.labelNutrientFat,
      Nutrient.saturatedFat => l.labelNutrientSaturatedFat,
      Nutrient.fibre => l.labelNutrientFibre,
      Nutrient.sugars => l.labelNutrientSugars,
      Nutrient.sodium => l.labelNutrientSodium,
      Nutrient.calcium => l.labelNutrientCalcium,
      Nutrient.iron => l.labelNutrientIron,
      Nutrient.potassium => l.labelNutrientPotassium,
      Nutrient.vitaminC => l.labelNutrientVitaminC,
      ProfessionalKind.dietitian => l.labelProfessionalKindDietitian,
      ProfessionalKind.dentist => l.labelProfessionalKindDentist,
      ProfessionalKind.dentalHygienist => l.labelProfessionalKindDentalHygienist,
      ProfessionalKind.physician => l.labelProfessionalKindPhysician,
      ProfessionalKind.nurse => l.labelProfessionalKindNurse,
      ShareCategory.journal => l.labelShareCategoryJournal,
      ShareCategory.nutrition => l.labelShareCategoryNutrition,
      ShareCategory.glucose => l.labelShareCategoryGlucose,
      ShareCategory.oral => l.labelShareCategoryOral,
      ShareCategory.concerns => l.labelShareCategoryConcerns,
      ShareCategory.dietary => l.labelShareCategoryDietary,
      DisclosureStatus.notAsked => l.labelDisclosureStatusNotAsked,
      DisclosureStatus.provided => l.labelDisclosureStatusProvided,
      DisclosureStatus.noneKnown => l.labelDisclosureStatusNoneKnown,
      DisclosureStatus.preferNotToSay => l.labelDisclosureStatusPreferNotToSay,
      CookingConfidence.beginner => l.labelCookingConfidenceBeginner,
      CookingConfidence.comfortable => l.labelCookingConfidenceComfortable,
      CookingConfidence.confident => l.labelCookingConfidenceConfident,
      CookingConfidence.accomplished => l.labelCookingConfidenceAccomplished,
      HouseholdType.single => l.labelHouseholdTypeSingle,
      HouseholdType.couple => l.labelHouseholdTypeCouple,
      HouseholdType.family => l.labelHouseholdTypeFamily,
      ReceiptStatus.uploading => l.labelReceiptStatusUploading,
      ReceiptStatus.uploaded => l.labelReceiptStatusUploaded,
      ReceiptStatus.processing => l.labelReceiptStatusProcessing,
      ReceiptStatus.needsReview => l.labelReceiptStatusNeedsReview,
      ReceiptStatus.imported => l.labelReceiptStatusImported,
      ReceiptStatus.failed => l.labelReceiptStatusFailed,
      ReceiptStatus.duplicate => l.labelReceiptStatusDuplicate,
      ReceiptStatus.cancelled => l.labelReceiptStatusCancelled,
      MealType.breakfast => l.labelMealTypeBreakfast,
      MealType.lunch => l.labelMealTypeLunch,
      MealType.dinner => l.labelMealTypeDinner,
      MealType.snack => l.labelMealTypeSnack,
      Difficulty.easy => l.labelDifficultyEasy,
      Difficulty.medium => l.labelDifficultyMedium,
      Difficulty.involved => l.labelDifficultyInvolved,
      RecipeOrigin.curated => l.labelRecipeOriginCurated,
      RecipeOrigin.ai => l.labelRecipeOriginAi,
      RecipeOrigin.user => l.labelRecipeOriginUser,
      RecipeOrigin.professional => l.labelRecipeOriginProfessional,
      Unit.mg => l.labelUnitMg,
      Unit.g => l.labelUnitG,
      Unit.kg => l.labelUnitKg,
      Unit.oz => l.labelUnitOz,
      Unit.lb => l.labelUnitLb,
      Unit.ml => l.labelUnitMl,
      Unit.l => l.labelUnitL,
      Unit.tsp => l.labelUnitTsp,
      Unit.tbsp => l.labelUnitTbsp,
      Unit.cup => l.labelUnitCup,
      Unit.piece => l.labelUnitPiece,
      Unit.dozen => l.labelUnitDozen,
      _ => throw ArgumentError('No translated label for $value'),
    };

String localizedAllergen(AppLocalizations l, String key) => switch (key) {
      'peanut' => l.allergenPeanut,
      'tree_nut' => l.allergenTreeNut,
      'sesame' => l.allergenSesame,
      'milk' => l.allergenMilk,
      'egg' => l.allergenEgg,
      'fish' => l.allergenFish,
      'shellfish' => l.allergenShellfish,
      'soy' => l.allergenSoy,
      'wheat' => l.allergenWheat,
      'mustard' => l.allergenMustard,
      'sulphites' => l.allergenSulphites,
      'gluten' => l.allergenGluten,
      _ => key,
    };

String localizedRestriction(AppLocalizations l, String key) => switch (key) {
      'vegetarian' => l.restrictionVegetarian,
      'vegan' => l.restrictionVegan,
      'pescatarian' => l.restrictionPescatarian,
      'halal' => l.restrictionHalal,
      'kosher_style' => l.restrictionKosherStyle,
      'no_pork' => l.restrictionNoPork,
      'no_alcohol' => l.restrictionNoAlcohol,
      'gluten_free' => l.restrictionGlutenFree,
      'dairy_free' => l.restrictionDairyFree,
      _ => key,
    };

String localizedIntolerance(AppLocalizations l, String key) => switch (key) {
      'lactose' => l.intoleranceLactose,
      'gluten' => l.intoleranceGluten,
      'egg' => l.intoleranceEgg,
      'soy' => l.intoleranceSoy,
      _ => key,
    };
