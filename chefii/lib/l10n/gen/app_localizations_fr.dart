// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get commonContinue => 'Continuer';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonDone => 'Terminé';

  @override
  String get commonBack => 'Retour';

  @override
  String get commonTryAgain => 'Réessayer';

  @override
  String get commonUndo => 'Annuler l\'action';

  @override
  String get commonRemove => 'Retirer';

  @override
  String get commonEdit => 'Modifier';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonYes => 'Oui';

  @override
  String get commonNo => 'Non';

  @override
  String get commonLoading => 'Chargement';

  @override
  String commonItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles',
      one: '1 article',
    );
    return '$_temp0';
  }

  @override
  String get commonToday => 'Aujourd\'hui';

  @override
  String get commonYesterday => 'Hier';

  @override
  String get commonTomorrow => 'Demain';

  @override
  String get commonGoodMorning => 'Bonjour';

  @override
  String get commonGoodAfternoon => 'Bon après-midi';

  @override
  String get commonGoodEvening => 'Bonsoir';

  @override
  String get labelInventoryCommandActionConsume => 'Utiliser';

  @override
  String get labelInventoryCommandActionAdd => 'Ajouter';

  @override
  String get labelInventoryCommandActionDiscard => 'Jeter';

  @override
  String get labelInventoryCommandActionMarkEmpty => 'Marquer comme terminé';

  @override
  String get labelInventoryCommandActionSetCount => 'Corriger la quantité';

  @override
  String get labelGlucoseUnitMmolL => 'mmol/L';

  @override
  String get labelGlucoseUnitMgdL => 'mg/dL';

  @override
  String get labelOralExposureKindSugaryDrink => 'Boisson sucrée';

  @override
  String get labelOralExposureKindSweetSnack => 'Collation sucrée';

  @override
  String get labelOralExposureKindStickyFood =>
      'Sucrerie collante ou à dissolution lente';

  @override
  String get labelOralExposureKindAcidicDrink => 'Boisson acide';

  @override
  String get labelOralExposureKindCitrus => 'Agrumes ou fruit acide';

  @override
  String get labelOralExposureKindSipping => 'Boisson sirotée longtemps';

  @override
  String get labelOralExposureKindWater => 'Eau après le repas';

  @override
  String get labelOralExposureKindCheese =>
      'Fromage ou produit laitier en fin de repas';

  @override
  String get labelOralExposureKindBrushed => 'Dents brossées';

  @override
  String get labelStudyTypeGuideline =>
      'Ligne directrice clinique ou de santé publique';

  @override
  String get labelStudyTypeSystematicReview =>
      'Revue systématique / méta-analyse';

  @override
  String get labelStudyTypeRct => 'Essai contrôlé randomisé';

  @override
  String get labelStudyTypeCohort => 'Étude de cohorte observationnelle';

  @override
  String get labelStudyTypeReference =>
      'Valeurs de référence / organisme faisant autorité';

  @override
  String get labelEvidenceStrengthStrong => 'Solide';

  @override
  String get labelEvidenceStrengthModerate => 'Modérée';

  @override
  String get labelEvidenceStrengthLimited => 'Limitée';

  @override
  String get labelEvidenceStrengthInsufficient => 'Insuffisante';

  @override
  String get labelFoodCategoryProduce => 'Fruits et légumes';

  @override
  String get labelFoodCategoryDairy => 'Produits laitiers et œufs';

  @override
  String get labelFoodCategoryMeat => 'Viandes';

  @override
  String get labelFoodCategorySeafood => 'Poissons et fruits de mer';

  @override
  String get labelFoodCategoryBakery => 'Boulangerie';

  @override
  String get labelFoodCategoryGrains => 'Céréales et pâtes';

  @override
  String get labelFoodCategoryPantry => 'Essentiels du garde-manger';

  @override
  String get labelFoodCategorySpices => 'Fines herbes et épices';

  @override
  String get labelFoodCategoryCondiments => 'Sauces et condiments';

  @override
  String get labelFoodCategoryFrozen => 'Surgelés';

  @override
  String get labelFoodCategoryBeverages => 'Boissons';

  @override
  String get labelFoodCategorySnacks => 'Collations';

  @override
  String get labelFoodCategoryPrepared => 'Plats préparés et restes';

  @override
  String get labelFoodCategoryOther => 'Autre';

  @override
  String get labelFoodCategoryNonFood => 'Non alimentaire';

  @override
  String get labelStorageKindFridge => 'Réfrigérateur';

  @override
  String get labelStorageKindFreezer => 'Congélateur';

  @override
  String get labelStorageKindPantry => 'Garde-manger';

  @override
  String get labelStorageKindCustom => 'Autre';

  @override
  String get labelInventoryStatusConfirmed => 'Confirmé';

  @override
  String get labelInventoryStatusEstimated => 'Estimé';

  @override
  String get labelInventoryStatusNeedsReview => 'À vérifier';

  @override
  String get labelInventoryStatusDepleted => 'Terminé';

  @override
  String get labelInventoryStatusPastRecordedDate => 'Date inscrite dépassée';

  @override
  String get labelAdjustmentTypeIntake => 'Ajouté';

  @override
  String get labelAdjustmentTypeConsume => 'Utilisé';

  @override
  String get labelAdjustmentTypeDiscard => 'Jeté';

  @override
  String get labelAdjustmentTypeCorrection => 'Corrigé';

  @override
  String get labelAdjustmentTypeTransferOut => 'Déplacé (sortie)';

  @override
  String get labelAdjustmentTypeTransferIn => 'Déplacé (entrée)';

  @override
  String get labelAdjustmentTypeReversal => 'Annulé';

  @override
  String get labelNutrientEnergyKcal => 'Calories';

  @override
  String get labelNutrientProtein => 'Protéines';

  @override
  String get labelNutrientCarbohydrate => 'Glucides';

  @override
  String get labelNutrientFat => 'Lipides';

  @override
  String get labelNutrientSaturatedFat => 'Gras saturés';

  @override
  String get labelNutrientFibre => 'Fibres';

  @override
  String get labelNutrientSugars => 'Sucres totaux';

  @override
  String get labelNutrientSodium => 'Sodium';

  @override
  String get labelNutrientCalcium => 'Calcium';

  @override
  String get labelNutrientIron => 'Fer';

  @override
  String get labelNutrientPotassium => 'Potassium';

  @override
  String get labelNutrientVitaminC => 'Vitamine C';

  @override
  String get labelProfessionalKindDietitian => 'Diététiste-nutritionniste';

  @override
  String get labelProfessionalKindDentist => 'Dentiste';

  @override
  String get labelProfessionalKindDentalHygienist => 'Hygiéniste dentaire';

  @override
  String get labelProfessionalKindPhysician => 'Médecin';

  @override
  String get labelProfessionalKindNurse =>
      'Personnel infirmier / éducation en diabète';

  @override
  String get labelShareCategoryJournal => 'Journal alimentaire';

  @override
  String get labelShareCategoryNutrition => 'Estimations nutritionnelles';

  @override
  String get labelShareCategoryGlucose => 'Journal de glycémie';

  @override
  String get labelShareCategoryOral => 'Journal Sourire et alimentation';

  @override
  String get labelShareCategoryConcerns => 'Notes cheveux, peau et ongles';

  @override
  String get labelShareCategoryDietary => 'Allergies et préférences';

  @override
  String get labelDisclosureStatusNotAsked => 'Non fourni';

  @override
  String get labelDisclosureStatusProvided => 'Fourni';

  @override
  String get labelDisclosureStatusNoneKnown => 'Aucune connue';

  @override
  String get labelDisclosureStatusPreferNotToSay =>
      'Je préfère ne pas répondre';

  @override
  String get labelCookingConfidenceBeginner => 'Je débute';

  @override
  String get labelCookingConfidenceComfortable => 'À l’aise';

  @override
  String get labelCookingConfidenceConfident => 'En confiance';

  @override
  String get labelCookingConfidenceAccomplished => 'Très à l’aise';

  @override
  String get labelHouseholdTypeSingle => 'Juste moi';

  @override
  String get labelHouseholdTypeCouple => 'Nous deux';

  @override
  String get labelHouseholdTypeFamily => 'Famille';

  @override
  String get labelReceiptStatusUploading => 'Envoi en cours';

  @override
  String get labelReceiptStatusUploaded => 'En attente d\'analyse';

  @override
  String get labelReceiptStatusProcessing => 'Lecture de votre reçu';

  @override
  String get labelReceiptStatusNeedsReview => 'Prêt à vérifier';

  @override
  String get labelReceiptStatusImported => 'Ajouté à votre cuisine';

  @override
  String get labelReceiptStatusFailed => 'Lecture impossible';

  @override
  String get labelReceiptStatusDuplicate => 'Déjà importé';

  @override
  String get labelReceiptStatusCancelled => 'Annulé';

  @override
  String get labelMealTypeBreakfast => 'Déjeuner';

  @override
  String get labelMealTypeLunch => 'Dîner';

  @override
  String get labelMealTypeDinner => 'Souper';

  @override
  String get labelMealTypeSnack => 'Collation';

  @override
  String get labelDifficultyEasy => 'Facile';

  @override
  String get labelDifficultyMedium => 'Moyen';

  @override
  String get labelDifficultyInvolved => 'Élaboré';

  @override
  String get labelRecipeOriginCurated => 'Cuisine Chefii';

  @override
  String get labelRecipeOriginAi => 'Créée par votre chef IA';

  @override
  String get labelRecipeOriginUser => 'Votre recette';

  @override
  String get labelRecipeOriginProfessional =>
      'De votre professionnel de la santé';

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
  String get labelUnitTsp => 'c. à thé';

  @override
  String get labelUnitTbsp => 'c. à soupe';

  @override
  String get labelUnitCup => 'tasse';

  @override
  String get labelUnitPiece => 'pc';

  @override
  String get labelUnitDozen => 'douzaine';

  @override
  String get allergenPeanut => 'Arachides';

  @override
  String get allergenTreeNut => 'Noix';

  @override
  String get allergenSesame => 'Sésame';

  @override
  String get allergenMilk => 'Lait';

  @override
  String get allergenEgg => 'Œufs';

  @override
  String get allergenFish => 'Poisson';

  @override
  String get allergenShellfish => 'Crustacés et mollusques';

  @override
  String get allergenSoy => 'Soya';

  @override
  String get allergenWheat => 'Blé et triticale';

  @override
  String get allergenMustard => 'Moutarde';

  @override
  String get allergenSulphites => 'Sulfites';

  @override
  String get allergenGluten => 'Gluten (blé, orge, seigle, avoine)';

  @override
  String get restrictionVegetarian => 'Végétarien';

  @override
  String get restrictionVegan => 'Végétalien';

  @override
  String get restrictionPescatarian => 'Pescétarien';

  @override
  String get restrictionHalal => 'Halal';

  @override
  String get restrictionKosherStyle => 'Style casher';

  @override
  String get restrictionNoPork => 'Sans porc';

  @override
  String get restrictionNoAlcohol => 'Sans alcool';

  @override
  String get restrictionGlutenFree => 'Sans gluten';

  @override
  String get restrictionDairyFree => 'Sans produits laitiers';

  @override
  String get intoleranceLactose => 'Lactose';

  @override
  String get intoleranceGluten => 'Gluten';

  @override
  String get intoleranceEgg => 'Œufs';

  @override
  String get intoleranceSoy => 'Soya';
}
