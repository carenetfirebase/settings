// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDone => 'Done';

  @override
  String get commonBack => 'Back';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonClose => 'Close';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonLoading => 'Loading';

  @override
  String commonItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get commonToday => 'Today';

  @override
  String get commonYesterday => 'Yesterday';

  @override
  String get commonTomorrow => 'Tomorrow';

  @override
  String get commonGoodMorning => 'Good morning';

  @override
  String get commonGoodAfternoon => 'Good afternoon';

  @override
  String get commonGoodEvening => 'Good evening';

  @override
  String get labelInventoryCommandActionConsume => 'Use';

  @override
  String get labelInventoryCommandActionAdd => 'Add';

  @override
  String get labelInventoryCommandActionDiscard => 'Discard';

  @override
  String get labelInventoryCommandActionMarkEmpty => 'Mark empty';

  @override
  String get labelInventoryCommandActionSetCount => 'Set count';

  @override
  String get labelGlucoseUnitMmolL => 'mmol/L';

  @override
  String get labelGlucoseUnitMgdL => 'mg/dL';

  @override
  String get labelOralExposureKindSugaryDrink => 'Sugary drink';

  @override
  String get labelOralExposureKindSweetSnack => 'Sweet snack';

  @override
  String get labelOralExposureKindStickyFood =>
      'Sticky or slow-dissolving sweet';

  @override
  String get labelOralExposureKindAcidicDrink => 'Acidic drink';

  @override
  String get labelOralExposureKindCitrus => 'Citrus or acidic fruit';

  @override
  String get labelOralExposureKindSipping => 'Long sipping session';

  @override
  String get labelOralExposureKindWater => 'Water after eating';

  @override
  String get labelOralExposureKindCheese => 'Cheese or dairy finish';

  @override
  String get labelOralExposureKindBrushed => 'Brushed teeth';

  @override
  String get labelStudyTypeGuideline => 'Clinical/public-health guideline';

  @override
  String get labelStudyTypeSystematicReview =>
      'Systematic review / meta-analysis';

  @override
  String get labelStudyTypeRct => 'Randomised controlled trial';

  @override
  String get labelStudyTypeCohort => 'Observational cohort';

  @override
  String get labelStudyTypeReference => 'Reference values / authoritative body';

  @override
  String get labelEvidenceStrengthStrong => 'Strong';

  @override
  String get labelEvidenceStrengthModerate => 'Moderate';

  @override
  String get labelEvidenceStrengthLimited => 'Limited';

  @override
  String get labelEvidenceStrengthInsufficient => 'Insufficient';

  @override
  String get labelFoodCategoryProduce => 'Produce';

  @override
  String get labelFoodCategoryDairy => 'Dairy & eggs';

  @override
  String get labelFoodCategoryMeat => 'Meat';

  @override
  String get labelFoodCategorySeafood => 'Fish & seafood';

  @override
  String get labelFoodCategoryBakery => 'Bakery';

  @override
  String get labelFoodCategoryGrains => 'Grains & pasta';

  @override
  String get labelFoodCategoryPantry => 'Pantry staples';

  @override
  String get labelFoodCategorySpices => 'Herbs & spices';

  @override
  String get labelFoodCategoryCondiments => 'Sauces & condiments';

  @override
  String get labelFoodCategoryFrozen => 'Frozen';

  @override
  String get labelFoodCategoryBeverages => 'Beverages';

  @override
  String get labelFoodCategorySnacks => 'Snacks';

  @override
  String get labelFoodCategoryPrepared => 'Prepared & leftovers';

  @override
  String get labelFoodCategoryOther => 'Other';

  @override
  String get labelFoodCategoryNonFood => 'Non-food';

  @override
  String get labelStorageKindFridge => 'Fridge';

  @override
  String get labelStorageKindFreezer => 'Freezer';

  @override
  String get labelStorageKindPantry => 'Pantry';

  @override
  String get labelStorageKindCustom => 'Other';

  @override
  String get labelInventoryStatusConfirmed => 'Confirmed';

  @override
  String get labelInventoryStatusEstimated => 'Estimated';

  @override
  String get labelInventoryStatusNeedsReview => 'Needs review';

  @override
  String get labelInventoryStatusDepleted => 'Used up';

  @override
  String get labelInventoryStatusPastRecordedDate => 'Past recorded date';

  @override
  String get labelAdjustmentTypeIntake => 'Added';

  @override
  String get labelAdjustmentTypeConsume => 'Used';

  @override
  String get labelAdjustmentTypeDiscard => 'Discarded';

  @override
  String get labelAdjustmentTypeCorrection => 'Corrected';

  @override
  String get labelAdjustmentTypeTransferOut => 'Moved out';

  @override
  String get labelAdjustmentTypeTransferIn => 'Moved in';

  @override
  String get labelAdjustmentTypeReversal => 'Undone';

  @override
  String get labelNutrientEnergyKcal => 'Calories';

  @override
  String get labelNutrientProtein => 'Protein';

  @override
  String get labelNutrientCarbohydrate => 'Carbohydrates';

  @override
  String get labelNutrientFat => 'Fat';

  @override
  String get labelNutrientSaturatedFat => 'Saturated fat';

  @override
  String get labelNutrientFibre => 'Fibre';

  @override
  String get labelNutrientSugars => 'Total sugars';

  @override
  String get labelNutrientSodium => 'Sodium';

  @override
  String get labelNutrientCalcium => 'Calcium';

  @override
  String get labelNutrientIron => 'Iron';

  @override
  String get labelNutrientPotassium => 'Potassium';

  @override
  String get labelNutrientVitaminC => 'Vitamin C';

  @override
  String get labelProfessionalKindDietitian => 'Registered Dietitian';

  @override
  String get labelProfessionalKindDentist => 'Dentist';

  @override
  String get labelProfessionalKindDentalHygienist => 'Dental Hygienist';

  @override
  String get labelProfessionalKindPhysician => 'Physician';

  @override
  String get labelProfessionalKindNurse => 'Nurse / Diabetes Educator';

  @override
  String get labelShareCategoryJournal => 'Food journal';

  @override
  String get labelShareCategoryNutrition => 'Nutrition estimates';

  @override
  String get labelShareCategoryGlucose => 'Glucose journal';

  @override
  String get labelShareCategoryOral => 'Smile & Food log';

  @override
  String get labelShareCategoryConcerns => 'Hair, skin & nails notes';

  @override
  String get labelShareCategoryDietary => 'Allergies & preferences';

  @override
  String get labelDisclosureStatusNotAsked => 'Not provided';

  @override
  String get labelDisclosureStatusProvided => 'Provided';

  @override
  String get labelDisclosureStatusNoneKnown => 'None known';

  @override
  String get labelDisclosureStatusPreferNotToSay => 'Prefer not to say';

  @override
  String get labelCookingConfidenceBeginner => 'Just starting';

  @override
  String get labelCookingConfidenceComfortable => 'Comfortable';

  @override
  String get labelCookingConfidenceConfident => 'Confident';

  @override
  String get labelCookingConfidenceAccomplished => 'Accomplished';

  @override
  String get labelHouseholdTypeSingle => 'Just me';

  @override
  String get labelHouseholdTypeCouple => 'Two of us';

  @override
  String get labelHouseholdTypeFamily => 'Family';

  @override
  String get labelReceiptStatusUploading => 'Uploading';

  @override
  String get labelReceiptStatusUploaded => 'Waiting to analyze';

  @override
  String get labelReceiptStatusProcessing => 'Reading your receipt';

  @override
  String get labelReceiptStatusNeedsReview => 'Ready for review';

  @override
  String get labelReceiptStatusImported => 'Added to your kitchen';

  @override
  String get labelReceiptStatusFailed => 'Could not read';

  @override
  String get labelReceiptStatusDuplicate => 'Already imported';

  @override
  String get labelReceiptStatusCancelled => 'Cancelled';

  @override
  String get labelMealTypeBreakfast => 'Breakfast';

  @override
  String get labelMealTypeLunch => 'Lunch';

  @override
  String get labelMealTypeDinner => 'Dinner';

  @override
  String get labelMealTypeSnack => 'Snack';

  @override
  String get labelDifficultyEasy => 'Easy';

  @override
  String get labelDifficultyMedium => 'Medium';

  @override
  String get labelDifficultyInvolved => 'Involved';

  @override
  String get labelRecipeOriginCurated => 'Chefii kitchen';

  @override
  String get labelRecipeOriginAi => 'Created by your AI chef';

  @override
  String get labelRecipeOriginUser => 'Your recipe';

  @override
  String get labelRecipeOriginProfessional => 'From your professional';

  @override
  String get labelUnitMg => 'mg';

  @override
  String get labelUnitG => 'g';

  @override
  String get labelUnitKg => 'kg';

  @override
  String get labelUnitOz => 'oz';

  @override
  String get labelUnitLb => 'lb';

  @override
  String get labelUnitMl => 'ml';

  @override
  String get labelUnitL => 'L';

  @override
  String get labelUnitTsp => 'tsp';

  @override
  String get labelUnitTbsp => 'tbsp';

  @override
  String get labelUnitCup => 'cup';

  @override
  String get labelUnitPiece => 'pc';

  @override
  String get labelUnitDozen => 'dozen';

  @override
  String get allergenPeanut => 'Peanuts';

  @override
  String get allergenTreeNut => 'Tree nuts';

  @override
  String get allergenSesame => 'Sesame';

  @override
  String get allergenMilk => 'Milk';

  @override
  String get allergenEgg => 'Eggs';

  @override
  String get allergenFish => 'Fish';

  @override
  String get allergenShellfish => 'Crustaceans & molluscs';

  @override
  String get allergenSoy => 'Soy';

  @override
  String get allergenWheat => 'Wheat & triticale';

  @override
  String get allergenMustard => 'Mustard';

  @override
  String get allergenSulphites => 'Sulphites';

  @override
  String get allergenGluten => 'Gluten (wheat, barley, rye, oats)';

  @override
  String get restrictionVegetarian => 'Vegetarian';

  @override
  String get restrictionVegan => 'Vegan';

  @override
  String get restrictionPescatarian => 'Pescatarian';

  @override
  String get restrictionHalal => 'Halal';

  @override
  String get restrictionKosherStyle => 'Kosher-style';

  @override
  String get restrictionNoPork => 'No pork';

  @override
  String get restrictionNoAlcohol => 'No alcohol';

  @override
  String get restrictionGlutenFree => 'Gluten-free';

  @override
  String get restrictionDairyFree => 'Dairy-free';

  @override
  String get intoleranceLactose => 'Lactose';

  @override
  String get intoleranceGluten => 'Gluten';

  @override
  String get intoleranceEgg => 'Eggs';

  @override
  String get intoleranceSoy => 'Soy';
}
