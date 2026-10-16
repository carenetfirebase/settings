import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// No description provided for @commonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get commonLoading;

  /// No description provided for @commonItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String commonItemCount(int count);

  /// No description provided for @commonToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get commonToday;

  /// No description provided for @commonYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get commonYesterday;

  /// No description provided for @commonTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get commonTomorrow;

  /// No description provided for @commonGoodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get commonGoodMorning;

  /// No description provided for @commonGoodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get commonGoodAfternoon;

  /// No description provided for @commonGoodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get commonGoodEvening;

  /// No description provided for @labelInventoryCommandActionConsume.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get labelInventoryCommandActionConsume;

  /// No description provided for @labelInventoryCommandActionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get labelInventoryCommandActionAdd;

  /// No description provided for @labelInventoryCommandActionDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get labelInventoryCommandActionDiscard;

  /// No description provided for @labelInventoryCommandActionMarkEmpty.
  ///
  /// In en, this message translates to:
  /// **'Mark empty'**
  String get labelInventoryCommandActionMarkEmpty;

  /// No description provided for @labelInventoryCommandActionSetCount.
  ///
  /// In en, this message translates to:
  /// **'Set count'**
  String get labelInventoryCommandActionSetCount;

  /// No description provided for @labelGlucoseUnitMmolL.
  ///
  /// In en, this message translates to:
  /// **'mmol/L'**
  String get labelGlucoseUnitMmolL;

  /// No description provided for @labelGlucoseUnitMgdL.
  ///
  /// In en, this message translates to:
  /// **'mg/dL'**
  String get labelGlucoseUnitMgdL;

  /// No description provided for @labelOralExposureKindSugaryDrink.
  ///
  /// In en, this message translates to:
  /// **'Sugary drink'**
  String get labelOralExposureKindSugaryDrink;

  /// No description provided for @labelOralExposureKindSweetSnack.
  ///
  /// In en, this message translates to:
  /// **'Sweet snack'**
  String get labelOralExposureKindSweetSnack;

  /// No description provided for @labelOralExposureKindStickyFood.
  ///
  /// In en, this message translates to:
  /// **'Sticky or slow-dissolving sweet'**
  String get labelOralExposureKindStickyFood;

  /// No description provided for @labelOralExposureKindAcidicDrink.
  ///
  /// In en, this message translates to:
  /// **'Acidic drink'**
  String get labelOralExposureKindAcidicDrink;

  /// No description provided for @labelOralExposureKindCitrus.
  ///
  /// In en, this message translates to:
  /// **'Citrus or acidic fruit'**
  String get labelOralExposureKindCitrus;

  /// No description provided for @labelOralExposureKindSipping.
  ///
  /// In en, this message translates to:
  /// **'Long sipping session'**
  String get labelOralExposureKindSipping;

  /// No description provided for @labelOralExposureKindWater.
  ///
  /// In en, this message translates to:
  /// **'Water after eating'**
  String get labelOralExposureKindWater;

  /// No description provided for @labelOralExposureKindCheese.
  ///
  /// In en, this message translates to:
  /// **'Cheese or dairy finish'**
  String get labelOralExposureKindCheese;

  /// No description provided for @labelOralExposureKindBrushed.
  ///
  /// In en, this message translates to:
  /// **'Brushed teeth'**
  String get labelOralExposureKindBrushed;

  /// No description provided for @labelStudyTypeGuideline.
  ///
  /// In en, this message translates to:
  /// **'Clinical/public-health guideline'**
  String get labelStudyTypeGuideline;

  /// No description provided for @labelStudyTypeSystematicReview.
  ///
  /// In en, this message translates to:
  /// **'Systematic review / meta-analysis'**
  String get labelStudyTypeSystematicReview;

  /// No description provided for @labelStudyTypeRct.
  ///
  /// In en, this message translates to:
  /// **'Randomised controlled trial'**
  String get labelStudyTypeRct;

  /// No description provided for @labelStudyTypeCohort.
  ///
  /// In en, this message translates to:
  /// **'Observational cohort'**
  String get labelStudyTypeCohort;

  /// No description provided for @labelStudyTypeReference.
  ///
  /// In en, this message translates to:
  /// **'Reference values / authoritative body'**
  String get labelStudyTypeReference;

  /// No description provided for @labelEvidenceStrengthStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get labelEvidenceStrengthStrong;

  /// No description provided for @labelEvidenceStrengthModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get labelEvidenceStrengthModerate;

  /// No description provided for @labelEvidenceStrengthLimited.
  ///
  /// In en, this message translates to:
  /// **'Limited'**
  String get labelEvidenceStrengthLimited;

  /// No description provided for @labelEvidenceStrengthInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient'**
  String get labelEvidenceStrengthInsufficient;

  /// No description provided for @labelFoodCategoryProduce.
  ///
  /// In en, this message translates to:
  /// **'Produce'**
  String get labelFoodCategoryProduce;

  /// No description provided for @labelFoodCategoryDairy.
  ///
  /// In en, this message translates to:
  /// **'Dairy & eggs'**
  String get labelFoodCategoryDairy;

  /// No description provided for @labelFoodCategoryMeat.
  ///
  /// In en, this message translates to:
  /// **'Meat'**
  String get labelFoodCategoryMeat;

  /// No description provided for @labelFoodCategorySeafood.
  ///
  /// In en, this message translates to:
  /// **'Fish & seafood'**
  String get labelFoodCategorySeafood;

  /// No description provided for @labelFoodCategoryBakery.
  ///
  /// In en, this message translates to:
  /// **'Bakery'**
  String get labelFoodCategoryBakery;

  /// No description provided for @labelFoodCategoryGrains.
  ///
  /// In en, this message translates to:
  /// **'Grains & pasta'**
  String get labelFoodCategoryGrains;

  /// No description provided for @labelFoodCategoryPantry.
  ///
  /// In en, this message translates to:
  /// **'Pantry staples'**
  String get labelFoodCategoryPantry;

  /// No description provided for @labelFoodCategorySpices.
  ///
  /// In en, this message translates to:
  /// **'Herbs & spices'**
  String get labelFoodCategorySpices;

  /// No description provided for @labelFoodCategoryCondiments.
  ///
  /// In en, this message translates to:
  /// **'Sauces & condiments'**
  String get labelFoodCategoryCondiments;

  /// No description provided for @labelFoodCategoryFrozen.
  ///
  /// In en, this message translates to:
  /// **'Frozen'**
  String get labelFoodCategoryFrozen;

  /// No description provided for @labelFoodCategoryBeverages.
  ///
  /// In en, this message translates to:
  /// **'Beverages'**
  String get labelFoodCategoryBeverages;

  /// No description provided for @labelFoodCategorySnacks.
  ///
  /// In en, this message translates to:
  /// **'Snacks'**
  String get labelFoodCategorySnacks;

  /// No description provided for @labelFoodCategoryPrepared.
  ///
  /// In en, this message translates to:
  /// **'Prepared & leftovers'**
  String get labelFoodCategoryPrepared;

  /// No description provided for @labelFoodCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get labelFoodCategoryOther;

  /// No description provided for @labelFoodCategoryNonFood.
  ///
  /// In en, this message translates to:
  /// **'Non-food'**
  String get labelFoodCategoryNonFood;

  /// No description provided for @labelStorageKindFridge.
  ///
  /// In en, this message translates to:
  /// **'Fridge'**
  String get labelStorageKindFridge;

  /// No description provided for @labelStorageKindFreezer.
  ///
  /// In en, this message translates to:
  /// **'Freezer'**
  String get labelStorageKindFreezer;

  /// No description provided for @labelStorageKindPantry.
  ///
  /// In en, this message translates to:
  /// **'Pantry'**
  String get labelStorageKindPantry;

  /// No description provided for @labelStorageKindCustom.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get labelStorageKindCustom;

  /// No description provided for @labelInventoryStatusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get labelInventoryStatusConfirmed;

  /// No description provided for @labelInventoryStatusEstimated.
  ///
  /// In en, this message translates to:
  /// **'Estimated'**
  String get labelInventoryStatusEstimated;

  /// No description provided for @labelInventoryStatusNeedsReview.
  ///
  /// In en, this message translates to:
  /// **'Needs review'**
  String get labelInventoryStatusNeedsReview;

  /// No description provided for @labelInventoryStatusDepleted.
  ///
  /// In en, this message translates to:
  /// **'Used up'**
  String get labelInventoryStatusDepleted;

  /// No description provided for @labelInventoryStatusPastRecordedDate.
  ///
  /// In en, this message translates to:
  /// **'Past recorded date'**
  String get labelInventoryStatusPastRecordedDate;

  /// No description provided for @labelAdjustmentTypeIntake.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get labelAdjustmentTypeIntake;

  /// No description provided for @labelAdjustmentTypeConsume.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get labelAdjustmentTypeConsume;

  /// No description provided for @labelAdjustmentTypeDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discarded'**
  String get labelAdjustmentTypeDiscard;

  /// No description provided for @labelAdjustmentTypeCorrection.
  ///
  /// In en, this message translates to:
  /// **'Corrected'**
  String get labelAdjustmentTypeCorrection;

  /// No description provided for @labelAdjustmentTypeTransferOut.
  ///
  /// In en, this message translates to:
  /// **'Moved out'**
  String get labelAdjustmentTypeTransferOut;

  /// No description provided for @labelAdjustmentTypeTransferIn.
  ///
  /// In en, this message translates to:
  /// **'Moved in'**
  String get labelAdjustmentTypeTransferIn;

  /// No description provided for @labelAdjustmentTypeReversal.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get labelAdjustmentTypeReversal;

  /// No description provided for @labelNutrientEnergyKcal.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get labelNutrientEnergyKcal;

  /// No description provided for @labelNutrientProtein.
  ///
  /// In en, this message translates to:
  /// **'Protein'**
  String get labelNutrientProtein;

  /// No description provided for @labelNutrientCarbohydrate.
  ///
  /// In en, this message translates to:
  /// **'Carbohydrates'**
  String get labelNutrientCarbohydrate;

  /// No description provided for @labelNutrientFat.
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get labelNutrientFat;

  /// No description provided for @labelNutrientSaturatedFat.
  ///
  /// In en, this message translates to:
  /// **'Saturated fat'**
  String get labelNutrientSaturatedFat;

  /// No description provided for @labelNutrientFibre.
  ///
  /// In en, this message translates to:
  /// **'Fibre'**
  String get labelNutrientFibre;

  /// No description provided for @labelNutrientSugars.
  ///
  /// In en, this message translates to:
  /// **'Total sugars'**
  String get labelNutrientSugars;

  /// No description provided for @labelNutrientSodium.
  ///
  /// In en, this message translates to:
  /// **'Sodium'**
  String get labelNutrientSodium;

  /// No description provided for @labelNutrientCalcium.
  ///
  /// In en, this message translates to:
  /// **'Calcium'**
  String get labelNutrientCalcium;

  /// No description provided for @labelNutrientIron.
  ///
  /// In en, this message translates to:
  /// **'Iron'**
  String get labelNutrientIron;

  /// No description provided for @labelNutrientPotassium.
  ///
  /// In en, this message translates to:
  /// **'Potassium'**
  String get labelNutrientPotassium;

  /// No description provided for @labelNutrientVitaminC.
  ///
  /// In en, this message translates to:
  /// **'Vitamin C'**
  String get labelNutrientVitaminC;

  /// No description provided for @labelProfessionalKindDietitian.
  ///
  /// In en, this message translates to:
  /// **'Registered Dietitian'**
  String get labelProfessionalKindDietitian;

  /// No description provided for @labelProfessionalKindDentist.
  ///
  /// In en, this message translates to:
  /// **'Dentist'**
  String get labelProfessionalKindDentist;

  /// No description provided for @labelProfessionalKindDentalHygienist.
  ///
  /// In en, this message translates to:
  /// **'Dental Hygienist'**
  String get labelProfessionalKindDentalHygienist;

  /// No description provided for @labelProfessionalKindPhysician.
  ///
  /// In en, this message translates to:
  /// **'Physician'**
  String get labelProfessionalKindPhysician;

  /// No description provided for @labelProfessionalKindNurse.
  ///
  /// In en, this message translates to:
  /// **'Nurse / Diabetes Educator'**
  String get labelProfessionalKindNurse;

  /// No description provided for @labelShareCategoryJournal.
  ///
  /// In en, this message translates to:
  /// **'Food journal'**
  String get labelShareCategoryJournal;

  /// No description provided for @labelShareCategoryNutrition.
  ///
  /// In en, this message translates to:
  /// **'Nutrition estimates'**
  String get labelShareCategoryNutrition;

  /// No description provided for @labelShareCategoryGlucose.
  ///
  /// In en, this message translates to:
  /// **'Glucose journal'**
  String get labelShareCategoryGlucose;

  /// No description provided for @labelShareCategoryOral.
  ///
  /// In en, this message translates to:
  /// **'Smile & Food log'**
  String get labelShareCategoryOral;

  /// No description provided for @labelShareCategoryConcerns.
  ///
  /// In en, this message translates to:
  /// **'Hair, skin & nails notes'**
  String get labelShareCategoryConcerns;

  /// No description provided for @labelShareCategoryDietary.
  ///
  /// In en, this message translates to:
  /// **'Allergies & preferences'**
  String get labelShareCategoryDietary;

  /// No description provided for @labelDisclosureStatusNotAsked.
  ///
  /// In en, this message translates to:
  /// **'Not provided'**
  String get labelDisclosureStatusNotAsked;

  /// No description provided for @labelDisclosureStatusProvided.
  ///
  /// In en, this message translates to:
  /// **'Provided'**
  String get labelDisclosureStatusProvided;

  /// No description provided for @labelDisclosureStatusNoneKnown.
  ///
  /// In en, this message translates to:
  /// **'None known'**
  String get labelDisclosureStatusNoneKnown;

  /// No description provided for @labelDisclosureStatusPreferNotToSay.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get labelDisclosureStatusPreferNotToSay;

  /// No description provided for @labelCookingConfidenceBeginner.
  ///
  /// In en, this message translates to:
  /// **'Just starting'**
  String get labelCookingConfidenceBeginner;

  /// No description provided for @labelCookingConfidenceComfortable.
  ///
  /// In en, this message translates to:
  /// **'Comfortable'**
  String get labelCookingConfidenceComfortable;

  /// No description provided for @labelCookingConfidenceConfident.
  ///
  /// In en, this message translates to:
  /// **'Confident'**
  String get labelCookingConfidenceConfident;

  /// No description provided for @labelCookingConfidenceAccomplished.
  ///
  /// In en, this message translates to:
  /// **'Accomplished'**
  String get labelCookingConfidenceAccomplished;

  /// No description provided for @labelHouseholdTypeSingle.
  ///
  /// In en, this message translates to:
  /// **'Just me'**
  String get labelHouseholdTypeSingle;

  /// No description provided for @labelHouseholdTypeCouple.
  ///
  /// In en, this message translates to:
  /// **'Two of us'**
  String get labelHouseholdTypeCouple;

  /// No description provided for @labelHouseholdTypeFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get labelHouseholdTypeFamily;

  /// No description provided for @labelReceiptStatusUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get labelReceiptStatusUploading;

  /// No description provided for @labelReceiptStatusUploaded.
  ///
  /// In en, this message translates to:
  /// **'Waiting to analyze'**
  String get labelReceiptStatusUploaded;

  /// No description provided for @labelReceiptStatusProcessing.
  ///
  /// In en, this message translates to:
  /// **'Reading your receipt'**
  String get labelReceiptStatusProcessing;

  /// No description provided for @labelReceiptStatusNeedsReview.
  ///
  /// In en, this message translates to:
  /// **'Ready for review'**
  String get labelReceiptStatusNeedsReview;

  /// No description provided for @labelReceiptStatusImported.
  ///
  /// In en, this message translates to:
  /// **'Added to your kitchen'**
  String get labelReceiptStatusImported;

  /// No description provided for @labelReceiptStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read'**
  String get labelReceiptStatusFailed;

  /// No description provided for @labelReceiptStatusDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Already imported'**
  String get labelReceiptStatusDuplicate;

  /// No description provided for @labelReceiptStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get labelReceiptStatusCancelled;

  /// No description provided for @labelMealTypeBreakfast.
  ///
  /// In en, this message translates to:
  /// **'Breakfast'**
  String get labelMealTypeBreakfast;

  /// No description provided for @labelMealTypeLunch.
  ///
  /// In en, this message translates to:
  /// **'Lunch'**
  String get labelMealTypeLunch;

  /// No description provided for @labelMealTypeDinner.
  ///
  /// In en, this message translates to:
  /// **'Dinner'**
  String get labelMealTypeDinner;

  /// No description provided for @labelMealTypeSnack.
  ///
  /// In en, this message translates to:
  /// **'Snack'**
  String get labelMealTypeSnack;

  /// No description provided for @labelDifficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get labelDifficultyEasy;

  /// No description provided for @labelDifficultyMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get labelDifficultyMedium;

  /// No description provided for @labelDifficultyInvolved.
  ///
  /// In en, this message translates to:
  /// **'Involved'**
  String get labelDifficultyInvolved;

  /// No description provided for @labelRecipeOriginCurated.
  ///
  /// In en, this message translates to:
  /// **'Chefii kitchen'**
  String get labelRecipeOriginCurated;

  /// No description provided for @labelRecipeOriginAi.
  ///
  /// In en, this message translates to:
  /// **'Created by your AI chef'**
  String get labelRecipeOriginAi;

  /// No description provided for @labelRecipeOriginUser.
  ///
  /// In en, this message translates to:
  /// **'Your recipe'**
  String get labelRecipeOriginUser;

  /// No description provided for @labelRecipeOriginProfessional.
  ///
  /// In en, this message translates to:
  /// **'From your professional'**
  String get labelRecipeOriginProfessional;

  /// No description provided for @labelUnitMg.
  ///
  /// In en, this message translates to:
  /// **'mg'**
  String get labelUnitMg;

  /// No description provided for @labelUnitG.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get labelUnitG;

  /// No description provided for @labelUnitKg.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get labelUnitKg;

  /// No description provided for @labelUnitOz.
  ///
  /// In en, this message translates to:
  /// **'oz'**
  String get labelUnitOz;

  /// No description provided for @labelUnitLb.
  ///
  /// In en, this message translates to:
  /// **'lb'**
  String get labelUnitLb;

  /// No description provided for @labelUnitMl.
  ///
  /// In en, this message translates to:
  /// **'ml'**
  String get labelUnitMl;

  /// No description provided for @labelUnitL.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get labelUnitL;

  /// No description provided for @labelUnitTsp.
  ///
  /// In en, this message translates to:
  /// **'tsp'**
  String get labelUnitTsp;

  /// No description provided for @labelUnitTbsp.
  ///
  /// In en, this message translates to:
  /// **'tbsp'**
  String get labelUnitTbsp;

  /// No description provided for @labelUnitCup.
  ///
  /// In en, this message translates to:
  /// **'cup'**
  String get labelUnitCup;

  /// No description provided for @labelUnitPiece.
  ///
  /// In en, this message translates to:
  /// **'pc'**
  String get labelUnitPiece;

  /// No description provided for @labelUnitDozen.
  ///
  /// In en, this message translates to:
  /// **'dozen'**
  String get labelUnitDozen;

  /// No description provided for @allergenPeanut.
  ///
  /// In en, this message translates to:
  /// **'Peanuts'**
  String get allergenPeanut;

  /// No description provided for @allergenTreeNut.
  ///
  /// In en, this message translates to:
  /// **'Tree nuts'**
  String get allergenTreeNut;

  /// No description provided for @allergenSesame.
  ///
  /// In en, this message translates to:
  /// **'Sesame'**
  String get allergenSesame;

  /// No description provided for @allergenMilk.
  ///
  /// In en, this message translates to:
  /// **'Milk'**
  String get allergenMilk;

  /// No description provided for @allergenEgg.
  ///
  /// In en, this message translates to:
  /// **'Eggs'**
  String get allergenEgg;

  /// No description provided for @allergenFish.
  ///
  /// In en, this message translates to:
  /// **'Fish'**
  String get allergenFish;

  /// No description provided for @allergenShellfish.
  ///
  /// In en, this message translates to:
  /// **'Crustaceans & molluscs'**
  String get allergenShellfish;

  /// No description provided for @allergenSoy.
  ///
  /// In en, this message translates to:
  /// **'Soy'**
  String get allergenSoy;

  /// No description provided for @allergenWheat.
  ///
  /// In en, this message translates to:
  /// **'Wheat & triticale'**
  String get allergenWheat;

  /// No description provided for @allergenMustard.
  ///
  /// In en, this message translates to:
  /// **'Mustard'**
  String get allergenMustard;

  /// No description provided for @allergenSulphites.
  ///
  /// In en, this message translates to:
  /// **'Sulphites'**
  String get allergenSulphites;

  /// No description provided for @allergenGluten.
  ///
  /// In en, this message translates to:
  /// **'Gluten (wheat, barley, rye, oats)'**
  String get allergenGluten;

  /// No description provided for @restrictionVegetarian.
  ///
  /// In en, this message translates to:
  /// **'Vegetarian'**
  String get restrictionVegetarian;

  /// No description provided for @restrictionVegan.
  ///
  /// In en, this message translates to:
  /// **'Vegan'**
  String get restrictionVegan;

  /// No description provided for @restrictionPescatarian.
  ///
  /// In en, this message translates to:
  /// **'Pescatarian'**
  String get restrictionPescatarian;

  /// No description provided for @restrictionHalal.
  ///
  /// In en, this message translates to:
  /// **'Halal'**
  String get restrictionHalal;

  /// No description provided for @restrictionKosherStyle.
  ///
  /// In en, this message translates to:
  /// **'Kosher-style'**
  String get restrictionKosherStyle;

  /// No description provided for @restrictionNoPork.
  ///
  /// In en, this message translates to:
  /// **'No pork'**
  String get restrictionNoPork;

  /// No description provided for @restrictionNoAlcohol.
  ///
  /// In en, this message translates to:
  /// **'No alcohol'**
  String get restrictionNoAlcohol;

  /// No description provided for @restrictionGlutenFree.
  ///
  /// In en, this message translates to:
  /// **'Gluten-free'**
  String get restrictionGlutenFree;

  /// No description provided for @restrictionDairyFree.
  ///
  /// In en, this message translates to:
  /// **'Dairy-free'**
  String get restrictionDairyFree;

  /// No description provided for @intoleranceLactose.
  ///
  /// In en, this message translates to:
  /// **'Lactose'**
  String get intoleranceLactose;

  /// No description provided for @intoleranceGluten.
  ///
  /// In en, this message translates to:
  /// **'Gluten'**
  String get intoleranceGluten;

  /// No description provided for @intoleranceEgg.
  ///
  /// In en, this message translates to:
  /// **'Eggs'**
  String get intoleranceEgg;

  /// No description provided for @intoleranceSoy.
  ///
  /// In en, this message translates to:
  /// **'Soy'**
  String get intoleranceSoy;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
