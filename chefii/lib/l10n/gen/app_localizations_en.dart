// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get accountEyebrow => 'You';

  @override
  String get accountTitleFallback => 'Your account';

  @override
  String get accountEditName => 'Edit name';

  @override
  String get accountYourName => 'Your name';

  @override
  String get accountSectionPreferences => 'Preferences';

  @override
  String get accountDietarySafety => 'Dietary safety';

  @override
  String get accountNoAllergies => 'No allergies recorded';

  @override
  String get accountNotProvidedYet => 'Not provided yet';

  @override
  String get accountCulinaryPreferences => 'Culinary preferences';

  @override
  String get accountWellnessPreferences => 'Wellness preferences';

  @override
  String get accountMorningRoutine => 'Morning routine';

  @override
  String get accountMealReminders => 'Meal reminders';

  @override
  String get accountSectionHealth => 'Health & nutrition';

  @override
  String get accountNutrition => 'Nutrition';

  @override
  String get accountNutritionInsights => 'Nutrition insights';

  @override
  String get accountSmileAndFood => 'Smile & Food';

  @override
  String get accountGlucoseJournal => 'Glucose journal';

  @override
  String get accountOptional => 'Optional';

  @override
  String get accountNutritionCircle => 'My nutrition circle';

  @override
  String get accountSectionHousehold => 'Household & account';

  @override
  String get accountHouseholdMembers => 'Household members';

  @override
  String get accountPrivacyData => 'Privacy & data';

  @override
  String get accountConnectedServices => 'Connected services';

  @override
  String get accountMembership => 'Membership';

  @override
  String get accountAccessibilityLanguage => 'Accessibility & language';

  @override
  String get accountSecuritySessions => 'Security & sessions';

  @override
  String get accountHelpSupport => 'Help & support';

  @override
  String get accountLegalEvidence => 'Legal & evidence';

  @override
  String get accountExportOrDelete => 'Export or delete your data';

  @override
  String get accountProPortal => 'Professional portal';

  @override
  String get accountSignOut => 'Sign out';

  @override
  String get accountFooterDemo => 'Chefii · Demo mode';

  @override
  String get accountFooterEarlyAccess => 'Chefii · Early access';

  @override
  String get accountHousehold => 'Household';

  @override
  String accountUsualPortions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count usual portions',
    );
    return '$_temp0';
  }

  @override
  String get accountInviteSomeone => 'Invite someone';

  @override
  String accountInviteShareText(String code) {
    return 'Join our kitchen on Chefii with code $code (valid for 7 days).';
  }

  @override
  String get accountInviteShareSubject => 'Join my Chefii kitchen';

  @override
  String accountMemberYou(String name) {
    return '$name (you)';
  }

  @override
  String accountMemberSubtitle(String role, String date) {
    return '$role · since $date';
  }

  @override
  String get accountRoleOwner => 'Owner';

  @override
  String get accountRoleAdult => 'Adult';

  @override
  String get accountRoleMember => 'Member';

  @override
  String accountRemoveMemberTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get accountRemoveMemberMessage =>
      'They\'ll lose access to the shared kitchen. Their private journal stays theirs.';

  @override
  String get accountOpenInvitations => 'Open invitations';

  @override
  String accountInviteCode(String code) {
    return 'Code $code';
  }

  @override
  String get accountInviteValidity => 'Valid for 7 days, single use';

  @override
  String get accountWhatMembersShare => 'What members share';

  @override
  String get accountMembersShareBody =>
      'Everyone shares the kitchen, shopping list, meal plan and saved recipes. Each person\'s journal, nutrition, glucose, Smile & Food log and professional reviews stay private. Allergies are shared with the household only so shared meals stay safe.';

  @override
  String get accountPrivacyEyebrow => 'Privacy';

  @override
  String get accountPrivacyTitle => 'Your data, your choice';

  @override
  String get accountPrivacySubtitle =>
      'Chefii never sells your data or uses your health records for advertising.';

  @override
  String get accountAiProcessing => 'AI processing';

  @override
  String get accountAiProcessingBody =>
      'Send receipt and fridge photos, and chef requests, to our AI providers (Google Gemini; OpenAI if enabled below) through our secure servers. Providers may not train on your data under our agreements.';

  @override
  String get accountOptionalAiProvider => 'Optional second AI provider';

  @override
  String get accountOptionalAiProviderBody =>
      'Allow OpenAI for conversation and recipe writing. Off means Gemini only.';

  @override
  String get accountAnalytics => 'Product analytics';

  @override
  String get accountAnalyticsBody =>
      'Anonymous usage events (e.g. \"receipt imported\"). Never food names, health data or free text.';

  @override
  String get accountProfessionalSharing => 'Professional sharing';

  @override
  String get accountConsentHistory => 'Consent history';

  @override
  String get accountNoConsents => 'No consents recorded.';

  @override
  String accountConsentGranted(String purpose) {
    return '$purpose · granted';
  }

  @override
  String accountConsentWithdrawn(String purpose) {
    return '$purpose · withdrawn';
  }

  @override
  String accountConsentVersion(String date, String version) {
    return '$date · version $version';
  }

  @override
  String get accountDataResidency =>
      'Data is stored in Canada (Google Cloud, Montréal region) where supported. See the Privacy Policy for details.';

  @override
  String get accountServicesEyebrow => 'Services';

  @override
  String get accountNotifications => 'Notifications';

  @override
  String get accountNotificationsBody =>
      'For reminders, timers and your morning alarm';

  @override
  String get accountNotificationsOn => 'Notifications are on';

  @override
  String get accountNotificationsOff =>
      'Notifications are off — you can change this in system Settings.';

  @override
  String get accountCheck => 'Check';

  @override
  String get accountKitchenAi => 'Kitchen AI';

  @override
  String get accountKitchenAiDemo =>
      'Demo mode — sample results, no AI provider connected';

  @override
  String get accountKitchenAiConnected =>
      'Connected through Chefii\'s secure servers';

  @override
  String get accountHealthApps => 'Apple Health / Health Connect';

  @override
  String get accountHealthAppsBody =>
      'Coming later: read-only glucose import with clear provenance. Not available yet.';

  @override
  String get accountProfessionals => 'Professionals';

  @override
  String get accountProfessionalsBody => 'Manage who can see your records';

  @override
  String get accountBackendDemo => 'Backend: local demo storage on this device';

  @override
  String get accountBackendFirebase => 'Backend: Firebase';

  @override
  String get accountBackendEmulators => 'Backend: Firebase (emulators)';

  @override
  String get accountEarlyAccess => 'Early access';

  @override
  String get accountMembershipSubtitle =>
      'Every Chefii feature is included while we\'re in early access.';

  @override
  String get accountMembershipName => 'Chefii Membership';

  @override
  String get accountMembershipBody =>
      'Paid plans aren\'t available yet. When they launch, you\'ll be told the price in advance and nothing will be charged without your confirmation through the App Store or Google Play.';

  @override
  String get accountIncludedNow => 'Included now';

  @override
  String get accountFeatureScanning => 'Receipt and fridge scanning';

  @override
  String get accountFeatureChef => 'AI chef and guided cooking';

  @override
  String get accountFeaturePlanning => 'Meal planning and smart shopping';

  @override
  String get accountFeatureJournal => 'Nutrition journal and insights';

  @override
  String get accountFeatureCircle => 'Sharing with your nutrition circle';

  @override
  String get accountBillingNote =>
      'Receipts and billing history will appear here once memberships launch.';

  @override
  String get accountSettingsEyebrow => 'Settings';

  @override
  String get accountTextSize => 'Text size';

  @override
  String accountTextScaleValue(int percent) {
    return '$percent%';
  }

  @override
  String accountTextScaleSemantic(int percent) {
    return '$percent percent';
  }

  @override
  String get accountTextPreview =>
      'Preview: Simmer gently until the lentils collapse.';

  @override
  String get accountDeviceTextSize =>
      'Chefii also follows your device\'s text size.';

  @override
  String get accountReduceMotion => 'Reduce motion';

  @override
  String get accountReduceMotionBody => 'Fewer animations and transitions';

  @override
  String get accountReadStepsAloud => 'Read cooking steps aloud';

  @override
  String get accountReadStepsAloudBody => 'In guided cooking';

  @override
  String get accountLanguage => 'Language';

  @override
  String get accountLanguageSystem => 'Same as my device';

  @override
  String get accountDemoAccount => 'Demo account';

  @override
  String get accountSignedIn => 'Signed in';

  @override
  String get accountStoredOnDevice => 'Stored only on this device';

  @override
  String accountIdShort(String id) {
    return 'Account ID $id…';
  }

  @override
  String get accountResetPassword => 'Reset password';

  @override
  String get accountResetPasswordSent => 'Password reset email sent';

  @override
  String get accountSignOutAll => 'Sign out of all devices';

  @override
  String get accountSignOutAllBody => 'Ends every session, including this one';

  @override
  String get accountSignOutEverywhereTitle => 'Sign out everywhere?';

  @override
  String get accountSignOutEverywhereMessage =>
      'You\'ll need to sign in again on each device.';

  @override
  String get accountSignOutEverywhere => 'Sign out everywhere';

  @override
  String get accountReauthNote =>
      'Sensitive actions such as deleting your account or exporting health data ask you to confirm your identity again.';

  @override
  String get accountHelpEyebrow => 'Help';

  @override
  String get accountHelpTitle => 'How can we help?';

  @override
  String get accountSend => 'Send';

  @override
  String get accountFeedbackThanks => 'Thank you — we read every message.';

  @override
  String get accountFaqAccuracyQ => 'How accurate is my kitchen?';

  @override
  String get accountFaqAccuracyA =>
      'Items from receipts you reviewed are confirmed. Amounts after cooking are deducted from what you confirm. Anything estimated is labelled, and Chefii occasionally asks you to verify.';

  @override
  String get accountFaqUntrackedQ =>
      'What if I use something without telling Chefii?';

  @override
  String get accountFaqUntrackedA =>
      'Use the \"I used…\" button or tap − on an item. If counts drift, Quick check lets you fix several items in seconds.';

  @override
  String get accountFaqFreshnessQ => 'Are freshness dates safe to rely on?';

  @override
  String get accountFaqFreshnessA =>
      'No — they\'re estimates from typical storage times. Always follow the package date and your own judgement.';

  @override
  String get accountFaqMedicalQ => 'Does Chefii give medical advice?';

  @override
  String get accountFaqMedicalA =>
      'No. Nutrition features are education. For personal advice, share your records with a registered dietitian in My nutrition circle.';

  @override
  String get accountFaqHealthDataQ => 'Who can see my health data?';

  @override
  String get accountFaqHealthDataA =>
      'Only you, plus any professional you explicitly share with, for the time you choose. Household members never see your journal or health records.';

  @override
  String get accountWriteToUs => 'Write to us';

  @override
  String get accountFeedback => 'Feedback';

  @override
  String get accountReportProblem => 'Report a problem';

  @override
  String get accountFeedbackHint =>
      'Tell us what happened or what you\'d love to see. Please don\'t include health details.';

  @override
  String get accountEmailSupport => 'Email support';

  @override
  String get accountSupportEmailSubject => 'Chefii support';

  @override
  String get accountLegalEyebrow => 'Legal';

  @override
  String get accountLegalTitle => 'Legal & disclosures';

  @override
  String get accountLegalTermsTitle => 'Terms of Service (summary)';

  @override
  String get accountLegalTermsBody =>
      'Chefii is provided for household kitchen organisation, cooking guidance and general nutrition education. You\'re responsible for food safety decisions in your home. Full terms will be published before public launch and require legal review.';

  @override
  String get accountLegalPrivacyTitle => 'Privacy Policy (summary)';

  @override
  String get accountLegalPrivacyBody =>
      'We collect what you enter or scan to run Chefii: kitchen items, receipts, recipes, meal records, and optional health information you choose to add. We process data in Canada where possible, use AI providers only with your consent and under data-processing agreements, never sell personal information, and let you export or delete your data at any time. Prepared to meet PIPEDA and applicable provincial health privacy laws; full policy subject to legal review.';

  @override
  String get accountLegalMedicalTitle => 'Medical limitations';

  @override
  String get accountLegalMedicalBody =>
      'Chefii does not diagnose, treat, cure or prevent any disease, and is not a medical device. Nutrition values are estimates. Glucose features are a personal journal and do not replace medical devices, alarms or your care team. Allergy screening relies on ingredient names and labels you check; it cannot guarantee a food is free of an allergen.';

  @override
  String get accountLegalFoodSafetyTitle => 'Food safety';

  @override
  String get accountLegalFoodSafetyBody =>
      'Freshness indicators are estimates based on typical storage times. Always follow package dates, safe storage temperatures and safe internal cooking temperatures.';

  @override
  String get accountLegalEvidenceTitle => 'Evidence methodology';

  @override
  String get accountLegalEvidenceBody =>
      'Nutrition statements come from national guidelines and authoritative references. Each shows its sources, evidence strength, limitations and review status. AI may rephrase approved statements but may not create new health claims.';

  @override
  String get accountLegalAiTitle => 'AI disclosure';

  @override
  String get accountLegalAiBody =>
      'Recipes marked \"Created by your AI chef\", receipt readings and photo suggestions are generated by AI and may contain mistakes. Illustrations are not photographs of your food.';

  @override
  String get accountEvidenceLibrary => 'Evidence library';

  @override
  String get accountLicences => 'Open-source licences';

  @override
  String get accountLicencesBody =>
      'Including Cormorant Garamond and Inter (SIL Open Font License)';

  @override
  String get accountDataEyebrow => 'Your data';

  @override
  String get accountDataTitle => 'Export or delete';

  @override
  String get accountExport => 'Export';

  @override
  String get accountExportBody =>
      'A complete copy of your profile, kitchen, journal, health records, consents and sharing history as a JSON file.';

  @override
  String get accountPasswordConfirm => 'Password (to confirm it\'s you)';

  @override
  String get accountExportMyData => 'Export my data';

  @override
  String get accountExportShareSubject => 'Your Chefii data';

  @override
  String get accountDeleteAccount => 'Delete account';

  @override
  String get accountDeleteBody =>
      'Permanently deletes your account, journal, health records and sharing grants. If you\'re the only member of your household, its kitchen is deleted too. Some records may be kept where the law requires (for example, purchase receipts for membership billing). This can\'t be undone.';

  @override
  String get accountDeleteConfirmWord => 'DELETE';

  @override
  String accountDeleteConfirmLabel(String word) {
    return 'Type $word to confirm';
  }

  @override
  String get accountDeleteMyAccount => 'Delete my account';

  @override
  String chefChatUnavailable(String message) {
    return '$message Your curated recipes are still available in Discover.';
  }

  @override
  String get chefChatError =>
      'I couldn\'t reach the kitchen assistant just now. Please try again.';

  @override
  String get chefPromptQuickDinner => 'Something quick for dinner';

  @override
  String get chefPromptProteinBreakfast => 'A high-protein breakfast';

  @override
  String get chefPromptUseWhatIHave => 'What can I make with what I have?';

  @override
  String get chefPromptVegetarian => 'A comforting vegetarian meal';

  @override
  String get chefAiFeature => 'your AI chef';

  @override
  String get chefHomeTitle => 'Your chef';

  @override
  String get chefPreferencesTooltip => 'Preferences';

  @override
  String get chefNewConversation => 'New conversation';

  @override
  String get chefDemoChat =>
      'Demo: replies use the curated recipe library, not AI.';

  @override
  String get chefHomeHeadline => 'What shall we cook?';

  @override
  String get chefHomeSubtitle =>
      'Ask for anything — I know what\'s in your kitchen and what everyone can eat.';

  @override
  String get chefChooseOptions => 'Choose time, portions and more';

  @override
  String get chefAskHint => 'Ask your chef…';

  @override
  String get chefSend => 'Send';

  @override
  String get chefEyebrow => 'Chef';

  @override
  String get chefPreferencesTitle => 'Tonight, I\'d like…';

  @override
  String get chefShowRecipes => 'Show me recipes';

  @override
  String get chefMeal => 'Meal';

  @override
  String get chefTimeAvailable => 'Time available';

  @override
  String get chefTimeAvailableSemantics => 'Time available in minutes';

  @override
  String chefUpTo(String duration) {
    return 'Up to $duration';
  }

  @override
  String get chefPortions => 'Portions';

  @override
  String get chefFewer => 'Fewer';

  @override
  String get chefMore => 'More';

  @override
  String get chefUseWhatIHave => 'Use what I have';

  @override
  String get chefUseWhatIHaveSubtitle => 'Prefer recipes I can make now';

  @override
  String get chefNutrition => 'Nutrition';

  @override
  String get chefFocusMoreProtein => 'more protein';

  @override
  String get chefFocusMoreVegetables => 'more vegetables';

  @override
  String get chefFocusLighter => 'lighter';

  @override
  String get chefFocusMoreFibre => 'more fibre';

  @override
  String get chefCuisine => 'Cuisine';

  @override
  String get chefCuisineItalian => 'Italian';

  @override
  String get chefCuisineFrench => 'French';

  @override
  String get chefCuisineMediterranean => 'Mediterranean';

  @override
  String get chefCuisineIndian => 'Indian';

  @override
  String get chefCuisineMiddleEastern => 'Middle Eastern';

  @override
  String get chefCuisineMexican => 'Mexican';

  @override
  String get chefCuisineJapanese => 'Japanese';

  @override
  String get chefCuisineChinese => 'Chinese';

  @override
  String get chefCuisineModern => 'Modern';

  @override
  String get chefEquipment => 'Equipment';

  @override
  String get chefEquipmentOven => 'Oven';

  @override
  String get chefEquipmentStovetop => 'Stovetop';

  @override
  String get chefEquipmentAirFryer => 'Air fryer';

  @override
  String get chefEquipmentSlowCooker => 'Slow cooker';

  @override
  String get chefEquipmentInstantPot => 'Instant Pot';

  @override
  String get chefEquipmentBlender => 'Blender';

  @override
  String get chefEquipmentMicrowave => 'Microwave';

  @override
  String get chefLeaveOut => 'Leave out';

  @override
  String get chefLeaveOutHint => 'e.g. mushrooms, olives';

  @override
  String chefAlwaysRespected(String list) {
    return 'Always respected: $list.';
  }

  @override
  String get chefNoAllergiesRecorded => 'no allergies or restrictions recorded';

  @override
  String get chefAddAllergies =>
      'Add your allergies in Profile so I can screen every recipe.';

  @override
  String get chefNoRequestTitle => 'Tell me what you\'d like';

  @override
  String get chefNoRequestMessage => 'Choose time and portions first.';

  @override
  String get chefSetPreferences => 'Set preferences';

  @override
  String get chefResultsTitle => 'For you';

  @override
  String chefResultsSubtitle(String meal, String duration, int servings) {
    return '$meal · up to $duration · $servings portions';
  }

  @override
  String get chefAnyMeal => 'Any meal';

  @override
  String get chefTryAnother => 'Try another';

  @override
  String get chefDemoResults =>
      'Demo: ranked from the curated library, not generated by AI.';

  @override
  String get chefConsidering => 'Considering your kitchen…';

  @override
  String get chefNoMoreIdeasTitle => 'No more ideas with these settings';

  @override
  String get chefNoMoreIdeasMessage =>
      'Try a longer time or fewer restrictions.';

  @override
  String get chefAdjust => 'Adjust';

  @override
  String chefFilteredForSafety(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ideas were left out for your household\'s dietary needs.',
      one: '1 idea was left out for your household\'s dietary needs.',
    );
    return '$_temp0';
  }

  @override
  String get chefRecipeUnavailableTitle => 'Recipe unavailable';

  @override
  String get chefRecipeUnavailableMessage =>
      'This suggestion wasn\'t saved. Ask your chef again or browse Discover.';

  @override
  String get chefDiscover => 'Discover';

  @override
  String get chefRemoveFavourite => 'Remove from favourites';

  @override
  String get chefSaveFavourite => 'Save to favourites';

  @override
  String get chefAddToPlan => 'Add to meal plan';

  @override
  String get chefNotSafe => 'Not safe for your household';

  @override
  String get chefStartCooking => 'Start cooking';

  @override
  String chefTotalTime(String duration) {
    return '$duration total';
  }

  @override
  String get chefAiCreated =>
      'Created by AI for you. Check cooking temperatures and your own judgement.';

  @override
  String chefAiCreatedWithModel(String model) {
    return 'Created by AI for you ($model). Check cooking temperatures and your own judgement.';
  }

  @override
  String get chefConflicts => 'Conflicts with your household\'s needs';

  @override
  String get chefWorthALook => 'Worth a look';

  @override
  String chefConflictLine(String ingredient, String reason) {
    return '• $ingredient: $reason';
  }

  @override
  String get chefSeeSubstitutions => 'See substitutions';

  @override
  String get chefIngredients => 'Ingredients';

  @override
  String get chefServings => 'Servings';

  @override
  String get chefFewerServings => 'Fewer servings';

  @override
  String get chefMoreServings => 'More servings';

  @override
  String chefAddMissingToList(int count) {
    return 'Add $count to list';
  }

  @override
  String get chefAddedToList => 'Added to your shopping list';

  @override
  String get chefSubstitutions => 'Substitutions';

  @override
  String get chefMethod => 'Method';

  @override
  String get chefStoring => 'Storing';

  @override
  String get chefSavedToRecipes => 'Saved to your recipes';

  @override
  String get chefSaveRecipe => 'Save this recipe';

  @override
  String get chefInYourKitchenLower => 'in your kitchen';

  @override
  String chefNeedQuantity(String quantity) {
    return 'need $quantity';
  }

  @override
  String get chefNeedMore => 'need more';

  @override
  String get chefToBuy => 'to buy';

  @override
  String get chefOptional => 'optional';

  @override
  String chefOptionalIngredient(String ingredient) {
    return '$ingredient (optional)';
  }

  @override
  String get chefSmartSubstitutions => 'Smart substitutions';

  @override
  String get chefSubstitutionsNote =>
      'Every swap is checked against your household\'s allergies and diet.';

  @override
  String get chefNoSafeSwapsTitle => 'No safe swaps we\'re confident about';

  @override
  String get chefNoSafeSwapsMessage =>
      'Try asking your chef for a different recipe.';

  @override
  String get chefInYourKitchen => 'In your kitchen';

  @override
  String chefProteinDiff(String diff) {
    return 'Protein $diff g / serving';
  }

  @override
  String get chefUseThis => 'Use this';

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
  String get cookingSessionNotFound =>
      'This cooking session could not be found.';

  @override
  String get cookingBeforeYouBegin => 'Before you begin';

  @override
  String cookingPrepSubtitle(int servings) {
    return '$servings servings · gather everything first';
  }

  @override
  String get cookingBeginCooking => 'Begin cooking';

  @override
  String get cookingBeginAnyway => 'Begin anyway';

  @override
  String cookingReadyCount(int ready, int total) {
    return '$ready of $total ready';
  }

  @override
  String get cookingIngredients => 'Ingredients';

  @override
  String get cookingEquipment => 'Equipment';

  @override
  String cookingKitchenShows(String quantity) {
    return 'Kitchen shows $quantity — check you have enough';
  }

  @override
  String get cookingNotInKitchen => 'Not in your kitchen records';

  @override
  String cookingStepSpeech(int step, String text) {
    return 'Step $step. $text';
  }

  @override
  String get cookingStopReadingAloud => 'Stop reading steps aloud';

  @override
  String get cookingReadAloud => 'Read steps aloud';

  @override
  String get cookingTimers => 'Timers';

  @override
  String cookingStepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String cookingStepOfCaps(int step, int total) {
    return 'STEP $step OF $total';
  }

  @override
  String cookingStartNamedTimer(String label, String duration) {
    return 'Start $label · $duration';
  }

  @override
  String cookingStartTimer(String duration) {
    return 'Start timer · $duration';
  }

  @override
  String cookingStepTimerLabel(int step) {
    return 'Step $step';
  }

  @override
  String get cookingFinishCooking => 'Finish cooking';

  @override
  String get cookingNextStep => 'Next step';

  @override
  String cookingTimerChipDone(String label) {
    return '$label done';
  }

  @override
  String get cookingKitchenEyebrow => 'Kitchen';

  @override
  String get cookingTimersSubtitle =>
      'They\'ll alert you even if you leave the app.';

  @override
  String cookingStartMinutesTimer(int minutes) {
    return 'Start $minutes min timer';
  }

  @override
  String get cookingDefaultTimerName => 'Timer';

  @override
  String get cookingNoTimersTitle => 'No timers running';

  @override
  String get cookingNoTimersMessage =>
      'Start one from a recipe step, or below.';

  @override
  String get cookingAddMinute => '+1 minute';

  @override
  String get cookingPause => 'Pause';

  @override
  String get cookingResume => 'Resume';

  @override
  String get cookingNewTimer => 'New timer';

  @override
  String get cookingTimerName => 'Name';

  @override
  String get cookingTimerNameHint => 'e.g. Rice';

  @override
  String cookingMinutesChip(int minutes) {
    return '$minutes min';
  }

  @override
  String get cookingAlmostDone => 'Almost done';

  @override
  String get cookingWhatDidYouUse => 'What did you use?';

  @override
  String get cookingConfirmSubtitle =>
      'Adjust anything that differed. This updates your kitchen once.';

  @override
  String get cookingConfirmAndUpdate => 'Confirm and update kitchen';

  @override
  String cookingDiscrepancies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Kitchen updated. $count items weren\'t fully recorded — we\'ll ask you to check later.',
      one: 'Kitchen updated. 1 item wasn\'t fully recorded — we\'ll ask you to check later.',
    );
    return '$_temp0';
  }

  @override
  String get cookingNothingTracked =>
      'None of these ingredients are tracked in your kitchen, so nothing will change.';

  @override
  String get cookingInclude => 'Include';

  @override
  String get cookingDidntUse => 'Didn\'t use';

  @override
  String cookingRecipeAmount(String quantity) {
    return 'Recipe: $quantity';
  }

  @override
  String cookingAmountUsed(String ingredient) {
    return 'Amount of $ingredient used';
  }

  @override
  String get cookingBonAppetit => 'Bon appétit';

  @override
  String get cookingKitchenUpdated => 'Your kitchen has been updated.';

  @override
  String get cookingFinish => 'Finish';

  @override
  String cookingLoggedWithLeftovers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count portions',
      one: '1 portion',
    );
    return 'Logged, and $_temp0 saved in the fridge.';
  }

  @override
  String get cookingLoggedToJournal => 'Logged to your journal.';

  @override
  String get cookingHowWasIt => 'How was it?';

  @override
  String cookingStars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stars',
      one: '1 star',
    );
    return '$_temp0';
  }

  @override
  String get cookingYourPortion => 'Your portion';

  @override
  String get cookingPortionsYouAte => 'Portions you ate';

  @override
  String get cookingYourMeal => 'Your meal';

  @override
  String cookingPortionCount(num count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$amount portions',
      one: '1 portion',
    );
    return '$_temp0';
  }

  @override
  String get cookingLeftovers => 'Leftovers';

  @override
  String get cookingPortionsToSave => 'Portions to save';

  @override
  String get cookingLeftoversReminder =>
      'We\'ll add them to your fridge with a reminder to eat them within 3 days.';

  @override
  String get cookingSaveFavourite => 'Save to favourites';

  @override
  String cookingTimerNotificationTitle(String label) {
    return '$label is done';
  }

  @override
  String get cookingTimerNotificationBody => 'Your Chefii timer has finished.';

  @override
  String get coreErrorTitle => 'Something went wrong';

  @override
  String get coreErrorOffline =>
      'You appear to be offline, so nothing was changed. Please try again when you\'re connected.';

  @override
  String get coreErrorPermissionDenied =>
      'You don\'t have access to this. If it was shared with you, the owner may have changed permissions.';

  @override
  String get coreErrorGeneric => 'Please try again in a moment.';

  @override
  String corePermissionOff(String permission) {
    return '$permission is turned off';
  }

  @override
  String get coreOpenSettings => 'Open Settings';

  @override
  String coreInProgress(String label) {
    return '$label, in progress';
  }

  @override
  String get coreLess => 'Less';

  @override
  String get coreMore => 'More';

  @override
  String get coreClearSearch => 'Clear search';

  @override
  String get corePhotoFrameHint => 'Fit the whole receipt inside the frame';

  @override
  String get coreIllustration => 'Illustration';

  @override
  String coreIllustrationFor(String label) {
    return 'Illustration for $label';
  }

  @override
  String coreStatus(String status) {
    return 'Status: $status';
  }

  @override
  String coreMinutesSpoken(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
    );
    return '$_temp0';
  }

  @override
  String coreMinutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String coreKcalApprox(int kcal) {
    return '≈ $kcal kcal';
  }

  @override
  String get coreLikelyPastBest => 'Likely past best';

  @override
  String get corePastRecordedDate => 'Past recorded date';

  @override
  String coreDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String coreDaysLeftApprox(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '~$days days left',
      one: '~1 day left',
    );
    return '$_temp0';
  }

  @override
  String get coreUseSome => 'Use some';

  @override
  String get coreNutritionTitle => 'Nutrition';

  @override
  String get corePerServing => 'per serving';

  @override
  String get coreEstimate => 'Estimate';

  @override
  String coreNutrientAbout(String nutrient, String amount) {
    return '$nutrient about $amount';
  }

  @override
  String get coreNutritionNoData =>
      'We don\'t have nutrition data for these ingredients yet.';

  @override
  String coreNutritionPartial(int percent) {
    return 'Based on $percent% of ingredients — some couldn\'t be estimated.';
  }

  @override
  String coreMealAt(String meal, String time, String title) {
    return '$meal at $time: $title';
  }

  @override
  String coreMealAtDone(String meal, String time, String title) {
    return '$meal at $time: $title, done';
  }

  @override
  String get coreMorningRoutine => 'Morning routine';

  @override
  String get coreSetUpMornings => 'Set up your mornings';

  @override
  String coreMorningSummary(String wake, String departure, int minutes) {
    return 'Up $wake · out by $departure · $minutes min free';
  }

  @override
  String get coreMorningPitch =>
      'A calm plan from alarm to door, with breakfast decided.';

  @override
  String coreBreakfastLine(String title) {
    return 'Breakfast: $title';
  }

  @override
  String get coreChefDemoNote => 'Demo · curated suggestions, no AI';

  @override
  String coreSaidByYou(String text) {
    return 'You: $text';
  }

  @override
  String coreSaidByChef(String text) {
    return 'Chef: $text';
  }

  @override
  String coreEvidenceStrength(String strength) {
    return '$strength evidence';
  }

  @override
  String coreReviewed(String date) {
    return 'Reviewed $date';
  }

  @override
  String coreInternalSummary(String date) {
    return 'Internal summary, $date · awaiting professional review';
  }

  @override
  String coreOverMinutes(int minutes) {
    return 'over $minutes min';
  }

  @override
  String get coreHelpfulHabit => 'helpful habit';

  @override
  String get coreDelete => 'Delete';

  @override
  String get coreShareJournal => 'Meals you logged, portions and times';

  @override
  String get coreShareNutrition => 'Estimated nutrients from your journal';

  @override
  String get coreShareGlucose => 'Glucose readings you entered';

  @override
  String get coreShareOral => 'Sugar and acid exposure log';

  @override
  String get coreShareConcerns => 'Hair, skin & nail notes';

  @override
  String get coreShareDietary => 'Allergies, intolerances and preferences';

  @override
  String get coreAssessmentNew => 'New';

  @override
  String get coreAssessmentRead => 'Read';

  @override
  String get coreAssessmentAccepted => 'Accepted';

  @override
  String get coreAssessmentDeclined => 'Declined';

  @override
  String get coreAssessmentDraft => 'Draft';

  @override
  String get coreDemoBanner => 'Demo mode — sample data, no AI used.';

  @override
  String get coreTabToday => 'Today';

  @override
  String get coreTabKitchen => 'Kitchen';

  @override
  String get coreTabDiscover => 'Discover';

  @override
  String get coreTabJournal => 'Journal';

  @override
  String get coreTabYou => 'You';

  @override
  String get corePageNotFound => 'Page not found';

  @override
  String get corePageNotFoundMessage =>
      'That link doesn\'t lead anywhere in Chefii.';

  @override
  String get coreGoToToday => 'Go to Today';

  @override
  String get coreAppLoading => 'Chefii is loading';

  @override
  String get coreSnoozeWakeBody =>
      'Your snoozed alarm. Tap to start your morning.';

  @override
  String get coreSnoozeEveningTitle => 'Tomorrow morning';

  @override
  String get coreSnoozeEveningBody => 'Your snoozed evening preview.';

  @override
  String get coreSnoozeReminderTitle => 'A gentle reminder';

  @override
  String get coreSnoozeReminderBody => 'Your snoozed reminder from Chefii.';

  @override
  String get coreSnoozeAction => 'Snooze 10 min';

  @override
  String get coreChannelReminders => 'Meal reminders';

  @override
  String get coreChannelRemindersDescription =>
      'Gentle reminders for meals and kitchen tasks';

  @override
  String get coreChannelAlarm => 'Morning alarm';

  @override
  String get coreChannelAlarmDescription => 'Your morning routine alarm';

  @override
  String get coreChannelTimers => 'Cooking timers';

  @override
  String get coreChannelTimersDescription =>
      'Alerts when a cooking timer finishes';

  @override
  String get coreErrNotSignedIn => 'Please sign in to continue.';

  @override
  String get coreErrReceiptDuplicate =>
      'This receipt looks like one you already scanned.';

  @override
  String get coreErrPlaceNameLength =>
      'Give the place a name of up to 30 characters.';

  @override
  String coreErrPlaceNameTaken(String name) {
    return 'You already have a place called $name.';
  }

  @override
  String get coreErrPlaceLimit => 'You can have up to 12 places.';

  @override
  String get coreErrBuiltInRename => 'The built-in places can\'t be renamed.';

  @override
  String get coreErrBuiltInRemove => 'The built-in places can\'t be removed.';

  @override
  String get coreErrPlaceNotEmpty =>
      'Move or use up what\'s stored there first.';

  @override
  String get coreErrNothingToAdd => 'Nothing to add.';

  @override
  String coreErrQuantityNotPositive(String product) {
    return '$product: quantity must be greater than zero.';
  }

  @override
  String get coreErrNothingToDeduct => 'Nothing to deduct.';

  @override
  String get coreErrNothingToCorrect => 'Nothing to correct.';

  @override
  String get coreErrNegativeCount => 'Counts cannot be negative.';

  @override
  String get coreErrItemGone => 'That item no longer exists.';

  @override
  String coreErrWrongUnit(String product, String unit) {
    return '$product: use $unit for this item.';
  }

  @override
  String get coreErrNothingToUndo => 'Nothing to undo.';

  @override
  String get coreErrAlreadyUndone => 'This change has already been undone.';

  @override
  String get coreErrUndoOfUndo => 'An undo cannot itself be undone.';

  @override
  String coreErrProductNotRecorded(String product) {
    return 'No $product recorded in your kitchen.';
  }

  @override
  String get coreErrReceiptNotFound => 'Receipt not found.';

  @override
  String get coreErrReceiptNotEditable =>
      'This receipt can no longer be edited.';

  @override
  String get coreErrReceiptNotReady => 'This receipt is not ready to import.';

  @override
  String coreErrReceiptLinesIncomplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items need a name and quantity before importing.',
      one: '1 item needs a name and quantity before importing.',
    );
    return '$_temp0';
  }

  @override
  String get coreErrReceiptNoFoodItems => 'There are no food items to add.';

  @override
  String get coreErrReceiptNoPhotos => 'Add at least one photo.';

  @override
  String coreErrReceiptTooManyPages(int max) {
    return 'Up to $max pages per receipt.';
  }

  @override
  String get coreErrImageEmpty => 'That image appears to be empty.';

  @override
  String get coreErrImageTooLarge =>
      'That image is too large (over 12 MB). Try a closer, single-page photo.';

  @override
  String get coreErrImageFormat =>
      'Please use a JPEG, PNG, HEIC or WebP photo.';

  @override
  String get coreErrAiUnavailable =>
      'The kitchen assistant is unavailable right now.';

  @override
  String get coreErrAuthCredentialMismatch =>
      'That email and password don\'t match.';

  @override
  String get coreErrAuthEmailInUse =>
      'An account already exists for that email. Try signing in.';

  @override
  String get coreErrAuthWeakPassword =>
      'Please choose a longer password (at least 8 characters).';

  @override
  String get coreErrAuthInvalidEmail =>
      'That email address doesn\'t look right.';

  @override
  String get coreErrAuthOffline =>
      'You appear to be offline. Please try again.';

  @override
  String get coreErrAuthTooManyRequests =>
      'Too many attempts. Please wait a moment and try again.';

  @override
  String get coreErrAuthRecentLogin =>
      'For your security, please sign in again to continue.';

  @override
  String get coreErrAuthCancelled => 'Sign-in was cancelled.';

  @override
  String get coreErrAuthFailed => 'Sign-in failed.';

  @override
  String get coreErrAuthFailedRetry => 'Sign-in failed. Please try again.';

  @override
  String get coreErrAuthNoGoogleToken =>
      'Google did not return an identity token.';

  @override
  String get coreErrAuthSignInAgain => 'Please sign in again.';

  @override
  String get coreErrAuthPasswordRequired => 'Enter your password to continue.';

  @override
  String get coreErrAuthAppleNeedsFirebase =>
      'Apple sign-in needs Firebase configured. Use the demo account.';

  @override
  String get coreErrAuthGoogleNeedsFirebase =>
      'Google sign-in needs Firebase configured. Use the demo account.';

  @override
  String get coreErrOwnerNotRemovable => 'The owner cannot be removed.';

  @override
  String get coreErrProfessionalNotVerified =>
      'Only verified professionals can be granted access.';

  @override
  String get coreErrNoShareCategories =>
      'Choose at least one category to share.';

  @override
  String coreErrNoActivePermission(String category) {
    return 'No active permission for $category.';
  }

  @override
  String get discoverFilterAvailableNow => 'Available now';

  @override
  String get discoverFilterBreakfast => 'Breakfast';

  @override
  String get discoverFilterLunch => 'Lunch';

  @override
  String get discoverFilterDinner => 'Dinner';

  @override
  String get discoverFilterSnacks => 'Snacks';

  @override
  String get discoverFilter15Minute => '15-minute';

  @override
  String get discoverFilterHighProtein => 'High-protein';

  @override
  String get discoverFilterVegetarian => 'Vegetarian';

  @override
  String get discoverFilterComfort => 'Comfort';

  @override
  String get discoverFilterWorldCuisines => 'World cuisines';

  @override
  String get discoverMealPlanner => 'Meal planner';

  @override
  String get discoverAskChef => 'Ask the chef';

  @override
  String get discoverEyebrow => 'Discover';

  @override
  String get discoverTitle => 'Something delicious';

  @override
  String discoverCookWith(String ingredient) {
    return 'Cook with $ingredient';
  }

  @override
  String get discoverSubtitle =>
      'Every recipe here suits your household\'s dietary needs.';

  @override
  String get discoverSearchHint => 'Search recipes or ingredients';

  @override
  String get discoverNoMatchTitle => 'No recipes match';

  @override
  String get discoverNoMatchMessage =>
      'Try another filter, or ask your chef to create something.';

  @override
  String get discoverUsesExpiring => 'Uses something that needs eating soon';

  @override
  String discoverNutritionFootnote(int grams) {
    return 'Nutrition is estimated per serving from reference data. Protein-rich means at least $grams g per serving.';
  }

  @override
  String discoverNutritionFootnoteHidden(int grams) {
    return 'Nutrition is estimated per serving from reference data (hidden in your preferences). Protein-rich means at least $grams g per serving.';
  }

  @override
  String discoverProteinLabel(int grams) {
    return '$grams g protein';
  }

  @override
  String get healthOpenLinkError => 'Couldn\'t open the link.';

  @override
  String get healthNutritionEyebrow => 'Nutrition';

  @override
  String get healthYourNutrition => 'Your nutrition';

  @override
  String healthDailyAverageSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Daily average across $count logged days',
      one: 'Daily average across 1 logged day',
    );
    return '$_temp0';
  }

  @override
  String get healthInsights => 'Insights';

  @override
  String healthDaysSegment(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get healthNoMealsTitle => 'No meals logged yet';

  @override
  String get healthNoMealsMessage =>
      'Cook with Chefii or log meals in your journal to see estimates here.';

  @override
  String get healthLogMeal => 'Log a meal';

  @override
  String get healthEstimatesNote =>
      'Estimates from recipes and reference data.';

  @override
  String healthMissingDataNote(int percent) {
    return 'Some meals had no nutrition data ($percent%), so totals are likely low.';
  }

  @override
  String get healthDailyValueNote =>
      'Daily Values are Health Canada\'s label reference — a yardstick, not a personal target.';

  @override
  String healthNutrientBarSemantics(String nutrient, String amount) {
    return '$nutrient: about $amount';
  }

  @override
  String healthNutrientBarSemanticsDv(
    String nutrient,
    String amount,
    int percent,
  ) {
    return '$nutrient: about $amount, $percent percent of the Daily Value';
  }

  @override
  String healthPercentDv(int percent) {
    return '$percent% DV';
  }

  @override
  String get healthNotEnoughHistory => 'Not enough history yet';

  @override
  String healthPerDay(String amount) {
    return '≈ $amount a day';
  }

  @override
  String healthSteadyAt(String amount) {
    return 'Steady at ≈ $amount a day';
  }

  @override
  String healthTrendUp(int percent) {
    return 'Up $percent% vs the week before';
  }

  @override
  String healthTrendDown(int percent) {
    return 'Down $percent% vs the week before';
  }

  @override
  String get healthInsightsSubtitle =>
      'Patterns from your journal, explained with evidence.';

  @override
  String get healthEvidenceLibrary => 'Evidence library';

  @override
  String get healthInsightsEmptyTitle => 'Insights need a few days of meals';

  @override
  String get healthInsightsEmptyMessage =>
      'Keep cooking and logging — we\'ll look for patterns after a few days.';

  @override
  String get healthTrends => 'Trends';

  @override
  String get healthVarietyThisWeek => 'Variety this week';

  @override
  String healthDifferentMeals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'different meals',
      one: 'different meals',
    );
    return '$_temp0';
  }

  @override
  String healthPlantFoods(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'plant foods in Chefii recipes',
      one: 'plant foods in Chefii recipes',
    );
    return '$_temp0';
  }

  @override
  String get healthSomethingToTry => 'Something to try';

  @override
  String healthFibrePerServing(int grams) {
    return '≈ $grams g fibre per serving';
  }

  @override
  String healthAvailabilityLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ingredients to buy',
      one: '1 ingredient to buy',
      zero: 'Everything on hand',
    );
    return '$_temp0';
  }

  @override
  String get healthMoreToExplore => 'More to explore';

  @override
  String get healthHairSkinNails => 'Hair, skin & nails';

  @override
  String get healthSmileAndFood => 'Smile & Food';

  @override
  String get healthEducationDisclaimer =>
      'Chefii provides general nutrition education, not medical advice. For personal guidance, talk to a registered dietitian.';

  @override
  String get healthHairSubtitle =>
      'A private notebook, plus what the evidence does — and doesn\'t — say.';

  @override
  String get healthHairCausesNote =>
      'Changes in hair, skin and nails have many causes besides diet — hormones, thyroid, stress, medications, skin conditions and genetics. Sudden hair loss, rashes, or nail changes that don\'t settle are worth seeing a doctor, dermatologist or pharmacist about.';

  @override
  String get healthNoteAConcern => 'Note a concern';

  @override
  String get healthConcernHair => 'Hair';

  @override
  String get healthConcernSkin => 'Skin';

  @override
  String get healthConcernNails => 'Nails';

  @override
  String get healthConcernEnergy => 'Energy';

  @override
  String get healthConcernDigestion => 'Digestion';

  @override
  String get healthConcernOther => 'Other';

  @override
  String get healthWhatHaveYouNoticed => 'What have you noticed?';

  @override
  String healthBotherLevel(int severity) {
    return 'How much is it bothering you? ($severity of 5)';
  }

  @override
  String get healthBotherSemantics => 'How much it bothers you, 1 to 5';

  @override
  String get healthSaveNote => 'Save note';

  @override
  String get healthSavedPrivately => 'Saved privately';

  @override
  String get healthYourNotes => 'Your notes';

  @override
  String get healthDelete => 'Delete';

  @override
  String get healthWhatEvidenceSays => 'What the evidence says';

  @override
  String get healthShareWithDietitian => 'Share with a dietitian';

  @override
  String get healthEvidence => 'Evidence';

  @override
  String get healthHowWeKnow => 'How we know';

  @override
  String get healthEvidenceSubtitle =>
      'Every nutrition statement in Chefii, its sources and its limits.';

  @override
  String get healthReview => 'Review';

  @override
  String healthProfessionallyReviewed(String date) {
    return 'Professionally reviewed $date';
  }

  @override
  String healthInternalSummary(String date) {
    return 'Internal summary ($date), awaiting professional review';
  }

  @override
  String get healthLimitations => 'Limitations';

  @override
  String get healthFoods => 'Foods';

  @override
  String healthLabelColon(String label) {
    return '$label:';
  }

  @override
  String get healthCitationPending => 'Source: citation pending review.';

  @override
  String get healthMethodNote =>
      'Method: we prefer national guidelines and systematic reviews; single studies are not used for recommendations.';

  @override
  String get healthNutrientEyebrow => 'Nutrient';

  @override
  String get healthNoDataYet => 'No data yet';

  @override
  String get healthLogMealsForEstimate => 'Log meals to see an estimate.';

  @override
  String healthAverageThisWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Average over $count logged days this week',
      one: 'Average over 1 logged day this week',
    );
    return '$_temp0';
  }

  @override
  String healthReferenceDailyValue(String amount) {
    return 'Reference: $amount (Daily Value, Health Canada, Table of Daily Values)';
  }

  @override
  String healthReferenceOther(String amount, String kind, String source) {
    return 'Reference: $amount ($kind, $source)';
  }

  @override
  String healthDataCompleteness(int percent) {
    return 'Data completeness: $percent% of meals had nutrition estimates.';
  }

  @override
  String get healthBiggestContributors => 'Biggest contributors this week';

  @override
  String get healthRichSources => 'Rich sources';

  @override
  String healthPer100g(String amount) {
    return '$amount / 100 g';
  }

  @override
  String get healthIndividualNeeds =>
      'Individual needs vary. Estimates can\'t account for exact brands, portions, or added salt.';

  @override
  String get healthWellnessEyebrow => 'Wellness';

  @override
  String get healthSmileIntroSubtitle =>
      'Learn how the timing of sugary and acidic foods affects your teeth.';

  @override
  String get healthTurnOnSmile => 'Turn on Smile & Food';

  @override
  String get healthSmileOptionalNote =>
      'This is optional education. It isn\'t a dental assessment, and your entries stay private unless you choose to share them.';

  @override
  String get healthSmileSubtitle =>
      'Tap to log. It\'s about frequency and timing, not perfection.';

  @override
  String get healthHistory => 'History';

  @override
  String get healthSugarExposuresToday => 'sugar exposures today';

  @override
  String get healthAcidExposuresToday => 'acid exposures today';

  @override
  String get healthHelpfulHabits => 'helpful habits';

  @override
  String get healthLogNow => 'Log now';

  @override
  String healthLoggedMessage(String item) {
    return '$item logged';
  }

  @override
  String get healthKinderChoices => 'Kinder choices';

  @override
  String get healthTipSweetsTitle => 'Keep sweets with meals';

  @override
  String get healthTipSweetsBody =>
      'One sugar exposure at dinner is gentler on teeth than the same amount spread through the afternoon.';

  @override
  String get healthTipFinishTitle => 'Finish with water or cheese';

  @override
  String get healthTipFinishBody =>
      'Rinsing with water or ending on cheese helps your mouth recover after eating.';

  @override
  String get healthTipSipTitle => 'Sip, then stop';

  @override
  String get healthTipSipBody =>
      'If you enjoy juice or soda, drinking it with a meal rather than over an hour limits acid time.';

  @override
  String get healthTipBrushTitle => 'Wait to brush after acid';

  @override
  String get healthTipBrushBody =>
      'Many dental professionals suggest waiting a while after acidic food or drink before brushing. Ask your dentist what\'s right for you.';

  @override
  String get healthSmileFooter =>
      'Education only. For tooth pain, sensitivity or concerns, see your dentist.';

  @override
  String healthHistoryExposuresPerDay(String rate) {
    return 'About $rate sugar or acid exposures a day this week';
  }

  @override
  String get healthNothingLoggedYet => 'Nothing logged yet';

  @override
  String get healthLogWillAppear => 'Your log will appear here.';

  @override
  String get healthDiabetesConsentText =>
      'I choose to store glucose readings I enter in Chefii. I understand Chefii does not diagnose, interpret readings, recommend insulin or medication, or replace my glucose meter\'s or CGM\'s alarms. My readings are private and only shared if I grant access.';

  @override
  String get healthOptionalEyebrow => 'Optional';

  @override
  String get healthGlucoseJournal => 'Glucose journal';

  @override
  String get healthDiabetesSubtitle =>
      'For people who already track glucose and want it alongside their meals.';

  @override
  String get healthTurnOffGlucose => 'Turn off glucose features';

  @override
  String get healthTurnOnGlucose => 'Turn on glucose journal';

  @override
  String get healthGlucoseOn => 'Glucose journal is on.';

  @override
  String get healthOpenGlucose => 'Open glucose journal';

  @override
  String get healthDiabetesPointRecord =>
      'Record readings you take, with the time and context.';

  @override
  String get healthDiabetesPointMeals =>
      'See them next to the meals in your journal.';

  @override
  String get healthDiabetesPointNoAdvice =>
      'No predictions, scores, diagnoses or dosing advice — ever.';

  @override
  String get healthDiabetesPointNotAlarm =>
      'Not an alarm. Keep using your meter or CGM alerts.';

  @override
  String get healthDiabetesPointPrivate =>
      'Private to you. Shared only with a professional you choose.';

  @override
  String get healthUnits => 'Units';

  @override
  String get healthUnderstandJournal =>
      'I understand this is a journal, not a medical device';

  @override
  String get healthConsentStore =>
      'I consent to Chefii storing my glucose readings';

  @override
  String get healthSymptomsWarning =>
      'If you have symptoms of very high or low blood sugar, follow your care plan or seek medical help.';

  @override
  String get healthEnterNumber => 'Enter a number.';

  @override
  String get healthEnterPositive => 'Enter a positive value.';

  @override
  String get healthValueOutOfRange =>
      'That value looks outside what meters typically report. Please double-check it.';

  @override
  String get healthGlucoseOffTitle => 'Glucose journal is off';

  @override
  String get healthGlucoseOffConsent =>
      'Turn it on with explicit consent first.';

  @override
  String get healthSetUp => 'Set up';

  @override
  String get healthGlucoseEyebrow => 'Glucose';

  @override
  String get healthGlucoseSubtitle => 'Your readings, as you entered them.';

  @override
  String get healthTimelineWithMeals => 'Timeline with meals';

  @override
  String get healthAddReading => 'Add reading';

  @override
  String get healthReading => 'Reading';

  @override
  String get healthContextFasting => 'Fasting';

  @override
  String get healthContextBeforeMeal => 'Before meal';

  @override
  String get healthContextAfterMeal => 'After meal';

  @override
  String get healthContextBedtime => 'Bedtime';

  @override
  String get healthContextOther => 'Other';

  @override
  String healthDayAtTime(String day, String time) {
    return '$day at $time';
  }

  @override
  String get healthReadings => 'Readings';

  @override
  String get healthNoReadings => 'No readings yet.';

  @override
  String get healthSourceManual => 'entered by you';

  @override
  String get healthSourceHealthApp => 'from Health app';

  @override
  String healthSourceDevice(String device) {
    return 'from $device';
  }

  @override
  String get healthDevice => 'device';

  @override
  String healthEnteredAs(String value) {
    return 'entered as $value';
  }

  @override
  String get healthNoHealthImport =>
      'Reading from Apple Health or Health Connect isn\'t available yet. Chefii never interprets readings.';

  @override
  String get healthGlucoseOffShort => 'Turn it on first.';

  @override
  String get healthTimelineSubtitle =>
      'Meals and readings in order. No interpretation.';

  @override
  String get healthPreviousDay => 'Previous day';

  @override
  String get healthNextDay => 'Next day';

  @override
  String get healthNothingRecorded => 'Nothing recorded';

  @override
  String get healthTimelineEmptyMessage =>
      'Meals and readings for this day will appear here.';

  @override
  String get healthTimelineFooter =>
      'Discuss patterns with your diabetes care team. Chefii does not replace glucose alarms or medical advice.';

  @override
  String get journalNutritionTooltip => 'Nutrition';

  @override
  String get journalMoreTooltip => 'More';

  @override
  String get journalFullHistory => 'Full history';

  @override
  String get journalEatingPatterns => 'Eating patterns';

  @override
  String get journalMealReminders => 'Meal reminders';

  @override
  String get journalEyebrow => 'Journal';

  @override
  String get journalPreviousDay => 'Previous day';

  @override
  String get journalNextDay => 'Next day';

  @override
  String get journalLogAMeal => 'Log a meal';

  @override
  String get journalEmptyTodayTitle => 'Nothing logged yet today';

  @override
  String get journalEmptyTitle => 'Nothing logged';

  @override
  String get journalEmptyMessage =>
      'Meals you cook in Chefii are logged automatically. You can also add anything you ate.';

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
    return 'Repeat $title';
  }

  @override
  String journalLoggedAgain(String title) {
    return 'Logged $title again';
  }

  @override
  String get journalDaySoFar => 'Day so far';

  @override
  String get journalEstimatedIntake => 'Estimated intake';

  @override
  String journalMealCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count meals',
      one: '1 meal',
    );
    return '$_temp0';
  }

  @override
  String get journalHistoryTitle => 'Last 30 days';

  @override
  String get journalHistorySubtitle => 'Tap any meal to correct it.';

  @override
  String get journalHistoryEmptyTitle => 'No history yet';

  @override
  String get journalHistoryEmptyMessage => 'Your meals will build up here.';

  @override
  String get journalEntryNotFoundTitle => 'Entry not found';

  @override
  String get journalEntryNotFoundMessage => 'It may have been deleted.';

  @override
  String get journalDelete => 'Delete';

  @override
  String get journalDeleteTitle => 'Delete this entry?';

  @override
  String get journalDeleteMessage =>
      'This removes it from your journal. Your kitchen isn\'t changed.';

  @override
  String get journalSaveChanges => 'Save changes';

  @override
  String journalDayAtTime(String day, String time) {
    return '$day at $time';
  }

  @override
  String get journalPortions => 'Portions';

  @override
  String get journalEstimated => 'Estimated';

  @override
  String journalForPortions(num count, String portions) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'for $portions portions',
      one: 'for $portions portion',
    );
    return '$_temp0';
  }

  @override
  String get journalViewRecipe => 'View recipe';

  @override
  String get journalQuickTitle => 'What did you eat?';

  @override
  String get journalLogMeal => 'Log meal';

  @override
  String get journalAiFeatureEstimatingMeals => 'estimating meals';

  @override
  String journalMealLogged(String title) {
    return '$title logged';
  }

  @override
  String get journalQuickHint => 'e.g. Greek yogurt with berries';

  @override
  String get journalListening => 'Listening';

  @override
  String get journalSpeak => 'Speak';

  @override
  String get journalVoiceUnavailable =>
      'Voice isn\'t available — try your keyboard\'s dictation.';

  @override
  String get journalAddPhoto => 'Add a photo';

  @override
  String get journalPhotoAdded => 'Photo added';

  @override
  String get journalCameraOff =>
      'Camera access is off. You can still describe the meal.';

  @override
  String get journalEstimateNutrition => 'Estimate nutrition';

  @override
  String get journalSavedRecipe => 'Saved recipe';

  @override
  String get journalDemoEstimate =>
      'Demo estimate from reference data — no AI used.';

  @override
  String get journalDetails => 'Details';

  @override
  String get journalRemindersSubtitle =>
      'Gentle nudges, never nagging. Quiet hours are always respected.';

  @override
  String get journalSaveReminders => 'Save reminders';

  @override
  String get journalNotificationsOff =>
      'Notifications are off for Chefii in Settings.';

  @override
  String journalReminderNotificationTitle(String meal) {
    return '$meal time';
  }

  @override
  String get journalReminderNotificationBody =>
      'A gentle reminder from Chefii.';

  @override
  String get journalRemindersSaved => 'Reminders saved';

  @override
  String journalRemindersSavedSkipped(int count, String meals) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Saved. $meals fall in quiet hours and won\'t notify.',
      one: 'Saved. $meals falls in quiet hours and won\'t notify.',
    );
    return '$_temp0';
  }

  @override
  String get journalReminderOff => 'Off';

  @override
  String get journalQuietHours => 'Quiet hours';

  @override
  String journalQuietHoursRange(String start, String end) {
    return 'No reminders between $start:00 and $end:00.';
  }

  @override
  String journalWakeLabel(String hour) {
    return 'Wake $hour:00';
  }

  @override
  String journalSleepLabel(String hour) {
    return 'Sleep $hour:00';
  }

  @override
  String get journalRemindersFootnote =>
      'Snooze any reminder from the notification itself, or just ignore it — Chefii never repeats.';

  @override
  String get journalPatternsSubtitle => 'The last two weeks, as recorded.';

  @override
  String get journalMealsPerDay => 'meals logged per day';

  @override
  String get journalDaysNoRecords => 'days with no records';

  @override
  String get journalUsualTimes => 'Usual times';

  @override
  String get journalPatternsEmpty => 'Log a few meals to see your rhythm.';

  @override
  String journalWithinHour(int percent) {
    return '$percent% within an hour of your reminder';
  }

  @override
  String journalAround(String time) {
    return 'around $time';
  }

  @override
  String get journalLast14Days => 'Last 14 days';

  @override
  String journalDayMealsSemantics(int count, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$date: $count meals',
      one: '$date: 1 meal',
    );
    return '$_temp0';
  }

  @override
  String get journalPatternsDisclaimer =>
      'Gaps usually mean a meal wasn\'t logged, not that it wasn\'t eaten. Chefii describes your records; it doesn\'t predict blood sugar or judge your habits.';

  @override
  String get kitchenShoppingList => 'Shopping list';

  @override
  String get kitchenTellChefii => 'Tell Chefii';

  @override
  String get kitchenEyebrow => 'Kitchen';

  @override
  String get kitchenMyKitchen => 'My kitchen';

  @override
  String kitchenItemsAcrossPlaces(int count, int places) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items across $places places',
      one: '1 item across $places places',
    );
    return '$_temp0';
  }

  @override
  String get kitchenScanReceipt => 'Scan a receipt';

  @override
  String get kitchenOpening => 'Opening your kitchen…';

  @override
  String get kitchenEmptyTitle => 'Your kitchen is empty';

  @override
  String get kitchenEmptyMessage =>
      'Scan a grocery receipt and Chefii fills it in for you — or add a few things by hand.';

  @override
  String get kitchenAddAnItem => 'Add an item';

  @override
  String get kitchenScanFridgeInstead => 'Scan the fridge instead';

  @override
  String get kitchenUseSoon => 'Use soon';

  @override
  String get kitchenToVerify => 'To verify';

  @override
  String get kitchenStatAdd => 'Add';

  @override
  String get kitchenStatAnItem => 'an item';

  @override
  String kitchenStatSemantics(String label, String value) {
    return '$label: $value';
  }

  @override
  String get kitchenFilterAll => 'All';

  @override
  String get kitchenManagePlaces => 'Manage places';

  @override
  String get kitchenSearchHint => 'Search your kitchen';

  @override
  String get kitchenNoMatchTitle => 'Nothing matches';

  @override
  String get kitchenNoMatchMessage => 'Try a different search or filter.';

  @override
  String get kitchenScanFridge => 'Scan fridge';

  @override
  String get kitchenSpendingWaste => 'Spending & waste';

  @override
  String get kitchenReceipts => 'Receipts';

  @override
  String get kitchenStorageEyebrow => 'Storage';

  @override
  String kitchenConfirmedOfTotal(int confirmed, int total) {
    return '$confirmed of $total confirmed · soonest first';
  }

  @override
  String get kitchenVerifyTheseItems => 'Verify these items';

  @override
  String get kitchenNothingHereTitle => 'Nothing here yet';

  @override
  String kitchenNothingHereMessage(String place) {
    return 'Items you add to $place appear here.';
  }

  @override
  String get kitchenItemNotFoundTitle => 'Item not found';

  @override
  String get kitchenItemNotFoundMessage =>
      'It may have been removed by someone in your household.';

  @override
  String get kitchenMore => 'More';

  @override
  String kitchenDiscardTitle(String name) {
    return 'Discard $name?';
  }

  @override
  String kitchenDiscardMessage(String amount) {
    return 'Records the remaining $amount as food waste.';
  }

  @override
  String get kitchenDiscard => 'Discard';

  @override
  String kitchenMoveTo(String place) {
    return 'Move to $place';
  }

  @override
  String get kitchenUpdateAmount => 'Update amount';

  @override
  String get kitchenRecordedAmount => 'Recorded amount';

  @override
  String get kitchenOriginally => 'Originally';

  @override
  String get kitchenAdded => 'Added';

  @override
  String get kitchenSource => 'Source';

  @override
  String get kitchenSourceReceipt => 'Receipt';

  @override
  String kitchenSourceReceiptLine(String line) {
    return 'Receipt · \"$line\"';
  }

  @override
  String get kitchenSourcePhotoScan => 'Photo scan';

  @override
  String get kitchenSourceBarcode => 'Barcode';

  @override
  String get kitchenSourceLeftover => 'Leftovers you saved';

  @override
  String get kitchenSourceDemo => 'Example ingredient';

  @override
  String get kitchenSourceManual => 'Added by hand';

  @override
  String get kitchenPackage => 'Package';

  @override
  String get kitchenDateOnPackage => 'Date on package';

  @override
  String get kitchenEstimatedQuality => 'Estimated quality';

  @override
  String get kitchenUnknown => 'Unknown';

  @override
  String get kitchenSetDateFromPackage => 'Set date from package';

  @override
  String get kitchenDatePrintedOnPackage => 'Date printed on the package';

  @override
  String get kitchenEstimateWarning =>
      'Our estimate suggests using this soon. Estimates are a guide only — check how it looks and smells, and follow the package date.';

  @override
  String get kitchenRecordedDatePast =>
      'The date you recorded is past. Follow the package guidance; when in doubt, throw it out.';

  @override
  String get kitchenRecordedDateClose =>
      'The date you recorded is close. Follow the package guidance; when in doubt, throw it out.';

  @override
  String get kitchenThisAmountIsRight => 'This amount is right';

  @override
  String get kitchenNutritionReference => 'Nutrition reference';

  @override
  String kitchenPer100g(String source) {
    return 'per 100 g · $source';
  }

  @override
  String get kitchenActivity => 'Activity';

  @override
  String get kitchenNoActivity => 'No activity yet.';

  @override
  String get kitchenNewBarcode =>
      'New barcode — tell us what it is once and we\'ll remember it.';

  @override
  String get kitchenChooseAnItem => 'Choose an item';

  @override
  String get kitchenAddToKitchen => 'Add to kitchen';

  @override
  String get kitchenWhatAreYouAdding => 'What are you adding?';

  @override
  String get kitchenChange => 'Change';

  @override
  String get kitchenScanBarcode => 'Scan barcode';

  @override
  String kitchenBarcodeValue(String code) {
    return 'Barcode $code';
  }

  @override
  String kitchenWillAddNew(String name) {
    return 'We\'ll add \"$name\" as a new item.';
  }

  @override
  String get kitchenHowMuch => 'How much?';

  @override
  String get kitchenWhereDoesItLive => 'Where does it live?';

  @override
  String get kitchenDateOnThePackage => 'Date on the package';

  @override
  String get kitchenAddDateOptional =>
      'Add a best-before or use-by date (optional)';

  @override
  String get kitchenScanABarcode => 'Scan a barcode';

  @override
  String get kitchenPointAtBarcode => 'Point at the barcode on the package';

  @override
  String get kitchenCamera => 'Camera';

  @override
  String get kitchenBarcodeCameraWhy =>
      'Chefii needs the camera to read barcodes. You can still type the item name.';

  @override
  String get kitchenTypeItInstead => 'Type it instead';

  @override
  String get kitchenAiFeatureShelfScan => 'scanning your shelves';

  @override
  String kitchenEnterAmountFor(String name) {
    return 'Enter an amount for $name.';
  }

  @override
  String kitchenScanSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count items from a photo',
      one: 'Added 1 item from a photo',
    );
    return '$_temp0';
  }

  @override
  String get kitchenScanTitle => 'Scan your shelves';

  @override
  String get kitchenScanSubtitle =>
      'We\'ll suggest what we can see. Nothing is added until you confirm it.';

  @override
  String get kitchenTakePhoto => 'Take a photo';

  @override
  String get kitchenSelectItemsToAdd => 'Select items to add';

  @override
  String kitchenAddCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add $count items',
      one: 'Add 1 item',
    );
    return '$_temp0';
  }

  @override
  String get kitchenCameraDeniedWhy =>
      'Allow camera access in Settings to scan, or choose a photo from your library.';

  @override
  String get kitchenChooseFromLibrary => 'Choose from library';

  @override
  String get kitchenOpenFridgeArt => 'Open fridge';

  @override
  String get kitchenScanTips =>
      'Tips: open the door fully, use good light, and take one photo per shelf for best results.';

  @override
  String get kitchenScanDemo =>
      'Demo: sample suggestions — your photo was not analysed.';

  @override
  String get kitchenScanNothingTitle => 'We couldn\'t spot anything';

  @override
  String get kitchenScanNothingMessage =>
      'Try a brighter, closer photo of one shelf.';

  @override
  String kitchenPercentSure(int percent) {
    return '$percent% sure';
  }

  @override
  String get kitchenAmount => 'Amount';

  @override
  String get kitchenEnterAmount => 'Enter amount';

  @override
  String get kitchenTakeAnotherPhoto => 'Take another photo';

  @override
  String get kitchenFreshnessSubtitle =>
      'Things worth cooking, freezing or deciding on.';

  @override
  String get kitchenFindRecipes => 'Find recipes that use these';

  @override
  String get kitchenNothingNeedsAttentionTitle => 'Nothing needs attention';

  @override
  String get kitchenNothingNeedsAttentionMessage =>
      'We\'ll let you know when something should be used soon.';

  @override
  String kitchenDatePassed(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'date passed $days days ago',
      one: 'date passed 1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get kitchenDateIsToday => 'date is today';

  @override
  String kitchenDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String kitchenWithEstimate(String text) {
    return '$text (estimate)';
  }

  @override
  String get kitchenCookWithThis => 'Cook with this';

  @override
  String get kitchenFreeze => 'Freeze';

  @override
  String get kitchenFoodSafety => 'Food safety';

  @override
  String get kitchenFoodSafetyBody =>
      'Chefii\'s dates are estimates from typical storage times, not safety guarantees. Follow \"use by\" and \"best before\" dates on packages, keep your fridge at 4 °C (40 °F) or below, and when in doubt, throw it out. For guidance, see Health Canada\'s food safety pages.';

  @override
  String get kitchenAllSquaredAway => 'All squared away';

  @override
  String get kitchenBackToKitchen => 'Back to kitchen';

  @override
  String kitchenItemsVerified(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items verified',
      one: '1 item verified',
    );
    return '$_temp0';
  }

  @override
  String get kitchenEveryAmountRight => 'Every amount was already right.';

  @override
  String kitchenAmountsCorrected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count amounts were corrected. You can undo from the kitchen.',
      one: '1 amount was corrected. You can undo from the kitchen.',
    );
    return '$_temp0';
  }

  @override
  String get kitchenQuickCheck => 'Quick check';

  @override
  String kitchenQuickCheckSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Adjust anything that\'s off, then confirm. $count items.',
      one: 'Adjust anything that\'s off, then confirm. 1 item.',
    );
    return '$_temp0';
  }

  @override
  String get kitchenConfirmAll => 'Confirm all';

  @override
  String get kitchenEverythingAccurateTitle => 'Everything looks accurate';

  @override
  String get kitchenEverythingAccurateMessage =>
      'Nothing needs checking right now.';

  @override
  String kitchenWasAmount(String amount) {
    return 'was $amount';
  }

  @override
  String get kitchenAlreadyDone => 'Already done — nothing changed.';

  @override
  String kitchenRecorded(String amount) {
    return 'Recorded: $amount';
  }

  @override
  String get kitchenModeUsed => 'Used';

  @override
  String get kitchenModeAdded => 'Added';

  @override
  String get kitchenModeTossed => 'Tossed';

  @override
  String get kitchenModeCount => 'Count';

  @override
  String get kitchenAmountYouHaveNow => 'Amount you have now';

  @override
  String get kitchenCountingConfirms =>
      'Counting confirms this item as accurate.';

  @override
  String kitchenUseAmount(String amount) {
    return 'Use $amount';
  }

  @override
  String kitchenAddAmount(String amount) {
    return 'Add $amount';
  }

  @override
  String kitchenDiscardAmount(String amount) {
    return 'Discard $amount';
  }

  @override
  String kitchenSetToAmount(String amount) {
    return 'Set to $amount';
  }

  @override
  String get kitchenMarkFinished => 'Mark as finished';

  @override
  String get kitchenCommandTryHint =>
      'Try \"I used two eggs\" or \"add 1 kg flour\".';

  @override
  String get kitchenVoiceUnavailable =>
      'Voice isn\'t available. You can type instead — or use your keyboard\'s dictation.';

  @override
  String get kitchenCommandExamples =>
      '\"I used two eggs\" · \"we\'re out of milk\" · \"add 1 kg flour\"';

  @override
  String get kitchenCommandFieldHint => 'What happened in the kitchen?';

  @override
  String get kitchenListening => 'Listening';

  @override
  String get kitchenSpeak => 'Speak';

  @override
  String kitchenCouldNotFind(String query) {
    return 'We couldn\'t find \"$query\"';
  }

  @override
  String get kitchenHereIsWhatWillHappen => 'Here\'s what will happen';

  @override
  String get kitchenTrySimplerName =>
      'Try a simpler name, or add it from the Kitchen tab.';

  @override
  String get kitchenNoAmountSaid =>
      'You didn\'t say how much — check the amount:';

  @override
  String kitchenQuoted(String text) {
    return '\"$text\"';
  }

  @override
  String kitchenCommandMarkEmpty(String what) {
    return 'Mark $what as used up';
  }

  @override
  String kitchenCommandSetCount(String what, String amount) {
    return 'Set $what to $amount';
  }

  @override
  String kitchenCommandAction(String action, String amount, String what) {
    return '$action $amount $what';
  }

  @override
  String get kitchenConfirm => 'Confirm';

  @override
  String get kitchenRenamePlace => 'Rename place';

  @override
  String get kitchenPlacesTitle => 'Places in your kitchen';

  @override
  String get kitchenPlacesSubtitle =>
      'Add spots like a garage freezer or a wine fridge.';

  @override
  String get kitchenBuiltIn => 'Built in';

  @override
  String kitchenKeptLike(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'fridge': 'Kept like a fridge',
      'freezer': 'Kept like a freezer',
      'pantry': 'Kept like a pantry',
      'other': 'Kept like a other',
    });
    return '$_temp0';
  }

  @override
  String kitchenRenameTooltip(String place) {
    return 'Rename $place';
  }

  @override
  String kitchenRemoveTooltip(String place) {
    return 'Remove $place';
  }

  @override
  String kitchenRemovedPlace(String place) {
    return 'Removed $place.';
  }

  @override
  String kitchenAddedPlace(String place) {
    return 'Added $place.';
  }

  @override
  String get kitchenNewPlace => 'New place';

  @override
  String get kitchenNewPlaceHint => 'e.g. Garage freezer';

  @override
  String get kitchenKeptLikeHeader => 'Kept like a…';

  @override
  String get kitchenAddPlace => 'Add place';

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

  @override
  String get tag15Minute => '15 minutes';

  @override
  String get tagHighProtein => 'High protein';

  @override
  String get tagVegan => 'Vegan';

  @override
  String get tagVegetarian => 'Vegetarian';

  @override
  String get tagBatch => 'Batch cooking';

  @override
  String get tagComfort => 'Comfort';

  @override
  String get tagMakeAhead => 'Make ahead';

  @override
  String get tagNoCook => 'No cooking';

  @override
  String get availabilityAllOnHand => 'Everything on hand';

  @override
  String availabilityToBuy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ingredients to buy',
      one: '1 ingredient to buy',
    );
    return '$_temp0';
  }

  @override
  String get morningStepWake => 'Wake';

  @override
  String get morningStepGetReady => 'Get ready';

  @override
  String morningStepMake(String recipe) {
    return 'Make $recipe';
  }

  @override
  String get morningStepEat => 'Eat';

  @override
  String get morningStepTidy => 'Tidy up';

  @override
  String get morningStepLeave => 'Leave';

  @override
  String get morningEyebrow => 'Mornings';

  @override
  String get morningSetupTitle => 'A calmer morning';

  @override
  String get morningSetupSubtitle =>
      'Tell us when you wake and when you leave. We\'ll plan the bit in between.';

  @override
  String get morningOnTheseDays => 'On these days';

  @override
  String get morningWakeUp => 'Wake up';

  @override
  String get morningOutTheDoorBy => 'Out the door by';

  @override
  String morningBufferValue(int minutes) {
    return 'Buffer before leaving: $minutes min';
  }

  @override
  String get morningBuffer => 'Buffer before leaving';

  @override
  String morningMinutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String get morningInvalidTimes =>
      'Your departure time needs to be after your wake time plus the buffer.';

  @override
  String morningTimeLeft(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'That leaves $minutes minutes for getting ready and breakfast.',
    );
    return '$_temp0';
  }

  @override
  String get morningBreakfastStyle => 'Breakfast style';

  @override
  String get morningStyleQuick => 'Quick & simple';

  @override
  String get morningStyleCooked => 'Something warm';

  @override
  String get morningStyleNoCook => 'No cooking';

  @override
  String get morningStyleGrabAndGo => 'Grab and go';

  @override
  String get morningNotificationsOff =>
      'Notifications are off for Chefii. Turn them on in Settings to use alarms.';

  @override
  String get morningAlarmNotificationBody => 'Your morning plan is ready.';

  @override
  String get morningPreviewNotificationTitle => 'Tomorrow\'s breakfast';

  @override
  String get morningPreviewNotificationBody =>
      'Take a look at tomorrow morning\'s plan.';

  @override
  String morningAlarmAt(String time) {
    return 'Alarm at $time';
  }

  @override
  String morningPreviewAt(String time) {
    return 'Evening preview at $time';
  }

  @override
  String get morningAlarmTitle => 'Alarm & reminders';

  @override
  String get morningSaveSchedule => 'Save schedule';

  @override
  String get morningWakeWithChefii => 'Wake me with Chefii';

  @override
  String morningWakeWithChefiiSubtitle(String time) {
    return 'An alarm at $time that opens your morning plan';
  }

  @override
  String get morningEveningPreview => 'Evening preview';

  @override
  String morningEveningPreviewSubtitle(String time) {
    return 'A gentle note at $time with tomorrow\'s breakfast';
  }

  @override
  String get morningPlatformNote =>
      'On Android, Chefii uses a system alarm clock entry. On iPhone, it uses a time-sensitive notification that respects Focus settings; it isn\'t a replacement for the Clock app, so keep a backup alarm for anything critical.';

  @override
  String get morningAllOff => 'All morning notifications are off.';

  @override
  String morningScheduled(String items) {
    return 'Scheduled: $items';
  }

  @override
  String get morningSeeTomorrow => 'See tomorrow\'s plan';

  @override
  String get morningSetUpTitle => 'Set up your mornings';

  @override
  String get morningSetUpMessage =>
      'Chefii can plan breakfast around your wake and leave times.';

  @override
  String get morningSetUp => 'Set up';

  @override
  String get morningPlannedTitle => 'Your morning, planned';

  @override
  String get morningDayOffTitle => 'Tomorrow is a day off';

  @override
  String morningWindow(int minutes, String wake, String leave) {
    return '$minutes minutes from $wake to $leave';
  }

  @override
  String get morningEditRoutine => 'Edit routine';

  @override
  String get morningSoundsGood => 'Sounds good';

  @override
  String get morningBreakfastSet => 'Breakfast is set for tomorrow.';

  @override
  String get morningNoBreakfastFits => 'No breakfast fits';

  @override
  String get morningNoBreakfastFitsMessage =>
      'Try a longer morning or a different breakfast style.';

  @override
  String morningMissing(String items) {
    return 'Missing: $items';
  }

  @override
  String get morningTimeline => 'Timeline';

  @override
  String get morningOrChoose => 'Or choose';

  @override
  String morningItIs(String time) {
    return 'It is $time';
  }

  @override
  String get morningImUp => 'I\'m up';

  @override
  String get morningSnooze => 'Snooze 9 minutes';

  @override
  String get morningSnoozeTitle => 'Time to get up';

  @override
  String get morningSnoozeBody =>
      'Snooze is over. Your morning plan is waiting.';

  @override
  String get morningThisMorning => 'This morning';

  @override
  String get morningTimeToGo => 'Time to go';

  @override
  String morningUntilYouLeave(int minutes) {
    return '$minutes min until you leave';
  }

  @override
  String get morningRunningBehind => 'Running behind? See faster options';

  @override
  String get morningRunningLate => 'I\'m running late';

  @override
  String get morningNoStress => 'No stress';

  @override
  String morningMinutesLeft(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes left',
    );
    return '$_temp0';
  }

  @override
  String get morningWhatStillWorks => 'Here\'s what still works.';

  @override
  String get morningSkipBreakfast => 'Skip breakfast today';

  @override
  String get morningSkipped => 'Skipped. Nothing in your kitchen was changed.';

  @override
  String get morningNoCookNone =>
      'Nothing no-cook fits your kitchen right now.';

  @override
  String get morningTenMinutes => 'Ten minutes or less';

  @override
  String get morningNothingElse => 'Nothing else fits in ten minutes.';

  @override
  String get onboardingSkipForNow => 'Skip for now';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String onboardingStepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get onboardingWelcomeArtLabel => 'A beautifully set kitchen table';

  @override
  String get onboardingWelcomeTitle =>
      'Your kitchen,\nbeautifully taken care of.';

  @override
  String get onboardingWelcomeBody =>
      'Chefii knows what\'s in your kitchen, suggests what to make, guides you through it — and keeps everything in order.';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get onboardingHaveAccount => 'I already have an account';

  @override
  String get onboardingMeetTitle => 'Meet your chef';

  @override
  String get onboardingMeetSubtitle =>
      'Three things Chefii does for you, every day.';

  @override
  String get onboardingBenefitKitchenTitle => 'Knows your kitchen';

  @override
  String get onboardingBenefitKitchenBody =>
      'Scan a receipt and your pantry, fridge and freezer stay up to date — with almost no typing.';

  @override
  String get onboardingBenefitDecideTitle => 'Decides what to make';

  @override
  String get onboardingBenefitDecideBody =>
      'Recipes matched to what you have, how much time you have, and everyone\'s dietary needs.';

  @override
  String get onboardingBenefitGuideTitle => 'Guides you calmly';

  @override
  String get onboardingBenefitGuideBody =>
      'Step-by-step cooking with timers, then one tap to update your kitchen.';

  @override
  String get onboardingTasteHeader => 'A taste';

  @override
  String get onboardingExample => 'Example';

  @override
  String get onboardingConsentRequired =>
      'Please accept the Terms and Privacy Policy to continue.';

  @override
  String get onboardingDefaultName => 'Friend';

  @override
  String get onboardingWelcomeBack => 'Welcome back';

  @override
  String get onboardingSignInSubtitle => 'Sign in to your kitchen.';

  @override
  String get onboardingCreateTitle => 'Create your account';

  @override
  String get onboardingCreateSubtitle =>
      'Your kitchen stays private to you and the people you invite.';

  @override
  String get onboardingSignIn => 'Sign in';

  @override
  String get onboardingCreateAccount => 'Create account';

  @override
  String get onboardingDemoBanner =>
      'Demo mode: your account and data stay on this device only.';

  @override
  String get onboardingDemoAccount => 'Continue with a demo account';

  @override
  String get onboardingContinueApple => 'Continue with Apple';

  @override
  String get onboardingContinueGoogle => 'Continue with Google';

  @override
  String get onboardingOrEmail => 'or with email';

  @override
  String get onboardingFirstNameLabel => 'Your first name';

  @override
  String get onboardingFirstNameError => 'Please tell us what to call you';

  @override
  String get onboardingEmailLabel => 'Email';

  @override
  String get onboardingEmailError => 'Enter a valid email';

  @override
  String get onboardingPasswordLabel => 'Password';

  @override
  String get onboardingPasswordError => 'At least 8 characters';

  @override
  String get onboardingEnterEmailFirst => 'Enter your email first.';

  @override
  String get onboardingResetSent =>
      'If that email has an account, a reset link is on its way.';

  @override
  String get onboardingForgotPassword => 'Forgot password?';

  @override
  String get onboardingConsentLabel =>
      'I agree to the Terms of Service and Privacy Policy';

  @override
  String get onboardingReadThem => 'Read them';

  @override
  String get onboardingSwitchToCreate => 'New here? Create an account';

  @override
  String get onboardingSwitchToSignIn => 'Already have an account? Sign in';

  @override
  String onboardingDefaultHouseholdName(String name) {
    return '$name\'s kitchen';
  }

  @override
  String get onboardingInviteCodeTitle => 'Invite code';

  @override
  String get onboardingInviteCodeHint => 'e.g. 7KQ2M9XA';

  @override
  String get onboardingJoin => 'Join';

  @override
  String get onboardingJoinNeedsOnline =>
      'Joining another household needs the online version of Chefii.';

  @override
  String get onboardingJoinFailed => 'That code didn\'t work.';

  @override
  String get onboardingHouseholdTitle => 'Your household';

  @override
  String get onboardingHouseholdSubtitle =>
      'So portions and planning fit the way you live.';

  @override
  String onboardingOptionSelected(String option) {
    return '$option, selected';
  }

  @override
  String get onboardingPortionsTitle => 'Usual portions per meal';

  @override
  String get onboardingFewerPortions => 'Fewer portions';

  @override
  String get onboardingMorePortions => 'More portions';

  @override
  String get onboardingHouseholdNameLabel => 'Household name (optional)';

  @override
  String get onboardingHouseholdNameHint => 'e.g. The Laurier kitchen';

  @override
  String get onboardingHouseholdPrivacy =>
      'You can invite others to share the kitchen later. Each person\'s health and journal stay private to them.';

  @override
  String get onboardingJoinWithCode => 'Join a household with an invite code';

  @override
  String get onboardingAllergyQuestion => 'Do you have any food allergies?';

  @override
  String get onboardingAllergyNoneKnown => 'None that I know of';

  @override
  String get onboardingAllergyPreferNot => 'Prefer not to say';

  @override
  String get onboardingCrossContactTitle => 'Warn me about cross-contact';

  @override
  String get onboardingCrossContactSubtitle =>
      'Reminders about \"may contain\" labels and shared equipment';

  @override
  String get onboardingNoAllergyAssumption =>
      'We won\'t assume you have no allergies — recipes will remind you to check ingredients.';

  @override
  String get onboardingIntolerances => 'Intolerances';

  @override
  String get onboardingDietaryPattern => 'Dietary pattern';

  @override
  String get onboardingDislikes => 'Foods you\'d rather avoid';

  @override
  String get onboardingAddFoodLabel => 'Add a food (e.g. cilantro)';

  @override
  String get onboardingAdd => 'Add';

  @override
  String get onboardingDietaryNotice =>
      'Chefii screens every recipe against these, but it can\'t see inside packaged foods. Always check labels. Allergies you list are shared with your household only to keep shared meals safe.';

  @override
  String get onboardingDietaryTitle => 'Dietary safety';

  @override
  String get onboardingDietaryEditSubtitle =>
      'Allergies, intolerances and preferences.';

  @override
  String get onboardingDietarySubtitle =>
      'The most important thing we\'ll ask. You can change it any time.';

  @override
  String get onboardingCuisineItalian => 'Italian';

  @override
  String get onboardingCuisineFrench => 'French';

  @override
  String get onboardingCuisineMediterranean => 'Mediterranean';

  @override
  String get onboardingCuisineMiddleEastern => 'Middle Eastern';

  @override
  String get onboardingCuisineIndian => 'Indian';

  @override
  String get onboardingCuisineJapanese => 'Japanese';

  @override
  String get onboardingCuisineChinese => 'Chinese';

  @override
  String get onboardingCuisineThai => 'Thai';

  @override
  String get onboardingCuisineKorean => 'Korean';

  @override
  String get onboardingCuisineMexican => 'Mexican';

  @override
  String get onboardingCuisineGreek => 'Greek';

  @override
  String get onboardingCuisineNordic => 'Nordic';

  @override
  String get onboardingCuisineCanadian => 'Canadian';

  @override
  String get onboardingFoodSalmon => 'Salmon';

  @override
  String get onboardingFoodChicken => 'Chicken';

  @override
  String get onboardingFoodPasta => 'Pasta';

  @override
  String get onboardingFoodEggs => 'Eggs';

  @override
  String get onboardingFoodTofu => 'Tofu';

  @override
  String get onboardingFoodLentils => 'Lentils';

  @override
  String get onboardingFoodVegetables => 'Vegetables';

  @override
  String get onboardingFoodSalads => 'Salads';

  @override
  String get onboardingFoodSoups => 'Soups';

  @override
  String get onboardingFoodRiceBowls => 'Rice bowls';

  @override
  String get onboardingFoodBaking => 'Baking';

  @override
  String get onboardingEquipmentOven => 'Oven';

  @override
  String get onboardingEquipmentStovetop => 'Stovetop';

  @override
  String get onboardingEquipmentAirFryer => 'Air fryer';

  @override
  String get onboardingEquipmentSlowCooker => 'Slow cooker';

  @override
  String get onboardingEquipmentInstantPot => 'Instant Pot';

  @override
  String get onboardingEquipmentBlender => 'Blender';

  @override
  String get onboardingEquipmentMicrowave => 'Microwave';

  @override
  String get onboardingEquipmentGrill => 'Grill';

  @override
  String get onboardingSpiceNone => 'None';

  @override
  String get onboardingSpiceMild => 'Mild';

  @override
  String get onboardingSpiceMedium => 'Medium';

  @override
  String get onboardingSpiceWarm => 'Warm';

  @override
  String get onboardingSpiceHot => 'Hot';

  @override
  String get onboardingCuisinesTitle => 'Cuisines you love';

  @override
  String get onboardingFavouriteFoods => 'Favourite foods';

  @override
  String get onboardingCookingConfidence => 'Cooking confidence';

  @override
  String get onboardingSpice => 'Spice';

  @override
  String get onboardingSpiceLevel => 'Spice level';

  @override
  String onboardingSpiceValue(String level) {
    return 'Spice: $level';
  }

  @override
  String get onboardingWeeknightTime => 'Weeknight time';

  @override
  String get onboardingYourEquipment => 'Your equipment';

  @override
  String get onboardingCulinaryEditTitle => 'Culinary preferences';

  @override
  String get onboardingCulinaryTitle => 'What you love to eat';

  @override
  String get onboardingCulinarySubtitle =>
      'Pick as many or as few as you like.';

  @override
  String get onboardingInterestBalanced => 'Balanced meals';

  @override
  String get onboardingInterestProtein => 'More protein';

  @override
  String get onboardingInterestVariety => 'More variety';

  @override
  String get onboardingInterestPlants => 'More vegetables & plants';

  @override
  String get onboardingInterestEducation => 'Learn about nutrition';

  @override
  String get onboardingWellnessQuestion => 'Anything you\'d like help with?';

  @override
  String get onboardingShowNutritionTitle => 'Show nutrition on recipes';

  @override
  String get onboardingShowNutritionSubtitle =>
      'Estimated protein, fibre and more';

  @override
  String get onboardingTrackCaloriesTitle => 'Track calories';

  @override
  String get onboardingTrackCaloriesSubtitle =>
      'Off by default. Chefii never sets targets for you.';

  @override
  String get onboardingSmileTitle => 'Smile & Food';

  @override
  String get onboardingSmileSubtitle =>
      'Education about sugar and acid exposure for your teeth';

  @override
  String get onboardingWellnessDisclaimer =>
      'Chefii offers food and nutrition education. It isn\'t medical advice and doesn\'t diagnose or treat any condition.';

  @override
  String get onboardingWellnessEditTitle => 'Wellness preferences';

  @override
  String get onboardingWellnessTitle => 'Wellness, your way';

  @override
  String get onboardingWellnessSubtitle =>
      'Entirely optional — and never about guilt.';

  @override
  String get onboardingKitchenTitle => 'Build your kitchen';

  @override
  String get onboardingKitchenSubtitle =>
      'The fastest way is your last grocery receipt.';

  @override
  String get onboardingKitchenLater => 'I\'ll do this later';

  @override
  String onboardingOptionSemantics(String title, String body) {
    return '$title. $body';
  }

  @override
  String get onboardingScanReceiptTitle => 'Scan a receipt';

  @override
  String get onboardingScanReceiptBody =>
      'Everything you bought, in about a minute';

  @override
  String get onboardingScanFridgeTitle => 'Scan your fridge or pantry';

  @override
  String get onboardingScanFridgeBody => 'Confirm what we spot';

  @override
  String get onboardingAddManualTitle => 'Add items manually';

  @override
  String get onboardingAddManualBody => 'Search, scan a barcode or speak';

  @override
  String get onboardingExampleKitchenTitle => 'Start with example ingredients';

  @override
  String get onboardingExampleKitchenBody =>
      'Explore Chefii with a sample kitchen';

  @override
  String get planningEyebrow => 'Plan';

  @override
  String get planningWeekTitle => 'Your week';

  @override
  String get planningPreviousWeek => 'Previous week';

  @override
  String get planningNextWeek => 'Next week';

  @override
  String get planningLeftoversBatch => 'Leftovers & batch cooking';

  @override
  String get planningBuildShoppingList => 'Build shopping list';

  @override
  String get planningHaveEverything => 'You have everything this week needs.';

  @override
  String planningItemsAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items added to your list',
      one: '1 item added to your list',
    );
    return '$_temp0';
  }

  @override
  String planningDayToday(String day) {
    return '$day · today';
  }

  @override
  String get planningAdd => 'Add';

  @override
  String get planningOptions => 'Options';

  @override
  String get planningOpenRecipe => 'Open recipe';

  @override
  String get planningAddToPlanTitle => 'Add to your plan';

  @override
  String get planningChooseRecipe => 'Choose a recipe';

  @override
  String planningPlanMeal(String day, String meal) {
    return 'Plan $day $meal';
  }

  @override
  String planningPlanned(String title) {
    return '$title planned';
  }

  @override
  String get planningChangeRecipe => 'Change recipe';

  @override
  String planningToBuy(String items) {
    return 'To buy: $items';
  }

  @override
  String get planningSearchRecipes => 'Search recipes';

  @override
  String get planningLeftoversSubtitle => 'Cook once, eat well all week.';

  @override
  String get planningInYourFridge => 'In your fridge';

  @override
  String get planningNoLeftovers =>
      'No saved leftovers. When you finish cooking, Chefii can save extra portions here.';

  @override
  String planningLeftoverPortions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count portions',
      one: '1 portion',
    );
    return '$_temp0';
  }

  @override
  String planningMadeOn(String day) {
    return 'made $day';
  }

  @override
  String planningEatWithin(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'eat within ~$count days',
      one: 'eat within ~1 day',
    );
    return '$_temp0';
  }

  @override
  String get planningEatPortion => 'Eat a portion';

  @override
  String get planningFreeze => 'Freeze';

  @override
  String get planningItemDetails => 'Item details';

  @override
  String get planningGoodForBatch => 'Good for batch cooking';

  @override
  String planningLeftoversEntryTitle(String name) {
    return '$name (leftovers)';
  }

  @override
  String get planningKitchenEyebrow => 'Kitchen';

  @override
  String get planningShoppingTitle => 'Shopping list';

  @override
  String planningToBuyCount(int count) {
    return '$count to buy';
  }

  @override
  String planningPutAway(int count) {
    return 'Put $count away in kitchen';
  }

  @override
  String get planningAddAmountsFirst =>
      'Add amounts to checked items first, or scan your receipt instead.';

  @override
  String get planningAddItemHint => 'Add an item';

  @override
  String get planningFromMealPlan => 'From meal plan';

  @override
  String get planningClearChecked => 'Clear checked';

  @override
  String get planningListEmptyTitle => 'Your list is empty';

  @override
  String get planningListEmptyMessage =>
      'Plan a few meals and Chefii will add exactly what\'s missing.';

  @override
  String get planningInBasket => 'In the basket';

  @override
  String get planningAfterShopping =>
      'After shopping, scan your receipt for exact amounts and prices — or put checked items away now.';

  @override
  String planningForRecipes(String titles) {
    return 'for $titles';
  }

  @override
  String get planningRunningLow => 'running low';

  @override
  String get planningDetails => 'Details';

  @override
  String get planningItemRemovedTitle => 'Item removed';

  @override
  String get planningItemRemovedMessage =>
      'It may have been bought or removed.';

  @override
  String get planningPortions => 'Portions';

  @override
  String get planningQuantity => 'Quantity';

  @override
  String get planningPreferredProduct => 'Preferred brand or product';

  @override
  String get planningExpectedPrice => 'Expected price (\$)';

  @override
  String planningLastPaid(String price) {
    return 'Last paid $price on a scanned receipt';
  }

  @override
  String get planningNote => 'Note';

  @override
  String get planningAlternatives => 'Alternatives';

  @override
  String get planningNeededFor => 'Needed for';

  @override
  String get planningSpendingTitle => 'Spending & waste';

  @override
  String get planningGroceriesThisMonth => 'groceries this month';

  @override
  String get planningItemsDiscarded => 'items discarded recently';

  @override
  String get planningLastSixWeeks => 'Last six weeks';

  @override
  String get planningScanReceiptsEmpty =>
      'Scan receipts to see spending trends.';

  @override
  String get planningThisWeek => 'This week';

  @override
  String planningWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks ago',
      one: '1 week ago',
    );
    return '$_temp0';
  }

  @override
  String planningWeeksAgoShort(int count) {
    return '$count wk ago';
  }

  @override
  String planningWeekAmount(String week, String amount) {
    return '$week: $amount';
  }

  @override
  String get planningRecentlyDiscarded => 'Recently discarded';

  @override
  String get planningNothingDiscarded => 'Nothing thrown out recently. Lovely.';

  @override
  String get planningSpendingFootnote =>
      'Spending comes from scanned receipts only. Waste counts items you marked as discarded.';

  @override
  String get prosEyebrow => 'Professionals';

  @override
  String get prosCircleTitle => 'My nutrition circle';

  @override
  String get prosCircleSubtitle =>
      'Share exactly what you choose, for as long as you choose, with verified dietitians and dental professionals.';

  @override
  String get prosInvite => 'Invite a professional';

  @override
  String get prosCodeHint => 'Their Chefii code';

  @override
  String get prosFind => 'Find';

  @override
  String get prosNoMatch =>
      'No verified professional has that code. Check it with them.';

  @override
  String get prosDemoSample => 'Demo: use a sample dietitian';

  @override
  String get prosWhoCanSee => 'Who can see what';

  @override
  String get prosNothingShared =>
      'You haven\'t shared anything. Nothing is visible to anyone.';

  @override
  String prosGrantUntil(String categories, String date) {
    return '$categories\nUntil $date';
  }

  @override
  String prosRevokedOn(String date) {
    return 'Access revoked $date';
  }

  @override
  String get prosRevoked => 'Access revoked';

  @override
  String get prosExpired => 'Access expired';

  @override
  String get prosActive => 'Active';

  @override
  String get prosEnded => 'Ended';

  @override
  String get prosReviews => 'Reviews';

  @override
  String get prosReadOnlyNote =>
      'Professionals see read-only copies of what you share. They can\'t change your meals, kitchen or plans.';

  @override
  String prosCredentialsVerified(String body, String number) {
    return '$body · #$number · verified';
  }

  @override
  String prosCredentialsNotVerified(String body, String number) {
    return '$body · #$number · not verified';
  }

  @override
  String get prosUpdateSharing => 'Update sharing';

  @override
  String prosShareWith(String name) {
    return 'Share with $name';
  }

  @override
  String prosShareWithQuestion(String name) {
    return 'Share with $name?';
  }

  @override
  String prosShareConfirm(String categories, int days, String date) {
    return '$categories from the last $days days, until $date. You can revoke any time.';
  }

  @override
  String get prosShare => 'Share';

  @override
  String prosSharedWith(String name) {
    return 'Shared with $name';
  }

  @override
  String get prosWhatToShare => 'What to share';

  @override
  String get prosHowFarBack => 'How far back';

  @override
  String get prosOneYear => '1 year';

  @override
  String prosDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get prosAccessEndsAfter => 'Access ends after';

  @override
  String get prosRevokeNow => 'Revoke access now';

  @override
  String get prosRevokeQuestion => 'Revoke access?';

  @override
  String prosRevokeMessage(String name) {
    return '$name will immediately lose access to everything you shared.';
  }

  @override
  String get prosRevoke => 'Revoke';

  @override
  String get prosAccessHistory => 'Access history';

  @override
  String prosNotViewedYet(String name) {
    return '$name hasn\'t viewed anything yet.';
  }

  @override
  String prosViewed(String what) {
    return 'Viewed $what';
  }

  @override
  String get prosProfessionalReview => 'Professional review';

  @override
  String get prosAcceptRecommendations => 'Accept recommendations';

  @override
  String get prosRecommendations => 'Recommendations';

  @override
  String get prosAcceptNote =>
      'Accepting keeps these on your profile. Nothing in your plan or kitchen changes unless you change it.';

  @override
  String get prosDecline => 'Decline';

  @override
  String get prosOpenPlanner => 'Open meal planner';

  @override
  String get prosPortal => 'Professional portal';

  @override
  String get prosVerificationPending => 'Verification pending';

  @override
  String prosVerificationPendingBody(String body) {
    return 'We\'re confirming your registration with $body. You\'ll be able to see clients\' shared records once verified.';
  }

  @override
  String get prosDemoVerify => 'Demo: simulate verification';

  @override
  String get prosClients => 'Clients';

  @override
  String prosClientCode(String code) {
    return 'Your client code: $code';
  }

  @override
  String get prosNoClients => 'No active clients';

  @override
  String get prosNoClientsMessage =>
      'Clients who share with you appear here while their access is active.';

  @override
  String prosClientAccessUntil(String categories, String date) {
    return '$categories\nAccess until $date';
  }

  @override
  String get prosRecordsNote =>
      'Records are read-only and every view is logged for your client to see.';

  @override
  String get prosJoinTitle => 'Join as a professional';

  @override
  String get prosJoinSubtitle =>
      'For regulated health professionals. We verify every registration.';

  @override
  String get prosSubmit => 'Submit for verification';

  @override
  String get prosProfession => 'Profession';

  @override
  String get prosRegulatoryCollege => 'Regulatory college';

  @override
  String get prosRegulatoryCollegeHint =>
      'e.g. College of Dietitians of Ontario';

  @override
  String get prosRegistrationNumber => 'Registration number';

  @override
  String get prosProvince => 'Province';

  @override
  String get prosAccessEnded => 'Access has ended';

  @override
  String get prosAccessEndedMessage =>
      'This client\'s sharing has expired or been revoked.';

  @override
  String get prosClient => 'Client';

  @override
  String prosSharedSince(String date) {
    return 'Shared since $date · read-only';
  }

  @override
  String get prosWriteAssessment => 'Write assessment';

  @override
  String get prosChooseCategory => 'Choose a category to view.';

  @override
  String get prosNoRecords => 'No records in the shared range.';

  @override
  String prosRecordMeal(String title, String meal, String portions) {
    return '$title · $meal · $portions portion(s)';
  }

  @override
  String prosRecordMealKcal(
    String title,
    String meal,
    String portions,
    String kcal,
  ) {
    return '$title · $meal · $portions portion(s) · ≈ $kcal kcal';
  }

  @override
  String prosRecordGlucose(String value, String context) {
    return '$value mmol/L · $context';
  }

  @override
  String prosGlucoseContext(String context) {
    String _temp0 = intl.Intl.selectLogic(context, {'other': '$context'});
    return '$_temp0';
  }

  @override
  String prosRecordConcern(String area, String description, String severity) {
    return '$area: $description ($severity/5)';
  }

  @override
  String prosConcernArea(String area) {
    String _temp0 = intl.Intl.selectLogic(area, {'other': '$area'});
    return '$_temp0';
  }

  @override
  String prosRecordDietary(String allergies, String restrictions) {
    return 'Allergies: $allergies · Restrictions: $restrictions';
  }

  @override
  String get prosAssessment => 'Assessment';

  @override
  String prosReviewing(String date) {
    return 'Reviewing $date – today';
  }

  @override
  String get prosShareWithClient => 'Share with client';

  @override
  String get prosSummary => 'Summary';

  @override
  String get prosAddRecommendation => 'Add a recommendation';

  @override
  String get prosAdd => 'Add';

  @override
  String prosSignedNote(String name, String kind) {
    return 'Your client must accept before anything changes. Signed as $name, $kind.';
  }

  @override
  String get prosSaveDraft => 'Save as draft';

  @override
  String get prosDraftSaved => 'Draft saved';

  @override
  String get receiptsEyebrow => 'Receipt';

  @override
  String get receiptsCaptureTitle => 'Scan a receipt';

  @override
  String get receiptsCaptureSubtitle =>
      'Lay it flat in good light. Long receipts can be captured in a few pages.';

  @override
  String get receiptsScanReceipt => 'Scan receipt';

  @override
  String get receiptsTakePhoto => 'Take a photo';

  @override
  String get receiptsDemoCapture =>
      'Demo mode: any photo works — we\'ll show a labelled sample receipt instead of reading it.';

  @override
  String get receiptsCameraPermission => 'Camera';

  @override
  String get receiptsCameraWhy =>
      'Allow camera access in Settings to scan receipts, or import a photo you already took.';

  @override
  String get receiptsImportPhoto => 'Import a photo';

  @override
  String get receiptsArtworkLabel => 'Receipt on a kitchen counter';

  @override
  String get receiptsTipLight =>
      'Bright, even light — avoid shadows across the paper';

  @override
  String get receiptsTipFrame =>
      'Include the store name at the top and the total at the bottom';

  @override
  String get receiptsTipPages =>
      'For long receipts, capture each section as its own page';

  @override
  String get receiptsTipPrivacy =>
      'Photos are stored privately for your household and used only to read your purchases';

  @override
  String get receiptsRegularCamera => 'Use the regular camera';

  @override
  String get receiptsImportFromPhotos => 'Import from photos';

  @override
  String get receiptsAiFeature => 'reading receipts';

  @override
  String get receiptsPreviewTitle => 'Check your photo';

  @override
  String receiptsPreviewSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0. Make sure the text is sharp.';
  }

  @override
  String get receiptsAnalyze => 'Analyze receipt';

  @override
  String get receiptsNoPagesTitle => 'No pages yet';

  @override
  String get receiptsNoPagesMessage => 'Capture your receipt to continue.';

  @override
  String get receiptsCapture => 'Capture';

  @override
  String receiptsPageSemantics(int number) {
    return 'Receipt page $number';
  }

  @override
  String receiptsPageLabel(int number) {
    return 'Page $number';
  }

  @override
  String get receiptsRotate => 'Rotate';

  @override
  String get receiptsRetake => 'Retake';

  @override
  String get receiptsRemovePage => 'Remove page';

  @override
  String get receiptsAddPage => 'Add another page';

  @override
  String get receiptsStepUploading => 'Uploading securely';

  @override
  String get receiptsStepReading => 'Reading every line';

  @override
  String get receiptsStepChecking => 'Checking totals and duplicates';

  @override
  String get receiptsStepMatching => 'Matching to your kitchen';

  @override
  String get receiptsProcessingTitle => 'Reading your receipt';

  @override
  String get receiptsProcessingSubtitle =>
      'This usually takes under a minute. You can leave — we\'ll keep going.';

  @override
  String receiptsProgressSemantics(int percent) {
    return 'Progress $percent percent';
  }

  @override
  String get receiptsContinueBackground => 'Continue in the background';

  @override
  String get receiptsNotFound => 'Receipt not found.';

  @override
  String get receiptsAlreadyInKitchenTitle => 'Already in your kitchen';

  @override
  String get receiptsAlreadyImportedMessage => 'This receipt was imported.';

  @override
  String get receiptsSeeSummary => 'See summary';

  @override
  String get receiptsReviewTitle => 'Review purchases';

  @override
  String receiptsReviewSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String receiptsReviewSubtitleToCheck(int count, int review) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0 · $review to check';
  }

  @override
  String receiptsResolveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Resolve $count items',
      one: 'Resolve 1 item',
    );
    return '$_temp0';
  }

  @override
  String get receiptsDemoReview =>
      'Demo: this is a built-in sample receipt, not your photo.';

  @override
  String get receiptsTotalsMatch => 'Items add up to the receipt subtotal.';

  @override
  String receiptsTotalsMatchWithTotal(String total) {
    return 'Items add up to the receipt subtotal · total $total.';
  }

  @override
  String receiptsTotalsMismatch(String linesTotal, String subtotal) {
    return 'Items add up to $linesTotal but the subtotal reads $subtotal. A line may be missing — you can add it.';
  }

  @override
  String get receiptsAddMissingItem => 'Add a missing item';

  @override
  String get receiptsUnknownItem => 'Unknown item';

  @override
  String get receiptsAmountNeeded => 'Amount needed';

  @override
  String get receiptsNotFood => 'Not food';

  @override
  String get receiptsChecked => 'Checked';

  @override
  String get receiptsPleaseCheck => 'Please check';

  @override
  String get receiptsExcludedSemantics => 'Excluded. Tap to include';

  @override
  String get receiptsIncludedSemantics => 'Included. Tap to exclude';

  @override
  String get receiptsAddedByYou => '(added by you)';

  @override
  String get receiptsAddItemTitle => 'Add an item';

  @override
  String get receiptsCorrectItemTitle => 'Correct item';

  @override
  String receiptsReceiptSays(String text) {
    return 'Receipt says: $text';
  }

  @override
  String get receiptsIsFood => 'This is food';

  @override
  String get receiptsIsFoodSubtitle =>
      'Non-food purchases are not added to your kitchen';

  @override
  String get receiptsProductName => 'Product name';

  @override
  String get receiptsBrandOptional => 'Brand (optional)';

  @override
  String get receiptsPackageOptional => 'Package size (optional)';

  @override
  String get receiptsPackageHint => 'e.g. 750 g tub';

  @override
  String get receiptsQuantity => 'Quantity';

  @override
  String get receiptsCategory => 'Category';

  @override
  String get receiptsStoreIn => 'Store in';

  @override
  String get receiptsUnknownTitle => 'A few to check';

  @override
  String get receiptsAllResolved => 'All resolved.';

  @override
  String get receiptsUnknownSubtitle =>
      'Tell us what these are, or leave them out.';

  @override
  String receiptsStillNeedNameAmount(int count) {
    return '$count still need a name and amount';
  }

  @override
  String get receiptsNothingLeftTitle => 'Nothing left to check';

  @override
  String get receiptsNothingLeftMessage =>
      'Everything has a name and an amount.';

  @override
  String get receiptsCouldntTell => 'We couldn\'t tell what this is';

  @override
  String receiptsLooksLikeUnknownAmount(String name) {
    return 'Looks like: $name (amount unknown)';
  }

  @override
  String receiptsLooksLikeWithAmount(String name, String quantity) {
    return 'Looks like: $name · $quantity';
  }

  @override
  String get receiptsFix => 'Fix';

  @override
  String get receiptsLooksRight => 'Looks right';

  @override
  String get receiptsLeaveOut => 'Leave out';

  @override
  String get receiptsStorageTitle => 'Where does it go?';

  @override
  String get receiptsStorageSubtitle =>
      'We\'ve suggested a spot for each. Tap to change.';

  @override
  String receiptsAddToKitchen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add $count items to kitchen',
      one: 'Add 1 item to kitchen',
    );
    return '$_temp0';
  }

  @override
  String get receiptsChangeStorage => 'Change storage';

  @override
  String get receiptsDuplicateTitle => 'Already scanned?';

  @override
  String get receiptsViewEarlier => 'View the earlier receipt';

  @override
  String get receiptsDuplicateHeadline =>
      'This looks like a receipt you\'ve already added';

  @override
  String get receiptsDuplicateMessage =>
      'To avoid counting groceries twice, we stopped here.';

  @override
  String receiptsDuplicateMessageWithDate(String date) {
    return 'To avoid counting groceries twice, we stopped here. Earlier scan: $date.';
  }

  @override
  String get receiptsDifferentReceipt => 'It\'s a different receipt — continue';

  @override
  String get receiptsErrorTitle => 'We couldn\'t read that one';

  @override
  String get receiptsRetakePhoto => 'Retake photo';

  @override
  String get receiptsSomethingWrong => 'Something went wrong';

  @override
  String get receiptsQualityMessage =>
      'The photo may be blurry, too dark or cut off. Lay the receipt flat in bright light and include the whole thing.';

  @override
  String get receiptsSafeRetry =>
      'Nothing was added to your kitchen, so it\'s safe to retry.';

  @override
  String get receiptsAddByHand => 'Add items by hand instead';

  @override
  String get receiptsDoneTitle => 'Your kitchen is up to date';

  @override
  String get receiptsViewKitchen => 'View kitchen';

  @override
  String receiptsMetricAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'items added',
    );
    return '$_temp0';
  }

  @override
  String receiptsMetricLeftOut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'left out',
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
          '$count items are marked as estimated. Chefii will ask you to confirm next time you\'re in the kitchen.',
      one: '1 item is marked as estimated. Chefii will ask you to confirm next time you\'re in the kitchen.',
    );
    return '$_temp0';
  }

  @override
  String get receiptsUndoImportButton => 'Undo this import';

  @override
  String get receiptsUndoImportTitle => 'Undo import?';

  @override
  String get receiptsUndoImportMessage =>
      'Removes these items from your kitchen. Anything already used stays recorded.';

  @override
  String get receiptsUndoImportConfirm => 'Undo import';

  @override
  String get receiptsScanAnother => 'Scan another receipt';

  @override
  String get receiptsListEyebrow => 'Kitchen';

  @override
  String get receiptsListTitle => 'Receipts';

  @override
  String get receiptsListEmptyTitle => 'No receipts yet';

  @override
  String get receiptsListEmptyMessage => 'Scanned receipts appear here.';

  @override
  String sharedAiConsentTitle(String feature) {
    return 'Use AI for $feature?';
  }

  @override
  String get sharedAiConsentMessage =>
      'To do this, Chefii sends the photo or text to its AI provider (Google Gemini) through our secure servers in Canada. It isn\'t used to train their models under our agreements, and you can turn this off any time in Privacy & data.';

  @override
  String get sharedAiConsentAllow => 'Allow';

  @override
  String get sharedAiConsentNotNow => 'Not now';

  @override
  String get sharedTakePhoto => 'Take a photo';

  @override
  String get sharedChooseFromLibrary => 'Choose from library';

  @override
  String get todayNotifications => 'Notifications';

  @override
  String todayUnreadNotifications(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread notifications',
      one: '1 unread notification',
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
  String get todayScanReceipt => 'Scan a receipt';

  @override
  String get todayStartCooking => 'Start cooking';

  @override
  String get todayReceiptReady => 'Your receipt is ready to review';

  @override
  String get todayReceiptReading => 'Reading your receipt…';

  @override
  String todayPlannedFor(String mealType, String meal) {
    String _temp0 = intl.Intl.selectLogic(mealType, {
      'other': 'Planned for $meal',
    });
    return '$_temp0';
  }

  @override
  String todayFor(String mealType, String meal) {
    String _temp0 = intl.Intl.selectLogic(mealType, {'other': 'For $meal'});
    return '$_temp0';
  }

  @override
  String todayMinutesChip(int minutes) {
    return '$minutes min';
  }

  @override
  String get todayUsesExpiring => 'Uses ingredients that need eating soon.';

  @override
  String todayNothingFits(int minutes) {
    return 'Nothing fits in $minutes minutes';
  }

  @override
  String get todayNothingFitsMessage =>
      'Try more time, or ask your chef for an idea.';

  @override
  String get todayAskChef => 'Ask the chef';

  @override
  String get todayDailyBriefing => 'Daily briefing';

  @override
  String get todayYourKitchen => 'Your kitchen';

  @override
  String get todayTileItems => 'items';

  @override
  String get todayTileUseSoon => 'use soon';

  @override
  String get todayTileToVerify => 'to verify';

  @override
  String get todayScan => 'Scan';

  @override
  String get todayIUsed => 'I used…';

  @override
  String get todayReminders => 'Reminders';

  @override
  String todayUseSoon(String name) {
    return 'Use $name soon';
  }

  @override
  String get todayEstimatedFromPurchase => 'Estimated from purchase date';

  @override
  String todayRecordedDate(String date) {
    return 'Recorded date $date';
  }

  @override
  String todayRunningLow(String name) {
    return 'Running low on $name';
  }

  @override
  String todayAddedToShopping(String name) {
    return '$name added to your shopping list';
  }

  @override
  String get todayAddToList => 'Add to list';

  @override
  String todayAvailability(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ingredients to buy',
      one: '1 ingredient to buy',
      zero: 'Everything on hand',
    );
    return '$_temp0';
  }

  @override
  String todayPrepStart(String recipe, String duration) {
    return 'Start $recipe ($duration)';
  }

  @override
  String get todayYourDayInFood => 'Your day in food';

  @override
  String get todayPlanMeals => 'Plan today\'s meals';

  @override
  String get todayMeals => 'Meals';

  @override
  String get todayNothingPlanned =>
      'Nothing planned yet — Today will suggest something at each meal.';

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
  String get todayPreparation => 'Preparation';

  @override
  String todayAround(String time) {
    return 'around $time';
  }

  @override
  String get todayKitchenAlerts => 'Kitchen alerts';

  @override
  String get todayNothingUrgent => 'Nothing urgent.';

  @override
  String todayUseTodayIfYouCan(String quantity) {
    return '$quantity · use today if you can';
  }

  @override
  String get todayTomorrowMorning => 'Tomorrow morning';

  @override
  String get todayMarkAllRead => 'Mark all read';

  @override
  String get todayAllCaughtUp => 'You\'re all caught up';

  @override
  String get todayAllCaughtUpMessage =>
      'Receipt results, sharing invitations and reviews will appear here.';
}
