// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get accountEyebrow => 'Vous';

  @override
  String get accountTitleFallback => 'Votre compte';

  @override
  String get accountEditName => 'Modifier le nom';

  @override
  String get accountYourName => 'Votre nom';

  @override
  String get accountSectionPreferences => 'Préférences';

  @override
  String get accountDietarySafety => 'Allergies et restrictions alimentaires';

  @override
  String get accountNoAllergies => 'Aucune allergie enregistrée';

  @override
  String get accountNotProvidedYet => 'Pas encore indiqué';

  @override
  String get accountCulinaryPreferences => 'Préférences culinaires';

  @override
  String get accountWellnessPreferences => 'Préférences mieux-être';

  @override
  String get accountMorningRoutine => 'Routine du matin';

  @override
  String get accountMealReminders => 'Rappels de repas';

  @override
  String get accountSectionHealth => 'Santé et nutrition';

  @override
  String get accountNutrition => 'Nutrition';

  @override
  String get accountNutritionInsights => 'Aperçus nutritionnels';

  @override
  String get accountSmileAndFood => 'Sourire et alimentation';

  @override
  String get accountGlucoseJournal => 'Journal de glycémie';

  @override
  String get accountOptional => 'Facultatif';

  @override
  String get accountNutritionCircle => 'Mon cercle nutrition';

  @override
  String get accountSectionHousehold => 'Foyer et compte';

  @override
  String get accountHouseholdMembers => 'Membres du foyer';

  @override
  String get accountPrivacyData => 'Confidentialité et données';

  @override
  String get accountConnectedServices => 'Services connectés';

  @override
  String get accountMembership => 'Abonnement';

  @override
  String get accountAccessibilityLanguage => 'Accessibilité et langue';

  @override
  String get accountSecuritySessions => 'Sécurité et sessions';

  @override
  String get accountHelpSupport => 'Aide et soutien';

  @override
  String get accountLegalEvidence => 'Mentions légales et données probantes';

  @override
  String get accountExportOrDelete => 'Exporter ou supprimer vos données';

  @override
  String get accountProPortal => 'Portail professionnel';

  @override
  String get accountSignOut => 'Se déconnecter';

  @override
  String get accountFooterDemo => 'Chefii · Mode démo';

  @override
  String get accountFooterEarlyAccess => 'Chefii · Accès anticipé';

  @override
  String get accountHousehold => 'Foyer';

  @override
  String accountUsualPortions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count portions habituelles',
      one: '$count portion habituelle',
    );
    return '$_temp0';
  }

  @override
  String get accountInviteSomeone => 'Inviter quelqu\'un';

  @override
  String accountInviteShareText(String code) {
    return 'Rejoignez notre cuisine sur Chefii avec le code $code (valide 7 jours).';
  }

  @override
  String get accountInviteShareSubject => 'Rejoignez ma cuisine Chefii';

  @override
  String accountMemberYou(String name) {
    return '$name (vous)';
  }

  @override
  String accountMemberSubtitle(String role, String date) {
    return '$role · ajout : $date';
  }

  @override
  String get accountRoleOwner => 'Propriétaire';

  @override
  String get accountRoleAdult => 'Adulte';

  @override
  String get accountRoleMember => 'Membre';

  @override
  String accountRemoveMemberTitle(String name) {
    return 'Retirer $name ?';
  }

  @override
  String get accountRemoveMemberMessage =>
      'Cette personne perdra l\'accès à la cuisine partagée. Son journal privé reste le sien.';

  @override
  String get accountOpenInvitations => 'Invitations en cours';

  @override
  String accountInviteCode(String code) {
    return 'Code $code';
  }

  @override
  String get accountInviteValidity => 'Valide 7 jours, usage unique';

  @override
  String get accountWhatMembersShare => 'Ce que les membres partagent';

  @override
  String get accountMembersShareBody =>
      'Tout le monde partage la cuisine, la liste d\'épicerie, le plan de repas et les recettes enregistrées. Le journal, la nutrition, la glycémie, le suivi Sourire et alimentation et les évaluations professionnelles de chaque personne restent privés. Les allergies sont communiquées au foyer uniquement pour que les repas partagés restent sécuritaires.';

  @override
  String get accountPrivacyEyebrow => 'Confidentialité';

  @override
  String get accountPrivacyTitle => 'Vos données, votre choix';

  @override
  String get accountPrivacySubtitle =>
      'Chefii ne vend jamais vos données et n\'utilise jamais vos dossiers de santé à des fins publicitaires.';

  @override
  String get accountAiProcessing => 'Traitement par l\'IA';

  @override
  String get accountAiProcessingBody =>
      'Envoyer les photos de reçus et du réfrigérateur, ainsi que vos demandes au chef, à nos fournisseurs d\'IA (Google Gemini ; OpenAI si activé ci-dessous) par l\'intermédiaire de nos serveurs sécurisés. Selon nos ententes, les fournisseurs n\'ont pas le droit d\'entraîner leurs modèles avec vos données.';

  @override
  String get accountOptionalAiProvider => 'Second fournisseur d\'IA facultatif';

  @override
  String get accountOptionalAiProviderBody =>
      'Autoriser OpenAI pour la conversation et la rédaction de recettes. Si désactivé, Gemini seulement.';

  @override
  String get accountAnalytics => 'Statistiques d\'utilisation';

  @override
  String get accountAnalyticsBody =>
      'Événements d\'utilisation anonymes (p. ex. « reçu importé »). Jamais de noms d\'aliments, de données de santé ni de texte libre.';

  @override
  String get accountProfessionalSharing => 'Partage avec des professionnels';

  @override
  String get accountConsentHistory => 'Historique des consentements';

  @override
  String get accountNoConsents => 'Aucun consentement enregistré.';

  @override
  String accountConsentGranted(String purpose) {
    return '$purpose · accordé';
  }

  @override
  String accountConsentWithdrawn(String purpose) {
    return '$purpose · retiré';
  }

  @override
  String accountConsentVersion(String date, String version) {
    return '$date · version $version';
  }

  @override
  String get accountDataResidency =>
      'Les données sont stockées au Canada (Google Cloud, région de Montréal) lorsque c\'est possible. Consultez la Politique de confidentialité pour en savoir plus.';

  @override
  String get accountServicesEyebrow => 'Services';

  @override
  String get accountNotifications => 'Notifications';

  @override
  String get accountNotificationsBody =>
      'Pour les rappels, les minuteries et votre réveil du matin';

  @override
  String get accountNotificationsOn => 'Les notifications sont activées';

  @override
  String get accountNotificationsOff =>
      'Les notifications sont désactivées — vous pouvez changer cela dans les paramètres du système.';

  @override
  String get accountCheck => 'Vérifier';

  @override
  String get accountKitchenAi => 'IA de cuisine';

  @override
  String get accountKitchenAiDemo =>
      'Mode démo — résultats d\'exemple, aucun fournisseur d\'IA connecté';

  @override
  String get accountKitchenAiConnected =>
      'Connexion par les serveurs sécurisés de Chefii';

  @override
  String get accountHealthApps => 'Santé (Apple) / Connexion Santé';

  @override
  String get accountHealthAppsBody =>
      'À venir : importation de la glycémie en lecture seule, avec une provenance claire. Pas encore offert.';

  @override
  String get accountProfessionals => 'Professionnels';

  @override
  String get accountProfessionalsBody => 'Gérez qui peut voir vos dossiers';

  @override
  String get accountBackendDemo =>
      'Serveur : stockage de démo local sur cet appareil';

  @override
  String get accountBackendFirebase => 'Serveur : Firebase';

  @override
  String get accountBackendEmulators => 'Serveur : Firebase (émulateurs)';

  @override
  String get accountEarlyAccess => 'Accès anticipé';

  @override
  String get accountMembershipSubtitle =>
      'Toutes les fonctionnalités de Chefii sont incluses pendant l\'accès anticipé.';

  @override
  String get accountMembershipName => 'Abonnement Chefii';

  @override
  String get accountMembershipBody =>
      'Les forfaits payants ne sont pas encore offerts. À leur lancement, le prix vous sera indiqué à l\'avance et rien ne vous sera facturé sans votre confirmation dans l\'App Store ou Google Play.';

  @override
  String get accountIncludedNow => 'Inclus actuellement';

  @override
  String get accountFeatureScanning => 'Numérisation des reçus et du frigo';

  @override
  String get accountFeatureChef => 'Chef IA et cuisine guidée';

  @override
  String get accountFeaturePlanning =>
      'Planification des repas et épicerie intelligente';

  @override
  String get accountFeatureJournal => 'Journal nutritionnel et aperçus';

  @override
  String get accountFeatureCircle => 'Partage avec votre cercle nutrition';

  @override
  String get accountBillingNote =>
      'Les reçus et l\'historique de facturation s\'afficheront ici au lancement des abonnements.';

  @override
  String get accountSettingsEyebrow => 'Paramètres';

  @override
  String get accountTextSize => 'Taille du texte';

  @override
  String accountTextScaleValue(int percent) {
    return '$percent %';
  }

  @override
  String accountTextScaleSemantic(int percent) {
    return '$percent pour cent';
  }

  @override
  String get accountTextPreview =>
      'Aperçu : laissez mijoter doucement jusqu\'à ce que les lentilles se défassent.';

  @override
  String get accountDeviceTextSize =>
      'Chefii suit aussi la taille du texte de votre appareil.';

  @override
  String get accountReduceMotion => 'Réduire les animations';

  @override
  String get accountReduceMotionBody => 'Moins d\'animations et de transitions';

  @override
  String get accountReadStepsAloud => 'Lire les étapes à voix haute';

  @override
  String get accountReadStepsAloudBody => 'En cuisine guidée';

  @override
  String get accountLanguage => 'Langue';

  @override
  String get accountLanguageSystem => 'Comme sur mon appareil';

  @override
  String get accountDemoAccount => 'Compte de démo';

  @override
  String get accountSignedIn => 'Session ouverte';

  @override
  String get accountStoredOnDevice => 'Stocké uniquement sur cet appareil';

  @override
  String accountIdShort(String id) {
    return 'Identifiant du compte $id…';
  }

  @override
  String get accountResetPassword => 'Réinitialiser le mot de passe';

  @override
  String get accountResetPasswordSent => 'Courriel de réinitialisation envoyé';

  @override
  String get accountSignOutAll => 'Se déconnecter de tous les appareils';

  @override
  String get accountSignOutAllBody =>
      'Met fin à toutes les sessions, y compris celle-ci';

  @override
  String get accountSignOutEverywhereTitle => 'Se déconnecter partout ?';

  @override
  String get accountSignOutEverywhereMessage =>
      'Vous devrez vous reconnecter sur chaque appareil.';

  @override
  String get accountSignOutEverywhere => 'Se déconnecter partout';

  @override
  String get accountReauthNote =>
      'Les actions délicates, comme supprimer votre compte ou exporter vos données de santé, vous demandent de confirmer de nouveau votre identité.';

  @override
  String get accountHelpEyebrow => 'Aide';

  @override
  String get accountHelpTitle => 'Comment pouvons-nous vous aider ?';

  @override
  String get accountSend => 'Envoyer';

  @override
  String get accountFeedbackThanks => 'Merci — nous lisons chaque message.';

  @override
  String get accountFaqAccuracyQ => 'Quelle est la précision de ma cuisine ?';

  @override
  String get accountFaqAccuracyA =>
      'Les articles des reçus que vous avez vérifiés sont confirmés. Après la cuisson, les quantités sont déduites selon ce que vous confirmez. Tout ce qui est estimé est indiqué comme tel, et Chefii vous demande de temps à autre de vérifier.';

  @override
  String get accountFaqUntrackedQ =>
      'Et si j\'utilise quelque chose sans le signaler à Chefii ?';

  @override
  String get accountFaqUntrackedA =>
      'Utilisez le bouton « J\'ai utilisé… » ou touchez − sur un article. Si les quantités ne correspondent plus, la vérification rapide vous permet de corriger plusieurs articles en quelques secondes.';

  @override
  String get accountFaqFreshnessQ => 'Puis-je me fier aux dates de fraîcheur ?';

  @override
  String get accountFaqFreshnessA =>
      'Non — ce sont des estimations fondées sur les durées de conservation habituelles. Suivez toujours la date sur l\'emballage et votre propre jugement.';

  @override
  String get accountFaqMedicalQ => 'Chefii donne-t-il des conseils médicaux ?';

  @override
  String get accountFaqMedicalA =>
      'Non. Les fonctions de nutrition servent à l\'éducation. Pour des conseils personnalisés, partagez vos dossiers avec un ou une diététiste-nutritionniste membre d\'un ordre professionnel dans Mon cercle nutrition.';

  @override
  String get accountFaqHealthDataQ => 'Qui peut voir mes données de santé ?';

  @override
  String get accountFaqHealthDataA =>
      'Personne d\'autre que vous, sauf les professionnels avec qui vous partagez explicitement vos données, pour la durée de votre choix. Les membres du foyer ne voient jamais votre journal ni vos dossiers de santé.';

  @override
  String get accountWriteToUs => 'Écrivez-nous';

  @override
  String get accountFeedback => 'Commentaires';

  @override
  String get accountReportProblem => 'Signaler un problème';

  @override
  String get accountFeedbackHint =>
      'Dites-nous ce qui s\'est passé ou ce que vous aimeriez voir. Veuillez ne pas inclure de renseignements sur votre santé.';

  @override
  String get accountEmailSupport => 'Écrire au soutien';

  @override
  String get accountSupportEmailSubject => 'Soutien Chefii';

  @override
  String get accountLegalEyebrow => 'Juridique';

  @override
  String get accountLegalTitle => 'Mentions légales et avis';

  @override
  String get accountLegalTermsTitle => 'Conditions d\'utilisation (résumé)';

  @override
  String get accountLegalTermsBody =>
      'Chefii est offert pour l\'organisation de la cuisine à la maison, l\'accompagnement culinaire et l\'éducation générale en nutrition. Vous êtes responsable des décisions liées à la salubrité des aliments chez vous. Les conditions complètes seront publiées avant le lancement public et doivent faire l\'objet d\'une révision juridique.';

  @override
  String get accountLegalPrivacyTitle =>
      'Politique de confidentialité (résumé)';

  @override
  String get accountLegalPrivacyBody =>
      'Nous recueillons ce que vous saisissez ou numérisez pour faire fonctionner Chefii : articles de cuisine, reçus, recettes, repas consignés et renseignements de santé facultatifs que vous choisissez d\'ajouter. Nous traitons les données au Canada lorsque c\'est possible, faisons appel à des fournisseurs d\'IA uniquement avec votre consentement et en vertu d\'ententes de traitement des données, ne vendons jamais de renseignements personnels et vous permettons d\'exporter ou de supprimer vos données en tout temps. Préparée en vue de respecter la LPRPDE et les lois provinciales applicables sur la protection des renseignements de santé ; politique complète sous réserve d\'une révision juridique.';

  @override
  String get accountLegalMedicalTitle => 'Limites médicales';

  @override
  String get accountLegalMedicalBody =>
      'Chefii ne diagnostique, ne traite, ne guérit ni ne prévient aucune maladie, et n\'est pas un instrument médical. Les valeurs nutritives sont des estimations. Les fonctions de glycémie constituent un journal personnel et ne remplacent pas les instruments médicaux, les alarmes ni votre équipe soignante. La vérification des allergènes repose sur le nom des ingrédients et sur les étiquettes que vous vérifiez ; elle ne peut pas garantir qu\'un aliment est exempt d\'un allergène.';

  @override
  String get accountLegalFoodSafetyTitle => 'Salubrité des aliments';

  @override
  String get accountLegalFoodSafetyBody =>
      'Les indicateurs de fraîcheur sont des estimations fondées sur les durées de conservation habituelles. Respectez toujours les dates sur l\'emballage, les températures de conservation sécuritaires et les températures de cuisson internes sécuritaires.';

  @override
  String get accountLegalEvidenceTitle => 'Méthodologie des données probantes';

  @override
  String get accountLegalEvidenceBody =>
      'Les énoncés sur la nutrition proviennent de lignes directrices nationales et de références faisant autorité. Chacun indique ses sources, la solidité des données probantes, ses limites et son état de révision. L\'IA peut reformuler les énoncés approuvés, mais n\'est pas autorisée à créer de nouvelles allégations santé.';

  @override
  String get accountLegalAiTitle => 'Divulgation sur l\'IA';

  @override
  String get accountLegalAiBody =>
      'Les recettes marquées « Créée par votre chef IA », les lectures de reçus et les suggestions à partir de photos sont générées par l\'IA et peuvent contenir des erreurs. Les illustrations ne sont pas des photos de vos aliments.';

  @override
  String get accountEvidenceLibrary => 'Bibliothèque des données probantes';

  @override
  String get accountLicences => 'Licences open source';

  @override
  String get accountLicencesBody =>
      'Y compris Cormorant Garamond et Inter (SIL Open Font License)';

  @override
  String get accountDataEyebrow => 'Vos données';

  @override
  String get accountDataTitle => 'Exporter ou supprimer';

  @override
  String get accountExport => 'Exportation';

  @override
  String get accountExportBody =>
      'Une copie complète de votre profil, de votre cuisine, de votre journal, de vos dossiers de santé, de vos consentements et de votre historique de partage, dans un fichier JSON.';

  @override
  String get accountPasswordConfirm =>
      'Mot de passe (pour confirmer votre identité)';

  @override
  String get accountExportMyData => 'Exporter mes données';

  @override
  String get accountExportShareSubject => 'Vos données Chefii';

  @override
  String get accountDeleteAccount => 'Supprimer le compte';

  @override
  String get accountDeleteBody =>
      'Supprime définitivement votre compte, votre journal, vos dossiers de santé et vos autorisations de partage. Si personne d\'autre ne fait partie de votre foyer, sa cuisine est aussi supprimée. Certains documents peuvent être conservés lorsque la loi l\'exige (par exemple, les reçus d\'achat liés à la facturation de l\'abonnement). Cette action est irréversible.';

  @override
  String get accountDeleteConfirmWord => 'SUPPRIMER';

  @override
  String accountDeleteConfirmLabel(String word) {
    return 'Tapez $word pour confirmer';
  }

  @override
  String get accountDeleteMyAccount => 'Supprimer mon compte';

  @override
  String chefChatUnavailable(String message) {
    return '$message Vos recettes sélectionnées restent disponibles dans Découvrir.';
  }

  @override
  String get chefChatError =>
      'Je n\'arrive pas à joindre l\'assistant culinaire pour le moment. Veuillez réessayer.';

  @override
  String get chefPromptQuickDinner => 'Quelque chose de rapide pour le souper';

  @override
  String get chefPromptProteinBreakfast => 'Un déjeuner riche en protéines';

  @override
  String get chefPromptUseWhatIHave =>
      'Que puis-je cuisiner avec ce que j\'ai ?';

  @override
  String get chefPromptVegetarian => 'Un repas végétarien réconfortant';

  @override
  String get chefAiFeature => 'votre chef IA';

  @override
  String get chefHomeTitle => 'Votre chef';

  @override
  String get chefPreferencesTooltip => 'Préférences';

  @override
  String get chefNewConversation => 'Nouvelle conversation';

  @override
  String get chefDemoChat =>
      'Démo : les réponses proviennent de la bibliothèque de recettes sélectionnées, pas de l\'IA.';

  @override
  String get chefHomeHeadline => 'Qu\'est-ce qu\'on cuisine ?';

  @override
  String get chefHomeSubtitle =>
      'Demandez ce que vous voulez — je sais ce qu\'il y a dans votre cuisine et ce que chacun peut manger.';

  @override
  String get chefChooseOptions => 'Choisir le temps, les portions et plus';

  @override
  String get chefAskHint => 'Demandez à votre chef…';

  @override
  String get chefSend => 'Envoyer';

  @override
  String get chefEyebrow => 'Chef';

  @override
  String get chefPreferencesTitle => 'Ce soir, j\'aimerais…';

  @override
  String get chefShowRecipes => 'Voir des recettes';

  @override
  String get chefMeal => 'Repas';

  @override
  String get chefTimeAvailable => 'Temps disponible';

  @override
  String get chefTimeAvailableSemantics => 'Temps disponible en minutes';

  @override
  String chefUpTo(String duration) {
    return 'Jusqu\'à $duration';
  }

  @override
  String get chefPortions => 'Portions';

  @override
  String get chefFewer => 'Moins';

  @override
  String get chefMore => 'Plus';

  @override
  String get chefUseWhatIHave => 'Utiliser ce que j\'ai';

  @override
  String get chefUseWhatIHaveSubtitle =>
      'Privilégier les recettes que je peux faire maintenant';

  @override
  String get chefNutrition => 'Nutrition';

  @override
  String get chefFocusMoreProtein => 'plus de protéines';

  @override
  String get chefFocusMoreVegetables => 'plus de légumes';

  @override
  String get chefFocusLighter => 'plus léger';

  @override
  String get chefFocusMoreFibre => 'plus de fibres';

  @override
  String get chefCuisine => 'Cuisine';

  @override
  String get chefCuisineItalian => 'Italienne';

  @override
  String get chefCuisineFrench => 'Française';

  @override
  String get chefCuisineMediterranean => 'Méditerranéenne';

  @override
  String get chefCuisineIndian => 'Indienne';

  @override
  String get chefCuisineMiddleEastern => 'Moyen-orientale';

  @override
  String get chefCuisineMexican => 'Mexicaine';

  @override
  String get chefCuisineJapanese => 'Japonaise';

  @override
  String get chefCuisineChinese => 'Chinoise';

  @override
  String get chefCuisineModern => 'Moderne';

  @override
  String get chefEquipment => 'Équipement';

  @override
  String get chefEquipmentOven => 'Four';

  @override
  String get chefEquipmentStovetop => 'Cuisinière';

  @override
  String get chefEquipmentAirFryer => 'Friteuse à air';

  @override
  String get chefEquipmentSlowCooker => 'Mijoteuse';

  @override
  String get chefEquipmentInstantPot => 'Instant Pot';

  @override
  String get chefEquipmentBlender => 'Mélangeur';

  @override
  String get chefEquipmentMicrowave => 'Micro-ondes';

  @override
  String get chefLeaveOut => 'À éviter';

  @override
  String get chefLeaveOutHint => 'p. ex. champignons, olives';

  @override
  String chefAlwaysRespected(String list) {
    return 'Toujours respectées : $list.';
  }

  @override
  String get chefNoAllergiesRecorded =>
      'aucune allergie ni restriction enregistrée';

  @override
  String get chefAddAllergies =>
      'Ajoutez vos allergies dans Profil pour que je puisse vérifier chaque recette.';

  @override
  String get chefNoRequestTitle => 'Dites-moi ce qui vous ferait envie';

  @override
  String get chefNoRequestMessage =>
      'Choisissez d\'abord le temps et les portions.';

  @override
  String get chefSetPreferences => 'Préférences';

  @override
  String get chefResultsTitle => 'Pour vous';

  @override
  String chefResultsSubtitle(String meal, String duration, int servings) {
    String _temp0 = intl.Intl.pluralLogic(
      servings,
      locale: localeName,
      other: '$servings portions',
      one: '1 portion',
    );
    return '$meal · jusqu\'à $duration · $_temp0';
  }

  @override
  String get chefAnyMeal => 'Tout repas';

  @override
  String get chefTryAnother => 'Autres idées';

  @override
  String get chefDemoResults =>
      'Démo : classées à partir de la bibliothèque sélectionnée, non générées par l\'IA.';

  @override
  String get chefConsidering => 'J\'examine votre cuisine…';

  @override
  String get chefNoMoreIdeasTitle => 'Plus d\'idées avec ces réglages';

  @override
  String get chefNoMoreIdeasMessage =>
      'Essayez un temps plus long ou moins de restrictions.';

  @override
  String get chefAdjust => 'Ajuster';

  @override
  String chefFilteredForSafety(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count idées ont été écartées en raison des besoins alimentaires de votre foyer.',
      one: '1 idée a été écartée en raison des besoins alimentaires de votre foyer.',
    );
    return '$_temp0';
  }

  @override
  String get chefRecipeUnavailableTitle => 'Recette non disponible';

  @override
  String get chefRecipeUnavailableMessage =>
      'Cette suggestion n\'a pas été enregistrée. Redemandez à votre chef ou parcourez Découvrir.';

  @override
  String get chefDiscover => 'Découvrir';

  @override
  String get chefRemoveFavourite => 'Retirer des favoris';

  @override
  String get chefSaveFavourite => 'Ajouter aux favoris';

  @override
  String get chefAddToPlan => 'Ajouter au plan de repas';

  @override
  String get chefNotSafe => 'Non sécuritaire pour votre foyer';

  @override
  String get chefStartCooking => 'Commencer à cuisiner';

  @override
  String chefTotalTime(String duration) {
    return '$duration au total';
  }

  @override
  String get chefAiCreated =>
      'Créée par l\'IA pour vous. Vérifiez les températures de cuisson et fiez-vous à votre jugement.';

  @override
  String chefAiCreatedWithModel(String model) {
    return 'Créée par l\'IA pour vous ($model). Vérifiez les températures de cuisson et fiez-vous à votre jugement.';
  }

  @override
  String get chefConflicts => 'Incompatible avec les besoins de votre foyer';

  @override
  String get chefWorthALook => 'À vérifier';

  @override
  String chefConflictLine(String ingredient, String reason) {
    return '• $ingredient : $reason';
  }

  @override
  String get chefSeeSubstitutions => 'Voir les substitutions';

  @override
  String get chefIngredients => 'Ingrédients';

  @override
  String get chefServings => 'Portions';

  @override
  String get chefFewerServings => 'Moins de portions';

  @override
  String get chefMoreServings => 'Plus de portions';

  @override
  String chefAddMissingToList(int count) {
    return 'Ajouter $count à la liste';
  }

  @override
  String get chefAddedToList => 'Ajouté à votre liste d\'épicerie';

  @override
  String get chefSubstitutions => 'Substitutions';

  @override
  String get chefMethod => 'Préparation';

  @override
  String get chefStoring => 'Conservation';

  @override
  String get chefSavedToRecipes => 'Enregistrée dans vos recettes';

  @override
  String get chefSaveRecipe => 'Enregistrer cette recette';

  @override
  String get chefInYourKitchenLower => 'dans votre cuisine';

  @override
  String chefNeedQuantity(String quantity) {
    return 'il manque $quantity';
  }

  @override
  String get chefNeedMore => 'il en manque';

  @override
  String get chefToBuy => 'à acheter';

  @override
  String get chefOptional => 'facultatif';

  @override
  String chefOptionalIngredient(String ingredient) {
    return '$ingredient (facultatif)';
  }

  @override
  String get chefSmartSubstitutions => 'Substitutions intelligentes';

  @override
  String get chefSubstitutionsNote =>
      'Chaque substitution est vérifiée en fonction des allergies et du régime alimentaire de votre foyer.';

  @override
  String get chefNoSafeSwapsTitle =>
      'Aucune substitution sécuritaire dont nous sommes sûrs';

  @override
  String get chefNoSafeSwapsMessage =>
      'Demandez plutôt une autre recette à votre chef.';

  @override
  String get chefInYourKitchen => 'Dans votre cuisine';

  @override
  String chefProteinDiff(String diff) {
    return 'Protéines $diff g / portion';
  }

  @override
  String get chefUseThis => 'Utiliser';

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
  String get cookingSessionNotFound =>
      'Cette séance de cuisine est introuvable.';

  @override
  String get cookingBeforeYouBegin => 'Avant de commencer';

  @override
  String cookingPrepSubtitle(int servings) {
    String _temp0 = intl.Intl.pluralLogic(
      servings,
      locale: localeName,
      other: '$servings portions',
      one: '1 portion',
    );
    return '$_temp0 · rassemblez tout d\'abord';
  }

  @override
  String get cookingBeginCooking => 'Commencer';

  @override
  String get cookingBeginAnyway => 'Commencer quand même';

  @override
  String cookingReadyCount(int ready, int total) {
    return 'Prêt : $ready sur $total';
  }

  @override
  String get cookingIngredients => 'Ingrédients';

  @override
  String get cookingEquipment => 'Équipement';

  @override
  String cookingKitchenShows(String quantity) {
    return 'Votre cuisine indique $quantity — vérifiez que vous en avez assez';
  }

  @override
  String get cookingNotInKitchen => 'Absent de l\'inventaire de votre cuisine';

  @override
  String cookingStepSpeech(int step, String text) {
    return 'Étape $step. $text';
  }

  @override
  String get cookingStopReadingAloud => 'Arrêter la lecture à voix haute';

  @override
  String get cookingReadAloud => 'Lire les étapes à voix haute';

  @override
  String get cookingTimers => 'Minuteries';

  @override
  String cookingStepOf(int step, int total) {
    return 'Étape $step sur $total';
  }

  @override
  String cookingStepOfCaps(int step, int total) {
    return 'ÉTAPE $step SUR $total';
  }

  @override
  String cookingStartNamedTimer(String label, String duration) {
    return 'Démarrer « $label » · $duration';
  }

  @override
  String cookingStartTimer(String duration) {
    return 'Démarrer la minuterie · $duration';
  }

  @override
  String cookingStepTimerLabel(int step) {
    return 'Étape $step';
  }

  @override
  String get cookingFinishCooking => 'Terminer';

  @override
  String get cookingNextStep => 'Étape suivante';

  @override
  String cookingTimerChipDone(String label) {
    return '$label : terminé';
  }

  @override
  String get cookingKitchenEyebrow => 'Cuisine';

  @override
  String get cookingTimersSubtitle =>
      'Elles vous alerteront même si vous quittez l\'appli.';

  @override
  String cookingStartMinutesTimer(int minutes) {
    return 'Démarrer $minutes min';
  }

  @override
  String get cookingDefaultTimerName => 'Minuterie';

  @override
  String get cookingNoTimersTitle => 'Aucune minuterie en cours';

  @override
  String get cookingNoTimersMessage =>
      'Lancez-en une depuis une étape de recette ou ci-dessous.';

  @override
  String get cookingAddMinute => '+1 minute';

  @override
  String get cookingPause => 'Pause';

  @override
  String get cookingResume => 'Reprendre';

  @override
  String get cookingNewTimer => 'Nouvelle minuterie';

  @override
  String get cookingTimerName => 'Nom';

  @override
  String get cookingTimerNameHint => 'p. ex. Riz';

  @override
  String cookingMinutesChip(int minutes) {
    return '$minutes min';
  }

  @override
  String get cookingAlmostDone => 'Presque fini';

  @override
  String get cookingWhatDidYouUse => 'Qu\'avez-vous utilisé ?';

  @override
  String get cookingConfirmSubtitle =>
      'Ajustez ce qui a changé. Votre cuisine sera mise à jour une seule fois.';

  @override
  String get cookingConfirmAndUpdate => 'Confirmer et mettre à jour';

  @override
  String cookingDiscrepancies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Cuisine mise à jour. $count articles n\'ont pas été entièrement enregistrés — nous vous demanderons de vérifier plus tard.',
      one: 'Cuisine mise à jour. 1 article n\'a pas été entièrement enregistré — nous vous demanderons de vérifier plus tard.',
    );
    return '$_temp0';
  }

  @override
  String get cookingNothingTracked =>
      'Aucun de ces ingrédients n\'est suivi dans votre cuisine ; rien ne changera donc.';

  @override
  String get cookingInclude => 'Inclure';

  @override
  String get cookingDidntUse => 'Pas utilisé';

  @override
  String cookingRecipeAmount(String quantity) {
    return 'Recette : $quantity';
  }

  @override
  String cookingAmountUsed(String ingredient) {
    return 'Quantité utilisée : $ingredient';
  }

  @override
  String get cookingBonAppetit => 'Bon appétit';

  @override
  String get cookingKitchenUpdated => 'Votre cuisine a été mise à jour.';

  @override
  String get cookingFinish => 'Terminer';

  @override
  String cookingLoggedWithLeftovers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count portions ont été mises',
      one: '1 portion a été mise',
    );
    return 'C\'est noté, et $_temp0 au frigo.';
  }

  @override
  String get cookingLoggedToJournal => 'Ajouté à votre journal.';

  @override
  String get cookingHowWasIt => 'C\'était comment ?';

  @override
  String cookingStars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count étoiles',
      one: '1 étoile',
    );
    return '$_temp0';
  }

  @override
  String get cookingYourPortion => 'Votre portion';

  @override
  String get cookingPortionsYouAte => 'Portions mangées';

  @override
  String get cookingYourMeal => 'Votre repas';

  @override
  String cookingPortionCount(num count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$amount portions',
      one: '$amount portion',
    );
    return '$_temp0';
  }

  @override
  String get cookingLeftovers => 'Restes';

  @override
  String get cookingPortionsToSave => 'Portions à garder';

  @override
  String get cookingLeftoversReminder =>
      'Nous les ajouterons à votre frigo avec un rappel de les manger dans les 3 jours.';

  @override
  String get cookingSaveFavourite => 'Ajouter aux favoris';

  @override
  String cookingTimerNotificationTitle(String label) {
    return '$label : c\'est prêt';
  }

  @override
  String get cookingTimerNotificationBody =>
      'Votre minuterie Chefii est terminée.';

  @override
  String get coreErrorTitle => 'Un problème est survenu';

  @override
  String get coreErrorOffline =>
      'Vous semblez être hors ligne, donc rien n\'a été modifié. Veuillez réessayer une fois la connexion rétablie.';

  @override
  String get coreErrorPermissionDenied =>
      'Vous n\'avez pas accès à ce contenu. S\'il vous a été partagé, la personne propriétaire a peut-être modifié les autorisations.';

  @override
  String get coreErrorGeneric => 'Veuillez réessayer dans un moment.';

  @override
  String corePermissionOff(String permission) {
    return 'Accès désactivé : $permission';
  }

  @override
  String get coreOpenSettings => 'Ouvrir les réglages';

  @override
  String coreInProgress(String label) {
    return '$label, en cours';
  }

  @override
  String get coreLess => 'Moins';

  @override
  String get coreMore => 'Plus';

  @override
  String get coreClearSearch => 'Effacer la recherche';

  @override
  String get corePhotoFrameHint => 'Placez tout le reçu dans le cadre';

  @override
  String get coreIllustration => 'Illustration';

  @override
  String coreIllustrationFor(String label) {
    return 'Illustration : $label';
  }

  @override
  String coreStatus(String status) {
    return 'État : $status';
  }

  @override
  String coreMinutesSpoken(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '$minutes minute',
    );
    return '$_temp0';
  }

  @override
  String coreMinutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String coreKcalApprox(int kcal) {
    return '≈ $kcal kcal';
  }

  @override
  String get coreLikelyPastBest => 'Probablement plus à son meilleur';

  @override
  String get corePastRecordedDate => 'Date notée dépassée';

  @override
  String coreDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days jours restants',
      one: '1 jour restant',
    );
    return '$_temp0';
  }

  @override
  String coreDaysLeftApprox(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '~$days jours restants',
      one: '~1 jour restant',
    );
    return '$_temp0';
  }

  @override
  String get coreUseSome => 'En utiliser';

  @override
  String get coreNutritionTitle => 'Nutrition';

  @override
  String get corePerServing => 'par portion';

  @override
  String get coreEstimate => 'Estimation';

  @override
  String coreNutrientAbout(String nutrient, String amount) {
    return '$nutrient : environ $amount';
  }

  @override
  String get coreNutritionNoData =>
      'Nous n\'avons pas encore de données nutritionnelles pour ces ingrédients.';

  @override
  String coreNutritionPartial(int percent) {
    return 'Selon $percent % des ingrédients — certains n\'ont pas pu être estimés.';
  }

  @override
  String coreMealAt(String meal, String time, String title) {
    return '$meal à $time : $title';
  }

  @override
  String coreMealAtDone(String meal, String time, String title) {
    return '$meal à $time : $title, terminé';
  }

  @override
  String get coreMorningRoutine => 'Routine du matin';

  @override
  String get coreSetUpMornings => 'Planifiez vos matins';

  @override
  String coreMorningSummary(String wake, String departure, int minutes) {
    return 'Debout à $wake · départ à $departure · $minutes min libres';
  }

  @override
  String get coreMorningPitch =>
      'Un plan serein, du réveil jusqu\'à la porte, avec le déjeuner déjà choisi.';

  @override
  String coreBreakfastLine(String title) {
    return 'Déjeuner : $title';
  }

  @override
  String get coreChefDemoNote => 'Démo · suggestions choisies, sans IA';

  @override
  String coreSaidByYou(String text) {
    return 'Vous : $text';
  }

  @override
  String coreSaidByChef(String text) {
    return 'Chef : $text';
  }

  @override
  String coreEvidenceStrength(String strength) {
    return 'Preuve : $strength';
  }

  @override
  String coreReviewed(String date) {
    return 'Révisé : $date';
  }

  @override
  String coreInternalSummary(String date) {
    return 'Résumé interne, $date · en attente de révision professionnelle';
  }

  @override
  String coreOverMinutes(int minutes) {
    return 'pendant $minutes min';
  }

  @override
  String get coreHelpfulHabit => 'habitude bénéfique';

  @override
  String get coreDelete => 'Supprimer';

  @override
  String get coreShareJournal => 'Repas consignés, portions et heures';

  @override
  String get coreShareNutrition =>
      'Nutriments estimés à partir de votre journal';

  @override
  String get coreShareGlucose => 'Lectures de glycémie que vous avez saisies';

  @override
  String get coreShareOral => 'Journal d\'exposition au sucre et à l\'acidité';

  @override
  String get coreShareConcerns =>
      'Notes sur les cheveux, la peau et les ongles';

  @override
  String get coreShareDietary => 'Allergies, intolérances et préférences';

  @override
  String get coreAssessmentNew => 'Nouvelle';

  @override
  String get coreAssessmentRead => 'Lue';

  @override
  String get coreAssessmentAccepted => 'Acceptée';

  @override
  String get coreAssessmentDeclined => 'Refusée';

  @override
  String get coreAssessmentDraft => 'Brouillon';

  @override
  String get coreDemoBanner =>
      'Mode démo — données d\'exemple, aucune IA utilisée.';

  @override
  String get coreTabToday => 'Aujourd\'hui';

  @override
  String get coreTabKitchen => 'Cuisine';

  @override
  String get coreTabDiscover => 'Découvrir';

  @override
  String get coreTabJournal => 'Journal';

  @override
  String get coreTabYou => 'Vous';

  @override
  String get corePageNotFound => 'Page introuvable';

  @override
  String get corePageNotFoundMessage =>
      'Ce lien ne mène nulle part dans Chefii.';

  @override
  String get coreGoToToday => 'Aller à Aujourd\'hui';

  @override
  String get coreAppLoading => 'Chargement de Chefii';

  @override
  String get coreSnoozeWakeBody =>
      'Votre alarme reportée. Touchez pour commencer votre matinée.';

  @override
  String get coreSnoozeEveningTitle => 'Demain matin';

  @override
  String get coreSnoozeEveningBody => 'Votre aperçu du soir reporté.';

  @override
  String get coreSnoozeReminderTitle => 'Un petit rappel';

  @override
  String get coreSnoozeReminderBody => 'Votre rappel Chefii reporté.';

  @override
  String get coreSnoozeAction => 'Reporter de 10 min';

  @override
  String get coreChannelReminders => 'Rappels de repas';

  @override
  String get coreChannelRemindersDescription =>
      'Rappels doux pour les repas et les tâches en cuisine';

  @override
  String get coreChannelAlarm => 'Alarme du matin';

  @override
  String get coreChannelAlarmDescription =>
      'L\'alarme de votre routine du matin';

  @override
  String get coreChannelTimers => 'Minuteries de cuisson';

  @override
  String get coreChannelTimersDescription =>
      'Alertes à la fin d\'une minuterie de cuisson';

  @override
  String get coreErrNotSignedIn => 'Veuillez vous connecter pour continuer.';

  @override
  String get coreErrReceiptDuplicate =>
      'Ce reçu ressemble à un reçu que vous avez déjà numérisé.';

  @override
  String get coreErrPlaceNameLength =>
      'Donnez à cet endroit un nom de 30 caractères au plus.';

  @override
  String coreErrPlaceNameTaken(String name) {
    return 'Vous avez déjà un endroit appelé $name.';
  }

  @override
  String get coreErrPlaceLimit => 'Vous pouvez avoir jusqu\'à 12 endroits.';

  @override
  String get coreErrBuiltInRename =>
      'Les endroits par défaut ne peuvent pas être renommés.';

  @override
  String get coreErrBuiltInRemove =>
      'Les endroits par défaut ne peuvent pas être supprimés.';

  @override
  String get coreErrPlaceNotEmpty =>
      'Déplacez ou utilisez d\'abord ce qui s\'y trouve.';

  @override
  String get coreErrNothingToAdd => 'Rien à ajouter.';

  @override
  String coreErrQuantityNotPositive(String product) {
    return '$product : la quantité doit être supérieure à zéro.';
  }

  @override
  String get coreErrNothingToDeduct => 'Rien à déduire.';

  @override
  String get coreErrNothingToCorrect => 'Rien à corriger.';

  @override
  String get coreErrNegativeCount =>
      'Les quantités ne peuvent pas être négatives.';

  @override
  String get coreErrItemGone => 'Cet article n\'existe plus.';

  @override
  String coreErrWrongUnit(String product, String unit) {
    return '$product : utilisez l\'unité « $unit » pour cet article.';
  }

  @override
  String get coreErrNothingToUndo => 'Rien à annuler.';

  @override
  String get coreErrAlreadyUndone => 'Cette modification a déjà été annulée.';

  @override
  String get coreErrUndoOfUndo =>
      'Une annulation ne peut pas elle-même être annulée.';

  @override
  String coreErrProductNotRecorded(String product) {
    return 'Aucun article « $product » n\'est inscrit dans votre cuisine.';
  }

  @override
  String get coreErrReceiptNotFound => 'Reçu introuvable.';

  @override
  String get coreErrReceiptNotEditable => 'Ce reçu ne peut plus être modifié.';

  @override
  String get coreErrReceiptNotReady =>
      'Ce reçu n\'est pas prêt à être importé.';

  @override
  String coreErrReceiptLinesIncomplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count articles doivent avoir un nom et une quantité avant l\'importation.',
      one: '1 article doit avoir un nom et une quantité avant l\'importation.',
    );
    return '$_temp0';
  }

  @override
  String get coreErrReceiptNoFoodItems => 'Il n\'y a aucun aliment à ajouter.';

  @override
  String get coreErrReceiptNoPhotos => 'Ajoutez au moins une photo.';

  @override
  String coreErrReceiptTooManyPages(int max) {
    return 'Jusqu\'à $max pages par reçu.';
  }

  @override
  String get coreErrImageEmpty => 'Cette image semble vide.';

  @override
  String get coreErrImageTooLarge =>
      'Cette image est trop volumineuse (plus de 12 Mo). Essayez une photo plus rapprochée, d\'une seule page.';

  @override
  String get coreErrImageFormat =>
      'Veuillez utiliser une photo JPEG, PNG, HEIC ou WebP.';

  @override
  String get coreErrAiUnavailable =>
      'L\'assistant culinaire n\'est pas disponible pour le moment.';

  @override
  String get coreErrAuthCredentialMismatch =>
      'Ce courriel et ce mot de passe ne correspondent pas.';

  @override
  String get coreErrAuthEmailInUse =>
      'Un compte existe déjà pour ce courriel. Essayez de vous connecter.';

  @override
  String get coreErrAuthWeakPassword =>
      'Veuillez choisir un mot de passe plus long (au moins 8 caractères).';

  @override
  String get coreErrAuthInvalidEmail =>
      'Cette adresse courriel ne semble pas valide.';

  @override
  String get coreErrAuthOffline =>
      'Vous semblez être hors ligne. Veuillez réessayer.';

  @override
  String get coreErrAuthTooManyRequests =>
      'Trop de tentatives. Patientez un moment, puis réessayez.';

  @override
  String get coreErrAuthRecentLogin =>
      'Pour votre sécurité, veuillez vous reconnecter pour continuer.';

  @override
  String get coreErrAuthCancelled => 'La connexion a été annulée.';

  @override
  String get coreErrAuthFailed => 'La connexion a échoué.';

  @override
  String get coreErrAuthFailedRetry =>
      'La connexion a échoué. Veuillez réessayer.';

  @override
  String get coreErrAuthNoGoogleToken =>
      'Google n\'a pas renvoyé de jeton d\'identité.';

  @override
  String get coreErrAuthSignInAgain => 'Veuillez vous reconnecter.';

  @override
  String get coreErrAuthPasswordRequired =>
      'Entrez votre mot de passe pour continuer.';

  @override
  String get coreErrAuthAppleNeedsFirebase =>
      'La connexion avec Apple nécessite la configuration de Firebase. Utilisez le compte démo.';

  @override
  String get coreErrAuthGoogleNeedsFirebase =>
      'La connexion avec Google nécessite la configuration de Firebase. Utilisez le compte démo.';

  @override
  String get coreErrOwnerNotRemovable =>
      'La personne propriétaire ne peut pas être retirée.';

  @override
  String get coreErrProfessionalNotVerified =>
      'L\'accès ne peut être accordé qu\'aux comptes professionnels vérifiés.';

  @override
  String get coreErrNoShareCategories =>
      'Choisissez au moins une catégorie à partager.';

  @override
  String coreErrNoActivePermission(String category) {
    return 'Aucune autorisation active pour : $category.';
  }

  @override
  String get discoverFilterAvailableNow => 'Possible maintenant';

  @override
  String get discoverFilterBreakfast => 'Déjeuner';

  @override
  String get discoverFilterLunch => 'Dîner';

  @override
  String get discoverFilterDinner => 'Souper';

  @override
  String get discoverFilterSnacks => 'Collations';

  @override
  String get discoverFilter15Minute => '15 minutes';

  @override
  String get discoverFilterHighProtein => 'Riche en protéines';

  @override
  String get discoverFilterVegetarian => 'Végétarien';

  @override
  String get discoverFilterComfort => 'Réconfort';

  @override
  String get discoverFilterWorldCuisines => 'Cuisines du monde';

  @override
  String get discoverMealPlanner => 'Planificateur de repas';

  @override
  String get discoverAskChef => 'Demander au chef';

  @override
  String get discoverEyebrow => 'Découvrir';

  @override
  String get discoverTitle => 'Quelque chose de délicieux';

  @override
  String discoverCookWith(String ingredient) {
    return 'Cuisiner avec $ingredient';
  }

  @override
  String get discoverSubtitle =>
      'Chaque recette ici convient aux besoins alimentaires de votre foyer.';

  @override
  String get discoverSearchHint => 'Rechercher des recettes ou des ingrédients';

  @override
  String get discoverNoMatchTitle => 'Aucune recette ne correspond';

  @override
  String get discoverNoMatchMessage =>
      'Essayez un autre filtre, ou demandez à votre chef de créer quelque chose.';

  @override
  String get discoverUsesExpiring => 'Utilise un aliment à consommer bientôt';

  @override
  String discoverNutritionFootnote(int grams) {
    return 'Les valeurs nutritives sont estimées par portion à partir de données de référence. « Riche en protéines » signifie au moins $grams g par portion.';
  }

  @override
  String discoverNutritionFootnoteHidden(int grams) {
    return 'Les valeurs nutritives sont estimées par portion à partir de données de référence (masquées dans vos préférences). « Riche en protéines » signifie au moins $grams g par portion.';
  }

  @override
  String discoverProteinLabel(int grams) {
    return '$grams g de protéines';
  }

  @override
  String get healthOpenLinkError => 'Impossible d’ouvrir le lien.';

  @override
  String get healthNutritionEyebrow => 'Nutrition';

  @override
  String get healthYourNutrition => 'Votre nutrition';

  @override
  String healthDailyAverageSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Moyenne quotidienne sur $count jours consignés',
      one: 'Moyenne quotidienne sur 1 jour consigné',
    );
    return '$_temp0';
  }

  @override
  String get healthInsights => 'Constats';

  @override
  String healthDaysSegment(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours',
      one: '1 jour',
    );
    return '$_temp0';
  }

  @override
  String get healthNoMealsTitle => 'Aucun repas consigné pour l’instant';

  @override
  String get healthNoMealsMessage =>
      'Cuisinez avec Chefii ou consignez vos repas dans votre journal pour voir des estimations ici.';

  @override
  String get healthLogMeal => 'Consigner un repas';

  @override
  String get healthEstimatesNote =>
      'Estimations tirées des recettes et de données de référence.';

  @override
  String healthMissingDataNote(int percent) {
    return 'Certains repas n’avaient pas de données nutritionnelles ($percent %) ; les totaux sont donc probablement sous-estimés.';
  }

  @override
  String get healthDailyValueNote =>
      'Les valeurs quotidiennes sont la référence d’étiquetage de Santé Canada — un repère, pas un objectif personnel.';

  @override
  String healthNutrientBarSemantics(String nutrient, String amount) {
    return '$nutrient : environ $amount';
  }

  @override
  String healthNutrientBarSemanticsDv(
    String nutrient,
    String amount,
    int percent,
  ) {
    return '$nutrient : environ $amount, $percent % de la valeur quotidienne';
  }

  @override
  String healthPercentDv(int percent) {
    return '$percent % VQ';
  }

  @override
  String get healthNotEnoughHistory => 'Historique encore insuffisant';

  @override
  String healthPerDay(String amount) {
    return '≈ $amount par jour';
  }

  @override
  String healthSteadyAt(String amount) {
    return 'Stable à ≈ $amount par jour';
  }

  @override
  String healthTrendUp(int percent) {
    return 'En hausse de $percent % par rapport à la semaine précédente';
  }

  @override
  String healthTrendDown(int percent) {
    return 'En baisse de $percent % par rapport à la semaine précédente';
  }

  @override
  String get healthInsightsSubtitle =>
      'Les tendances de votre journal, expliquées données probantes à l’appui.';

  @override
  String get healthEvidenceLibrary => 'Bibliothèque des données probantes';

  @override
  String get healthInsightsEmptyTitle =>
      'Il faut quelques jours de repas pour dégager des constats';

  @override
  String get healthInsightsEmptyMessage =>
      'Continuez de cuisiner et de consigner vos repas — nous chercherons des tendances après quelques jours.';

  @override
  String get healthTrends => 'Tendances';

  @override
  String get healthVarietyThisWeek => 'Variété cette semaine';

  @override
  String healthDifferentMeals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'repas différents',
      one: 'repas différent',
      zero: 'repas différent',
    );
    return '$_temp0';
  }

  @override
  String healthPlantFoods(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'aliments végétaux dans les recettes Chefii',
      one: 'aliment végétal dans les recettes Chefii',
      zero: 'aliment végétal dans les recettes Chefii',
    );
    return '$_temp0';
  }

  @override
  String get healthSomethingToTry => 'Une idée à essayer';

  @override
  String healthFibrePerServing(int grams) {
    return '≈ $grams g de fibres par portion';
  }

  @override
  String healthAvailabilityLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ingrédients à acheter',
      one: '1 ingrédient à acheter',
      zero: 'Tout est sous la main',
    );
    return '$_temp0';
  }

  @override
  String get healthMoreToExplore => 'À explorer aussi';

  @override
  String get healthHairSkinNails => 'Cheveux, peau et ongles';

  @override
  String get healthSmileAndFood => 'Sourire et alimentation';

  @override
  String get healthEducationDisclaimer =>
      'Chefii offre de l’information générale sur la nutrition, et non des conseils médicaux. Pour des conseils personnalisés, adressez-vous à une ou un diététiste.';

  @override
  String get healthHairSubtitle =>
      'Un carnet privé, et ce que les données probantes disent — et ne disent pas.';

  @override
  String get healthHairCausesNote =>
      'Les changements aux cheveux, à la peau et aux ongles ont bien des causes autres que l’alimentation — hormones, thyroïde, stress, médicaments, affections de la peau et génétique. Une perte de cheveux soudaine, des éruptions cutanées ou des changements aux ongles qui ne se résorbent pas justifient une consultation auprès d’un médecin, d’un dermatologue ou d’un pharmacien.';

  @override
  String get healthNoteAConcern => 'Noter une préoccupation';

  @override
  String get healthConcernHair => 'Cheveux';

  @override
  String get healthConcernSkin => 'Peau';

  @override
  String get healthConcernNails => 'Ongles';

  @override
  String get healthConcernEnergy => 'Énergie';

  @override
  String get healthConcernDigestion => 'Digestion';

  @override
  String get healthConcernOther => 'Autre';

  @override
  String get healthWhatHaveYouNoticed => 'Qu’avez-vous remarqué ?';

  @override
  String healthBotherLevel(int severity) {
    return 'À quel point cela vous dérange-t-il ? ($severity sur 5)';
  }

  @override
  String get healthBotherSemantics =>
      'À quel point cela vous dérange, de 1 à 5';

  @override
  String get healthSaveNote => 'Enregistrer la note';

  @override
  String get healthSavedPrivately => 'Enregistré en privé';

  @override
  String get healthYourNotes => 'Vos notes';

  @override
  String get healthDelete => 'Supprimer';

  @override
  String get healthWhatEvidenceSays => 'Ce que disent les données probantes';

  @override
  String get healthShareWithDietitian => 'Partager avec une ou un diététiste';

  @override
  String get healthEvidence => 'Données probantes';

  @override
  String get healthHowWeKnow => 'Sur quoi nous nous appuyons';

  @override
  String get healthEvidenceSubtitle =>
      'Chaque énoncé nutritionnel de Chefii, avec ses sources et ses limites.';

  @override
  String get healthReview => 'Révision';

  @override
  String healthProfessionallyReviewed(String date) {
    return 'Révisé par des professionnels le $date';
  }

  @override
  String healthInternalSummary(String date) {
    return 'Résumé interne ($date), en attente de révision professionnelle';
  }

  @override
  String get healthLimitations => 'Limites';

  @override
  String get healthFoods => 'Aliments';

  @override
  String healthLabelColon(String label) {
    return '$label :';
  }

  @override
  String get healthCitationPending =>
      'Source : référence en attente de vérification.';

  @override
  String get healthMethodNote =>
      'Méthode : nous privilégions les lignes directrices nationales et les revues systématiques ; aucune recommandation ne repose sur une étude isolée.';

  @override
  String get healthNutrientEyebrow => 'Nutriment';

  @override
  String get healthNoDataYet => 'Aucune donnée pour l’instant';

  @override
  String get healthLogMealsForEstimate =>
      'Consignez vos repas pour voir une estimation.';

  @override
  String healthAverageThisWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Moyenne sur $count jours consignés cette semaine',
      one: 'Moyenne sur 1 jour consigné cette semaine',
    );
    return '$_temp0';
  }

  @override
  String healthReferenceDailyValue(String amount) {
    return 'Référence : $amount (valeur quotidienne, Santé Canada, Tableau des valeurs quotidiennes)';
  }

  @override
  String healthReferenceOther(String amount, String kind, String source) {
    return 'Référence : $amount ($kind, $source)';
  }

  @override
  String healthDataCompleteness(int percent) {
    return 'Exhaustivité des données : $percent % des repas avaient des estimations nutritionnelles.';
  }

  @override
  String get healthBiggestContributors => 'Principales sources cette semaine';

  @override
  String get healthRichSources => 'Sources riches';

  @override
  String healthPer100g(String amount) {
    return '$amount / 100 g';
  }

  @override
  String get healthIndividualNeeds =>
      'Les besoins varient d’une personne à l’autre. Les estimations ne peuvent pas tenir compte des marques exactes, des portions ni du sel ajouté.';

  @override
  String get healthWellnessEyebrow => 'Mieux-être';

  @override
  String get healthSmileIntroSubtitle =>
      'Découvrez comment le moment où vous consommez des aliments sucrés et acides influe sur vos dents.';

  @override
  String get healthTurnOnSmile => 'Activer Sourire et alimentation';

  @override
  String get healthSmileOptionalNote =>
      'Il s’agit d’information facultative. Ce n’est pas une évaluation dentaire, et vos entrées restent privées, sauf si vous choisissez de les partager.';

  @override
  String get healthSmileSubtitle =>
      'Touchez pour noter. C’est une question de fréquence et de moment, pas de perfection.';

  @override
  String get healthHistory => 'Historique';

  @override
  String get healthSugarExposuresToday => 'expositions au sucre aujourd’hui';

  @override
  String get healthAcidExposuresToday => 'expositions à l’acide aujourd’hui';

  @override
  String get healthHelpfulHabits => 'bonnes habitudes';

  @override
  String get healthLogNow => 'Noter maintenant';

  @override
  String healthLoggedMessage(String item) {
    return 'Noté : $item';
  }

  @override
  String get healthKinderChoices => 'Des choix plus doux';

  @override
  String get healthTipSweetsTitle => 'Gardez les sucreries pour les repas';

  @override
  String get healthTipSweetsBody =>
      'Une seule exposition au sucre au souper est plus douce pour les dents que la même quantité étalée sur l’après-midi.';

  @override
  String get healthTipFinishTitle => 'Terminez avec de l’eau ou du fromage';

  @override
  String get healthTipFinishBody =>
      'Se rincer la bouche à l’eau ou terminer par du fromage aide la bouche à se rétablir après avoir mangé.';

  @override
  String get healthTipSipTitle => 'Buvez, puis arrêtez';

  @override
  String get healthTipSipBody =>
      'Si vous aimez le jus ou les boissons gazeuses, les boire pendant un repas plutôt qu’en les sirotant pendant une heure limite la durée d’exposition à l’acide.';

  @override
  String get healthTipBrushTitle => 'Attendez avant de brosser après l’acide';

  @override
  String get healthTipBrushBody =>
      'Bien des professionnels dentaires suggèrent d’attendre un peu après un aliment ou une boisson acide avant de se brosser les dents. Demandez à votre dentiste ce qui vous convient.';

  @override
  String get healthSmileFooter =>
      'À titre informatif seulement. En cas de douleur dentaire, de sensibilité ou d’inquiétude, consultez votre dentiste.';

  @override
  String healthHistoryExposuresPerDay(String rate) {
    return 'Environ $rate expositions au sucre ou à l’acide par jour cette semaine';
  }

  @override
  String get healthNothingLoggedYet => 'Rien de noté pour l’instant';

  @override
  String get healthLogWillAppear => 'Vos entrées apparaîtront ici.';

  @override
  String get healthDiabetesConsentText =>
      'Je choisis de conserver dans Chefii les lectures de glycémie que j’y saisis. Je comprends que Chefii ne pose pas de diagnostic, n’interprète pas les lectures, ne recommande ni insuline ni médicament, et ne remplace pas les alarmes de mon glucomètre ou de mon capteur de glucose en continu (CGM). Mes lectures sont privées et ne sont partagées que si j’en donne l’accès.';

  @override
  String get healthOptionalEyebrow => 'Facultatif';

  @override
  String get healthGlucoseJournal => 'Journal de glycémie';

  @override
  String get healthDiabetesSubtitle =>
      'Pour les personnes qui suivent déjà leur glycémie et veulent la voir à côté de leurs repas.';

  @override
  String get healthTurnOffGlucose => 'Désactiver les fonctions de glycémie';

  @override
  String get healthTurnOnGlucose => 'Activer le journal de glycémie';

  @override
  String get healthGlucoseOn => 'Le journal de glycémie est activé.';

  @override
  String get healthOpenGlucose => 'Ouvrir le journal de glycémie';

  @override
  String get healthDiabetesPointRecord =>
      'Notez les lectures que vous prenez, avec l’heure et le contexte.';

  @override
  String get healthDiabetesPointMeals =>
      'Voyez-les à côté des repas de votre journal.';

  @override
  String get healthDiabetesPointNoAdvice =>
      'Aucune prédiction, aucun score, aucun diagnostic ni conseil de dosage — jamais.';

  @override
  String get healthDiabetesPointNotAlarm =>
      'Ce n’est pas une alarme. Continuez d’utiliser les alertes de votre glucomètre ou de votre CGM.';

  @override
  String get healthDiabetesPointPrivate =>
      'Privé. Partagé seulement avec le ou la professionnelle de votre choix.';

  @override
  String get healthUnits => 'Unités';

  @override
  String get healthUnderstandJournal =>
      'Je comprends qu’il s’agit d’un journal et non d’un instrument médical';

  @override
  String get healthConsentStore =>
      'Je consens à ce que Chefii conserve mes lectures de glycémie';

  @override
  String get healthSymptomsWarning =>
      'Si vous avez des symptômes de glycémie très élevée ou très basse, suivez votre plan de soins ou obtenez de l’aide médicale.';

  @override
  String get healthEnterNumber => 'Entrez un nombre.';

  @override
  String get healthEnterPositive => 'Entrez une valeur positive.';

  @override
  String get healthValueOutOfRange =>
      'Cette valeur semble hors de ce que les glucomètres affichent habituellement. Veuillez la vérifier.';

  @override
  String get healthGlucoseOffTitle => 'Le journal de glycémie est désactivé';

  @override
  String get healthGlucoseOffConsent =>
      'Activez-le d’abord en donnant votre consentement explicite.';

  @override
  String get healthSetUp => 'Configurer';

  @override
  String get healthGlucoseEyebrow => 'Glycémie';

  @override
  String get healthGlucoseSubtitle =>
      'Vos lectures, telles que vous les avez saisies.';

  @override
  String get healthTimelineWithMeals => 'Chronologie avec les repas';

  @override
  String get healthAddReading => 'Ajouter une lecture';

  @override
  String get healthReading => 'Lecture';

  @override
  String get healthContextFasting => 'À jeun';

  @override
  String get healthContextBeforeMeal => 'Avant le repas';

  @override
  String get healthContextAfterMeal => 'Après le repas';

  @override
  String get healthContextBedtime => 'Au coucher';

  @override
  String get healthContextOther => 'Autre';

  @override
  String healthDayAtTime(String day, String time) {
    return '$day à $time';
  }

  @override
  String get healthReadings => 'Lectures';

  @override
  String get healthNoReadings => 'Aucune lecture pour l’instant.';

  @override
  String get healthSourceManual => 'saisie par vous';

  @override
  String get healthSourceHealthApp => 'de l’app Santé';

  @override
  String healthSourceDevice(String device) {
    return 'de $device';
  }

  @override
  String get healthDevice => 'l’appareil';

  @override
  String healthEnteredAs(String value) {
    return 'saisie en $value';
  }

  @override
  String get healthNoHealthImport =>
      'L’importation depuis Apple Santé ou Health Connect n’est pas encore offerte. Chefii n’interprète jamais les lectures.';

  @override
  String get healthGlucoseOffShort => 'Activez-le d’abord.';

  @override
  String get healthTimelineSubtitle =>
      'Repas et lectures en ordre chronologique. Aucune interprétation.';

  @override
  String get healthPreviousDay => 'Jour précédent';

  @override
  String get healthNextDay => 'Jour suivant';

  @override
  String get healthNothingRecorded => 'Rien d’enregistré';

  @override
  String get healthTimelineEmptyMessage =>
      'Les repas et les lectures de cette journée apparaîtront ici.';

  @override
  String get healthTimelineFooter =>
      'Discutez des tendances avec votre équipe de soins du diabète. Chefii ne remplace ni les alarmes de glycémie ni les conseils médicaux.';

  @override
  String get journalNutritionTooltip => 'Nutrition';

  @override
  String get journalMoreTooltip => 'Plus';

  @override
  String get journalFullHistory => 'Historique complet';

  @override
  String get journalEatingPatterns => 'Habitudes alimentaires';

  @override
  String get journalMealReminders => 'Rappels de repas';

  @override
  String get journalEyebrow => 'Journal';

  @override
  String get journalPreviousDay => 'Jour précédent';

  @override
  String get journalNextDay => 'Jour suivant';

  @override
  String get journalLogAMeal => 'Noter un repas';

  @override
  String get journalEmptyTodayTitle => 'Rien de noté aujourd\'hui';

  @override
  String get journalEmptyTitle => 'Rien de noté';

  @override
  String get journalEmptyMessage =>
      'Les repas cuisinés dans Chefii sont notés automatiquement. Vous pouvez aussi ajouter tout ce que vous avez mangé.';

  @override
  String journalPortionCount(num count, String portions) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$portions portions',
      one: '$portions portion',
    );
    return '$_temp0';
  }

  @override
  String journalRepeatMeal(String title) {
    return 'Reprendre $title';
  }

  @override
  String journalLoggedAgain(String title) {
    return '$title noté de nouveau';
  }

  @override
  String get journalDaySoFar => 'La journée jusqu\'ici';

  @override
  String get journalEstimatedIntake => 'Apport estimé';

  @override
  String journalMealCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count repas',
      one: '1 repas',
    );
    return '$_temp0';
  }

  @override
  String get journalHistoryTitle => '30 derniers jours';

  @override
  String get journalHistorySubtitle => 'Touchez un repas pour le corriger.';

  @override
  String get journalHistoryEmptyTitle => 'Aucun historique pour l\'instant';

  @override
  String get journalHistoryEmptyMessage => 'Vos repas s\'accumuleront ici.';

  @override
  String get journalEntryNotFoundTitle => 'Entrée introuvable';

  @override
  String get journalEntryNotFoundMessage => 'Elle a peut-être été supprimée.';

  @override
  String get journalDelete => 'Supprimer';

  @override
  String get journalDeleteTitle => 'Supprimer cette entrée ?';

  @override
  String get journalDeleteMessage =>
      'Elle sera retirée de votre journal. Votre cuisine reste inchangée.';

  @override
  String get journalSaveChanges => 'Enregistrer les modifications';

  @override
  String journalDayAtTime(String day, String time) {
    return '$day à $time';
  }

  @override
  String get journalPortions => 'Portions';

  @override
  String get journalEstimated => 'Estimation';

  @override
  String journalForPortions(num count, String portions) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pour $portions portions',
      one: 'pour $portions portion',
    );
    return '$_temp0';
  }

  @override
  String get journalViewRecipe => 'Voir la recette';

  @override
  String get journalQuickTitle => 'Qu\'avez-vous mangé ?';

  @override
  String get journalLogMeal => 'Noter le repas';

  @override
  String get journalAiFeatureEstimatingMeals => 'estimer les repas';

  @override
  String journalMealLogged(String title) {
    return '$title noté';
  }

  @override
  String get journalQuickHint => 'p. ex. yogourt grec et petits fruits';

  @override
  String get journalListening => 'Écoute en cours';

  @override
  String get journalSpeak => 'Dicter';

  @override
  String get journalVoiceUnavailable =>
      'La saisie vocale n\'est pas disponible — essayez la dictée de votre clavier.';

  @override
  String get journalAddPhoto => 'Ajouter une photo';

  @override
  String get journalPhotoAdded => 'Photo ajoutée';

  @override
  String get journalCameraOff =>
      'L\'accès à l\'appareil photo est désactivé. Vous pouvez quand même décrire le repas.';

  @override
  String get journalEstimateNutrition => 'Estimer la nutrition';

  @override
  String get journalSavedRecipe => 'Recette enregistrée';

  @override
  String get journalDemoEstimate =>
      'Estimation de démonstration tirée de données de référence — aucune IA utilisée.';

  @override
  String get journalDetails => 'Détails';

  @override
  String get journalRemindersSubtitle =>
      'De doux rappels, jamais insistants. Les heures de silence sont toujours respectées.';

  @override
  String get journalSaveReminders => 'Enregistrer les rappels';

  @override
  String get journalNotificationsOff =>
      'Les notifications de Chefii sont désactivées dans les réglages.';

  @override
  String journalReminderNotificationTitle(String meal) {
    return '$meal : c\'est l\'heure';
  }

  @override
  String get journalReminderNotificationBody => 'Un petit rappel de Chefii.';

  @override
  String get journalRemindersSaved => 'Rappels enregistrés';

  @override
  String journalRemindersSavedSkipped(int count, String meals) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Enregistré. Aucune notification pour $meals : heures de silence.',
      one: 'Enregistré. Aucune notification pour $meals : heures de silence.',
    );
    return '$_temp0';
  }

  @override
  String get journalReminderOff => 'Désactivé';

  @override
  String get journalQuietHours => 'Heures de silence';

  @override
  String journalQuietHoursRange(String start, String end) {
    return 'Aucun rappel entre $start h et $end h.';
  }

  @override
  String journalWakeLabel(String hour) {
    return 'Réveil $hour h';
  }

  @override
  String journalSleepLabel(String hour) {
    return 'Coucher $hour h';
  }

  @override
  String get journalRemindersFootnote =>
      'Reportez un rappel depuis la notification elle-même, ou ignorez-le simplement — Chefii ne le répète jamais.';

  @override
  String get journalPatternsSubtitle =>
      'Les deux dernières semaines, telles que notées.';

  @override
  String get journalMealsPerDay => 'repas notés par jour';

  @override
  String get journalDaysNoRecords => 'jours sans données';

  @override
  String get journalUsualTimes => 'Heures habituelles';

  @override
  String get journalPatternsEmpty =>
      'Notez quelques repas pour voir votre rythme.';

  @override
  String journalWithinHour(int percent) {
    return '$percent % à moins d\'une heure de votre rappel';
  }

  @override
  String journalAround(String time) {
    return 'vers $time';
  }

  @override
  String get journalLast14Days => '14 derniers jours';

  @override
  String journalDayMealsSemantics(int count, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$date : $count repas',
      one: '$date : 1 repas',
    );
    return '$_temp0';
  }

  @override
  String get journalPatternsDisclaimer =>
      'Un jour sans données signifie habituellement qu\'un repas n\'a pas été noté, et non qu\'il n\'a pas été mangé. Chefii décrit vos données ; il ne prédit pas la glycémie et ne juge pas vos habitudes.';

  @override
  String get kitchenShoppingList => 'Liste d\'épicerie';

  @override
  String get kitchenTellChefii => 'Dire à Chefii';

  @override
  String get kitchenEyebrow => 'Cuisine';

  @override
  String get kitchenMyKitchen => 'Ma cuisine';

  @override
  String kitchenItemsAcrossPlaces(int count, int places) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles',
      one: '1 article',
    );
    String _temp1 = intl.Intl.pluralLogic(
      places,
      locale: localeName,
      other: '$places emplacements',
      one: '1 emplacement',
    );
    return '$_temp0 dans $_temp1';
  }

  @override
  String get kitchenScanReceipt => 'Numériser un reçu';

  @override
  String get kitchenOpening => 'Ouverture de votre cuisine…';

  @override
  String get kitchenEmptyTitle => 'Votre cuisine est vide';

  @override
  String get kitchenEmptyMessage =>
      'Numérisez un reçu d\'épicerie et Chefii la remplit pour vous — ou ajoutez quelques articles à la main.';

  @override
  String get kitchenAddAnItem => 'Ajouter un article';

  @override
  String get kitchenScanFridgeInstead => 'Numériser plutôt le frigo';

  @override
  String get kitchenUseSoon => 'À utiliser bientôt';

  @override
  String get kitchenToVerify => 'À vérifier';

  @override
  String get kitchenStatAdd => 'Ajouter';

  @override
  String get kitchenStatAnItem => 'un article';

  @override
  String kitchenStatSemantics(String label, String value) {
    return '$label : $value';
  }

  @override
  String get kitchenFilterAll => 'Tout';

  @override
  String get kitchenManagePlaces => 'Gérer les emplacements';

  @override
  String get kitchenSearchHint => 'Chercher dans votre cuisine';

  @override
  String get kitchenNoMatchTitle => 'Aucun résultat';

  @override
  String get kitchenNoMatchMessage =>
      'Essayez une autre recherche ou un autre filtre.';

  @override
  String get kitchenScanFridge => 'Numériser le frigo';

  @override
  String get kitchenSpendingWaste => 'Dépenses et gaspillage';

  @override
  String get kitchenReceipts => 'Reçus';

  @override
  String get kitchenStorageEyebrow => 'Rangement';

  @override
  String kitchenConfirmedOfTotal(int confirmed, int total) {
    return 'Confirmés : $confirmed sur $total · les plus urgents d\'abord';
  }

  @override
  String get kitchenVerifyTheseItems => 'Vérifier ces articles';

  @override
  String get kitchenNothingHereTitle => 'Rien ici pour l\'instant';

  @override
  String kitchenNothingHereMessage(String place) {
    return 'Les articles que vous ajoutez à « $place » apparaissent ici.';
  }

  @override
  String get kitchenItemNotFoundTitle => 'Article introuvable';

  @override
  String get kitchenItemNotFoundMessage =>
      'Il a peut-être été retiré par un membre de votre foyer.';

  @override
  String get kitchenMore => 'Plus d\'options';

  @override
  String kitchenDiscardTitle(String name) {
    return 'Jeter $name ?';
  }

  @override
  String kitchenDiscardMessage(String amount) {
    return 'La quantité restante ($amount) sera comptée comme gaspillage alimentaire.';
  }

  @override
  String get kitchenDiscard => 'Jeter';

  @override
  String kitchenMoveTo(String place) {
    return 'Déplacer vers $place';
  }

  @override
  String get kitchenUpdateAmount => 'Modifier la quantité';

  @override
  String get kitchenRecordedAmount => 'Quantité inscrite';

  @override
  String get kitchenOriginally => 'Au départ';

  @override
  String get kitchenAdded => 'Ajout';

  @override
  String get kitchenSource => 'Provenance';

  @override
  String get kitchenSourceReceipt => 'Reçu';

  @override
  String kitchenSourceReceiptLine(String line) {
    return 'Reçu · « $line »';
  }

  @override
  String get kitchenSourcePhotoScan => 'Numérisation photo';

  @override
  String get kitchenSourceBarcode => 'Code-barres';

  @override
  String get kitchenSourceLeftover => 'Restes que vous avez gardés';

  @override
  String get kitchenSourceDemo => 'Ingrédient d\'exemple';

  @override
  String get kitchenSourceManual => 'Ajouté à la main';

  @override
  String get kitchenPackage => 'Emballage';

  @override
  String get kitchenDateOnPackage => 'Date sur l\'emballage';

  @override
  String get kitchenEstimatedQuality => 'Qualité estimée';

  @override
  String get kitchenUnknown => 'Inconnue';

  @override
  String get kitchenSetDateFromPackage => 'Indiquer la date de l\'emballage';

  @override
  String get kitchenDatePrintedOnPackage => 'Date imprimée sur l\'emballage';

  @override
  String get kitchenEstimateWarning =>
      'Selon notre estimation, il vaudrait mieux l\'utiliser bientôt. Les estimations ne sont qu\'un repère — vérifiez son apparence et son odeur, et suivez la date sur l\'emballage.';

  @override
  String get kitchenRecordedDatePast =>
      'La date que vous avez inscrite est passée. Suivez les indications de l\'emballage ; en cas de doute, jetez-le.';

  @override
  String get kitchenRecordedDateClose =>
      'La date que vous avez inscrite approche. Suivez les indications de l\'emballage ; en cas de doute, jetez-le.';

  @override
  String get kitchenThisAmountIsRight => 'Cette quantité est exacte';

  @override
  String get kitchenNutritionReference => 'Valeurs nutritives de référence';

  @override
  String kitchenPer100g(String source) {
    return 'par 100 g · $source';
  }

  @override
  String get kitchenActivity => 'Activité';

  @override
  String get kitchenNoActivity => 'Aucune activité pour l\'instant.';

  @override
  String get kitchenNewBarcode =>
      'Nouveau code-barres — dites-nous une fois ce que c\'est et nous nous en souviendrons.';

  @override
  String get kitchenChooseAnItem => 'Choisir un article';

  @override
  String get kitchenAddToKitchen => 'Ajouter à la cuisine';

  @override
  String get kitchenWhatAreYouAdding => 'Qu\'ajoutez-vous ?';

  @override
  String get kitchenChange => 'Changer';

  @override
  String get kitchenScanBarcode => 'Numériser le code-barres';

  @override
  String kitchenBarcodeValue(String code) {
    return 'Code-barres $code';
  }

  @override
  String kitchenWillAddNew(String name) {
    return 'Nous ajouterons « $name » comme nouvel article.';
  }

  @override
  String get kitchenHowMuch => 'Quelle quantité ?';

  @override
  String get kitchenWhereDoesItLive => 'Où le rangez-vous ?';

  @override
  String get kitchenDateOnThePackage => 'Date sur l\'emballage';

  @override
  String get kitchenAddDateOptional =>
      'Ajouter une date « meilleur avant » ou limite d\'utilisation (facultatif)';

  @override
  String get kitchenScanABarcode => 'Numériser un code-barres';

  @override
  String get kitchenPointAtBarcode => 'Visez le code-barres sur l\'emballage';

  @override
  String get kitchenCamera => 'Appareil photo';

  @override
  String get kitchenBarcodeCameraWhy =>
      'Chefii a besoin de l\'appareil photo pour lire les codes-barres. Vous pouvez quand même taper le nom de l\'article.';

  @override
  String get kitchenTypeItInstead => 'Le taper plutôt';

  @override
  String get kitchenAiFeatureShelfScan => 'la numérisation de vos tablettes';

  @override
  String kitchenEnterAmountFor(String name) {
    return 'Indiquez une quantité pour $name.';
  }

  @override
  String kitchenScanSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles ajoutés à partir d\'une photo',
      one: '1 article ajouté à partir d\'une photo',
    );
    return '$_temp0';
  }

  @override
  String get kitchenScanTitle => 'Numérisez vos tablettes';

  @override
  String get kitchenScanSubtitle =>
      'Nous vous suggérerons ce que nous voyons. Rien n\'est ajouté avant votre confirmation.';

  @override
  String get kitchenTakePhoto => 'Prendre une photo';

  @override
  String get kitchenSelectItemsToAdd => 'Choisir les articles';

  @override
  String kitchenAddCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ajouter $count articles',
      one: 'Ajouter 1 article',
    );
    return '$_temp0';
  }

  @override
  String get kitchenCameraDeniedWhy =>
      'Autorisez l\'accès à l\'appareil photo dans les Paramètres pour numériser, ou choisissez une photo dans votre galerie.';

  @override
  String get kitchenChooseFromLibrary => 'Choisir dans la galerie';

  @override
  String get kitchenOpenFridgeArt => 'Frigo ouvert';

  @override
  String get kitchenScanTips =>
      'Conseils : ouvrez la porte au complet, assurez-vous d\'avoir un bon éclairage et prenez une photo par tablette pour de meilleurs résultats.';

  @override
  String get kitchenScanDemo =>
      'Démo : suggestions d\'exemple — votre photo n\'a pas été analysée.';

  @override
  String get kitchenScanNothingTitle => 'Nous n\'avons rien repéré';

  @override
  String get kitchenScanNothingMessage =>
      'Essayez une photo plus éclairée et plus rapprochée d\'une seule tablette.';

  @override
  String kitchenPercentSure(int percent) {
    return 'Certitude : $percent %';
  }

  @override
  String get kitchenAmount => 'Quantité';

  @override
  String get kitchenEnterAmount => 'Entrer la quantité';

  @override
  String get kitchenTakeAnotherPhoto => 'Prendre une autre photo';

  @override
  String get kitchenFreshnessSubtitle =>
      'Des aliments à cuisiner, à congeler ou sur lesquels trancher.';

  @override
  String get kitchenFindRecipes => 'Trouver des recettes avec ces aliments';

  @override
  String get kitchenNothingNeedsAttentionTitle => 'Rien ne presse';

  @override
  String get kitchenNothingNeedsAttentionMessage =>
      'Nous vous préviendrons quand un aliment devrait être utilisé bientôt.';

  @override
  String kitchenDatePassed(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'date passée depuis $days jours',
      one: 'date passée depuis 1 jour',
    );
    return '$_temp0';
  }

  @override
  String get kitchenDateIsToday => 'la date est aujourd\'hui';

  @override
  String kitchenDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days jours restants',
      one: '1 jour restant',
    );
    return '$_temp0';
  }

  @override
  String kitchenWithEstimate(String text) {
    return '$text (estimation)';
  }

  @override
  String get kitchenCookWithThis => 'Cuisiner avec ceci';

  @override
  String get kitchenFreeze => 'Congeler';

  @override
  String get kitchenFoodSafety => 'Salubrité des aliments';

  @override
  String get kitchenFoodSafetyBody =>
      'Les dates de Chefii sont des estimations fondées sur des durées de conservation habituelles, et non des garanties de salubrité. Suivez les dates limites d\'utilisation et « meilleur avant » indiquées sur les emballages, gardez votre réfrigérateur à 4 °C (40 °F) ou moins et, en cas de doute, jetez l\'aliment. Pour des conseils, consultez les pages de Santé Canada sur la salubrité des aliments.';

  @override
  String get kitchenAllSquaredAway => 'Tout est en ordre';

  @override
  String get kitchenBackToKitchen => 'Retour à la cuisine';

  @override
  String kitchenItemsVerified(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles vérifiés',
      one: '1 article vérifié',
    );
    return '$_temp0';
  }

  @override
  String get kitchenEveryAmountRight =>
      'Toutes les quantités étaient déjà exactes.';

  @override
  String kitchenAmountsCorrected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count quantités ont été corrigées. Vous pouvez annuler depuis la cuisine.',
      one: '1 quantité a été corrigée. Vous pouvez annuler depuis la cuisine.',
    );
    return '$_temp0';
  }

  @override
  String get kitchenQuickCheck => 'Vérification rapide';

  @override
  String kitchenQuickCheckSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Corrigez ce qui ne va pas, puis confirmez. $count articles.',
      one: 'Corrigez ce qui ne va pas, puis confirmez. 1 article.',
    );
    return '$_temp0';
  }

  @override
  String get kitchenConfirmAll => 'Tout confirmer';

  @override
  String get kitchenEverythingAccurateTitle => 'Tout semble exact';

  @override
  String get kitchenEverythingAccurateMessage =>
      'Rien à vérifier pour le moment.';

  @override
  String kitchenWasAmount(String amount) {
    return 'avant : $amount';
  }

  @override
  String get kitchenAlreadyDone => 'Déjà fait — rien n\'a changé.';

  @override
  String kitchenRecorded(String amount) {
    return 'Inscrit : $amount';
  }

  @override
  String get kitchenModeUsed => 'Utilisé';

  @override
  String get kitchenModeAdded => 'Ajouté';

  @override
  String get kitchenModeTossed => 'Jeté';

  @override
  String get kitchenModeCount => 'Compter';

  @override
  String get kitchenAmountYouHaveNow => 'Quantité actuelle';

  @override
  String get kitchenCountingConfirms =>
      'Le compte confirme l\'exactitude de cet article.';

  @override
  String kitchenUseAmount(String amount) {
    return 'Utiliser $amount';
  }

  @override
  String kitchenAddAmount(String amount) {
    return 'Ajouter $amount';
  }

  @override
  String kitchenDiscardAmount(String amount) {
    return 'Jeter $amount';
  }

  @override
  String kitchenSetToAmount(String amount) {
    return 'Régler à $amount';
  }

  @override
  String get kitchenMarkFinished => 'Marquer comme terminé';

  @override
  String get kitchenCommandTryHint =>
      'Essayez « J\'ai utilisé deux œufs » ou « J\'ai acheté 1 kg de farine ».';

  @override
  String get kitchenVoiceUnavailable =>
      'La saisie vocale n\'est pas disponible. Vous pouvez taper à la place — ou utiliser la dictée de votre clavier.';

  @override
  String get kitchenCommandExamples =>
      '« J\'ai utilisé deux œufs » · « On n\'a plus de lait » · « J\'ai acheté 1 kg de farine »';

  @override
  String get kitchenCommandFieldHint => 'Que s\'est-il passé dans la cuisine ?';

  @override
  String get kitchenListening => 'Écoute en cours';

  @override
  String get kitchenSpeak => 'Parler';

  @override
  String kitchenCouldNotFind(String query) {
    return 'Nous n\'avons pas trouvé « $query »';
  }

  @override
  String get kitchenHereIsWhatWillHappen => 'Voici ce qui va se passer';

  @override
  String get kitchenTrySimplerName =>
      'Essayez un nom plus simple, ou ajoutez-le depuis l\'onglet Cuisine.';

  @override
  String get kitchenNoAmountSaid =>
      'Vous n\'avez pas précisé la quantité — vérifiez-la :';

  @override
  String kitchenQuoted(String text) {
    return '« $text »';
  }

  @override
  String kitchenCommandMarkEmpty(String what) {
    return 'Marquer $what comme épuisé';
  }

  @override
  String kitchenCommandSetCount(String what, String amount) {
    return 'Régler $what à $amount';
  }

  @override
  String kitchenCommandAction(String action, String amount, String what) {
    return '$action $amount $what';
  }

  @override
  String get kitchenConfirm => 'Confirmer';

  @override
  String get kitchenRenamePlace => 'Renommer l\'emplacement';

  @override
  String get kitchenPlacesTitle => 'Emplacements de votre cuisine';

  @override
  String get kitchenPlacesSubtitle =>
      'Ajoutez des endroits comme un congélateur au garage ou un cellier à vin.';

  @override
  String get kitchenBuiltIn => 'Par défaut';

  @override
  String kitchenKeptLike(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'fridge': 'Conservé comme au réfrigérateur',
      'freezer': 'Conservé comme au congélateur',
      'pantry': 'Conservé comme au garde-manger',
      'other': 'Autre type de rangement',
    });
    return '$_temp0';
  }

  @override
  String kitchenRenameTooltip(String place) {
    return 'Renommer $place';
  }

  @override
  String kitchenRemoveTooltip(String place) {
    return 'Retirer $place';
  }

  @override
  String kitchenRemovedPlace(String place) {
    return 'Emplacement retiré : $place.';
  }

  @override
  String kitchenAddedPlace(String place) {
    return 'Emplacement ajouté : $place.';
  }

  @override
  String get kitchenNewPlace => 'Nouvel emplacement';

  @override
  String get kitchenNewPlaceHint => 'p. ex. Congélateur du garage';

  @override
  String get kitchenKeptLikeHeader => 'Conservé comme…';

  @override
  String get kitchenAddPlace => 'Ajouter l\'emplacement';

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

  @override
  String get tag15Minute => '15 minutes';

  @override
  String get tagHighProtein => 'Riche en protéines';

  @override
  String get tagVegan => 'Végétalien';

  @override
  String get tagVegetarian => 'Végétarien';

  @override
  String get tagBatch => 'Cuisine en lot';

  @override
  String get tagComfort => 'Réconfortant';

  @override
  String get tagMakeAhead => 'À préparer d’avance';

  @override
  String get tagNoCook => 'Sans cuisson';

  @override
  String get availabilityAllOnHand => 'Tout est à portée de main';

  @override
  String availabilityToBuy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ingrédients à acheter',
      one: '1 ingrédient à acheter',
    );
    return '$_temp0';
  }

  @override
  String get morningStepWake => 'Se lever';

  @override
  String get morningStepGetReady => 'Se préparer';

  @override
  String morningStepMake(String recipe) {
    return 'Préparer $recipe';
  }

  @override
  String get morningStepEat => 'Déjeuner';

  @override
  String get morningStepTidy => 'Ranger';

  @override
  String get morningStepLeave => 'Partir';

  @override
  String get morningEyebrow => 'Matins';

  @override
  String get morningSetupTitle => 'Un matin plus calme';

  @override
  String get morningSetupSubtitle =>
      'Dites-nous quand vous vous levez et quand vous partez. Nous planifions le moment entre les deux.';

  @override
  String get morningOnTheseDays => 'Les jours suivants';

  @override
  String get morningWakeUp => 'Heure du lever';

  @override
  String get morningOutTheDoorBy => 'Départ au plus tard à';

  @override
  String morningBufferValue(int minutes) {
    return 'Marge avant de partir : $minutes min';
  }

  @override
  String get morningBuffer => 'Marge avant de partir';

  @override
  String morningMinutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String get morningInvalidTimes =>
      'Votre heure de départ doit être après votre heure de lever, plus la marge.';

  @override
  String morningTimeLeft(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other:
          'Il vous reste donc $minutes minutes pour vous préparer et déjeuner.',
      one: 'Il vous reste donc $minutes minute pour vous préparer et déjeuner.',
    );
    return '$_temp0';
  }

  @override
  String get morningBreakfastStyle => 'Style de déjeuner';

  @override
  String get morningStyleQuick => 'Rapide et simple';

  @override
  String get morningStyleCooked => 'Quelque chose de chaud';

  @override
  String get morningStyleNoCook => 'Sans cuisson';

  @override
  String get morningStyleGrabAndGo => 'Pour emporter';

  @override
  String get morningNotificationsOff =>
      'Les notifications sont désactivées pour Chefii. Activez-les dans les paramètres de votre appareil pour utiliser les alarmes.';

  @override
  String get morningAlarmNotificationBody => 'Votre plan du matin est prêt.';

  @override
  String get morningPreviewNotificationTitle => 'Le déjeuner de demain';

  @override
  String get morningPreviewNotificationBody =>
      'Jetez un coup d\'œil au plan de demain matin.';

  @override
  String morningAlarmAt(String time) {
    return 'Alarme à $time';
  }

  @override
  String morningPreviewAt(String time) {
    return 'Aperçu du soir à $time';
  }

  @override
  String get morningAlarmTitle => 'Alarme et rappels';

  @override
  String get morningSaveSchedule => 'Enregistrer l\'horaire';

  @override
  String get morningWakeWithChefii => 'Me réveiller avec Chefii';

  @override
  String morningWakeWithChefiiSubtitle(String time) {
    return 'Une alarme à $time qui ouvre votre plan du matin';
  }

  @override
  String get morningEveningPreview => 'Aperçu du soir';

  @override
  String morningEveningPreviewSubtitle(String time) {
    return 'Un petit mot à $time avec le déjeuner de demain';
  }

  @override
  String get morningPlatformNote =>
      'Sur Android, Chefii utilise une alarme du système. Sur iPhone, il utilise une notification urgente qui respecte vos réglages de concentration ; elle ne remplace pas l\'app Horloge, alors gardez une alarme de secours pour tout ce qui est essentiel.';

  @override
  String get morningAllOff =>
      'Toutes les notifications du matin sont désactivées.';

  @override
  String morningScheduled(String items) {
    return 'Programmé : $items';
  }

  @override
  String get morningSeeTomorrow => 'Voir le plan de demain';

  @override
  String get morningSetUpTitle => 'Configurez vos matins';

  @override
  String get morningSetUpMessage =>
      'Chefii peut planifier votre déjeuner selon vos heures de lever et de départ.';

  @override
  String get morningSetUp => 'Configurer';

  @override
  String get morningPlannedTitle => 'Votre matin, planifié';

  @override
  String get morningDayOffTitle => 'Demain, c\'est congé';

  @override
  String morningWindow(int minutes, String wake, String leave) {
    return '$minutes minutes de $wake à $leave';
  }

  @override
  String get morningEditRoutine => 'Modifier la routine';

  @override
  String get morningSoundsGood => 'Parfait';

  @override
  String get morningBreakfastSet => 'Le déjeuner de demain est prévu.';

  @override
  String get morningNoBreakfastFits => 'Aucun déjeuner ne convient';

  @override
  String get morningNoBreakfastFitsMessage =>
      'Essayez un matin plus long ou un autre style de déjeuner.';

  @override
  String morningMissing(String items) {
    return 'Manquant : $items';
  }

  @override
  String get morningTimeline => 'Déroulement';

  @override
  String get morningOrChoose => 'Ou choisissez';

  @override
  String morningItIs(String time) {
    return 'Il est $time';
  }

  @override
  String get morningImUp => 'Debout !';

  @override
  String get morningSnooze => 'Répéter dans 9 minutes';

  @override
  String get morningSnoozeTitle => 'C\'est l\'heure de se lever';

  @override
  String get morningSnoozeBody =>
      'Fin du rappel. Votre plan du matin vous attend.';

  @override
  String get morningThisMorning => 'Ce matin';

  @override
  String get morningTimeToGo => 'C\'est l\'heure de partir';

  @override
  String morningUntilYouLeave(int minutes) {
    return 'Départ dans $minutes min';
  }

  @override
  String get morningRunningBehind =>
      'En retard ? Voir des options plus rapides';

  @override
  String get morningRunningLate => 'Je suis en retard';

  @override
  String get morningNoStress => 'Pas de stress';

  @override
  String morningMinutesLeft(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes restantes',
      one: '$minutes minute restante',
    );
    return '$_temp0';
  }

  @override
  String get morningWhatStillWorks => 'Voici ce qui reste possible.';

  @override
  String get morningSkipBreakfast => 'Sauter le déjeuner';

  @override
  String get morningSkipped =>
      'C\'est noté. Rien n\'a été modifié dans votre cuisine.';

  @override
  String get morningNoCookNone =>
      'Aucune option sans cuisson ne convient à votre cuisine pour l\'instant.';

  @override
  String get morningTenMinutes => 'Dix minutes ou moins';

  @override
  String get morningNothingElse =>
      'Rien d\'autre ne se prépare en dix minutes.';

  @override
  String get onboardingSkipForNow => 'Passer pour l\'instant';

  @override
  String get onboardingSkip => 'Passer';

  @override
  String onboardingStepOf(int step, int total) {
    return 'Étape $step sur $total';
  }

  @override
  String get onboardingWelcomeArtLabel => 'Une table joliment dressée';

  @override
  String get onboardingWelcomeTitle => 'Votre cuisine,\nentre de bonnes mains.';

  @override
  String get onboardingWelcomeBody =>
      'Chefii sait ce qu\'il y a dans votre cuisine, vous suggère quoi préparer, vous guide pas à pas — et garde tout en ordre.';

  @override
  String get onboardingGetStarted => 'Commencer';

  @override
  String get onboardingHaveAccount => 'J\'ai déjà un compte';

  @override
  String get onboardingMeetTitle => 'Votre chef personnel';

  @override
  String get onboardingMeetSubtitle =>
      'Trois choses que Chefii fait pour vous, chaque jour.';

  @override
  String get onboardingBenefitKitchenTitle => 'Connaît votre cuisine';

  @override
  String get onboardingBenefitKitchenBody =>
      'Numérisez un reçu, et votre garde-manger, votre frigo et votre congélateur restent à jour — presque sans rien taper.';

  @override
  String get onboardingBenefitDecideTitle => 'Décide quoi préparer';

  @override
  String get onboardingBenefitDecideBody =>
      'Des recettes adaptées à ce que vous avez, au temps dont vous disposez et aux besoins alimentaires de chacun.';

  @override
  String get onboardingBenefitGuideTitle => 'Vous guide en douceur';

  @override
  String get onboardingBenefitGuideBody =>
      'Une cuisine pas à pas avec minuteries, puis un seul toucher pour mettre votre cuisine à jour.';

  @override
  String get onboardingTasteHeader => 'Un avant-goût';

  @override
  String get onboardingExample => 'Exemple';

  @override
  String get onboardingConsentRequired =>
      'Veuillez accepter les Conditions d\'utilisation et la Politique de confidentialité pour continuer.';

  @override
  String get onboardingDefaultName => 'Ami';

  @override
  String get onboardingWelcomeBack => 'Bon retour';

  @override
  String get onboardingSignInSubtitle => 'Connectez-vous à votre cuisine.';

  @override
  String get onboardingCreateTitle => 'Créez votre compte';

  @override
  String get onboardingCreateSubtitle =>
      'Votre cuisine reste privée, entre vous et les personnes que vous invitez.';

  @override
  String get onboardingSignIn => 'Se connecter';

  @override
  String get onboardingCreateAccount => 'Créer le compte';

  @override
  String get onboardingDemoBanner =>
      'Mode démo : votre compte et vos données restent uniquement sur cet appareil.';

  @override
  String get onboardingDemoAccount => 'Continuer avec un compte démo';

  @override
  String get onboardingContinueApple => 'Continuer avec Apple';

  @override
  String get onboardingContinueGoogle => 'Continuer avec Google';

  @override
  String get onboardingOrEmail => 'ou par courriel';

  @override
  String get onboardingFirstNameLabel => 'Votre prénom';

  @override
  String get onboardingFirstNameError => 'Dites-nous comment vous appeler';

  @override
  String get onboardingEmailLabel => 'Courriel';

  @override
  String get onboardingEmailError => 'Entrez un courriel valide';

  @override
  String get onboardingPasswordLabel => 'Mot de passe';

  @override
  String get onboardingPasswordError => 'Au moins 8 caractères';

  @override
  String get onboardingEnterEmailFirst => 'Entrez d\'abord votre courriel.';

  @override
  String get onboardingResetSent =>
      'Si un compte est associé à ce courriel, un lien de réinitialisation est en route.';

  @override
  String get onboardingForgotPassword => 'Mot de passe oublié ?';

  @override
  String get onboardingConsentLabel =>
      'J\'accepte les Conditions d\'utilisation et la Politique de confidentialité';

  @override
  String get onboardingReadThem => 'Les consulter';

  @override
  String get onboardingSwitchToCreate => 'Première visite ? Créez un compte';

  @override
  String get onboardingSwitchToSignIn =>
      'Vous avez déjà un compte ? Connectez-vous';

  @override
  String onboardingDefaultHouseholdName(String name) {
    return 'Cuisine de $name';
  }

  @override
  String get onboardingInviteCodeTitle => 'Code d\'invitation';

  @override
  String get onboardingInviteCodeHint => 'p. ex. 7KQ2M9XA';

  @override
  String get onboardingJoin => 'Rejoindre';

  @override
  String get onboardingJoinNeedsOnline =>
      'Pour rejoindre un autre foyer, il faut la version en ligne de Chefii.';

  @override
  String get onboardingJoinFailed => 'Ce code n\'a pas fonctionné.';

  @override
  String get onboardingHouseholdTitle => 'Votre foyer';

  @override
  String get onboardingHouseholdSubtitle =>
      'Pour que les portions et la planification suivent votre façon de vivre.';

  @override
  String onboardingOptionSelected(String option) {
    return '$option, sélectionné';
  }

  @override
  String get onboardingPortionsTitle => 'Portions habituelles par repas';

  @override
  String get onboardingFewerPortions => 'Moins de portions';

  @override
  String get onboardingMorePortions => 'Plus de portions';

  @override
  String get onboardingHouseholdNameLabel => 'Nom du foyer (facultatif)';

  @override
  String get onboardingHouseholdNameHint => 'p. ex. La cuisine Laurier';

  @override
  String get onboardingHouseholdPrivacy =>
      'Vous pourrez inviter d\'autres personnes à partager la cuisine plus tard. La santé et le journal de chaque personne restent privés.';

  @override
  String get onboardingJoinWithCode =>
      'Rejoindre un foyer avec un code d\'invitation';

  @override
  String get onboardingAllergyQuestion =>
      'Avez-vous des allergies alimentaires ?';

  @override
  String get onboardingAllergyNoneKnown => 'Aucune à ma connaissance';

  @override
  String get onboardingAllergyPreferNot => 'Je préfère ne pas répondre';

  @override
  String get onboardingCrossContactTitle =>
      'M\'avertir des risques de contact croisé';

  @override
  String get onboardingCrossContactSubtitle =>
      'Rappels sur les mentions « peut contenir » et l\'équipement partagé';

  @override
  String get onboardingNoAllergyAssumption =>
      'Nous ne supposerons pas que vous n\'avez aucune allergie — les recettes vous rappelleront de vérifier les ingrédients.';

  @override
  String get onboardingIntolerances => 'Intolérances';

  @override
  String get onboardingDietaryPattern => 'Régime alimentaire';

  @override
  String get onboardingDislikes => 'Aliments que vous préférez éviter';

  @override
  String get onboardingAddFoodLabel => 'Ajouter un aliment (p. ex. coriandre)';

  @override
  String get onboardingAdd => 'Ajouter';

  @override
  String get onboardingDietaryNotice =>
      'Chefii vérifie chaque recette en fonction de ces renseignements, mais ne peut pas voir le contenu des aliments emballés. Vérifiez toujours les étiquettes. Les allergies que vous indiquez sont partagées avec votre foyer uniquement pour assurer la sécurité des repas partagés.';

  @override
  String get onboardingDietaryTitle => 'Allergies et restrictions alimentaires';

  @override
  String get onboardingDietaryEditSubtitle =>
      'Allergies, intolérances et préférences.';

  @override
  String get onboardingDietarySubtitle =>
      'La question la plus importante que nous vous poserons. Vous pourrez la modifier en tout temps.';

  @override
  String get onboardingCuisineItalian => 'Italienne';

  @override
  String get onboardingCuisineFrench => 'Française';

  @override
  String get onboardingCuisineMediterranean => 'Méditerranéenne';

  @override
  String get onboardingCuisineMiddleEastern => 'Moyen-orientale';

  @override
  String get onboardingCuisineIndian => 'Indienne';

  @override
  String get onboardingCuisineJapanese => 'Japonaise';

  @override
  String get onboardingCuisineChinese => 'Chinoise';

  @override
  String get onboardingCuisineThai => 'Thaïlandaise';

  @override
  String get onboardingCuisineKorean => 'Coréenne';

  @override
  String get onboardingCuisineMexican => 'Mexicaine';

  @override
  String get onboardingCuisineGreek => 'Grecque';

  @override
  String get onboardingCuisineNordic => 'Nordique';

  @override
  String get onboardingCuisineCanadian => 'Canadienne';

  @override
  String get onboardingFoodSalmon => 'Saumon';

  @override
  String get onboardingFoodChicken => 'Poulet';

  @override
  String get onboardingFoodPasta => 'Pâtes';

  @override
  String get onboardingFoodEggs => 'Œufs';

  @override
  String get onboardingFoodTofu => 'Tofu';

  @override
  String get onboardingFoodLentils => 'Lentilles';

  @override
  String get onboardingFoodVegetables => 'Légumes';

  @override
  String get onboardingFoodSalads => 'Salades';

  @override
  String get onboardingFoodSoups => 'Soupes';

  @override
  String get onboardingFoodRiceBowls => 'Bols de riz';

  @override
  String get onboardingFoodBaking => 'Pâtisserie';

  @override
  String get onboardingEquipmentOven => 'Four';

  @override
  String get onboardingEquipmentStovetop => 'Cuisinière';

  @override
  String get onboardingEquipmentAirFryer => 'Friteuse à air';

  @override
  String get onboardingEquipmentSlowCooker => 'Mijoteuse';

  @override
  String get onboardingEquipmentInstantPot => 'Instant Pot';

  @override
  String get onboardingEquipmentBlender => 'Mélangeur';

  @override
  String get onboardingEquipmentMicrowave => 'Micro-ondes';

  @override
  String get onboardingEquipmentGrill => 'Barbecue';

  @override
  String get onboardingSpiceNone => 'Aucun';

  @override
  String get onboardingSpiceMild => 'Doux';

  @override
  String get onboardingSpiceMedium => 'Moyen';

  @override
  String get onboardingSpiceWarm => 'Relevé';

  @override
  String get onboardingSpiceHot => 'Très relevé';

  @override
  String get onboardingCuisinesTitle => 'Cuisines que vous aimez';

  @override
  String get onboardingFavouriteFoods => 'Aliments préférés';

  @override
  String get onboardingCookingConfidence => 'Aisance en cuisine';

  @override
  String get onboardingSpice => 'Piquant';

  @override
  String get onboardingSpiceLevel => 'Niveau de piquant';

  @override
  String onboardingSpiceValue(String level) {
    return 'Piquant : $level';
  }

  @override
  String get onboardingWeeknightTime => 'Temps en semaine';

  @override
  String get onboardingYourEquipment => 'Votre équipement';

  @override
  String get onboardingCulinaryEditTitle => 'Préférences culinaires';

  @override
  String get onboardingCulinaryTitle => 'Ce que vous aimez manger';

  @override
  String get onboardingCulinarySubtitle =>
      'Choisissez-en autant ou aussi peu que vous voulez.';

  @override
  String get onboardingInterestBalanced => 'Repas équilibrés';

  @override
  String get onboardingInterestProtein => 'Plus de protéines';

  @override
  String get onboardingInterestVariety => 'Plus de variété';

  @override
  String get onboardingInterestPlants => 'Plus de légumes et de végétaux';

  @override
  String get onboardingInterestEducation => 'En apprendre sur la nutrition';

  @override
  String get onboardingWellnessQuestion =>
      'Aimeriez-vous de l\'aide pour quelque chose ?';

  @override
  String get onboardingShowNutritionTitle =>
      'Afficher la nutrition dans les recettes';

  @override
  String get onboardingShowNutritionSubtitle =>
      'Protéines, fibres et plus, estimées';

  @override
  String get onboardingTrackCaloriesTitle => 'Suivre les calories';

  @override
  String get onboardingTrackCaloriesSubtitle =>
      'Désactivé par défaut. Chefii ne vous fixe jamais d\'objectifs.';

  @override
  String get onboardingSmileTitle => 'Sourire et alimentation';

  @override
  String get onboardingSmileSubtitle =>
      'De l\'information sur l\'exposition de vos dents au sucre et à l\'acidité';

  @override
  String get onboardingWellnessDisclaimer =>
      'Chefii offre de l\'information sur l\'alimentation et la nutrition. Il ne s\'agit pas d\'un avis médical, et Chefii ne diagnostique ni ne traite aucun problème de santé.';

  @override
  String get onboardingWellnessEditTitle => 'Préférences mieux-être';

  @override
  String get onboardingWellnessTitle => 'Le mieux-être, à votre façon';

  @override
  String get onboardingWellnessSubtitle =>
      'Entièrement facultatif — et jamais culpabilisant.';

  @override
  String get onboardingKitchenTitle => 'Créez votre cuisine';

  @override
  String get onboardingKitchenSubtitle =>
      'Le plus rapide, c\'est votre dernier reçu d\'épicerie.';

  @override
  String get onboardingKitchenLater => 'Je le ferai plus tard';

  @override
  String onboardingOptionSemantics(String title, String body) {
    return '$title. $body';
  }

  @override
  String get onboardingScanReceiptTitle => 'Numériser un reçu';

  @override
  String get onboardingScanReceiptBody =>
      'Tout ce que vous avez acheté, en une minute environ';

  @override
  String get onboardingScanFridgeTitle => 'Numériser frigo ou garde-manger';

  @override
  String get onboardingScanFridgeBody => 'Confirmez ce que nous repérons';

  @override
  String get onboardingAddManualTitle => 'Ajouter des articles à la main';

  @override
  String get onboardingAddManualBody =>
      'Cherchez, numérisez un code-barres ou parlez';

  @override
  String get onboardingExampleKitchenTitle => 'Commencer avec des exemples';

  @override
  String get onboardingExampleKitchenBody =>
      'Explorez Chefii avec une cuisine d\'exemple';

  @override
  String get planningEyebrow => 'Planification';

  @override
  String get planningWeekTitle => 'Votre semaine';

  @override
  String get planningPreviousWeek => 'Semaine précédente';

  @override
  String get planningNextWeek => 'Semaine suivante';

  @override
  String get planningLeftoversBatch => 'Restes et cuisine en lot';

  @override
  String get planningBuildShoppingList => 'Créer la liste d\'épicerie';

  @override
  String get planningHaveEverything =>
      'Vous avez tout ce qu\'il faut pour cette semaine.';

  @override
  String planningItemsAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles ajoutés à votre liste',
      one: '1 article ajouté à votre liste',
    );
    return '$_temp0';
  }

  @override
  String planningDayToday(String day) {
    return '$day · aujourd\'hui';
  }

  @override
  String get planningAdd => 'Ajouter';

  @override
  String get planningOptions => 'Options';

  @override
  String get planningOpenRecipe => 'Ouvrir la recette';

  @override
  String get planningAddToPlanTitle => 'Ajouter au menu';

  @override
  String get planningChooseRecipe => 'Choisir une recette';

  @override
  String planningPlanMeal(String day, String meal) {
    return 'Planifier $day : $meal';
  }

  @override
  String planningPlanned(String title) {
    return '$title : ajouté au menu';
  }

  @override
  String get planningChangeRecipe => 'Changer de recette';

  @override
  String planningToBuy(String items) {
    return 'À acheter : $items';
  }

  @override
  String get planningSearchRecipes => 'Rechercher des recettes';

  @override
  String get planningLeftoversSubtitle =>
      'Cuisinez une fois, mangez bien toute la semaine.';

  @override
  String get planningInYourFridge => 'Dans votre frigo';

  @override
  String get planningNoLeftovers =>
      'Aucun reste enregistré. Quand vous finissez de cuisiner, Chefii peut garder ici les portions en trop.';

  @override
  String planningLeftoverPortions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count portions',
      one: '$count portion',
    );
    return '$_temp0';
  }

  @override
  String planningMadeOn(String day) {
    return 'préparation : $day';
  }

  @override
  String planningEatWithin(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'à consommer d\'ici ~$count jours',
      one: 'à consommer d\'ici ~$count jour',
    );
    return '$_temp0';
  }

  @override
  String get planningEatPortion => 'Manger une portion';

  @override
  String get planningFreeze => 'Congeler';

  @override
  String get planningItemDetails => 'Détails de l\'article';

  @override
  String get planningGoodForBatch => 'Idéal pour cuisiner en lot';

  @override
  String planningLeftoversEntryTitle(String name) {
    return '$name (restes)';
  }

  @override
  String get planningKitchenEyebrow => 'Cuisine';

  @override
  String get planningShoppingTitle => 'Liste d\'épicerie';

  @override
  String planningToBuyCount(int count) {
    return '$count à acheter';
  }

  @override
  String planningPutAway(int count) {
    return 'Ranger $count dans la cuisine';
  }

  @override
  String get planningAddAmountsFirst =>
      'Ajoutez d\'abord les quantités aux articles cochés, ou numérisez plutôt votre reçu.';

  @override
  String get planningAddItemHint => 'Ajouter un article';

  @override
  String get planningFromMealPlan => 'Du menu planifié';

  @override
  String get planningClearChecked => 'Retirer les cochés';

  @override
  String get planningListEmptyTitle => 'Votre liste est vide';

  @override
  String get planningListEmptyMessage =>
      'Planifiez quelques repas et Chefii ajoutera exactement ce qui manque.';

  @override
  String get planningInBasket => 'Dans le panier';

  @override
  String get planningAfterShopping =>
      'Après l\'épicerie, numérisez votre reçu pour obtenir les quantités et les prix exacts — ou rangez dès maintenant les articles cochés.';

  @override
  String planningForRecipes(String titles) {
    return 'pour $titles';
  }

  @override
  String get planningRunningLow => 'bientôt épuisé';

  @override
  String get planningDetails => 'Détails';

  @override
  String get planningItemRemovedTitle => 'Article retiré';

  @override
  String get planningItemRemovedMessage =>
      'Il a peut-être été acheté ou retiré.';

  @override
  String get planningPortions => 'Portions';

  @override
  String get planningQuantity => 'Quantité';

  @override
  String get planningPreferredProduct => 'Marque ou produit préféré';

  @override
  String get planningExpectedPrice => 'Prix prévu (\$)';

  @override
  String planningLastPaid(String price) {
    return 'Dernier prix payé : $price (reçu numérisé)';
  }

  @override
  String get planningNote => 'Note';

  @override
  String get planningAlternatives => 'Autres options';

  @override
  String get planningNeededFor => 'Requis pour';

  @override
  String get planningSpendingTitle => 'Dépenses et gaspillage';

  @override
  String get planningGroceriesThisMonth => 'd\'épicerie ce mois-ci';

  @override
  String get planningItemsDiscarded => 'articles jetés récemment';

  @override
  String get planningLastSixWeeks => 'Six dernières semaines';

  @override
  String get planningScanReceiptsEmpty =>
      'Numérisez vos reçus pour voir l\'évolution de vos dépenses.';

  @override
  String get planningThisWeek => 'Cette semaine';

  @override
  String planningWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count semaines',
      one: 'il y a $count semaine',
    );
    return '$_temp0';
  }

  @override
  String planningWeeksAgoShort(int count) {
    return 'il y a $count sem.';
  }

  @override
  String planningWeekAmount(String week, String amount) {
    return '$week : $amount';
  }

  @override
  String get planningRecentlyDiscarded => 'Jetés récemment';

  @override
  String get planningNothingDiscarded => 'Rien de jeté récemment. Bravo !';

  @override
  String get planningSpendingFootnote =>
      'Les dépenses proviennent uniquement des reçus numérisés. Le gaspillage compte les articles que vous avez marqués comme jetés.';

  @override
  String get prosEyebrow => 'Professionnels';

  @override
  String get prosCircleTitle => 'Mon cercle nutrition';

  @override
  String get prosCircleSubtitle =>
      'Partagez exactement ce que vous choisissez, aussi longtemps que vous le choisissez, avec des diététistes-nutritionnistes et des professionnels dentaires vérifiés.';

  @override
  String get prosInvite => 'Inviter un professionnel';

  @override
  String get prosCodeHint => 'Son code Chefii';

  @override
  String get prosFind => 'Trouver';

  @override
  String get prosNoMatch =>
      'Aucun professionnel vérifié n\'a ce code. Vérifiez-le auprès de cette personne.';

  @override
  String get prosDemoSample => 'Démo : utiliser un profil de diététiste fictif';

  @override
  String get prosWhoCanSee => 'Qui voit quoi';

  @override
  String get prosNothingShared =>
      'Vous n\'avez rien partagé. Rien n\'est visible pour qui que ce soit.';

  @override
  String prosGrantUntil(String categories, String date) {
    return '$categories\nFin de l\'accès : $date';
  }

  @override
  String prosRevokedOn(String date) {
    return 'Accès révoqué : $date';
  }

  @override
  String get prosRevoked => 'Accès révoqué';

  @override
  String get prosExpired => 'Accès expiré';

  @override
  String get prosActive => 'Actif';

  @override
  String get prosEnded => 'Terminé';

  @override
  String get prosReviews => 'Évaluations';

  @override
  String get prosReadOnlyNote =>
      'Les professionnels voient une copie en lecture seule de ce que vous partagez. Ils ne peuvent pas modifier vos repas, votre cuisine ni vos plans.';

  @override
  String prosCredentialsVerified(String body, String number) {
    return '$body · no $number · inscription vérifiée';
  }

  @override
  String prosCredentialsNotVerified(String body, String number) {
    return '$body · no $number · inscription non vérifiée';
  }

  @override
  String get prosUpdateSharing => 'Mettre à jour le partage';

  @override
  String prosShareWith(String name) {
    return 'Partager avec $name';
  }

  @override
  String prosShareWithQuestion(String name) {
    return 'Partager avec $name ?';
  }

  @override
  String prosShareConfirm(String categories, int days, String date) {
    return '$categories des $days derniers jours, jusqu\'au $date. Vous pouvez révoquer l\'accès en tout temps.';
  }

  @override
  String get prosShare => 'Partager';

  @override
  String prosSharedWith(String name) {
    return 'Partagé avec $name';
  }

  @override
  String get prosWhatToShare => 'Ce que vous partagez';

  @override
  String get prosHowFarBack => 'Période à partager';

  @override
  String get prosOneYear => '1 an';

  @override
  String prosDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours',
      one: '1 jour',
    );
    return '$_temp0';
  }

  @override
  String get prosAccessEndsAfter => 'L\'accès prend fin après';

  @override
  String get prosRevokeNow => 'Révoquer l\'accès maintenant';

  @override
  String get prosRevokeQuestion => 'Révoquer l\'accès ?';

  @override
  String prosRevokeMessage(String name) {
    return '$name perdra immédiatement l\'accès à tout ce que vous avez partagé.';
  }

  @override
  String get prosRevoke => 'Révoquer';

  @override
  String get prosAccessHistory => 'Historique des consultations';

  @override
  String prosNotViewedYet(String name) {
    return '$name n\'a encore rien consulté.';
  }

  @override
  String prosViewed(String what) {
    return 'A consulté : $what';
  }

  @override
  String get prosProfessionalReview => 'Évaluation professionnelle';

  @override
  String get prosAcceptRecommendations => 'Accepter les recommandations';

  @override
  String get prosRecommendations => 'Recommandations';

  @override
  String get prosAcceptNote =>
      'Si vous acceptez, ces recommandations restent dans votre profil. Rien ne change dans votre plan ou votre cuisine, à moins que vous ne le modifiiez vous-même.';

  @override
  String get prosDecline => 'Refuser';

  @override
  String get prosOpenPlanner => 'Ouvrir le planificateur de repas';

  @override
  String get prosPortal => 'Portail professionnel';

  @override
  String get prosVerificationPending => 'Vérification en cours';

  @override
  String prosVerificationPendingBody(String body) {
    return 'Nous confirmons votre inscription auprès de $body. Vous pourrez consulter les dossiers que vos clients partagent une fois la vérification terminée.';
  }

  @override
  String get prosDemoVerify => 'Démo : simuler la vérification';

  @override
  String get prosClients => 'Clients';

  @override
  String prosClientCode(String code) {
    return 'Votre code client : $code';
  }

  @override
  String get prosNoClients => 'Aucun client actif';

  @override
  String get prosNoClientsMessage =>
      'Les personnes qui partagent leurs données avec vous s\'affichent ici tant que leur accès est actif.';

  @override
  String prosClientAccessUntil(String categories, String date) {
    return '$categories\nFin de l\'accès : $date';
  }

  @override
  String get prosRecordsNote =>
      'Les dossiers sont en lecture seule, et chaque consultation est consignée et visible par votre client.';

  @override
  String get prosJoinTitle => 'S\'inscrire comme professionnel';

  @override
  String get prosJoinSubtitle =>
      'Pour les professionnels de la santé membres d\'un ordre professionnel. Nous vérifions chaque inscription.';

  @override
  String get prosSubmit => 'Soumettre pour vérification';

  @override
  String get prosProfession => 'Profession';

  @override
  String get prosRegulatoryCollege => 'Ordre professionnel';

  @override
  String get prosRegulatoryCollegeHint =>
      'p. ex. Ordre des diététistes-nutritionnistes du Québec';

  @override
  String get prosRegistrationNumber => 'Numéro d\'inscription';

  @override
  String get prosProvince => 'Province';

  @override
  String get prosAccessEnded => 'L\'accès a pris fin';

  @override
  String get prosAccessEndedMessage =>
      'Le partage de ce client a expiré ou a été révoqué.';

  @override
  String get prosClient => 'Client';

  @override
  String prosSharedSince(String date) {
    return 'Partagé depuis $date · lecture seule';
  }

  @override
  String get prosWriteAssessment => 'Rédiger une évaluation';

  @override
  String get prosChooseCategory => 'Choisissez une catégorie à consulter.';

  @override
  String get prosNoRecords => 'Aucune donnée dans la période partagée.';

  @override
  String prosRecordMeal(String title, String meal, String portions) {
    return '$title · $meal · $portions portion(s)';
  }

  @override
  String prosRecordMealKcal(
    String title,
    String meal,
    String portions,
    String kcal,
  ) {
    return '$title · $meal · $portions portion(s) · ≈ $kcal kcal';
  }

  @override
  String prosRecordGlucose(String value, String context) {
    return '$value mmol/L · $context';
  }

  @override
  String prosGlucoseContext(String context) {
    String _temp0 = intl.Intl.selectLogic(context, {
      'fasting': 'à jeun',
      'beforeMeal': 'avant un repas',
      'afterMeal': 'après un repas',
      'bedtime': 'au coucher',
      'other': 'autre',
    });
    return '$_temp0';
  }

  @override
  String prosRecordConcern(String area, String description, String severity) {
    return '$area : $description ($severity/5)';
  }

  @override
  String prosConcernArea(String area) {
    String _temp0 = intl.Intl.selectLogic(area, {
      'hair': 'Cheveux',
      'skin': 'Peau',
      'nails': 'Ongles',
      'energy': 'Énergie',
      'digestion': 'Digestion',
      'other': 'Autre',
    });
    return '$_temp0';
  }

  @override
  String prosRecordDietary(String allergies, String restrictions) {
    return 'Allergies : $allergies · Restrictions : $restrictions';
  }

  @override
  String get prosAssessment => 'Évaluation';

  @override
  String prosReviewing(String date) {
    return 'Période examinée : $date – aujourd\'hui';
  }

  @override
  String get prosShareWithClient => 'Partager avec le client';

  @override
  String get prosSummary => 'Résumé';

  @override
  String get prosAddRecommendation => 'Ajouter une recommandation';

  @override
  String get prosAdd => 'Ajouter';

  @override
  String prosSignedNote(String name, String kind) {
    return 'Votre client doit accepter avant que quoi que ce soit change. Signé : $name, $kind.';
  }

  @override
  String get prosSaveDraft => 'Enregistrer comme brouillon';

  @override
  String get prosDraftSaved => 'Brouillon enregistré';

  @override
  String get receiptsEyebrow => 'Reçu';

  @override
  String get receiptsCaptureTitle => 'Numériser un reçu';

  @override
  String get receiptsCaptureSubtitle =>
      'Posez-le à plat, sous un bon éclairage. Un long reçu peut être pris en quelques pages.';

  @override
  String get receiptsScanReceipt => 'Numériser le reçu';

  @override
  String get receiptsTakePhoto => 'Prendre une photo';

  @override
  String get receiptsDemoCapture =>
      'Mode démo : n\'importe quelle photo fait l\'affaire — nous afficherons un reçu d\'exemple identifié comme tel au lieu de la lire.';

  @override
  String get receiptsCameraPermission => 'Appareil photo';

  @override
  String get receiptsCameraWhy =>
      'Autorisez l\'accès à l\'appareil photo dans les paramètres pour numériser vos reçus, ou importez une photo déjà prise.';

  @override
  String get receiptsImportPhoto => 'Importer une photo';

  @override
  String get receiptsArtworkLabel => 'Reçu sur un comptoir de cuisine';

  @override
  String get receiptsTipLight =>
      'Lumière vive et uniforme — évitez les ombres sur le papier';

  @override
  String get receiptsTipFrame =>
      'Incluez le nom du magasin en haut et le total en bas';

  @override
  String get receiptsTipPages =>
      'Pour un long reçu, photographiez chaque section comme une page distincte';

  @override
  String get receiptsTipPrivacy =>
      'Les photos sont conservées en privé pour votre foyer et servent uniquement à lire vos achats';

  @override
  String get receiptsRegularCamera => 'Utiliser l\'appareil photo standard';

  @override
  String get receiptsImportFromPhotos => 'Importer depuis les photos';

  @override
  String get receiptsAiFeature => 'la lecture des reçus';

  @override
  String get receiptsPreviewTitle => 'Vérifiez votre photo';

  @override
  String receiptsPreviewSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0. Assurez-vous que le texte est net.';
  }

  @override
  String get receiptsAnalyze => 'Analyser le reçu';

  @override
  String get receiptsNoPagesTitle => 'Aucune page pour l\'instant';

  @override
  String get receiptsNoPagesMessage =>
      'Photographiez votre reçu pour continuer.';

  @override
  String get receiptsCapture => 'Photographier';

  @override
  String receiptsPageSemantics(int number) {
    return 'Page $number du reçu';
  }

  @override
  String receiptsPageLabel(int number) {
    return 'Page $number';
  }

  @override
  String get receiptsRotate => 'Pivoter';

  @override
  String get receiptsRetake => 'Reprendre';

  @override
  String get receiptsRemovePage => 'Retirer la page';

  @override
  String get receiptsAddPage => 'Ajouter une page';

  @override
  String get receiptsStepUploading => 'Envoi sécurisé';

  @override
  String get receiptsStepReading => 'Lecture de chaque ligne';

  @override
  String get receiptsStepChecking => 'Vérification des totaux et des doublons';

  @override
  String get receiptsStepMatching => 'Association à votre cuisine';

  @override
  String get receiptsProcessingTitle => 'Lecture de votre reçu';

  @override
  String get receiptsProcessingSubtitle =>
      'Cela prend généralement moins d\'une minute. Vous pouvez quitter — nous poursuivons.';

  @override
  String receiptsProgressSemantics(int percent) {
    return 'Progression : $percent %';
  }

  @override
  String get receiptsContinueBackground => 'Continuer en arrière-plan';

  @override
  String get receiptsNotFound => 'Reçu introuvable.';

  @override
  String get receiptsAlreadyInKitchenTitle => 'Déjà dans votre cuisine';

  @override
  String get receiptsAlreadyImportedMessage => 'Ce reçu a été importé.';

  @override
  String get receiptsSeeSummary => 'Voir le résumé';

  @override
  String get receiptsReviewTitle => 'Vérifier les achats';

  @override
  String receiptsReviewSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles',
      one: '1 article',
    );
    return '$_temp0';
  }

  @override
  String receiptsReviewSubtitleToCheck(int count, int review) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count articles',
      one: '1 article',
    );
    return '$_temp0 · $review à vérifier';
  }

  @override
  String receiptsResolveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Régler $count articles',
      one: 'Régler 1 article',
    );
    return '$_temp0';
  }

  @override
  String get receiptsDemoReview =>
      'Démo : ceci est un reçu d\'exemple intégré, pas votre photo.';

  @override
  String get receiptsTotalsMatch =>
      'Les articles correspondent au sous-total du reçu.';

  @override
  String receiptsTotalsMatchWithTotal(String total) {
    return 'Les articles correspondent au sous-total du reçu · total : $total.';
  }

  @override
  String receiptsTotalsMismatch(String linesTotal, String subtotal) {
    return 'Les articles totalisent $linesTotal, mais le sous-total indique $subtotal. Il manque peut-être une ligne — vous pouvez l\'ajouter.';
  }

  @override
  String get receiptsAddMissingItem => 'Ajouter un article manquant';

  @override
  String get receiptsUnknownItem => 'Article inconnu';

  @override
  String get receiptsAmountNeeded => 'Quantité requise';

  @override
  String get receiptsNotFood => 'Non alimentaire';

  @override
  String get receiptsChecked => 'Vérifié';

  @override
  String get receiptsPleaseCheck => 'À vérifier';

  @override
  String get receiptsExcludedSemantics => 'Exclu. Touchez pour inclure';

  @override
  String get receiptsIncludedSemantics => 'Inclus. Touchez pour exclure';

  @override
  String get receiptsAddedByYou => '(ajouté par vous)';

  @override
  String get receiptsAddItemTitle => 'Ajouter un article';

  @override
  String get receiptsCorrectItemTitle => 'Corriger l\'article';

  @override
  String receiptsReceiptSays(String text) {
    return 'Sur le reçu : $text';
  }

  @override
  String get receiptsIsFood => 'C\'est un aliment';

  @override
  String get receiptsIsFoodSubtitle =>
      'Les achats non alimentaires ne sont pas ajoutés à votre cuisine';

  @override
  String get receiptsProductName => 'Nom du produit';

  @override
  String get receiptsBrandOptional => 'Marque (facultatif)';

  @override
  String get receiptsPackageOptional => 'Format (facultatif)';

  @override
  String get receiptsPackageHint => 'p. ex. pot de 750 g';

  @override
  String get receiptsQuantity => 'Quantité';

  @override
  String get receiptsCategory => 'Catégorie';

  @override
  String get receiptsStoreIn => 'Ranger dans';

  @override
  String get receiptsUnknownTitle => 'Quelques articles à vérifier';

  @override
  String get receiptsAllResolved => 'Tout est réglé.';

  @override
  String get receiptsUnknownSubtitle =>
      'Dites-nous ce que c\'est, ou laissez-les de côté.';

  @override
  String receiptsStillNeedNameAmount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Encore $count articles à compléter',
      one: 'Encore 1 article à compléter',
    );
    return '$_temp0';
  }

  @override
  String get receiptsNothingLeftTitle => 'Plus rien à vérifier';

  @override
  String get receiptsNothingLeftMessage =>
      'Chaque article a un nom et une quantité.';

  @override
  String get receiptsCouldntTell =>
      'Nous n\'avons pas pu identifier cet article';

  @override
  String receiptsLooksLikeUnknownAmount(String name) {
    return 'Semble être : $name (quantité inconnue)';
  }

  @override
  String receiptsLooksLikeWithAmount(String name, String quantity) {
    return 'Semble être : $name · $quantity';
  }

  @override
  String get receiptsFix => 'Corriger';

  @override
  String get receiptsLooksRight => 'C\'est exact';

  @override
  String get receiptsLeaveOut => 'Exclure';

  @override
  String get receiptsStorageTitle => 'Où ranger tout ça ?';

  @override
  String get receiptsStorageSubtitle =>
      'Nous suggérons un endroit pour chaque article. Touchez pour modifier.';

  @override
  String receiptsAddToKitchen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ajouter $count articles à la cuisine',
      one: 'Ajouter 1 article à la cuisine',
    );
    return '$_temp0';
  }

  @override
  String get receiptsChangeStorage => 'Changer le rangement';

  @override
  String get receiptsDuplicateTitle => 'Déjà numérisé ?';

  @override
  String get receiptsViewEarlier => 'Voir le reçu précédent';

  @override
  String get receiptsDuplicateHeadline =>
      'Ce reçu semble déjà avoir été ajouté';

  @override
  String get receiptsDuplicateMessage =>
      'Pour éviter de compter votre épicerie en double, nous nous sommes arrêtés ici.';

  @override
  String receiptsDuplicateMessageWithDate(String date) {
    return 'Pour éviter de compter votre épicerie en double, nous nous sommes arrêtés ici. Numérisation précédente : $date.';
  }

  @override
  String get receiptsDifferentReceipt => 'C\'est un autre reçu — continuer';

  @override
  String get receiptsErrorTitle => 'Nous n\'avons pas pu lire ce reçu';

  @override
  String get receiptsRetakePhoto => 'Reprendre la photo';

  @override
  String get receiptsSomethingWrong => 'Un problème est survenu';

  @override
  String get receiptsQualityMessage =>
      'La photo est peut-être floue, trop sombre ou coupée. Posez le reçu à plat sous une lumière vive et cadrez-le en entier.';

  @override
  String get receiptsSafeRetry =>
      'Rien n\'a été ajouté à votre cuisine, vous pouvez donc réessayer sans risque.';

  @override
  String get receiptsAddByHand => 'Ajouter les articles à la main';

  @override
  String get receiptsDoneTitle => 'Votre cuisine est à jour';

  @override
  String get receiptsViewKitchen => 'Voir la cuisine';

  @override
  String receiptsMetricAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'articles ajoutés',
      one: 'article ajouté',
      zero: 'article ajouté',
    );
    return '$_temp0';
  }

  @override
  String receiptsMetricLeftOut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'exclus',
      one: 'exclu',
      zero: 'exclu',
    );
    return '$_temp0';
  }

  @override
  String get receiptsMetricTotal => 'total';

  @override
  String receiptsEstimatedNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count articles sont marqués comme estimés. Chefii vous demandera de les confirmer la prochaine fois que vous serez dans la cuisine.',
      one: '1 article est marqué comme estimé. Chefii vous demandera de le confirmer la prochaine fois que vous serez dans la cuisine.',
    );
    return '$_temp0';
  }

  @override
  String get receiptsUndoImportButton => 'Annuler cette importation';

  @override
  String get receiptsUndoImportTitle => 'Annuler l\'importation ?';

  @override
  String get receiptsUndoImportMessage =>
      'Retire ces articles de votre cuisine. Ce qui a déjà été utilisé reste enregistré.';

  @override
  String get receiptsUndoImportConfirm => 'Annuler l\'importation';

  @override
  String get receiptsScanAnother => 'Numériser un autre reçu';

  @override
  String get receiptsListEyebrow => 'Cuisine';

  @override
  String get receiptsListTitle => 'Reçus';

  @override
  String get receiptsListEmptyTitle => 'Aucun reçu pour l\'instant';

  @override
  String get receiptsListEmptyMessage =>
      'Vos reçus numérisés s\'afficheront ici.';

  @override
  String sharedAiConsentTitle(String feature) {
    return 'Utiliser l\'IA pour $feature ?';
  }

  @override
  String get sharedAiConsentMessage =>
      'Pour ce faire, Chefii envoie la photo ou le texte à son fournisseur d\'IA (Google Gemini) par l\'intermédiaire de nos serveurs sécurisés au Canada. Selon nos ententes, ces données ne servent pas à entraîner ses modèles, et vous pouvez désactiver cette option en tout temps dans Confidentialité et données.';

  @override
  String get sharedAiConsentAllow => 'Autoriser';

  @override
  String get sharedAiConsentNotNow => 'Pas maintenant';

  @override
  String get sharedTakePhoto => 'Prendre une photo';

  @override
  String get sharedChooseFromLibrary => 'Choisir dans la photothèque';

  @override
  String get todayNotifications => 'Notifications';

  @override
  String todayUnreadNotifications(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notifications non lues',
      one: '1 notification non lue',
    );
    return '$_temp0';
  }

  @override
  String todayGreeting(String greeting) {
    return '$greeting.';
  }

  @override
  String todayGreetingName(String greeting, String name) {
    return '$greeting,\n$name.';
  }

  @override
  String get todayScanReceipt => 'Numériser un reçu';

  @override
  String get todayStartCooking => 'Commencer à cuisiner';

  @override
  String get todayReceiptReady => 'Votre reçu est prêt à vérifier';

  @override
  String get todayReceiptReading => 'Lecture de votre reçu…';

  @override
  String todayPlannedFor(String mealType, String meal) {
    String _temp0 = intl.Intl.selectLogic(mealType, {
      'snack': 'Prévu pour la $meal',
      'other': 'Prévu pour le $meal',
    });
    return '$_temp0';
  }

  @override
  String todayFor(String mealType, String meal) {
    String _temp0 = intl.Intl.selectLogic(mealType, {
      'snack': 'Pour la $meal',
      'other': 'Pour le $meal',
    });
    return '$_temp0';
  }

  @override
  String todayMinutesChip(int minutes) {
    return '$minutes min';
  }

  @override
  String get todayUsesExpiring =>
      'Utilise des ingrédients à consommer bientôt.';

  @override
  String todayNothingFits(int minutes) {
    return 'Aucune recette en $minutes minutes';
  }

  @override
  String get todayNothingFitsMessage =>
      'Prévoyez plus de temps ou demandez une idée à votre chef.';

  @override
  String get todayAskChef => 'Demander au chef';

  @override
  String get todayDailyBriefing => 'Résumé du jour';

  @override
  String get todayYourKitchen => 'Votre cuisine';

  @override
  String get todayTileItems => 'articles';

  @override
  String get todayTileUseSoon => 'à consommer';

  @override
  String get todayTileToVerify => 'à vérifier';

  @override
  String get todayScan => 'Numériser';

  @override
  String get todayIUsed => 'J\'ai utilisé…';

  @override
  String get todayReminders => 'Rappels';

  @override
  String todayUseSoon(String name) {
    return 'Utilisez bientôt : $name';
  }

  @override
  String get todayEstimatedFromPurchase => 'Estimée selon la date d\'achat';

  @override
  String todayRecordedDate(String date) {
    return 'Date inscrite : $date';
  }

  @override
  String todayRunningLow(String name) {
    return 'Bientôt épuisé : $name';
  }

  @override
  String todayAddedToShopping(String name) {
    return 'Ajouté à votre liste d\'épicerie : $name';
  }

  @override
  String get todayAddToList => 'Ajouter à la liste';

  @override
  String todayAvailability(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ingrédients à acheter',
      one: '1 ingrédient à acheter',
      zero: 'Tout est sous la main',
    );
    return '$_temp0';
  }

  @override
  String todayPrepStart(String recipe, String duration) {
    return 'Commencer $recipe ($duration)';
  }

  @override
  String get todayYourDayInFood => 'Votre journée à table';

  @override
  String get todayPlanMeals => 'Planifier les repas du jour';

  @override
  String get todayMeals => 'Repas';

  @override
  String get todayNothingPlanned =>
      'Rien de prévu pour l\'instant — l\'onglet Aujourd\'hui vous proposera une idée à chaque repas.';

  @override
  String todayPortions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count portions',
      one: '1 portion',
    );
    return '$_temp0';
  }

  @override
  String get todayPreparation => 'Préparation';

  @override
  String todayAround(String time) {
    return 'vers $time';
  }

  @override
  String get todayKitchenAlerts => 'Alertes cuisine';

  @override
  String get todayNothingUrgent => 'Rien d\'urgent.';

  @override
  String todayUseTodayIfYouCan(String quantity) {
    return '$quantity · à utiliser aujourd\'hui si possible';
  }

  @override
  String get todayTomorrowMorning => 'Demain matin';

  @override
  String get todayMarkAllRead => 'Tout marquer comme lu';

  @override
  String get todayAllCaughtUp => 'Vous êtes à jour';

  @override
  String get todayAllCaughtUpMessage =>
      'Les résultats de vos reçus, les invitations de partage et les évaluations s\'afficheront ici.';
}
