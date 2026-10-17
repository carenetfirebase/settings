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

  /// No description provided for @accountEyebrow.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get accountEyebrow;

  /// No description provided for @accountTitleFallback.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get accountTitleFallback;

  /// No description provided for @accountEditName.
  ///
  /// In en, this message translates to:
  /// **'Edit name'**
  String get accountEditName;

  /// No description provided for @accountYourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get accountYourName;

  /// No description provided for @accountSectionPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get accountSectionPreferences;

  /// No description provided for @accountDietarySafety.
  ///
  /// In en, this message translates to:
  /// **'Dietary safety'**
  String get accountDietarySafety;

  /// No description provided for @accountNoAllergies.
  ///
  /// In en, this message translates to:
  /// **'No allergies recorded'**
  String get accountNoAllergies;

  /// No description provided for @accountNotProvidedYet.
  ///
  /// In en, this message translates to:
  /// **'Not provided yet'**
  String get accountNotProvidedYet;

  /// No description provided for @accountCulinaryPreferences.
  ///
  /// In en, this message translates to:
  /// **'Culinary preferences'**
  String get accountCulinaryPreferences;

  /// No description provided for @accountWellnessPreferences.
  ///
  /// In en, this message translates to:
  /// **'Wellness preferences'**
  String get accountWellnessPreferences;

  /// No description provided for @accountMorningRoutine.
  ///
  /// In en, this message translates to:
  /// **'Morning routine'**
  String get accountMorningRoutine;

  /// No description provided for @accountMealReminders.
  ///
  /// In en, this message translates to:
  /// **'Meal reminders'**
  String get accountMealReminders;

  /// No description provided for @accountSectionHealth.
  ///
  /// In en, this message translates to:
  /// **'Health & nutrition'**
  String get accountSectionHealth;

  /// No description provided for @accountNutrition.
  ///
  /// In en, this message translates to:
  /// **'Nutrition'**
  String get accountNutrition;

  /// No description provided for @accountNutritionInsights.
  ///
  /// In en, this message translates to:
  /// **'Nutrition insights'**
  String get accountNutritionInsights;

  /// No description provided for @accountSmileAndFood.
  ///
  /// In en, this message translates to:
  /// **'Smile & Food'**
  String get accountSmileAndFood;

  /// No description provided for @accountGlucoseJournal.
  ///
  /// In en, this message translates to:
  /// **'Glucose journal'**
  String get accountGlucoseJournal;

  /// No description provided for @accountOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get accountOptional;

  /// No description provided for @accountNutritionCircle.
  ///
  /// In en, this message translates to:
  /// **'My nutrition circle'**
  String get accountNutritionCircle;

  /// No description provided for @accountSectionHousehold.
  ///
  /// In en, this message translates to:
  /// **'Household & account'**
  String get accountSectionHousehold;

  /// No description provided for @accountHouseholdMembers.
  ///
  /// In en, this message translates to:
  /// **'Household members'**
  String get accountHouseholdMembers;

  /// No description provided for @accountPrivacyData.
  ///
  /// In en, this message translates to:
  /// **'Privacy & data'**
  String get accountPrivacyData;

  /// No description provided for @accountConnectedServices.
  ///
  /// In en, this message translates to:
  /// **'Connected services'**
  String get accountConnectedServices;

  /// No description provided for @accountMembership.
  ///
  /// In en, this message translates to:
  /// **'Membership'**
  String get accountMembership;

  /// No description provided for @accountAccessibilityLanguage.
  ///
  /// In en, this message translates to:
  /// **'Accessibility & language'**
  String get accountAccessibilityLanguage;

  /// No description provided for @accountSecuritySessions.
  ///
  /// In en, this message translates to:
  /// **'Security & sessions'**
  String get accountSecuritySessions;

  /// No description provided for @accountHelpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get accountHelpSupport;

  /// No description provided for @accountLegalEvidence.
  ///
  /// In en, this message translates to:
  /// **'Legal & evidence'**
  String get accountLegalEvidence;

  /// No description provided for @accountExportOrDelete.
  ///
  /// In en, this message translates to:
  /// **'Export or delete your data'**
  String get accountExportOrDelete;

  /// No description provided for @accountProPortal.
  ///
  /// In en, this message translates to:
  /// **'Professional portal'**
  String get accountProPortal;

  /// No description provided for @accountSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get accountSignOut;

  /// No description provided for @accountFooterDemo.
  ///
  /// In en, this message translates to:
  /// **'Chefii · Demo mode'**
  String get accountFooterDemo;

  /// No description provided for @accountFooterEarlyAccess.
  ///
  /// In en, this message translates to:
  /// **'Chefii · Early access'**
  String get accountFooterEarlyAccess;

  /// No description provided for @accountHousehold.
  ///
  /// In en, this message translates to:
  /// **'Household'**
  String get accountHousehold;

  /// No description provided for @accountUsualPortions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count} usual portions}}'**
  String accountUsualPortions(int count);

  /// No description provided for @accountInviteSomeone.
  ///
  /// In en, this message translates to:
  /// **'Invite someone'**
  String get accountInviteSomeone;

  /// No description provided for @accountInviteShareText.
  ///
  /// In en, this message translates to:
  /// **'Join our kitchen on Chefii with code {code} (valid for 7 days).'**
  String accountInviteShareText(String code);

  /// No description provided for @accountInviteShareSubject.
  ///
  /// In en, this message translates to:
  /// **'Join my Chefii kitchen'**
  String get accountInviteShareSubject;

  /// No description provided for @accountMemberYou.
  ///
  /// In en, this message translates to:
  /// **'{name} (you)'**
  String accountMemberYou(String name);

  /// No description provided for @accountMemberSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{role} · since {date}'**
  String accountMemberSubtitle(String role, String date);

  /// No description provided for @accountRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get accountRoleOwner;

  /// No description provided for @accountRoleAdult.
  ///
  /// In en, this message translates to:
  /// **'Adult'**
  String get accountRoleAdult;

  /// No description provided for @accountRoleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get accountRoleMember;

  /// No description provided for @accountRemoveMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String accountRemoveMemberTitle(String name);

  /// No description provided for @accountRemoveMemberMessage.
  ///
  /// In en, this message translates to:
  /// **'They\'ll lose access to the shared kitchen. Their private journal stays theirs.'**
  String get accountRemoveMemberMessage;

  /// No description provided for @accountOpenInvitations.
  ///
  /// In en, this message translates to:
  /// **'Open invitations'**
  String get accountOpenInvitations;

  /// No description provided for @accountInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Code {code}'**
  String accountInviteCode(String code);

  /// No description provided for @accountInviteValidity.
  ///
  /// In en, this message translates to:
  /// **'Valid for 7 days, single use'**
  String get accountInviteValidity;

  /// No description provided for @accountWhatMembersShare.
  ///
  /// In en, this message translates to:
  /// **'What members share'**
  String get accountWhatMembersShare;

  /// No description provided for @accountMembersShareBody.
  ///
  /// In en, this message translates to:
  /// **'Everyone shares the kitchen, shopping list, meal plan and saved recipes. Each person\'s journal, nutrition, glucose, Smile & Food log and professional reviews stay private. Allergies are shared with the household only so shared meals stay safe.'**
  String get accountMembersShareBody;

  /// No description provided for @accountPrivacyEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get accountPrivacyEyebrow;

  /// No description provided for @accountPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your data, your choice'**
  String get accountPrivacyTitle;

  /// No description provided for @accountPrivacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Chefii never sells your data or uses your health records for advertising.'**
  String get accountPrivacySubtitle;

  /// No description provided for @accountAiProcessing.
  ///
  /// In en, this message translates to:
  /// **'AI processing'**
  String get accountAiProcessing;

  /// No description provided for @accountAiProcessingBody.
  ///
  /// In en, this message translates to:
  /// **'Send receipt and fridge photos, and chef requests, to our AI providers (Google Gemini; OpenAI if enabled below) through our secure servers. Providers may not train on your data under our agreements.'**
  String get accountAiProcessingBody;

  /// No description provided for @accountOptionalAiProvider.
  ///
  /// In en, this message translates to:
  /// **'Optional second AI provider'**
  String get accountOptionalAiProvider;

  /// No description provided for @accountOptionalAiProviderBody.
  ///
  /// In en, this message translates to:
  /// **'Allow OpenAI for conversation and recipe writing. Off means Gemini only.'**
  String get accountOptionalAiProviderBody;

  /// No description provided for @accountAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Product analytics'**
  String get accountAnalytics;

  /// No description provided for @accountAnalyticsBody.
  ///
  /// In en, this message translates to:
  /// **'Anonymous usage events (e.g. \"receipt imported\"). Never food names, health data or free text.'**
  String get accountAnalyticsBody;

  /// No description provided for @accountProfessionalSharing.
  ///
  /// In en, this message translates to:
  /// **'Professional sharing'**
  String get accountProfessionalSharing;

  /// No description provided for @accountConsentHistory.
  ///
  /// In en, this message translates to:
  /// **'Consent history'**
  String get accountConsentHistory;

  /// No description provided for @accountNoConsents.
  ///
  /// In en, this message translates to:
  /// **'No consents recorded.'**
  String get accountNoConsents;

  /// No description provided for @accountConsentGranted.
  ///
  /// In en, this message translates to:
  /// **'{purpose} · granted'**
  String accountConsentGranted(String purpose);

  /// No description provided for @accountConsentWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'{purpose} · withdrawn'**
  String accountConsentWithdrawn(String purpose);

  /// No description provided for @accountConsentVersion.
  ///
  /// In en, this message translates to:
  /// **'{date} · version {version}'**
  String accountConsentVersion(String date, String version);

  /// No description provided for @accountDataResidency.
  ///
  /// In en, this message translates to:
  /// **'Data is stored in Canada (Google Cloud, Montréal region) where supported. See the Privacy Policy for details.'**
  String get accountDataResidency;

  /// No description provided for @accountServicesEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get accountServicesEyebrow;

  /// No description provided for @accountNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get accountNotifications;

  /// No description provided for @accountNotificationsBody.
  ///
  /// In en, this message translates to:
  /// **'For reminders, timers and your morning alarm'**
  String get accountNotificationsBody;

  /// No description provided for @accountNotificationsOn.
  ///
  /// In en, this message translates to:
  /// **'Notifications are on'**
  String get accountNotificationsOn;

  /// No description provided for @accountNotificationsOff.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off — you can change this in system Settings.'**
  String get accountNotificationsOff;

  /// No description provided for @accountCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get accountCheck;

  /// No description provided for @accountKitchenAi.
  ///
  /// In en, this message translates to:
  /// **'Kitchen AI'**
  String get accountKitchenAi;

  /// No description provided for @accountKitchenAiDemo.
  ///
  /// In en, this message translates to:
  /// **'Demo mode — sample results, no AI provider connected'**
  String get accountKitchenAiDemo;

  /// No description provided for @accountKitchenAiConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected through Chefii\'s secure servers'**
  String get accountKitchenAiConnected;

  /// No description provided for @accountHealthApps.
  ///
  /// In en, this message translates to:
  /// **'Apple Health / Health Connect'**
  String get accountHealthApps;

  /// No description provided for @accountHealthAppsBody.
  ///
  /// In en, this message translates to:
  /// **'Coming later: read-only glucose import with clear provenance. Not available yet.'**
  String get accountHealthAppsBody;

  /// No description provided for @accountProfessionals.
  ///
  /// In en, this message translates to:
  /// **'Professionals'**
  String get accountProfessionals;

  /// No description provided for @accountProfessionalsBody.
  ///
  /// In en, this message translates to:
  /// **'Manage who can see your records'**
  String get accountProfessionalsBody;

  /// No description provided for @accountBackendDemo.
  ///
  /// In en, this message translates to:
  /// **'Backend: local demo storage on this device'**
  String get accountBackendDemo;

  /// No description provided for @accountBackendFirebase.
  ///
  /// In en, this message translates to:
  /// **'Backend: Firebase'**
  String get accountBackendFirebase;

  /// No description provided for @accountBackendEmulators.
  ///
  /// In en, this message translates to:
  /// **'Backend: Firebase (emulators)'**
  String get accountBackendEmulators;

  /// No description provided for @accountEarlyAccess.
  ///
  /// In en, this message translates to:
  /// **'Early access'**
  String get accountEarlyAccess;

  /// No description provided for @accountMembershipSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every Chefii feature is included while we\'re in early access.'**
  String get accountMembershipSubtitle;

  /// No description provided for @accountMembershipName.
  ///
  /// In en, this message translates to:
  /// **'Chefii Membership'**
  String get accountMembershipName;

  /// No description provided for @accountMembershipBody.
  ///
  /// In en, this message translates to:
  /// **'Paid plans aren\'t available yet. When they launch, you\'ll be told the price in advance and nothing will be charged without your confirmation through the App Store or Google Play.'**
  String get accountMembershipBody;

  /// No description provided for @accountIncludedNow.
  ///
  /// In en, this message translates to:
  /// **'Included now'**
  String get accountIncludedNow;

  /// No description provided for @accountFeatureScanning.
  ///
  /// In en, this message translates to:
  /// **'Receipt and fridge scanning'**
  String get accountFeatureScanning;

  /// No description provided for @accountFeatureChef.
  ///
  /// In en, this message translates to:
  /// **'AI chef and guided cooking'**
  String get accountFeatureChef;

  /// No description provided for @accountFeaturePlanning.
  ///
  /// In en, this message translates to:
  /// **'Meal planning and smart shopping'**
  String get accountFeaturePlanning;

  /// No description provided for @accountFeatureJournal.
  ///
  /// In en, this message translates to:
  /// **'Nutrition journal and insights'**
  String get accountFeatureJournal;

  /// No description provided for @accountFeatureCircle.
  ///
  /// In en, this message translates to:
  /// **'Sharing with your nutrition circle'**
  String get accountFeatureCircle;

  /// No description provided for @accountBillingNote.
  ///
  /// In en, this message translates to:
  /// **'Receipts and billing history will appear here once memberships launch.'**
  String get accountBillingNote;

  /// No description provided for @accountSettingsEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get accountSettingsEyebrow;

  /// No description provided for @accountTextSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get accountTextSize;

  /// No description provided for @accountTextScaleValue.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String accountTextScaleValue(int percent);

  /// No description provided for @accountTextScaleSemantic.
  ///
  /// In en, this message translates to:
  /// **'{percent} percent'**
  String accountTextScaleSemantic(int percent);

  /// No description provided for @accountTextPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview: Simmer gently until the lentils collapse.'**
  String get accountTextPreview;

  /// No description provided for @accountDeviceTextSize.
  ///
  /// In en, this message translates to:
  /// **'Chefii also follows your device\'s text size.'**
  String get accountDeviceTextSize;

  /// No description provided for @accountReduceMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get accountReduceMotion;

  /// No description provided for @accountReduceMotionBody.
  ///
  /// In en, this message translates to:
  /// **'Fewer animations and transitions'**
  String get accountReduceMotionBody;

  /// No description provided for @accountReadStepsAloud.
  ///
  /// In en, this message translates to:
  /// **'Read cooking steps aloud'**
  String get accountReadStepsAloud;

  /// No description provided for @accountReadStepsAloudBody.
  ///
  /// In en, this message translates to:
  /// **'In guided cooking'**
  String get accountReadStepsAloudBody;

  /// No description provided for @accountLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get accountLanguage;

  /// No description provided for @accountLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'Same as my device'**
  String get accountLanguageSystem;

  /// No description provided for @accountDemoAccount.
  ///
  /// In en, this message translates to:
  /// **'Demo account'**
  String get accountDemoAccount;

  /// No description provided for @accountSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get accountSignedIn;

  /// No description provided for @accountStoredOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Stored only on this device'**
  String get accountStoredOnDevice;

  /// No description provided for @accountIdShort.
  ///
  /// In en, this message translates to:
  /// **'Account ID {id}…'**
  String accountIdShort(String id);

  /// No description provided for @accountResetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get accountResetPassword;

  /// No description provided for @accountResetPasswordSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset email sent'**
  String get accountResetPasswordSent;

  /// No description provided for @accountSignOutAll.
  ///
  /// In en, this message translates to:
  /// **'Sign out of all devices'**
  String get accountSignOutAll;

  /// No description provided for @accountSignOutAllBody.
  ///
  /// In en, this message translates to:
  /// **'Ends every session, including this one'**
  String get accountSignOutAllBody;

  /// No description provided for @accountSignOutEverywhereTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out everywhere?'**
  String get accountSignOutEverywhereTitle;

  /// No description provided for @accountSignOutEverywhereMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ll need to sign in again on each device.'**
  String get accountSignOutEverywhereMessage;

  /// No description provided for @accountSignOutEverywhere.
  ///
  /// In en, this message translates to:
  /// **'Sign out everywhere'**
  String get accountSignOutEverywhere;

  /// No description provided for @accountReauthNote.
  ///
  /// In en, this message translates to:
  /// **'Sensitive actions such as deleting your account or exporting health data ask you to confirm your identity again.'**
  String get accountReauthNote;

  /// No description provided for @accountHelpEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get accountHelpEyebrow;

  /// No description provided for @accountHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get accountHelpTitle;

  /// No description provided for @accountSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get accountSend;

  /// No description provided for @accountFeedbackThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you — we read every message.'**
  String get accountFeedbackThanks;

  /// No description provided for @accountFaqAccuracyQ.
  ///
  /// In en, this message translates to:
  /// **'How accurate is my kitchen?'**
  String get accountFaqAccuracyQ;

  /// No description provided for @accountFaqAccuracyA.
  ///
  /// In en, this message translates to:
  /// **'Items from receipts you reviewed are confirmed. Amounts after cooking are deducted from what you confirm. Anything estimated is labelled, and Chefii occasionally asks you to verify.'**
  String get accountFaqAccuracyA;

  /// No description provided for @accountFaqUntrackedQ.
  ///
  /// In en, this message translates to:
  /// **'What if I use something without telling Chefii?'**
  String get accountFaqUntrackedQ;

  /// No description provided for @accountFaqUntrackedA.
  ///
  /// In en, this message translates to:
  /// **'Use the \"I used…\" button or tap − on an item. If counts drift, Quick check lets you fix several items in seconds.'**
  String get accountFaqUntrackedA;

  /// No description provided for @accountFaqFreshnessQ.
  ///
  /// In en, this message translates to:
  /// **'Are freshness dates safe to rely on?'**
  String get accountFaqFreshnessQ;

  /// No description provided for @accountFaqFreshnessA.
  ///
  /// In en, this message translates to:
  /// **'No — they\'re estimates from typical storage times. Always follow the package date and your own judgement.'**
  String get accountFaqFreshnessA;

  /// No description provided for @accountFaqMedicalQ.
  ///
  /// In en, this message translates to:
  /// **'Does Chefii give medical advice?'**
  String get accountFaqMedicalQ;

  /// No description provided for @accountFaqMedicalA.
  ///
  /// In en, this message translates to:
  /// **'No. Nutrition features are education. For personal advice, share your records with a registered dietitian in My nutrition circle.'**
  String get accountFaqMedicalA;

  /// No description provided for @accountFaqHealthDataQ.
  ///
  /// In en, this message translates to:
  /// **'Who can see my health data?'**
  String get accountFaqHealthDataQ;

  /// No description provided for @accountFaqHealthDataA.
  ///
  /// In en, this message translates to:
  /// **'Only you, plus any professional you explicitly share with, for the time you choose. Household members never see your journal or health records.'**
  String get accountFaqHealthDataA;

  /// No description provided for @accountWriteToUs.
  ///
  /// In en, this message translates to:
  /// **'Write to us'**
  String get accountWriteToUs;

  /// No description provided for @accountFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get accountFeedback;

  /// No description provided for @accountReportProblem.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get accountReportProblem;

  /// No description provided for @accountFeedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us what happened or what you\'d love to see. Please don\'t include health details.'**
  String get accountFeedbackHint;

  /// No description provided for @accountEmailSupport.
  ///
  /// In en, this message translates to:
  /// **'Email support'**
  String get accountEmailSupport;

  /// No description provided for @accountSupportEmailSubject.
  ///
  /// In en, this message translates to:
  /// **'Chefii support'**
  String get accountSupportEmailSubject;

  /// No description provided for @accountLegalEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get accountLegalEyebrow;

  /// No description provided for @accountLegalTitle.
  ///
  /// In en, this message translates to:
  /// **'Legal & disclosures'**
  String get accountLegalTitle;

  /// No description provided for @accountLegalTermsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service (summary)'**
  String get accountLegalTermsTitle;

  /// No description provided for @accountLegalTermsBody.
  ///
  /// In en, this message translates to:
  /// **'Chefii is provided for household kitchen organisation, cooking guidance and general nutrition education. You\'re responsible for food safety decisions in your home. Full terms will be published before public launch and require legal review.'**
  String get accountLegalTermsBody;

  /// No description provided for @accountLegalPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy (summary)'**
  String get accountLegalPrivacyTitle;

  /// No description provided for @accountLegalPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'We collect what you enter or scan to run Chefii: kitchen items, receipts, recipes, meal records, and optional health information you choose to add. We process data in Canada where possible, use AI providers only with your consent and under data-processing agreements, never sell personal information, and let you export or delete your data at any time. Prepared to meet PIPEDA and applicable provincial health privacy laws; full policy subject to legal review.'**
  String get accountLegalPrivacyBody;

  /// No description provided for @accountLegalMedicalTitle.
  ///
  /// In en, this message translates to:
  /// **'Medical limitations'**
  String get accountLegalMedicalTitle;

  /// No description provided for @accountLegalMedicalBody.
  ///
  /// In en, this message translates to:
  /// **'Chefii does not diagnose, treat, cure or prevent any disease, and is not a medical device. Nutrition values are estimates. Glucose features are a personal journal and do not replace medical devices, alarms or your care team. Allergy screening relies on ingredient names and labels you check; it cannot guarantee a food is free of an allergen.'**
  String get accountLegalMedicalBody;

  /// No description provided for @accountLegalFoodSafetyTitle.
  ///
  /// In en, this message translates to:
  /// **'Food safety'**
  String get accountLegalFoodSafetyTitle;

  /// No description provided for @accountLegalFoodSafetyBody.
  ///
  /// In en, this message translates to:
  /// **'Freshness indicators are estimates based on typical storage times. Always follow package dates, safe storage temperatures and safe internal cooking temperatures.'**
  String get accountLegalFoodSafetyBody;

  /// No description provided for @accountLegalEvidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Evidence methodology'**
  String get accountLegalEvidenceTitle;

  /// No description provided for @accountLegalEvidenceBody.
  ///
  /// In en, this message translates to:
  /// **'Nutrition statements come from national guidelines and authoritative references. Each shows its sources, evidence strength, limitations and review status. AI may rephrase approved statements but may not create new health claims.'**
  String get accountLegalEvidenceBody;

  /// No description provided for @accountLegalAiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI disclosure'**
  String get accountLegalAiTitle;

  /// No description provided for @accountLegalAiBody.
  ///
  /// In en, this message translates to:
  /// **'Recipes marked \"Created by your AI chef\", receipt readings and photo suggestions are generated by AI and may contain mistakes. Illustrations are not photographs of your food.'**
  String get accountLegalAiBody;

  /// No description provided for @accountEvidenceLibrary.
  ///
  /// In en, this message translates to:
  /// **'Evidence library'**
  String get accountEvidenceLibrary;

  /// No description provided for @accountLicences.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get accountLicences;

  /// No description provided for @accountLicencesBody.
  ///
  /// In en, this message translates to:
  /// **'Including Cormorant Garamond and Inter (SIL Open Font License)'**
  String get accountLicencesBody;

  /// No description provided for @accountDataEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Your data'**
  String get accountDataEyebrow;

  /// No description provided for @accountDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Export or delete'**
  String get accountDataTitle;

  /// No description provided for @accountExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get accountExport;

  /// No description provided for @accountExportBody.
  ///
  /// In en, this message translates to:
  /// **'A complete copy of your profile, kitchen, journal, health records, consents and sharing history as a JSON file.'**
  String get accountExportBody;

  /// No description provided for @accountPasswordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Password (to confirm it\'s you)'**
  String get accountPasswordConfirm;

  /// No description provided for @accountExportMyData.
  ///
  /// In en, this message translates to:
  /// **'Export my data'**
  String get accountExportMyData;

  /// No description provided for @accountExportShareSubject.
  ///
  /// In en, this message translates to:
  /// **'Your Chefii data'**
  String get accountExportShareSubject;

  /// No description provided for @accountDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get accountDeleteAccount;

  /// No description provided for @accountDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Permanently deletes your account, journal, health records and sharing grants. If you\'re the only member of your household, its kitchen is deleted too. Some records may be kept where the law requires (for example, purchase receipts for membership billing). This can\'t be undone.'**
  String get accountDeleteBody;

  /// No description provided for @accountDeleteConfirmWord.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get accountDeleteConfirmWord;

  /// No description provided for @accountDeleteConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Type {word} to confirm'**
  String accountDeleteConfirmLabel(String word);

  /// No description provided for @accountDeleteMyAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get accountDeleteMyAccount;

  /// No description provided for @chefChatUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{message} Your curated recipes are still available in Discover.'**
  String chefChatUnavailable(String message);

  /// No description provided for @chefChatError.
  ///
  /// In en, this message translates to:
  /// **'I couldn\'t reach the kitchen assistant just now. Please try again.'**
  String get chefChatError;

  /// No description provided for @chefPromptQuickDinner.
  ///
  /// In en, this message translates to:
  /// **'Something quick for dinner'**
  String get chefPromptQuickDinner;

  /// No description provided for @chefPromptProteinBreakfast.
  ///
  /// In en, this message translates to:
  /// **'A high-protein breakfast'**
  String get chefPromptProteinBreakfast;

  /// No description provided for @chefPromptUseWhatIHave.
  ///
  /// In en, this message translates to:
  /// **'What can I make with what I have?'**
  String get chefPromptUseWhatIHave;

  /// No description provided for @chefPromptVegetarian.
  ///
  /// In en, this message translates to:
  /// **'A comforting vegetarian meal'**
  String get chefPromptVegetarian;

  /// No description provided for @chefAiFeature.
  ///
  /// In en, this message translates to:
  /// **'your AI chef'**
  String get chefAiFeature;

  /// No description provided for @chefHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Your chef'**
  String get chefHomeTitle;

  /// No description provided for @chefPreferencesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get chefPreferencesTooltip;

  /// No description provided for @chefNewConversation.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get chefNewConversation;

  /// No description provided for @chefDemoChat.
  ///
  /// In en, this message translates to:
  /// **'Demo: replies use the curated recipe library, not AI.'**
  String get chefDemoChat;

  /// No description provided for @chefHomeHeadline.
  ///
  /// In en, this message translates to:
  /// **'What shall we cook?'**
  String get chefHomeHeadline;

  /// No description provided for @chefHomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ask for anything — I know what\'s in your kitchen and what everyone can eat.'**
  String get chefHomeSubtitle;

  /// No description provided for @chefChooseOptions.
  ///
  /// In en, this message translates to:
  /// **'Choose time, portions and more'**
  String get chefChooseOptions;

  /// No description provided for @chefAskHint.
  ///
  /// In en, this message translates to:
  /// **'Ask your chef…'**
  String get chefAskHint;

  /// No description provided for @chefSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chefSend;

  /// No description provided for @chefEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Chef'**
  String get chefEyebrow;

  /// No description provided for @chefPreferencesTitle.
  ///
  /// In en, this message translates to:
  /// **'Tonight, I\'d like…'**
  String get chefPreferencesTitle;

  /// No description provided for @chefShowRecipes.
  ///
  /// In en, this message translates to:
  /// **'Show me recipes'**
  String get chefShowRecipes;

  /// No description provided for @chefMeal.
  ///
  /// In en, this message translates to:
  /// **'Meal'**
  String get chefMeal;

  /// No description provided for @chefTimeAvailable.
  ///
  /// In en, this message translates to:
  /// **'Time available'**
  String get chefTimeAvailable;

  /// No description provided for @chefTimeAvailableSemantics.
  ///
  /// In en, this message translates to:
  /// **'Time available in minutes'**
  String get chefTimeAvailableSemantics;

  /// No description provided for @chefUpTo.
  ///
  /// In en, this message translates to:
  /// **'Up to {duration}'**
  String chefUpTo(String duration);

  /// No description provided for @chefPortions.
  ///
  /// In en, this message translates to:
  /// **'Portions'**
  String get chefPortions;

  /// No description provided for @chefFewer.
  ///
  /// In en, this message translates to:
  /// **'Fewer'**
  String get chefFewer;

  /// No description provided for @chefMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get chefMore;

  /// No description provided for @chefUseWhatIHave.
  ///
  /// In en, this message translates to:
  /// **'Use what I have'**
  String get chefUseWhatIHave;

  /// No description provided for @chefUseWhatIHaveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prefer recipes I can make now'**
  String get chefUseWhatIHaveSubtitle;

  /// No description provided for @chefNutrition.
  ///
  /// In en, this message translates to:
  /// **'Nutrition'**
  String get chefNutrition;

  /// No description provided for @chefFocusMoreProtein.
  ///
  /// In en, this message translates to:
  /// **'more protein'**
  String get chefFocusMoreProtein;

  /// No description provided for @chefFocusMoreVegetables.
  ///
  /// In en, this message translates to:
  /// **'more vegetables'**
  String get chefFocusMoreVegetables;

  /// No description provided for @chefFocusLighter.
  ///
  /// In en, this message translates to:
  /// **'lighter'**
  String get chefFocusLighter;

  /// No description provided for @chefFocusMoreFibre.
  ///
  /// In en, this message translates to:
  /// **'more fibre'**
  String get chefFocusMoreFibre;

  /// No description provided for @chefCuisine.
  ///
  /// In en, this message translates to:
  /// **'Cuisine'**
  String get chefCuisine;

  /// No description provided for @chefCuisineItalian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get chefCuisineItalian;

  /// No description provided for @chefCuisineFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get chefCuisineFrench;

  /// No description provided for @chefCuisineMediterranean.
  ///
  /// In en, this message translates to:
  /// **'Mediterranean'**
  String get chefCuisineMediterranean;

  /// No description provided for @chefCuisineIndian.
  ///
  /// In en, this message translates to:
  /// **'Indian'**
  String get chefCuisineIndian;

  /// No description provided for @chefCuisineMiddleEastern.
  ///
  /// In en, this message translates to:
  /// **'Middle Eastern'**
  String get chefCuisineMiddleEastern;

  /// No description provided for @chefCuisineMexican.
  ///
  /// In en, this message translates to:
  /// **'Mexican'**
  String get chefCuisineMexican;

  /// No description provided for @chefCuisineJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get chefCuisineJapanese;

  /// No description provided for @chefCuisineChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get chefCuisineChinese;

  /// No description provided for @chefCuisineModern.
  ///
  /// In en, this message translates to:
  /// **'Modern'**
  String get chefCuisineModern;

  /// No description provided for @chefEquipment.
  ///
  /// In en, this message translates to:
  /// **'Equipment'**
  String get chefEquipment;

  /// No description provided for @chefEquipmentOven.
  ///
  /// In en, this message translates to:
  /// **'Oven'**
  String get chefEquipmentOven;

  /// No description provided for @chefEquipmentStovetop.
  ///
  /// In en, this message translates to:
  /// **'Stovetop'**
  String get chefEquipmentStovetop;

  /// No description provided for @chefEquipmentAirFryer.
  ///
  /// In en, this message translates to:
  /// **'Air fryer'**
  String get chefEquipmentAirFryer;

  /// No description provided for @chefEquipmentSlowCooker.
  ///
  /// In en, this message translates to:
  /// **'Slow cooker'**
  String get chefEquipmentSlowCooker;

  /// No description provided for @chefEquipmentInstantPot.
  ///
  /// In en, this message translates to:
  /// **'Instant Pot'**
  String get chefEquipmentInstantPot;

  /// No description provided for @chefEquipmentBlender.
  ///
  /// In en, this message translates to:
  /// **'Blender'**
  String get chefEquipmentBlender;

  /// No description provided for @chefEquipmentMicrowave.
  ///
  /// In en, this message translates to:
  /// **'Microwave'**
  String get chefEquipmentMicrowave;

  /// No description provided for @chefLeaveOut.
  ///
  /// In en, this message translates to:
  /// **'Leave out'**
  String get chefLeaveOut;

  /// No description provided for @chefLeaveOutHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. mushrooms, olives'**
  String get chefLeaveOutHint;

  /// No description provided for @chefAlwaysRespected.
  ///
  /// In en, this message translates to:
  /// **'Always respected: {list}.'**
  String chefAlwaysRespected(String list);

  /// No description provided for @chefNoAllergiesRecorded.
  ///
  /// In en, this message translates to:
  /// **'no allergies or restrictions recorded'**
  String get chefNoAllergiesRecorded;

  /// No description provided for @chefAddAllergies.
  ///
  /// In en, this message translates to:
  /// **'Add your allergies in Profile so I can screen every recipe.'**
  String get chefAddAllergies;

  /// No description provided for @chefNoRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Tell me what you\'d like'**
  String get chefNoRequestTitle;

  /// No description provided for @chefNoRequestMessage.
  ///
  /// In en, this message translates to:
  /// **'Choose time and portions first.'**
  String get chefNoRequestMessage;

  /// No description provided for @chefSetPreferences.
  ///
  /// In en, this message translates to:
  /// **'Set preferences'**
  String get chefSetPreferences;

  /// No description provided for @chefResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'For you'**
  String get chefResultsTitle;

  /// No description provided for @chefResultsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{meal} · up to {duration} · {servings} portions'**
  String chefResultsSubtitle(String meal, String duration, int servings);

  /// No description provided for @chefAnyMeal.
  ///
  /// In en, this message translates to:
  /// **'Any meal'**
  String get chefAnyMeal;

  /// No description provided for @chefTryAnother.
  ///
  /// In en, this message translates to:
  /// **'Try another'**
  String get chefTryAnother;

  /// No description provided for @chefDemoResults.
  ///
  /// In en, this message translates to:
  /// **'Demo: ranked from the curated library, not generated by AI.'**
  String get chefDemoResults;

  /// No description provided for @chefConsidering.
  ///
  /// In en, this message translates to:
  /// **'Considering your kitchen…'**
  String get chefConsidering;

  /// No description provided for @chefNoMoreIdeasTitle.
  ///
  /// In en, this message translates to:
  /// **'No more ideas with these settings'**
  String get chefNoMoreIdeasTitle;

  /// No description provided for @chefNoMoreIdeasMessage.
  ///
  /// In en, this message translates to:
  /// **'Try a longer time or fewer restrictions.'**
  String get chefNoMoreIdeasMessage;

  /// No description provided for @chefAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get chefAdjust;

  /// No description provided for @chefFilteredForSafety.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 idea was left out for your household\'s dietary needs.} other{{count} ideas were left out for your household\'s dietary needs.}}'**
  String chefFilteredForSafety(int count);

  /// No description provided for @chefRecipeUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Recipe unavailable'**
  String get chefRecipeUnavailableTitle;

  /// No description provided for @chefRecipeUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'This suggestion wasn\'t saved. Ask your chef again or browse Discover.'**
  String get chefRecipeUnavailableMessage;

  /// No description provided for @chefDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get chefDiscover;

  /// No description provided for @chefRemoveFavourite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get chefRemoveFavourite;

  /// No description provided for @chefSaveFavourite.
  ///
  /// In en, this message translates to:
  /// **'Save to favourites'**
  String get chefSaveFavourite;

  /// No description provided for @chefAddToPlan.
  ///
  /// In en, this message translates to:
  /// **'Add to meal plan'**
  String get chefAddToPlan;

  /// No description provided for @chefNotSafe.
  ///
  /// In en, this message translates to:
  /// **'Not safe for your household'**
  String get chefNotSafe;

  /// No description provided for @chefStartCooking.
  ///
  /// In en, this message translates to:
  /// **'Start cooking'**
  String get chefStartCooking;

  /// No description provided for @chefTotalTime.
  ///
  /// In en, this message translates to:
  /// **'{duration} total'**
  String chefTotalTime(String duration);

  /// No description provided for @chefAiCreated.
  ///
  /// In en, this message translates to:
  /// **'Created by AI for you. Check cooking temperatures and your own judgement.'**
  String get chefAiCreated;

  /// No description provided for @chefAiCreatedWithModel.
  ///
  /// In en, this message translates to:
  /// **'Created by AI for you ({model}). Check cooking temperatures and your own judgement.'**
  String chefAiCreatedWithModel(String model);

  /// No description provided for @chefConflicts.
  ///
  /// In en, this message translates to:
  /// **'Conflicts with your household\'s needs'**
  String get chefConflicts;

  /// No description provided for @chefWorthALook.
  ///
  /// In en, this message translates to:
  /// **'Worth a look'**
  String get chefWorthALook;

  /// No description provided for @chefConflictLine.
  ///
  /// In en, this message translates to:
  /// **'• {ingredient}: {reason}'**
  String chefConflictLine(String ingredient, String reason);

  /// No description provided for @chefSeeSubstitutions.
  ///
  /// In en, this message translates to:
  /// **'See substitutions'**
  String get chefSeeSubstitutions;

  /// No description provided for @chefIngredients.
  ///
  /// In en, this message translates to:
  /// **'Ingredients'**
  String get chefIngredients;

  /// No description provided for @chefServings.
  ///
  /// In en, this message translates to:
  /// **'Servings'**
  String get chefServings;

  /// No description provided for @chefFewerServings.
  ///
  /// In en, this message translates to:
  /// **'Fewer servings'**
  String get chefFewerServings;

  /// No description provided for @chefMoreServings.
  ///
  /// In en, this message translates to:
  /// **'More servings'**
  String get chefMoreServings;

  /// No description provided for @chefAddMissingToList.
  ///
  /// In en, this message translates to:
  /// **'Add {count} to list'**
  String chefAddMissingToList(int count);

  /// No description provided for @chefAddedToList.
  ///
  /// In en, this message translates to:
  /// **'Added to your shopping list'**
  String get chefAddedToList;

  /// No description provided for @chefSubstitutions.
  ///
  /// In en, this message translates to:
  /// **'Substitutions'**
  String get chefSubstitutions;

  /// No description provided for @chefMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get chefMethod;

  /// No description provided for @chefStoring.
  ///
  /// In en, this message translates to:
  /// **'Storing'**
  String get chefStoring;

  /// No description provided for @chefSavedToRecipes.
  ///
  /// In en, this message translates to:
  /// **'Saved to your recipes'**
  String get chefSavedToRecipes;

  /// No description provided for @chefSaveRecipe.
  ///
  /// In en, this message translates to:
  /// **'Save this recipe'**
  String get chefSaveRecipe;

  /// No description provided for @chefInYourKitchenLower.
  ///
  /// In en, this message translates to:
  /// **'in your kitchen'**
  String get chefInYourKitchenLower;

  /// No description provided for @chefNeedQuantity.
  ///
  /// In en, this message translates to:
  /// **'need {quantity}'**
  String chefNeedQuantity(String quantity);

  /// No description provided for @chefNeedMore.
  ///
  /// In en, this message translates to:
  /// **'need more'**
  String get chefNeedMore;

  /// No description provided for @chefToBuy.
  ///
  /// In en, this message translates to:
  /// **'to buy'**
  String get chefToBuy;

  /// No description provided for @chefOptional.
  ///
  /// In en, this message translates to:
  /// **'optional'**
  String get chefOptional;

  /// No description provided for @chefOptionalIngredient.
  ///
  /// In en, this message translates to:
  /// **'{ingredient} (optional)'**
  String chefOptionalIngredient(String ingredient);

  /// No description provided for @chefSmartSubstitutions.
  ///
  /// In en, this message translates to:
  /// **'Smart substitutions'**
  String get chefSmartSubstitutions;

  /// No description provided for @chefSubstitutionsNote.
  ///
  /// In en, this message translates to:
  /// **'Every swap is checked against your household\'s allergies and diet.'**
  String get chefSubstitutionsNote;

  /// No description provided for @chefNoSafeSwapsTitle.
  ///
  /// In en, this message translates to:
  /// **'No safe swaps we\'re confident about'**
  String get chefNoSafeSwapsTitle;

  /// No description provided for @chefNoSafeSwapsMessage.
  ///
  /// In en, this message translates to:
  /// **'Try asking your chef for a different recipe.'**
  String get chefNoSafeSwapsMessage;

  /// No description provided for @chefInYourKitchen.
  ///
  /// In en, this message translates to:
  /// **'In your kitchen'**
  String get chefInYourKitchen;

  /// No description provided for @chefProteinDiff.
  ///
  /// In en, this message translates to:
  /// **'Protein {diff} g / serving'**
  String chefProteinDiff(String diff);

  /// No description provided for @chefUseThis.
  ///
  /// In en, this message translates to:
  /// **'Use this'**
  String get chefUseThis;

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

  /// No description provided for @cookingSessionNotFound.
  ///
  /// In en, this message translates to:
  /// **'This cooking session could not be found.'**
  String get cookingSessionNotFound;

  /// No description provided for @cookingBeforeYouBegin.
  ///
  /// In en, this message translates to:
  /// **'Before you begin'**
  String get cookingBeforeYouBegin;

  /// No description provided for @cookingPrepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{servings} servings · gather everything first'**
  String cookingPrepSubtitle(int servings);

  /// No description provided for @cookingBeginCooking.
  ///
  /// In en, this message translates to:
  /// **'Begin cooking'**
  String get cookingBeginCooking;

  /// No description provided for @cookingBeginAnyway.
  ///
  /// In en, this message translates to:
  /// **'Begin anyway'**
  String get cookingBeginAnyway;

  /// No description provided for @cookingReadyCount.
  ///
  /// In en, this message translates to:
  /// **'{ready} of {total} ready'**
  String cookingReadyCount(int ready, int total);

  /// No description provided for @cookingIngredients.
  ///
  /// In en, this message translates to:
  /// **'Ingredients'**
  String get cookingIngredients;

  /// No description provided for @cookingEquipment.
  ///
  /// In en, this message translates to:
  /// **'Equipment'**
  String get cookingEquipment;

  /// No description provided for @cookingKitchenShows.
  ///
  /// In en, this message translates to:
  /// **'Kitchen shows {quantity} — check you have enough'**
  String cookingKitchenShows(String quantity);

  /// No description provided for @cookingNotInKitchen.
  ///
  /// In en, this message translates to:
  /// **'Not in your kitchen records'**
  String get cookingNotInKitchen;

  /// No description provided for @cookingStepSpeech.
  ///
  /// In en, this message translates to:
  /// **'Step {step}. {text}'**
  String cookingStepSpeech(int step, String text);

  /// No description provided for @cookingStopReadingAloud.
  ///
  /// In en, this message translates to:
  /// **'Stop reading steps aloud'**
  String get cookingStopReadingAloud;

  /// No description provided for @cookingReadAloud.
  ///
  /// In en, this message translates to:
  /// **'Read steps aloud'**
  String get cookingReadAloud;

  /// No description provided for @cookingTimers.
  ///
  /// In en, this message translates to:
  /// **'Timers'**
  String get cookingTimers;

  /// No description provided for @cookingStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String cookingStepOf(int step, int total);

  /// No description provided for @cookingStepOfCaps.
  ///
  /// In en, this message translates to:
  /// **'STEP {step} OF {total}'**
  String cookingStepOfCaps(int step, int total);

  /// No description provided for @cookingStartNamedTimer.
  ///
  /// In en, this message translates to:
  /// **'Start {label} · {duration}'**
  String cookingStartNamedTimer(String label, String duration);

  /// No description provided for @cookingStartTimer.
  ///
  /// In en, this message translates to:
  /// **'Start timer · {duration}'**
  String cookingStartTimer(String duration);

  /// No description provided for @cookingStepTimerLabel.
  ///
  /// In en, this message translates to:
  /// **'Step {step}'**
  String cookingStepTimerLabel(int step);

  /// No description provided for @cookingFinishCooking.
  ///
  /// In en, this message translates to:
  /// **'Finish cooking'**
  String get cookingFinishCooking;

  /// No description provided for @cookingNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get cookingNextStep;

  /// No description provided for @cookingTimerChipDone.
  ///
  /// In en, this message translates to:
  /// **'{label} done'**
  String cookingTimerChipDone(String label);

  /// No description provided for @cookingKitchenEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get cookingKitchenEyebrow;

  /// No description provided for @cookingTimersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'They\'ll alert you even if you leave the app.'**
  String get cookingTimersSubtitle;

  /// No description provided for @cookingStartMinutesTimer.
  ///
  /// In en, this message translates to:
  /// **'Start {minutes} min timer'**
  String cookingStartMinutesTimer(int minutes);

  /// No description provided for @cookingDefaultTimerName.
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get cookingDefaultTimerName;

  /// No description provided for @cookingNoTimersTitle.
  ///
  /// In en, this message translates to:
  /// **'No timers running'**
  String get cookingNoTimersTitle;

  /// No description provided for @cookingNoTimersMessage.
  ///
  /// In en, this message translates to:
  /// **'Start one from a recipe step, or below.'**
  String get cookingNoTimersMessage;

  /// No description provided for @cookingAddMinute.
  ///
  /// In en, this message translates to:
  /// **'+1 minute'**
  String get cookingAddMinute;

  /// No description provided for @cookingPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get cookingPause;

  /// No description provided for @cookingResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get cookingResume;

  /// No description provided for @cookingNewTimer.
  ///
  /// In en, this message translates to:
  /// **'New timer'**
  String get cookingNewTimer;

  /// No description provided for @cookingTimerName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get cookingTimerName;

  /// No description provided for @cookingTimerNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Rice'**
  String get cookingTimerNameHint;

  /// No description provided for @cookingMinutesChip.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String cookingMinutesChip(int minutes);

  /// No description provided for @cookingAlmostDone.
  ///
  /// In en, this message translates to:
  /// **'Almost done'**
  String get cookingAlmostDone;

  /// No description provided for @cookingWhatDidYouUse.
  ///
  /// In en, this message translates to:
  /// **'What did you use?'**
  String get cookingWhatDidYouUse;

  /// No description provided for @cookingConfirmSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust anything that differed. This updates your kitchen once.'**
  String get cookingConfirmSubtitle;

  /// No description provided for @cookingConfirmAndUpdate.
  ///
  /// In en, this message translates to:
  /// **'Confirm and update kitchen'**
  String get cookingConfirmAndUpdate;

  /// No description provided for @cookingDiscrepancies.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Kitchen updated. 1 item wasn\'t fully recorded — we\'ll ask you to check later.} other{Kitchen updated. {count} items weren\'t fully recorded — we\'ll ask you to check later.}}'**
  String cookingDiscrepancies(int count);

  /// No description provided for @cookingNothingTracked.
  ///
  /// In en, this message translates to:
  /// **'None of these ingredients are tracked in your kitchen, so nothing will change.'**
  String get cookingNothingTracked;

  /// No description provided for @cookingInclude.
  ///
  /// In en, this message translates to:
  /// **'Include'**
  String get cookingInclude;

  /// No description provided for @cookingDidntUse.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t use'**
  String get cookingDidntUse;

  /// No description provided for @cookingRecipeAmount.
  ///
  /// In en, this message translates to:
  /// **'Recipe: {quantity}'**
  String cookingRecipeAmount(String quantity);

  /// No description provided for @cookingAmountUsed.
  ///
  /// In en, this message translates to:
  /// **'Amount of {ingredient} used'**
  String cookingAmountUsed(String ingredient);

  /// No description provided for @cookingBonAppetit.
  ///
  /// In en, this message translates to:
  /// **'Bon appétit'**
  String get cookingBonAppetit;

  /// No description provided for @cookingKitchenUpdated.
  ///
  /// In en, this message translates to:
  /// **'Your kitchen has been updated.'**
  String get cookingKitchenUpdated;

  /// No description provided for @cookingFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get cookingFinish;

  /// No description provided for @cookingLoggedWithLeftovers.
  ///
  /// In en, this message translates to:
  /// **'Logged, and {count, plural, =1{1 portion} other{{count} portions}} saved in the fridge.'**
  String cookingLoggedWithLeftovers(int count);

  /// No description provided for @cookingLoggedToJournal.
  ///
  /// In en, this message translates to:
  /// **'Logged to your journal.'**
  String get cookingLoggedToJournal;

  /// No description provided for @cookingHowWasIt.
  ///
  /// In en, this message translates to:
  /// **'How was it?'**
  String get cookingHowWasIt;

  /// No description provided for @cookingStars.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 star} other{{count} stars}}'**
  String cookingStars(int count);

  /// No description provided for @cookingYourPortion.
  ///
  /// In en, this message translates to:
  /// **'Your portion'**
  String get cookingYourPortion;

  /// No description provided for @cookingPortionsYouAte.
  ///
  /// In en, this message translates to:
  /// **'Portions you ate'**
  String get cookingPortionsYouAte;

  /// No description provided for @cookingYourMeal.
  ///
  /// In en, this message translates to:
  /// **'Your meal'**
  String get cookingYourMeal;

  /// No description provided for @cookingPortionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 portion} other{{amount} portions}}'**
  String cookingPortionCount(num count, String amount);

  /// No description provided for @cookingLeftovers.
  ///
  /// In en, this message translates to:
  /// **'Leftovers'**
  String get cookingLeftovers;

  /// No description provided for @cookingPortionsToSave.
  ///
  /// In en, this message translates to:
  /// **'Portions to save'**
  String get cookingPortionsToSave;

  /// No description provided for @cookingLeftoversReminder.
  ///
  /// In en, this message translates to:
  /// **'We\'ll add them to your fridge with a reminder to eat them within 3 days.'**
  String get cookingLeftoversReminder;

  /// No description provided for @cookingSaveFavourite.
  ///
  /// In en, this message translates to:
  /// **'Save to favourites'**
  String get cookingSaveFavourite;

  /// No description provided for @cookingTimerNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'{label} is done'**
  String cookingTimerNotificationTitle(String label);

  /// No description provided for @cookingTimerNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'Your Chefii timer has finished.'**
  String get cookingTimerNotificationBody;

  /// No description provided for @coreErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get coreErrorTitle;

  /// No description provided for @coreErrorOffline.
  ///
  /// In en, this message translates to:
  /// **'You appear to be offline, so nothing was changed. Please try again when you\'re connected.'**
  String get coreErrorOffline;

  /// No description provided for @coreErrorPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have access to this. If it was shared with you, the owner may have changed permissions.'**
  String get coreErrorPermissionDenied;

  /// No description provided for @coreErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Please try again in a moment.'**
  String get coreErrorGeneric;

  /// No description provided for @corePermissionOff.
  ///
  /// In en, this message translates to:
  /// **'{permission} is turned off'**
  String corePermissionOff(String permission);

  /// No description provided for @coreOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get coreOpenSettings;

  /// No description provided for @coreInProgress.
  ///
  /// In en, this message translates to:
  /// **'{label}, in progress'**
  String coreInProgress(String label);

  /// No description provided for @coreLess.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get coreLess;

  /// No description provided for @coreMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get coreMore;

  /// No description provided for @coreClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get coreClearSearch;

  /// No description provided for @corePhotoFrameHint.
  ///
  /// In en, this message translates to:
  /// **'Fit the whole receipt inside the frame'**
  String get corePhotoFrameHint;

  /// No description provided for @coreIllustration.
  ///
  /// In en, this message translates to:
  /// **'Illustration'**
  String get coreIllustration;

  /// No description provided for @coreIllustrationFor.
  ///
  /// In en, this message translates to:
  /// **'Illustration for {label}'**
  String coreIllustrationFor(String label);

  /// No description provided for @coreStatus.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String coreStatus(String status);

  /// No description provided for @coreMinutesSpoken.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, other{{minutes} minutes}}'**
  String coreMinutesSpoken(int minutes);

  /// No description provided for @coreMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String coreMinutesShort(int minutes);

  /// No description provided for @coreKcalApprox.
  ///
  /// In en, this message translates to:
  /// **'≈ {kcal} kcal'**
  String coreKcalApprox(int kcal);

  /// No description provided for @coreLikelyPastBest.
  ///
  /// In en, this message translates to:
  /// **'Likely past best'**
  String get coreLikelyPastBest;

  /// No description provided for @corePastRecordedDate.
  ///
  /// In en, this message translates to:
  /// **'Past recorded date'**
  String get corePastRecordedDate;

  /// No description provided for @coreDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day left} other{{days} days left}}'**
  String coreDaysLeft(int days);

  /// No description provided for @coreDaysLeftApprox.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{~1 day left} other{~{days} days left}}'**
  String coreDaysLeftApprox(int days);

  /// No description provided for @coreUseSome.
  ///
  /// In en, this message translates to:
  /// **'Use some'**
  String get coreUseSome;

  /// No description provided for @coreNutritionTitle.
  ///
  /// In en, this message translates to:
  /// **'Nutrition'**
  String get coreNutritionTitle;

  /// No description provided for @corePerServing.
  ///
  /// In en, this message translates to:
  /// **'per serving'**
  String get corePerServing;

  /// No description provided for @coreEstimate.
  ///
  /// In en, this message translates to:
  /// **'Estimate'**
  String get coreEstimate;

  /// No description provided for @coreNutrientAbout.
  ///
  /// In en, this message translates to:
  /// **'{nutrient} about {amount}'**
  String coreNutrientAbout(String nutrient, String amount);

  /// No description provided for @coreNutritionNoData.
  ///
  /// In en, this message translates to:
  /// **'We don\'t have nutrition data for these ingredients yet.'**
  String get coreNutritionNoData;

  /// No description provided for @coreNutritionPartial.
  ///
  /// In en, this message translates to:
  /// **'Based on {percent}% of ingredients — some couldn\'t be estimated.'**
  String coreNutritionPartial(int percent);

  /// No description provided for @coreMealAt.
  ///
  /// In en, this message translates to:
  /// **'{meal} at {time}: {title}'**
  String coreMealAt(String meal, String time, String title);

  /// No description provided for @coreMealAtDone.
  ///
  /// In en, this message translates to:
  /// **'{meal} at {time}: {title}, done'**
  String coreMealAtDone(String meal, String time, String title);

  /// No description provided for @coreMorningRoutine.
  ///
  /// In en, this message translates to:
  /// **'Morning routine'**
  String get coreMorningRoutine;

  /// No description provided for @coreSetUpMornings.
  ///
  /// In en, this message translates to:
  /// **'Set up your mornings'**
  String get coreSetUpMornings;

  /// No description provided for @coreMorningSummary.
  ///
  /// In en, this message translates to:
  /// **'Up {wake} · out by {departure} · {minutes} min free'**
  String coreMorningSummary(String wake, String departure, int minutes);

  /// No description provided for @coreMorningPitch.
  ///
  /// In en, this message translates to:
  /// **'A calm plan from alarm to door, with breakfast decided.'**
  String get coreMorningPitch;

  /// No description provided for @coreBreakfastLine.
  ///
  /// In en, this message translates to:
  /// **'Breakfast: {title}'**
  String coreBreakfastLine(String title);

  /// No description provided for @coreChefDemoNote.
  ///
  /// In en, this message translates to:
  /// **'Demo · curated suggestions, no AI'**
  String get coreChefDemoNote;

  /// No description provided for @coreSaidByYou.
  ///
  /// In en, this message translates to:
  /// **'You: {text}'**
  String coreSaidByYou(String text);

  /// No description provided for @coreSaidByChef.
  ///
  /// In en, this message translates to:
  /// **'Chef: {text}'**
  String coreSaidByChef(String text);

  /// No description provided for @coreEvidenceStrength.
  ///
  /// In en, this message translates to:
  /// **'{strength} evidence'**
  String coreEvidenceStrength(String strength);

  /// No description provided for @coreReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed {date}'**
  String coreReviewed(String date);

  /// No description provided for @coreInternalSummary.
  ///
  /// In en, this message translates to:
  /// **'Internal summary, {date} · awaiting professional review'**
  String coreInternalSummary(String date);

  /// No description provided for @coreOverMinutes.
  ///
  /// In en, this message translates to:
  /// **'over {minutes} min'**
  String coreOverMinutes(int minutes);

  /// No description provided for @coreHelpfulHabit.
  ///
  /// In en, this message translates to:
  /// **'helpful habit'**
  String get coreHelpfulHabit;

  /// No description provided for @coreDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get coreDelete;

  /// No description provided for @coreShareJournal.
  ///
  /// In en, this message translates to:
  /// **'Meals you logged, portions and times'**
  String get coreShareJournal;

  /// No description provided for @coreShareNutrition.
  ///
  /// In en, this message translates to:
  /// **'Estimated nutrients from your journal'**
  String get coreShareNutrition;

  /// No description provided for @coreShareGlucose.
  ///
  /// In en, this message translates to:
  /// **'Glucose readings you entered'**
  String get coreShareGlucose;

  /// No description provided for @coreShareOral.
  ///
  /// In en, this message translates to:
  /// **'Sugar and acid exposure log'**
  String get coreShareOral;

  /// No description provided for @coreShareConcerns.
  ///
  /// In en, this message translates to:
  /// **'Hair, skin & nail notes'**
  String get coreShareConcerns;

  /// No description provided for @coreShareDietary.
  ///
  /// In en, this message translates to:
  /// **'Allergies, intolerances and preferences'**
  String get coreShareDietary;

  /// No description provided for @coreAssessmentNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get coreAssessmentNew;

  /// No description provided for @coreAssessmentRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get coreAssessmentRead;

  /// No description provided for @coreAssessmentAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get coreAssessmentAccepted;

  /// No description provided for @coreAssessmentDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get coreAssessmentDeclined;

  /// No description provided for @coreAssessmentDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get coreAssessmentDraft;

  /// No description provided for @coreDemoBanner.
  ///
  /// In en, this message translates to:
  /// **'Demo mode — sample data, no AI used.'**
  String get coreDemoBanner;

  /// No description provided for @coreTabToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get coreTabToday;

  /// No description provided for @coreTabKitchen.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get coreTabKitchen;

  /// No description provided for @coreTabDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get coreTabDiscover;

  /// No description provided for @coreTabJournal.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get coreTabJournal;

  /// No description provided for @coreTabYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get coreTabYou;

  /// No description provided for @corePageNotFound.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get corePageNotFound;

  /// No description provided for @corePageNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'That link doesn\'t lead anywhere in Chefii.'**
  String get corePageNotFoundMessage;

  /// No description provided for @coreGoToToday.
  ///
  /// In en, this message translates to:
  /// **'Go to Today'**
  String get coreGoToToday;

  /// No description provided for @coreAppLoading.
  ///
  /// In en, this message translates to:
  /// **'Chefii is loading'**
  String get coreAppLoading;

  /// No description provided for @coreSnoozeWakeBody.
  ///
  /// In en, this message translates to:
  /// **'Your snoozed alarm. Tap to start your morning.'**
  String get coreSnoozeWakeBody;

  /// No description provided for @coreSnoozeEveningTitle.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow morning'**
  String get coreSnoozeEveningTitle;

  /// No description provided for @coreSnoozeEveningBody.
  ///
  /// In en, this message translates to:
  /// **'Your snoozed evening preview.'**
  String get coreSnoozeEveningBody;

  /// No description provided for @coreSnoozeReminderTitle.
  ///
  /// In en, this message translates to:
  /// **'A gentle reminder'**
  String get coreSnoozeReminderTitle;

  /// No description provided for @coreSnoozeReminderBody.
  ///
  /// In en, this message translates to:
  /// **'Your snoozed reminder from Chefii.'**
  String get coreSnoozeReminderBody;

  /// No description provided for @coreSnoozeAction.
  ///
  /// In en, this message translates to:
  /// **'Snooze 10 min'**
  String get coreSnoozeAction;

  /// No description provided for @coreChannelReminders.
  ///
  /// In en, this message translates to:
  /// **'Meal reminders'**
  String get coreChannelReminders;

  /// No description provided for @coreChannelRemindersDescription.
  ///
  /// In en, this message translates to:
  /// **'Gentle reminders for meals and kitchen tasks'**
  String get coreChannelRemindersDescription;

  /// No description provided for @coreChannelAlarm.
  ///
  /// In en, this message translates to:
  /// **'Morning alarm'**
  String get coreChannelAlarm;

  /// No description provided for @coreChannelAlarmDescription.
  ///
  /// In en, this message translates to:
  /// **'Your morning routine alarm'**
  String get coreChannelAlarmDescription;

  /// No description provided for @coreChannelTimers.
  ///
  /// In en, this message translates to:
  /// **'Cooking timers'**
  String get coreChannelTimers;

  /// No description provided for @coreChannelTimersDescription.
  ///
  /// In en, this message translates to:
  /// **'Alerts when a cooking timer finishes'**
  String get coreChannelTimersDescription;

  /// No description provided for @coreErrNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to continue.'**
  String get coreErrNotSignedIn;

  /// No description provided for @coreErrReceiptDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This receipt looks like one you already scanned.'**
  String get coreErrReceiptDuplicate;

  /// No description provided for @coreErrPlaceNameLength.
  ///
  /// In en, this message translates to:
  /// **'Give the place a name of up to 30 characters.'**
  String get coreErrPlaceNameLength;

  /// No description provided for @coreErrPlaceNameTaken.
  ///
  /// In en, this message translates to:
  /// **'You already have a place called {name}.'**
  String coreErrPlaceNameTaken(String name);

  /// No description provided for @coreErrPlaceLimit.
  ///
  /// In en, this message translates to:
  /// **'You can have up to 12 places.'**
  String get coreErrPlaceLimit;

  /// No description provided for @coreErrBuiltInRename.
  ///
  /// In en, this message translates to:
  /// **'The built-in places can\'t be renamed.'**
  String get coreErrBuiltInRename;

  /// No description provided for @coreErrBuiltInRemove.
  ///
  /// In en, this message translates to:
  /// **'The built-in places can\'t be removed.'**
  String get coreErrBuiltInRemove;

  /// No description provided for @coreErrPlaceNotEmpty.
  ///
  /// In en, this message translates to:
  /// **'Move or use up what\'s stored there first.'**
  String get coreErrPlaceNotEmpty;

  /// No description provided for @coreErrNothingToAdd.
  ///
  /// In en, this message translates to:
  /// **'Nothing to add.'**
  String get coreErrNothingToAdd;

  /// No description provided for @coreErrQuantityNotPositive.
  ///
  /// In en, this message translates to:
  /// **'{product}: quantity must be greater than zero.'**
  String coreErrQuantityNotPositive(String product);

  /// No description provided for @coreErrNothingToDeduct.
  ///
  /// In en, this message translates to:
  /// **'Nothing to deduct.'**
  String get coreErrNothingToDeduct;

  /// No description provided for @coreErrNothingToCorrect.
  ///
  /// In en, this message translates to:
  /// **'Nothing to correct.'**
  String get coreErrNothingToCorrect;

  /// No description provided for @coreErrNegativeCount.
  ///
  /// In en, this message translates to:
  /// **'Counts cannot be negative.'**
  String get coreErrNegativeCount;

  /// No description provided for @coreErrItemGone.
  ///
  /// In en, this message translates to:
  /// **'That item no longer exists.'**
  String get coreErrItemGone;

  /// No description provided for @coreErrWrongUnit.
  ///
  /// In en, this message translates to:
  /// **'{product}: use {unit} for this item.'**
  String coreErrWrongUnit(String product, String unit);

  /// No description provided for @coreErrNothingToUndo.
  ///
  /// In en, this message translates to:
  /// **'Nothing to undo.'**
  String get coreErrNothingToUndo;

  /// No description provided for @coreErrAlreadyUndone.
  ///
  /// In en, this message translates to:
  /// **'This change has already been undone.'**
  String get coreErrAlreadyUndone;

  /// No description provided for @coreErrUndoOfUndo.
  ///
  /// In en, this message translates to:
  /// **'An undo cannot itself be undone.'**
  String get coreErrUndoOfUndo;

  /// No description provided for @coreErrProductNotRecorded.
  ///
  /// In en, this message translates to:
  /// **'No {product} recorded in your kitchen.'**
  String coreErrProductNotRecorded(String product);

  /// No description provided for @coreErrReceiptNotFound.
  ///
  /// In en, this message translates to:
  /// **'Receipt not found.'**
  String get coreErrReceiptNotFound;

  /// No description provided for @coreErrReceiptNotEditable.
  ///
  /// In en, this message translates to:
  /// **'This receipt can no longer be edited.'**
  String get coreErrReceiptNotEditable;

  /// No description provided for @coreErrReceiptNotReady.
  ///
  /// In en, this message translates to:
  /// **'This receipt is not ready to import.'**
  String get coreErrReceiptNotReady;

  /// No description provided for @coreErrReceiptLinesIncomplete.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item needs a name and quantity before importing.} other{{count} items need a name and quantity before importing.}}'**
  String coreErrReceiptLinesIncomplete(int count);

  /// No description provided for @coreErrReceiptNoFoodItems.
  ///
  /// In en, this message translates to:
  /// **'There are no food items to add.'**
  String get coreErrReceiptNoFoodItems;

  /// No description provided for @coreErrReceiptNoPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add at least one photo.'**
  String get coreErrReceiptNoPhotos;

  /// No description provided for @coreErrReceiptTooManyPages.
  ///
  /// In en, this message translates to:
  /// **'Up to {max} pages per receipt.'**
  String coreErrReceiptTooManyPages(int max);

  /// No description provided for @coreErrImageEmpty.
  ///
  /// In en, this message translates to:
  /// **'That image appears to be empty.'**
  String get coreErrImageEmpty;

  /// No description provided for @coreErrImageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That image is too large (over 12 MB). Try a closer, single-page photo.'**
  String get coreErrImageTooLarge;

  /// No description provided for @coreErrImageFormat.
  ///
  /// In en, this message translates to:
  /// **'Please use a JPEG, PNG, HEIC or WebP photo.'**
  String get coreErrImageFormat;

  /// No description provided for @coreErrAiUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The kitchen assistant is unavailable right now.'**
  String get coreErrAiUnavailable;

  /// No description provided for @coreErrAuthCredentialMismatch.
  ///
  /// In en, this message translates to:
  /// **'That email and password don\'t match.'**
  String get coreErrAuthCredentialMismatch;

  /// No description provided for @coreErrAuthEmailInUse.
  ///
  /// In en, this message translates to:
  /// **'An account already exists for that email. Try signing in.'**
  String get coreErrAuthEmailInUse;

  /// No description provided for @coreErrAuthWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Please choose a longer password (at least 8 characters).'**
  String get coreErrAuthWeakPassword;

  /// No description provided for @coreErrAuthInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'That email address doesn\'t look right.'**
  String get coreErrAuthInvalidEmail;

  /// No description provided for @coreErrAuthOffline.
  ///
  /// In en, this message translates to:
  /// **'You appear to be offline. Please try again.'**
  String get coreErrAuthOffline;

  /// No description provided for @coreErrAuthTooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a moment and try again.'**
  String get coreErrAuthTooManyRequests;

  /// No description provided for @coreErrAuthRecentLogin.
  ///
  /// In en, this message translates to:
  /// **'For your security, please sign in again to continue.'**
  String get coreErrAuthRecentLogin;

  /// No description provided for @coreErrAuthCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was cancelled.'**
  String get coreErrAuthCancelled;

  /// No description provided for @coreErrAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed.'**
  String get coreErrAuthFailed;

  /// No description provided for @coreErrAuthFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Please try again.'**
  String get coreErrAuthFailedRetry;

  /// No description provided for @coreErrAuthNoGoogleToken.
  ///
  /// In en, this message translates to:
  /// **'Google did not return an identity token.'**
  String get coreErrAuthNoGoogleToken;

  /// No description provided for @coreErrAuthSignInAgain.
  ///
  /// In en, this message translates to:
  /// **'Please sign in again.'**
  String get coreErrAuthSignInAgain;

  /// No description provided for @coreErrAuthPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to continue.'**
  String get coreErrAuthPasswordRequired;

  /// No description provided for @coreErrAuthAppleNeedsFirebase.
  ///
  /// In en, this message translates to:
  /// **'Apple sign-in needs Firebase configured. Use the demo account.'**
  String get coreErrAuthAppleNeedsFirebase;

  /// No description provided for @coreErrAuthGoogleNeedsFirebase.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in needs Firebase configured. Use the demo account.'**
  String get coreErrAuthGoogleNeedsFirebase;

  /// No description provided for @coreErrOwnerNotRemovable.
  ///
  /// In en, this message translates to:
  /// **'The owner cannot be removed.'**
  String get coreErrOwnerNotRemovable;

  /// No description provided for @coreErrProfessionalNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Only verified professionals can be granted access.'**
  String get coreErrProfessionalNotVerified;

  /// No description provided for @coreErrNoShareCategories.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one category to share.'**
  String get coreErrNoShareCategories;

  /// No description provided for @coreErrNoActivePermission.
  ///
  /// In en, this message translates to:
  /// **'No active permission for {category}.'**
  String coreErrNoActivePermission(String category);

  /// No description provided for @discoverFilterAvailableNow.
  ///
  /// In en, this message translates to:
  /// **'Available now'**
  String get discoverFilterAvailableNow;

  /// No description provided for @discoverFilterBreakfast.
  ///
  /// In en, this message translates to:
  /// **'Breakfast'**
  String get discoverFilterBreakfast;

  /// No description provided for @discoverFilterLunch.
  ///
  /// In en, this message translates to:
  /// **'Lunch'**
  String get discoverFilterLunch;

  /// No description provided for @discoverFilterDinner.
  ///
  /// In en, this message translates to:
  /// **'Dinner'**
  String get discoverFilterDinner;

  /// No description provided for @discoverFilterSnacks.
  ///
  /// In en, this message translates to:
  /// **'Snacks'**
  String get discoverFilterSnacks;

  /// No description provided for @discoverFilter15Minute.
  ///
  /// In en, this message translates to:
  /// **'15-minute'**
  String get discoverFilter15Minute;

  /// No description provided for @discoverFilterHighProtein.
  ///
  /// In en, this message translates to:
  /// **'High-protein'**
  String get discoverFilterHighProtein;

  /// No description provided for @discoverFilterVegetarian.
  ///
  /// In en, this message translates to:
  /// **'Vegetarian'**
  String get discoverFilterVegetarian;

  /// No description provided for @discoverFilterComfort.
  ///
  /// In en, this message translates to:
  /// **'Comfort'**
  String get discoverFilterComfort;

  /// No description provided for @discoverFilterWorldCuisines.
  ///
  /// In en, this message translates to:
  /// **'World cuisines'**
  String get discoverFilterWorldCuisines;

  /// No description provided for @discoverMealPlanner.
  ///
  /// In en, this message translates to:
  /// **'Meal planner'**
  String get discoverMealPlanner;

  /// No description provided for @discoverAskChef.
  ///
  /// In en, this message translates to:
  /// **'Ask the chef'**
  String get discoverAskChef;

  /// No description provided for @discoverEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discoverEyebrow;

  /// No description provided for @discoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Something delicious'**
  String get discoverTitle;

  /// No description provided for @discoverCookWith.
  ///
  /// In en, this message translates to:
  /// **'Cook with {ingredient}'**
  String discoverCookWith(String ingredient);

  /// No description provided for @discoverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every recipe here suits your household\'s dietary needs.'**
  String get discoverSubtitle;

  /// No description provided for @discoverSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search recipes or ingredients'**
  String get discoverSearchHint;

  /// No description provided for @discoverNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No recipes match'**
  String get discoverNoMatchTitle;

  /// No description provided for @discoverNoMatchMessage.
  ///
  /// In en, this message translates to:
  /// **'Try another filter, or ask your chef to create something.'**
  String get discoverNoMatchMessage;

  /// No description provided for @discoverUsesExpiring.
  ///
  /// In en, this message translates to:
  /// **'Uses something that needs eating soon'**
  String get discoverUsesExpiring;

  /// No description provided for @discoverNutritionFootnote.
  ///
  /// In en, this message translates to:
  /// **'Nutrition is estimated per serving from reference data. Protein-rich means at least {grams} g per serving.'**
  String discoverNutritionFootnote(int grams);

  /// No description provided for @discoverNutritionFootnoteHidden.
  ///
  /// In en, this message translates to:
  /// **'Nutrition is estimated per serving from reference data (hidden in your preferences). Protein-rich means at least {grams} g per serving.'**
  String discoverNutritionFootnoteHidden(int grams);

  /// No description provided for @discoverProteinLabel.
  ///
  /// In en, this message translates to:
  /// **'{grams} g protein'**
  String discoverProteinLabel(int grams);

  /// No description provided for @healthOpenLinkError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link.'**
  String get healthOpenLinkError;

  /// No description provided for @healthNutritionEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Nutrition'**
  String get healthNutritionEyebrow;

  /// No description provided for @healthYourNutrition.
  ///
  /// In en, this message translates to:
  /// **'Your nutrition'**
  String get healthYourNutrition;

  /// No description provided for @healthDailyAverageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Daily average across 1 logged day} other{Daily average across {count} logged days}}'**
  String healthDailyAverageSubtitle(int count);

  /// No description provided for @healthInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get healthInsights;

  /// No description provided for @healthDaysSegment.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String healthDaysSegment(int count);

  /// No description provided for @healthNoMealsTitle.
  ///
  /// In en, this message translates to:
  /// **'No meals logged yet'**
  String get healthNoMealsTitle;

  /// No description provided for @healthNoMealsMessage.
  ///
  /// In en, this message translates to:
  /// **'Cook with Chefii or log meals in your journal to see estimates here.'**
  String get healthNoMealsMessage;

  /// No description provided for @healthLogMeal.
  ///
  /// In en, this message translates to:
  /// **'Log a meal'**
  String get healthLogMeal;

  /// No description provided for @healthEstimatesNote.
  ///
  /// In en, this message translates to:
  /// **'Estimates from recipes and reference data.'**
  String get healthEstimatesNote;

  /// No description provided for @healthMissingDataNote.
  ///
  /// In en, this message translates to:
  /// **'Some meals had no nutrition data ({percent}%), so totals are likely low.'**
  String healthMissingDataNote(int percent);

  /// No description provided for @healthDailyValueNote.
  ///
  /// In en, this message translates to:
  /// **'Daily Values are Health Canada\'s label reference — a yardstick, not a personal target.'**
  String get healthDailyValueNote;

  /// No description provided for @healthNutrientBarSemantics.
  ///
  /// In en, this message translates to:
  /// **'{nutrient}: about {amount}'**
  String healthNutrientBarSemantics(String nutrient, String amount);

  /// No description provided for @healthNutrientBarSemanticsDv.
  ///
  /// In en, this message translates to:
  /// **'{nutrient}: about {amount}, {percent} percent of the Daily Value'**
  String healthNutrientBarSemanticsDv(
    String nutrient,
    String amount,
    int percent,
  );

  /// No description provided for @healthPercentDv.
  ///
  /// In en, this message translates to:
  /// **'{percent}% DV'**
  String healthPercentDv(int percent);

  /// No description provided for @healthNotEnoughHistory.
  ///
  /// In en, this message translates to:
  /// **'Not enough history yet'**
  String get healthNotEnoughHistory;

  /// No description provided for @healthPerDay.
  ///
  /// In en, this message translates to:
  /// **'≈ {amount} a day'**
  String healthPerDay(String amount);

  /// No description provided for @healthSteadyAt.
  ///
  /// In en, this message translates to:
  /// **'Steady at ≈ {amount} a day'**
  String healthSteadyAt(String amount);

  /// No description provided for @healthTrendUp.
  ///
  /// In en, this message translates to:
  /// **'Up {percent}% vs the week before'**
  String healthTrendUp(int percent);

  /// No description provided for @healthTrendDown.
  ///
  /// In en, this message translates to:
  /// **'Down {percent}% vs the week before'**
  String healthTrendDown(int percent);

  /// No description provided for @healthInsightsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Patterns from your journal, explained with evidence.'**
  String get healthInsightsSubtitle;

  /// No description provided for @healthEvidenceLibrary.
  ///
  /// In en, this message translates to:
  /// **'Evidence library'**
  String get healthEvidenceLibrary;

  /// No description provided for @healthInsightsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Insights need a few days of meals'**
  String get healthInsightsEmptyTitle;

  /// No description provided for @healthInsightsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Keep cooking and logging — we\'ll look for patterns after a few days.'**
  String get healthInsightsEmptyMessage;

  /// No description provided for @healthTrends.
  ///
  /// In en, this message translates to:
  /// **'Trends'**
  String get healthTrends;

  /// No description provided for @healthVarietyThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Variety this week'**
  String get healthVarietyThisWeek;

  /// No description provided for @healthDifferentMeals.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{different meals} other{different meals}}'**
  String healthDifferentMeals(int count);

  /// No description provided for @healthPlantFoods.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{plant foods in Chefii recipes} other{plant foods in Chefii recipes}}'**
  String healthPlantFoods(int count);

  /// No description provided for @healthSomethingToTry.
  ///
  /// In en, this message translates to:
  /// **'Something to try'**
  String get healthSomethingToTry;

  /// No description provided for @healthFibrePerServing.
  ///
  /// In en, this message translates to:
  /// **'≈ {grams} g fibre per serving'**
  String healthFibrePerServing(int grams);

  /// No description provided for @healthAvailabilityLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Everything on hand} =1{1 ingredient to buy} other{{count} ingredients to buy}}'**
  String healthAvailabilityLabel(int count);

  /// No description provided for @healthMoreToExplore.
  ///
  /// In en, this message translates to:
  /// **'More to explore'**
  String get healthMoreToExplore;

  /// No description provided for @healthHairSkinNails.
  ///
  /// In en, this message translates to:
  /// **'Hair, skin & nails'**
  String get healthHairSkinNails;

  /// No description provided for @healthSmileAndFood.
  ///
  /// In en, this message translates to:
  /// **'Smile & Food'**
  String get healthSmileAndFood;

  /// No description provided for @healthEducationDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Chefii provides general nutrition education, not medical advice. For personal guidance, talk to a registered dietitian.'**
  String get healthEducationDisclaimer;

  /// No description provided for @healthHairSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A private notebook, plus what the evidence does — and doesn\'t — say.'**
  String get healthHairSubtitle;

  /// No description provided for @healthHairCausesNote.
  ///
  /// In en, this message translates to:
  /// **'Changes in hair, skin and nails have many causes besides diet — hormones, thyroid, stress, medications, skin conditions and genetics. Sudden hair loss, rashes, or nail changes that don\'t settle are worth seeing a doctor, dermatologist or pharmacist about.'**
  String get healthHairCausesNote;

  /// No description provided for @healthNoteAConcern.
  ///
  /// In en, this message translates to:
  /// **'Note a concern'**
  String get healthNoteAConcern;

  /// No description provided for @healthConcernHair.
  ///
  /// In en, this message translates to:
  /// **'Hair'**
  String get healthConcernHair;

  /// No description provided for @healthConcernSkin.
  ///
  /// In en, this message translates to:
  /// **'Skin'**
  String get healthConcernSkin;

  /// No description provided for @healthConcernNails.
  ///
  /// In en, this message translates to:
  /// **'Nails'**
  String get healthConcernNails;

  /// No description provided for @healthConcernEnergy.
  ///
  /// In en, this message translates to:
  /// **'Energy'**
  String get healthConcernEnergy;

  /// No description provided for @healthConcernDigestion.
  ///
  /// In en, this message translates to:
  /// **'Digestion'**
  String get healthConcernDigestion;

  /// No description provided for @healthConcernOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get healthConcernOther;

  /// No description provided for @healthWhatHaveYouNoticed.
  ///
  /// In en, this message translates to:
  /// **'What have you noticed?'**
  String get healthWhatHaveYouNoticed;

  /// No description provided for @healthBotherLevel.
  ///
  /// In en, this message translates to:
  /// **'How much is it bothering you? ({severity} of 5)'**
  String healthBotherLevel(int severity);

  /// No description provided for @healthBotherSemantics.
  ///
  /// In en, this message translates to:
  /// **'How much it bothers you, 1 to 5'**
  String get healthBotherSemantics;

  /// No description provided for @healthSaveNote.
  ///
  /// In en, this message translates to:
  /// **'Save note'**
  String get healthSaveNote;

  /// No description provided for @healthSavedPrivately.
  ///
  /// In en, this message translates to:
  /// **'Saved privately'**
  String get healthSavedPrivately;

  /// No description provided for @healthYourNotes.
  ///
  /// In en, this message translates to:
  /// **'Your notes'**
  String get healthYourNotes;

  /// No description provided for @healthDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get healthDelete;

  /// No description provided for @healthWhatEvidenceSays.
  ///
  /// In en, this message translates to:
  /// **'What the evidence says'**
  String get healthWhatEvidenceSays;

  /// No description provided for @healthShareWithDietitian.
  ///
  /// In en, this message translates to:
  /// **'Share with a dietitian'**
  String get healthShareWithDietitian;

  /// No description provided for @healthEvidence.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get healthEvidence;

  /// No description provided for @healthHowWeKnow.
  ///
  /// In en, this message translates to:
  /// **'How we know'**
  String get healthHowWeKnow;

  /// No description provided for @healthEvidenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every nutrition statement in Chefii, its sources and its limits.'**
  String get healthEvidenceSubtitle;

  /// No description provided for @healthReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get healthReview;

  /// No description provided for @healthProfessionallyReviewed.
  ///
  /// In en, this message translates to:
  /// **'Professionally reviewed {date}'**
  String healthProfessionallyReviewed(String date);

  /// No description provided for @healthInternalSummary.
  ///
  /// In en, this message translates to:
  /// **'Internal summary ({date}), awaiting professional review'**
  String healthInternalSummary(String date);

  /// No description provided for @healthLimitations.
  ///
  /// In en, this message translates to:
  /// **'Limitations'**
  String get healthLimitations;

  /// No description provided for @healthFoods.
  ///
  /// In en, this message translates to:
  /// **'Foods'**
  String get healthFoods;

  /// No description provided for @healthLabelColon.
  ///
  /// In en, this message translates to:
  /// **'{label}:'**
  String healthLabelColon(String label);

  /// No description provided for @healthCitationPending.
  ///
  /// In en, this message translates to:
  /// **'Source: citation pending review.'**
  String get healthCitationPending;

  /// No description provided for @healthMethodNote.
  ///
  /// In en, this message translates to:
  /// **'Method: we prefer national guidelines and systematic reviews; single studies are not used for recommendations.'**
  String get healthMethodNote;

  /// No description provided for @healthNutrientEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Nutrient'**
  String get healthNutrientEyebrow;

  /// No description provided for @healthNoDataYet.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get healthNoDataYet;

  /// No description provided for @healthLogMealsForEstimate.
  ///
  /// In en, this message translates to:
  /// **'Log meals to see an estimate.'**
  String get healthLogMealsForEstimate;

  /// No description provided for @healthAverageThisWeek.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Average over 1 logged day this week} other{Average over {count} logged days this week}}'**
  String healthAverageThisWeek(int count);

  /// No description provided for @healthReferenceDailyValue.
  ///
  /// In en, this message translates to:
  /// **'Reference: {amount} (Daily Value, Health Canada, Table of Daily Values)'**
  String healthReferenceDailyValue(String amount);

  /// No description provided for @healthReferenceOther.
  ///
  /// In en, this message translates to:
  /// **'Reference: {amount} ({kind}, {source})'**
  String healthReferenceOther(String amount, String kind, String source);

  /// No description provided for @healthDataCompleteness.
  ///
  /// In en, this message translates to:
  /// **'Data completeness: {percent}% of meals had nutrition estimates.'**
  String healthDataCompleteness(int percent);

  /// No description provided for @healthBiggestContributors.
  ///
  /// In en, this message translates to:
  /// **'Biggest contributors this week'**
  String get healthBiggestContributors;

  /// No description provided for @healthRichSources.
  ///
  /// In en, this message translates to:
  /// **'Rich sources'**
  String get healthRichSources;

  /// No description provided for @healthPer100g.
  ///
  /// In en, this message translates to:
  /// **'{amount} / 100 g'**
  String healthPer100g(String amount);

  /// No description provided for @healthIndividualNeeds.
  ///
  /// In en, this message translates to:
  /// **'Individual needs vary. Estimates can\'t account for exact brands, portions, or added salt.'**
  String get healthIndividualNeeds;

  /// No description provided for @healthWellnessEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Wellness'**
  String get healthWellnessEyebrow;

  /// No description provided for @healthSmileIntroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Learn how the timing of sugary and acidic foods affects your teeth.'**
  String get healthSmileIntroSubtitle;

  /// No description provided for @healthTurnOnSmile.
  ///
  /// In en, this message translates to:
  /// **'Turn on Smile & Food'**
  String get healthTurnOnSmile;

  /// No description provided for @healthSmileOptionalNote.
  ///
  /// In en, this message translates to:
  /// **'This is optional education. It isn\'t a dental assessment, and your entries stay private unless you choose to share them.'**
  String get healthSmileOptionalNote;

  /// No description provided for @healthSmileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap to log. It\'s about frequency and timing, not perfection.'**
  String get healthSmileSubtitle;

  /// No description provided for @healthHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get healthHistory;

  /// No description provided for @healthSugarExposuresToday.
  ///
  /// In en, this message translates to:
  /// **'sugar exposures today'**
  String get healthSugarExposuresToday;

  /// No description provided for @healthAcidExposuresToday.
  ///
  /// In en, this message translates to:
  /// **'acid exposures today'**
  String get healthAcidExposuresToday;

  /// No description provided for @healthHelpfulHabits.
  ///
  /// In en, this message translates to:
  /// **'helpful habits'**
  String get healthHelpfulHabits;

  /// No description provided for @healthLogNow.
  ///
  /// In en, this message translates to:
  /// **'Log now'**
  String get healthLogNow;

  /// No description provided for @healthLoggedMessage.
  ///
  /// In en, this message translates to:
  /// **'{item} logged'**
  String healthLoggedMessage(String item);

  /// No description provided for @healthKinderChoices.
  ///
  /// In en, this message translates to:
  /// **'Kinder choices'**
  String get healthKinderChoices;

  /// No description provided for @healthTipSweetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep sweets with meals'**
  String get healthTipSweetsTitle;

  /// No description provided for @healthTipSweetsBody.
  ///
  /// In en, this message translates to:
  /// **'One sugar exposure at dinner is gentler on teeth than the same amount spread through the afternoon.'**
  String get healthTipSweetsBody;

  /// No description provided for @healthTipFinishTitle.
  ///
  /// In en, this message translates to:
  /// **'Finish with water or cheese'**
  String get healthTipFinishTitle;

  /// No description provided for @healthTipFinishBody.
  ///
  /// In en, this message translates to:
  /// **'Rinsing with water or ending on cheese helps your mouth recover after eating.'**
  String get healthTipFinishBody;

  /// No description provided for @healthTipSipTitle.
  ///
  /// In en, this message translates to:
  /// **'Sip, then stop'**
  String get healthTipSipTitle;

  /// No description provided for @healthTipSipBody.
  ///
  /// In en, this message translates to:
  /// **'If you enjoy juice or soda, drinking it with a meal rather than over an hour limits acid time.'**
  String get healthTipSipBody;

  /// No description provided for @healthTipBrushTitle.
  ///
  /// In en, this message translates to:
  /// **'Wait to brush after acid'**
  String get healthTipBrushTitle;

  /// No description provided for @healthTipBrushBody.
  ///
  /// In en, this message translates to:
  /// **'Many dental professionals suggest waiting a while after acidic food or drink before brushing. Ask your dentist what\'s right for you.'**
  String get healthTipBrushBody;

  /// No description provided for @healthSmileFooter.
  ///
  /// In en, this message translates to:
  /// **'Education only. For tooth pain, sensitivity or concerns, see your dentist.'**
  String get healthSmileFooter;

  /// No description provided for @healthHistoryExposuresPerDay.
  ///
  /// In en, this message translates to:
  /// **'About {rate} sugar or acid exposures a day this week'**
  String healthHistoryExposuresPerDay(String rate);

  /// No description provided for @healthNothingLoggedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged yet'**
  String get healthNothingLoggedYet;

  /// No description provided for @healthLogWillAppear.
  ///
  /// In en, this message translates to:
  /// **'Your log will appear here.'**
  String get healthLogWillAppear;

  /// No description provided for @healthDiabetesConsentText.
  ///
  /// In en, this message translates to:
  /// **'I choose to store glucose readings I enter in Chefii. I understand Chefii does not diagnose, interpret readings, recommend insulin or medication, or replace my glucose meter\'s or CGM\'s alarms. My readings are private and only shared if I grant access.'**
  String get healthDiabetesConsentText;

  /// No description provided for @healthOptionalEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get healthOptionalEyebrow;

  /// No description provided for @healthGlucoseJournal.
  ///
  /// In en, this message translates to:
  /// **'Glucose journal'**
  String get healthGlucoseJournal;

  /// No description provided for @healthDiabetesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'For people who already track glucose and want it alongside their meals.'**
  String get healthDiabetesSubtitle;

  /// No description provided for @healthTurnOffGlucose.
  ///
  /// In en, this message translates to:
  /// **'Turn off glucose features'**
  String get healthTurnOffGlucose;

  /// No description provided for @healthTurnOnGlucose.
  ///
  /// In en, this message translates to:
  /// **'Turn on glucose journal'**
  String get healthTurnOnGlucose;

  /// No description provided for @healthGlucoseOn.
  ///
  /// In en, this message translates to:
  /// **'Glucose journal is on.'**
  String get healthGlucoseOn;

  /// No description provided for @healthOpenGlucose.
  ///
  /// In en, this message translates to:
  /// **'Open glucose journal'**
  String get healthOpenGlucose;

  /// No description provided for @healthDiabetesPointRecord.
  ///
  /// In en, this message translates to:
  /// **'Record readings you take, with the time and context.'**
  String get healthDiabetesPointRecord;

  /// No description provided for @healthDiabetesPointMeals.
  ///
  /// In en, this message translates to:
  /// **'See them next to the meals in your journal.'**
  String get healthDiabetesPointMeals;

  /// No description provided for @healthDiabetesPointNoAdvice.
  ///
  /// In en, this message translates to:
  /// **'No predictions, scores, diagnoses or dosing advice — ever.'**
  String get healthDiabetesPointNoAdvice;

  /// No description provided for @healthDiabetesPointNotAlarm.
  ///
  /// In en, this message translates to:
  /// **'Not an alarm. Keep using your meter or CGM alerts.'**
  String get healthDiabetesPointNotAlarm;

  /// No description provided for @healthDiabetesPointPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private to you. Shared only with a professional you choose.'**
  String get healthDiabetesPointPrivate;

  /// No description provided for @healthUnits.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get healthUnits;

  /// No description provided for @healthUnderstandJournal.
  ///
  /// In en, this message translates to:
  /// **'I understand this is a journal, not a medical device'**
  String get healthUnderstandJournal;

  /// No description provided for @healthConsentStore.
  ///
  /// In en, this message translates to:
  /// **'I consent to Chefii storing my glucose readings'**
  String get healthConsentStore;

  /// No description provided for @healthSymptomsWarning.
  ///
  /// In en, this message translates to:
  /// **'If you have symptoms of very high or low blood sugar, follow your care plan or seek medical help.'**
  String get healthSymptomsWarning;

  /// No description provided for @healthEnterNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a number.'**
  String get healthEnterNumber;

  /// No description provided for @healthEnterPositive.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive value.'**
  String get healthEnterPositive;

  /// No description provided for @healthValueOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'That value looks outside what meters typically report. Please double-check it.'**
  String get healthValueOutOfRange;

  /// No description provided for @healthGlucoseOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Glucose journal is off'**
  String get healthGlucoseOffTitle;

  /// No description provided for @healthGlucoseOffConsent.
  ///
  /// In en, this message translates to:
  /// **'Turn it on with explicit consent first.'**
  String get healthGlucoseOffConsent;

  /// No description provided for @healthSetUp.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get healthSetUp;

  /// No description provided for @healthGlucoseEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Glucose'**
  String get healthGlucoseEyebrow;

  /// No description provided for @healthGlucoseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your readings, as you entered them.'**
  String get healthGlucoseSubtitle;

  /// No description provided for @healthTimelineWithMeals.
  ///
  /// In en, this message translates to:
  /// **'Timeline with meals'**
  String get healthTimelineWithMeals;

  /// No description provided for @healthAddReading.
  ///
  /// In en, this message translates to:
  /// **'Add reading'**
  String get healthAddReading;

  /// No description provided for @healthReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get healthReading;

  /// No description provided for @healthContextFasting.
  ///
  /// In en, this message translates to:
  /// **'Fasting'**
  String get healthContextFasting;

  /// No description provided for @healthContextBeforeMeal.
  ///
  /// In en, this message translates to:
  /// **'Before meal'**
  String get healthContextBeforeMeal;

  /// No description provided for @healthContextAfterMeal.
  ///
  /// In en, this message translates to:
  /// **'After meal'**
  String get healthContextAfterMeal;

  /// No description provided for @healthContextBedtime.
  ///
  /// In en, this message translates to:
  /// **'Bedtime'**
  String get healthContextBedtime;

  /// No description provided for @healthContextOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get healthContextOther;

  /// No description provided for @healthDayAtTime.
  ///
  /// In en, this message translates to:
  /// **'{day} at {time}'**
  String healthDayAtTime(String day, String time);

  /// No description provided for @healthReadings.
  ///
  /// In en, this message translates to:
  /// **'Readings'**
  String get healthReadings;

  /// No description provided for @healthNoReadings.
  ///
  /// In en, this message translates to:
  /// **'No readings yet.'**
  String get healthNoReadings;

  /// No description provided for @healthSourceManual.
  ///
  /// In en, this message translates to:
  /// **'entered by you'**
  String get healthSourceManual;

  /// No description provided for @healthSourceHealthApp.
  ///
  /// In en, this message translates to:
  /// **'from Health app'**
  String get healthSourceHealthApp;

  /// No description provided for @healthSourceDevice.
  ///
  /// In en, this message translates to:
  /// **'from {device}'**
  String healthSourceDevice(String device);

  /// No description provided for @healthDevice.
  ///
  /// In en, this message translates to:
  /// **'device'**
  String get healthDevice;

  /// No description provided for @healthEnteredAs.
  ///
  /// In en, this message translates to:
  /// **'entered as {value}'**
  String healthEnteredAs(String value);

  /// No description provided for @healthNoHealthImport.
  ///
  /// In en, this message translates to:
  /// **'Reading from Apple Health or Health Connect isn\'t available yet. Chefii never interprets readings.'**
  String get healthNoHealthImport;

  /// No description provided for @healthGlucoseOffShort.
  ///
  /// In en, this message translates to:
  /// **'Turn it on first.'**
  String get healthGlucoseOffShort;

  /// No description provided for @healthTimelineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Meals and readings in order. No interpretation.'**
  String get healthTimelineSubtitle;

  /// No description provided for @healthPreviousDay.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get healthPreviousDay;

  /// No description provided for @healthNextDay.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get healthNextDay;

  /// No description provided for @healthNothingRecorded.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded'**
  String get healthNothingRecorded;

  /// No description provided for @healthTimelineEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Meals and readings for this day will appear here.'**
  String get healthTimelineEmptyMessage;

  /// No description provided for @healthTimelineFooter.
  ///
  /// In en, this message translates to:
  /// **'Discuss patterns with your diabetes care team. Chefii does not replace glucose alarms or medical advice.'**
  String get healthTimelineFooter;

  /// No description provided for @journalNutritionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Nutrition'**
  String get journalNutritionTooltip;

  /// No description provided for @journalMoreTooltip.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get journalMoreTooltip;

  /// No description provided for @journalFullHistory.
  ///
  /// In en, this message translates to:
  /// **'Full history'**
  String get journalFullHistory;

  /// No description provided for @journalEatingPatterns.
  ///
  /// In en, this message translates to:
  /// **'Eating patterns'**
  String get journalEatingPatterns;

  /// No description provided for @journalMealReminders.
  ///
  /// In en, this message translates to:
  /// **'Meal reminders'**
  String get journalMealReminders;

  /// No description provided for @journalEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Journal'**
  String get journalEyebrow;

  /// No description provided for @journalPreviousDay.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get journalPreviousDay;

  /// No description provided for @journalNextDay.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get journalNextDay;

  /// No description provided for @journalLogAMeal.
  ///
  /// In en, this message translates to:
  /// **'Log a meal'**
  String get journalLogAMeal;

  /// No description provided for @journalEmptyTodayTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged yet today'**
  String get journalEmptyTodayTitle;

  /// No description provided for @journalEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged'**
  String get journalEmptyTitle;

  /// No description provided for @journalEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Meals you cook in Chefii are logged automatically. You can also add anything you ate.'**
  String get journalEmptyMessage;

  /// No description provided for @journalPortionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{portions} portion} other{{portions} portions}}'**
  String journalPortionCount(num count, String portions);

  /// No description provided for @journalRepeatMeal.
  ///
  /// In en, this message translates to:
  /// **'Repeat {title}'**
  String journalRepeatMeal(String title);

  /// No description provided for @journalLoggedAgain.
  ///
  /// In en, this message translates to:
  /// **'Logged {title} again'**
  String journalLoggedAgain(String title);

  /// No description provided for @journalDaySoFar.
  ///
  /// In en, this message translates to:
  /// **'Day so far'**
  String get journalDaySoFar;

  /// No description provided for @journalEstimatedIntake.
  ///
  /// In en, this message translates to:
  /// **'Estimated intake'**
  String get journalEstimatedIntake;

  /// No description provided for @journalMealCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 meal} other{{count} meals}}'**
  String journalMealCount(int count);

  /// No description provided for @journalHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get journalHistoryTitle;

  /// No description provided for @journalHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap any meal to correct it.'**
  String get journalHistorySubtitle;

  /// No description provided for @journalHistoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get journalHistoryEmptyTitle;

  /// No description provided for @journalHistoryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Your meals will build up here.'**
  String get journalHistoryEmptyMessage;

  /// No description provided for @journalEntryNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Entry not found'**
  String get journalEntryNotFoundTitle;

  /// No description provided for @journalEntryNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted.'**
  String get journalEntryNotFoundMessage;

  /// No description provided for @journalDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get journalDelete;

  /// No description provided for @journalDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this entry?'**
  String get journalDeleteTitle;

  /// No description provided for @journalDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes it from your journal. Your kitchen isn\'t changed.'**
  String get journalDeleteMessage;

  /// No description provided for @journalSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get journalSaveChanges;

  /// No description provided for @journalDayAtTime.
  ///
  /// In en, this message translates to:
  /// **'{day} at {time}'**
  String journalDayAtTime(String day, String time);

  /// No description provided for @journalPortions.
  ///
  /// In en, this message translates to:
  /// **'Portions'**
  String get journalPortions;

  /// No description provided for @journalEstimated.
  ///
  /// In en, this message translates to:
  /// **'Estimated'**
  String get journalEstimated;

  /// No description provided for @journalForPortions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{for {portions} portion} other{for {portions} portions}}'**
  String journalForPortions(num count, String portions);

  /// No description provided for @journalViewRecipe.
  ///
  /// In en, this message translates to:
  /// **'View recipe'**
  String get journalViewRecipe;

  /// No description provided for @journalQuickTitle.
  ///
  /// In en, this message translates to:
  /// **'What did you eat?'**
  String get journalQuickTitle;

  /// No description provided for @journalLogMeal.
  ///
  /// In en, this message translates to:
  /// **'Log meal'**
  String get journalLogMeal;

  /// No description provided for @journalAiFeatureEstimatingMeals.
  ///
  /// In en, this message translates to:
  /// **'estimating meals'**
  String get journalAiFeatureEstimatingMeals;

  /// No description provided for @journalMealLogged.
  ///
  /// In en, this message translates to:
  /// **'{title} logged'**
  String journalMealLogged(String title);

  /// No description provided for @journalQuickHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Greek yogurt with berries'**
  String get journalQuickHint;

  /// No description provided for @journalListening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get journalListening;

  /// No description provided for @journalSpeak.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get journalSpeak;

  /// No description provided for @journalVoiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Voice isn\'t available — try your keyboard\'s dictation.'**
  String get journalVoiceUnavailable;

  /// No description provided for @journalAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get journalAddPhoto;

  /// No description provided for @journalPhotoAdded.
  ///
  /// In en, this message translates to:
  /// **'Photo added'**
  String get journalPhotoAdded;

  /// No description provided for @journalCameraOff.
  ///
  /// In en, this message translates to:
  /// **'Camera access is off. You can still describe the meal.'**
  String get journalCameraOff;

  /// No description provided for @journalEstimateNutrition.
  ///
  /// In en, this message translates to:
  /// **'Estimate nutrition'**
  String get journalEstimateNutrition;

  /// No description provided for @journalSavedRecipe.
  ///
  /// In en, this message translates to:
  /// **'Saved recipe'**
  String get journalSavedRecipe;

  /// No description provided for @journalDemoEstimate.
  ///
  /// In en, this message translates to:
  /// **'Demo estimate from reference data — no AI used.'**
  String get journalDemoEstimate;

  /// No description provided for @journalDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get journalDetails;

  /// No description provided for @journalRemindersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Gentle nudges, never nagging. Quiet hours are always respected.'**
  String get journalRemindersSubtitle;

  /// No description provided for @journalSaveReminders.
  ///
  /// In en, this message translates to:
  /// **'Save reminders'**
  String get journalSaveReminders;

  /// No description provided for @journalNotificationsOff.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off for Chefii in Settings.'**
  String get journalNotificationsOff;

  /// No description provided for @journalReminderNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'{meal} time'**
  String journalReminderNotificationTitle(String meal);

  /// No description provided for @journalReminderNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'A gentle reminder from Chefii.'**
  String get journalReminderNotificationBody;

  /// No description provided for @journalRemindersSaved.
  ///
  /// In en, this message translates to:
  /// **'Reminders saved'**
  String get journalRemindersSaved;

  /// No description provided for @journalRemindersSavedSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Saved. {meals} falls in quiet hours and won\'t notify.} other{Saved. {meals} fall in quiet hours and won\'t notify.}}'**
  String journalRemindersSavedSkipped(int count, String meals);

  /// No description provided for @journalReminderOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get journalReminderOff;

  /// No description provided for @journalQuietHours.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours'**
  String get journalQuietHours;

  /// No description provided for @journalQuietHoursRange.
  ///
  /// In en, this message translates to:
  /// **'No reminders between {start}:00 and {end}:00.'**
  String journalQuietHoursRange(String start, String end);

  /// No description provided for @journalWakeLabel.
  ///
  /// In en, this message translates to:
  /// **'Wake {hour}:00'**
  String journalWakeLabel(String hour);

  /// No description provided for @journalSleepLabel.
  ///
  /// In en, this message translates to:
  /// **'Sleep {hour}:00'**
  String journalSleepLabel(String hour);

  /// No description provided for @journalRemindersFootnote.
  ///
  /// In en, this message translates to:
  /// **'Snooze any reminder from the notification itself, or just ignore it — Chefii never repeats.'**
  String get journalRemindersFootnote;

  /// No description provided for @journalPatternsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The last two weeks, as recorded.'**
  String get journalPatternsSubtitle;

  /// No description provided for @journalMealsPerDay.
  ///
  /// In en, this message translates to:
  /// **'meals logged per day'**
  String get journalMealsPerDay;

  /// No description provided for @journalDaysNoRecords.
  ///
  /// In en, this message translates to:
  /// **'days with no records'**
  String get journalDaysNoRecords;

  /// No description provided for @journalUsualTimes.
  ///
  /// In en, this message translates to:
  /// **'Usual times'**
  String get journalUsualTimes;

  /// No description provided for @journalPatternsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Log a few meals to see your rhythm.'**
  String get journalPatternsEmpty;

  /// No description provided for @journalWithinHour.
  ///
  /// In en, this message translates to:
  /// **'{percent}% within an hour of your reminder'**
  String journalWithinHour(int percent);

  /// No description provided for @journalAround.
  ///
  /// In en, this message translates to:
  /// **'around {time}'**
  String journalAround(String time);

  /// No description provided for @journalLast14Days.
  ///
  /// In en, this message translates to:
  /// **'Last 14 days'**
  String get journalLast14Days;

  /// No description provided for @journalDayMealsSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{date}: 1 meal} other{{date}: {count} meals}}'**
  String journalDayMealsSemantics(int count, String date);

  /// No description provided for @journalPatternsDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Gaps usually mean a meal wasn\'t logged, not that it wasn\'t eaten. Chefii describes your records; it doesn\'t predict blood sugar or judge your habits.'**
  String get journalPatternsDisclaimer;

  /// No description provided for @kitchenShoppingList.
  ///
  /// In en, this message translates to:
  /// **'Shopping list'**
  String get kitchenShoppingList;

  /// No description provided for @kitchenTellChefii.
  ///
  /// In en, this message translates to:
  /// **'Tell Chefii'**
  String get kitchenTellChefii;

  /// No description provided for @kitchenEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get kitchenEyebrow;

  /// No description provided for @kitchenMyKitchen.
  ///
  /// In en, this message translates to:
  /// **'My kitchen'**
  String get kitchenMyKitchen;

  /// No description provided for @kitchenItemsAcrossPlaces.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item across {places} places} other{{count} items across {places} places}}'**
  String kitchenItemsAcrossPlaces(int count, int places);

  /// No description provided for @kitchenScanReceipt.
  ///
  /// In en, this message translates to:
  /// **'Scan a receipt'**
  String get kitchenScanReceipt;

  /// No description provided for @kitchenOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening your kitchen…'**
  String get kitchenOpening;

  /// No description provided for @kitchenEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your kitchen is empty'**
  String get kitchenEmptyTitle;

  /// No description provided for @kitchenEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Scan a grocery receipt and Chefii fills it in for you — or add a few things by hand.'**
  String get kitchenEmptyMessage;

  /// No description provided for @kitchenAddAnItem.
  ///
  /// In en, this message translates to:
  /// **'Add an item'**
  String get kitchenAddAnItem;

  /// No description provided for @kitchenScanFridgeInstead.
  ///
  /// In en, this message translates to:
  /// **'Scan the fridge instead'**
  String get kitchenScanFridgeInstead;

  /// No description provided for @kitchenUseSoon.
  ///
  /// In en, this message translates to:
  /// **'Use soon'**
  String get kitchenUseSoon;

  /// No description provided for @kitchenToVerify.
  ///
  /// In en, this message translates to:
  /// **'To verify'**
  String get kitchenToVerify;

  /// No description provided for @kitchenStatAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get kitchenStatAdd;

  /// No description provided for @kitchenStatAnItem.
  ///
  /// In en, this message translates to:
  /// **'an item'**
  String get kitchenStatAnItem;

  /// No description provided for @kitchenStatSemantics.
  ///
  /// In en, this message translates to:
  /// **'{label}: {value}'**
  String kitchenStatSemantics(String label, String value);

  /// No description provided for @kitchenFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get kitchenFilterAll;

  /// No description provided for @kitchenManagePlaces.
  ///
  /// In en, this message translates to:
  /// **'Manage places'**
  String get kitchenManagePlaces;

  /// No description provided for @kitchenSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search your kitchen'**
  String get kitchenSearchHint;

  /// No description provided for @kitchenNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches'**
  String get kitchenNoMatchTitle;

  /// No description provided for @kitchenNoMatchMessage.
  ///
  /// In en, this message translates to:
  /// **'Try a different search or filter.'**
  String get kitchenNoMatchMessage;

  /// No description provided for @kitchenScanFridge.
  ///
  /// In en, this message translates to:
  /// **'Scan fridge'**
  String get kitchenScanFridge;

  /// No description provided for @kitchenSpendingWaste.
  ///
  /// In en, this message translates to:
  /// **'Spending & waste'**
  String get kitchenSpendingWaste;

  /// No description provided for @kitchenReceipts.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get kitchenReceipts;

  /// No description provided for @kitchenStorageEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get kitchenStorageEyebrow;

  /// No description provided for @kitchenConfirmedOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{confirmed} of {total} confirmed · soonest first'**
  String kitchenConfirmedOfTotal(int confirmed, int total);

  /// No description provided for @kitchenVerifyTheseItems.
  ///
  /// In en, this message translates to:
  /// **'Verify these items'**
  String get kitchenVerifyTheseItems;

  /// No description provided for @kitchenNothingHereTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get kitchenNothingHereTitle;

  /// No description provided for @kitchenNothingHereMessage.
  ///
  /// In en, this message translates to:
  /// **'Items you add to {place} appear here.'**
  String kitchenNothingHereMessage(String place);

  /// No description provided for @kitchenItemNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Item not found'**
  String get kitchenItemNotFoundTitle;

  /// No description provided for @kitchenItemNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'It may have been removed by someone in your household.'**
  String get kitchenItemNotFoundMessage;

  /// No description provided for @kitchenMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get kitchenMore;

  /// No description provided for @kitchenDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard {name}?'**
  String kitchenDiscardTitle(String name);

  /// No description provided for @kitchenDiscardMessage.
  ///
  /// In en, this message translates to:
  /// **'Records the remaining {amount} as food waste.'**
  String kitchenDiscardMessage(String amount);

  /// No description provided for @kitchenDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get kitchenDiscard;

  /// No description provided for @kitchenMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to {place}'**
  String kitchenMoveTo(String place);

  /// No description provided for @kitchenUpdateAmount.
  ///
  /// In en, this message translates to:
  /// **'Update amount'**
  String get kitchenUpdateAmount;

  /// No description provided for @kitchenRecordedAmount.
  ///
  /// In en, this message translates to:
  /// **'Recorded amount'**
  String get kitchenRecordedAmount;

  /// No description provided for @kitchenOriginally.
  ///
  /// In en, this message translates to:
  /// **'Originally'**
  String get kitchenOriginally;

  /// No description provided for @kitchenAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get kitchenAdded;

  /// No description provided for @kitchenSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get kitchenSource;

  /// No description provided for @kitchenSourceReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get kitchenSourceReceipt;

  /// No description provided for @kitchenSourceReceiptLine.
  ///
  /// In en, this message translates to:
  /// **'Receipt · \"{line}\"'**
  String kitchenSourceReceiptLine(String line);

  /// No description provided for @kitchenSourcePhotoScan.
  ///
  /// In en, this message translates to:
  /// **'Photo scan'**
  String get kitchenSourcePhotoScan;

  /// No description provided for @kitchenSourceBarcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get kitchenSourceBarcode;

  /// No description provided for @kitchenSourceLeftover.
  ///
  /// In en, this message translates to:
  /// **'Leftovers you saved'**
  String get kitchenSourceLeftover;

  /// No description provided for @kitchenSourceDemo.
  ///
  /// In en, this message translates to:
  /// **'Example ingredient'**
  String get kitchenSourceDemo;

  /// No description provided for @kitchenSourceManual.
  ///
  /// In en, this message translates to:
  /// **'Added by hand'**
  String get kitchenSourceManual;

  /// No description provided for @kitchenPackage.
  ///
  /// In en, this message translates to:
  /// **'Package'**
  String get kitchenPackage;

  /// No description provided for @kitchenDateOnPackage.
  ///
  /// In en, this message translates to:
  /// **'Date on package'**
  String get kitchenDateOnPackage;

  /// No description provided for @kitchenEstimatedQuality.
  ///
  /// In en, this message translates to:
  /// **'Estimated quality'**
  String get kitchenEstimatedQuality;

  /// No description provided for @kitchenUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get kitchenUnknown;

  /// No description provided for @kitchenSetDateFromPackage.
  ///
  /// In en, this message translates to:
  /// **'Set date from package'**
  String get kitchenSetDateFromPackage;

  /// No description provided for @kitchenDatePrintedOnPackage.
  ///
  /// In en, this message translates to:
  /// **'Date printed on the package'**
  String get kitchenDatePrintedOnPackage;

  /// No description provided for @kitchenEstimateWarning.
  ///
  /// In en, this message translates to:
  /// **'Our estimate suggests using this soon. Estimates are a guide only — check how it looks and smells, and follow the package date.'**
  String get kitchenEstimateWarning;

  /// No description provided for @kitchenRecordedDatePast.
  ///
  /// In en, this message translates to:
  /// **'The date you recorded is past. Follow the package guidance; when in doubt, throw it out.'**
  String get kitchenRecordedDatePast;

  /// No description provided for @kitchenRecordedDateClose.
  ///
  /// In en, this message translates to:
  /// **'The date you recorded is close. Follow the package guidance; when in doubt, throw it out.'**
  String get kitchenRecordedDateClose;

  /// No description provided for @kitchenThisAmountIsRight.
  ///
  /// In en, this message translates to:
  /// **'This amount is right'**
  String get kitchenThisAmountIsRight;

  /// No description provided for @kitchenNutritionReference.
  ///
  /// In en, this message translates to:
  /// **'Nutrition reference'**
  String get kitchenNutritionReference;

  /// No description provided for @kitchenPer100g.
  ///
  /// In en, this message translates to:
  /// **'per 100 g · {source}'**
  String kitchenPer100g(String source);

  /// No description provided for @kitchenActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get kitchenActivity;

  /// No description provided for @kitchenNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No activity yet.'**
  String get kitchenNoActivity;

  /// No description provided for @kitchenNewBarcode.
  ///
  /// In en, this message translates to:
  /// **'New barcode — tell us what it is once and we\'ll remember it.'**
  String get kitchenNewBarcode;

  /// No description provided for @kitchenChooseAnItem.
  ///
  /// In en, this message translates to:
  /// **'Choose an item'**
  String get kitchenChooseAnItem;

  /// No description provided for @kitchenAddToKitchen.
  ///
  /// In en, this message translates to:
  /// **'Add to kitchen'**
  String get kitchenAddToKitchen;

  /// No description provided for @kitchenWhatAreYouAdding.
  ///
  /// In en, this message translates to:
  /// **'What are you adding?'**
  String get kitchenWhatAreYouAdding;

  /// No description provided for @kitchenChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get kitchenChange;

  /// No description provided for @kitchenScanBarcode.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get kitchenScanBarcode;

  /// No description provided for @kitchenBarcodeValue.
  ///
  /// In en, this message translates to:
  /// **'Barcode {code}'**
  String kitchenBarcodeValue(String code);

  /// No description provided for @kitchenWillAddNew.
  ///
  /// In en, this message translates to:
  /// **'We\'ll add \"{name}\" as a new item.'**
  String kitchenWillAddNew(String name);

  /// No description provided for @kitchenHowMuch.
  ///
  /// In en, this message translates to:
  /// **'How much?'**
  String get kitchenHowMuch;

  /// No description provided for @kitchenWhereDoesItLive.
  ///
  /// In en, this message translates to:
  /// **'Where does it live?'**
  String get kitchenWhereDoesItLive;

  /// No description provided for @kitchenDateOnThePackage.
  ///
  /// In en, this message translates to:
  /// **'Date on the package'**
  String get kitchenDateOnThePackage;

  /// No description provided for @kitchenAddDateOptional.
  ///
  /// In en, this message translates to:
  /// **'Add a best-before or use-by date (optional)'**
  String get kitchenAddDateOptional;

  /// No description provided for @kitchenScanABarcode.
  ///
  /// In en, this message translates to:
  /// **'Scan a barcode'**
  String get kitchenScanABarcode;

  /// No description provided for @kitchenPointAtBarcode.
  ///
  /// In en, this message translates to:
  /// **'Point at the barcode on the package'**
  String get kitchenPointAtBarcode;

  /// No description provided for @kitchenCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get kitchenCamera;

  /// No description provided for @kitchenBarcodeCameraWhy.
  ///
  /// In en, this message translates to:
  /// **'Chefii needs the camera to read barcodes. You can still type the item name.'**
  String get kitchenBarcodeCameraWhy;

  /// No description provided for @kitchenTypeItInstead.
  ///
  /// In en, this message translates to:
  /// **'Type it instead'**
  String get kitchenTypeItInstead;

  /// No description provided for @kitchenAiFeatureShelfScan.
  ///
  /// In en, this message translates to:
  /// **'scanning your shelves'**
  String get kitchenAiFeatureShelfScan;

  /// No description provided for @kitchenEnterAmountFor.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount for {name}.'**
  String kitchenEnterAmountFor(String name);

  /// No description provided for @kitchenScanSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 item from a photo} other{Added {count} items from a photo}}'**
  String kitchenScanSummary(int count);

  /// No description provided for @kitchenScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan your shelves'**
  String get kitchenScanTitle;

  /// No description provided for @kitchenScanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll suggest what we can see. Nothing is added until you confirm it.'**
  String get kitchenScanSubtitle;

  /// No description provided for @kitchenTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get kitchenTakePhoto;

  /// No description provided for @kitchenSelectItemsToAdd.
  ///
  /// In en, this message translates to:
  /// **'Select items to add'**
  String get kitchenSelectItemsToAdd;

  /// No description provided for @kitchenAddCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Add 1 item} other{Add {count} items}}'**
  String kitchenAddCount(int count);

  /// No description provided for @kitchenCameraDeniedWhy.
  ///
  /// In en, this message translates to:
  /// **'Allow camera access in Settings to scan, or choose a photo from your library.'**
  String get kitchenCameraDeniedWhy;

  /// No description provided for @kitchenChooseFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Choose from library'**
  String get kitchenChooseFromLibrary;

  /// No description provided for @kitchenOpenFridgeArt.
  ///
  /// In en, this message translates to:
  /// **'Open fridge'**
  String get kitchenOpenFridgeArt;

  /// No description provided for @kitchenScanTips.
  ///
  /// In en, this message translates to:
  /// **'Tips: open the door fully, use good light, and take one photo per shelf for best results.'**
  String get kitchenScanTips;

  /// No description provided for @kitchenScanDemo.
  ///
  /// In en, this message translates to:
  /// **'Demo: sample suggestions — your photo was not analysed.'**
  String get kitchenScanDemo;

  /// No description provided for @kitchenScanNothingTitle.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t spot anything'**
  String get kitchenScanNothingTitle;

  /// No description provided for @kitchenScanNothingMessage.
  ///
  /// In en, this message translates to:
  /// **'Try a brighter, closer photo of one shelf.'**
  String get kitchenScanNothingMessage;

  /// No description provided for @kitchenPercentSure.
  ///
  /// In en, this message translates to:
  /// **'{percent}% sure'**
  String kitchenPercentSure(int percent);

  /// No description provided for @kitchenAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get kitchenAmount;

  /// No description provided for @kitchenEnterAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter amount'**
  String get kitchenEnterAmount;

  /// No description provided for @kitchenTakeAnotherPhoto.
  ///
  /// In en, this message translates to:
  /// **'Take another photo'**
  String get kitchenTakeAnotherPhoto;

  /// No description provided for @kitchenFreshnessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Things worth cooking, freezing or deciding on.'**
  String get kitchenFreshnessSubtitle;

  /// No description provided for @kitchenFindRecipes.
  ///
  /// In en, this message translates to:
  /// **'Find recipes that use these'**
  String get kitchenFindRecipes;

  /// No description provided for @kitchenNothingNeedsAttentionTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs attention'**
  String get kitchenNothingNeedsAttentionTitle;

  /// No description provided for @kitchenNothingNeedsAttentionMessage.
  ///
  /// In en, this message translates to:
  /// **'We\'ll let you know when something should be used soon.'**
  String get kitchenNothingNeedsAttentionMessage;

  /// No description provided for @kitchenDatePassed.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{date passed 1 day ago} other{date passed {days} days ago}}'**
  String kitchenDatePassed(int days);

  /// No description provided for @kitchenDateIsToday.
  ///
  /// In en, this message translates to:
  /// **'date is today'**
  String get kitchenDateIsToday;

  /// No description provided for @kitchenDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day left} other{{days} days left}}'**
  String kitchenDaysLeft(int days);

  /// No description provided for @kitchenWithEstimate.
  ///
  /// In en, this message translates to:
  /// **'{text} (estimate)'**
  String kitchenWithEstimate(String text);

  /// No description provided for @kitchenCookWithThis.
  ///
  /// In en, this message translates to:
  /// **'Cook with this'**
  String get kitchenCookWithThis;

  /// No description provided for @kitchenFreeze.
  ///
  /// In en, this message translates to:
  /// **'Freeze'**
  String get kitchenFreeze;

  /// No description provided for @kitchenFoodSafety.
  ///
  /// In en, this message translates to:
  /// **'Food safety'**
  String get kitchenFoodSafety;

  /// No description provided for @kitchenFoodSafetyBody.
  ///
  /// In en, this message translates to:
  /// **'Chefii\'s dates are estimates from typical storage times, not safety guarantees. Follow \"use by\" and \"best before\" dates on packages, keep your fridge at 4 °C (40 °F) or below, and when in doubt, throw it out. For guidance, see Health Canada\'s food safety pages.'**
  String get kitchenFoodSafetyBody;

  /// No description provided for @kitchenAllSquaredAway.
  ///
  /// In en, this message translates to:
  /// **'All squared away'**
  String get kitchenAllSquaredAway;

  /// No description provided for @kitchenBackToKitchen.
  ///
  /// In en, this message translates to:
  /// **'Back to kitchen'**
  String get kitchenBackToKitchen;

  /// No description provided for @kitchenItemsVerified.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item verified} other{{count} items verified}}'**
  String kitchenItemsVerified(int count);

  /// No description provided for @kitchenEveryAmountRight.
  ///
  /// In en, this message translates to:
  /// **'Every amount was already right.'**
  String get kitchenEveryAmountRight;

  /// No description provided for @kitchenAmountsCorrected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 amount was corrected. You can undo from the kitchen.} other{{count} amounts were corrected. You can undo from the kitchen.}}'**
  String kitchenAmountsCorrected(int count);

  /// No description provided for @kitchenQuickCheck.
  ///
  /// In en, this message translates to:
  /// **'Quick check'**
  String get kitchenQuickCheck;

  /// No description provided for @kitchenQuickCheckSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Adjust anything that\'s off, then confirm. 1 item.} other{Adjust anything that\'s off, then confirm. {count} items.}}'**
  String kitchenQuickCheckSubtitle(int count);

  /// No description provided for @kitchenConfirmAll.
  ///
  /// In en, this message translates to:
  /// **'Confirm all'**
  String get kitchenConfirmAll;

  /// No description provided for @kitchenEverythingAccurateTitle.
  ///
  /// In en, this message translates to:
  /// **'Everything looks accurate'**
  String get kitchenEverythingAccurateTitle;

  /// No description provided for @kitchenEverythingAccurateMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs checking right now.'**
  String get kitchenEverythingAccurateMessage;

  /// No description provided for @kitchenWasAmount.
  ///
  /// In en, this message translates to:
  /// **'was {amount}'**
  String kitchenWasAmount(String amount);

  /// No description provided for @kitchenAlreadyDone.
  ///
  /// In en, this message translates to:
  /// **'Already done — nothing changed.'**
  String get kitchenAlreadyDone;

  /// No description provided for @kitchenRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded: {amount}'**
  String kitchenRecorded(String amount);

  /// No description provided for @kitchenModeUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get kitchenModeUsed;

  /// No description provided for @kitchenModeAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get kitchenModeAdded;

  /// No description provided for @kitchenModeTossed.
  ///
  /// In en, this message translates to:
  /// **'Tossed'**
  String get kitchenModeTossed;

  /// No description provided for @kitchenModeCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get kitchenModeCount;

  /// No description provided for @kitchenAmountYouHaveNow.
  ///
  /// In en, this message translates to:
  /// **'Amount you have now'**
  String get kitchenAmountYouHaveNow;

  /// No description provided for @kitchenCountingConfirms.
  ///
  /// In en, this message translates to:
  /// **'Counting confirms this item as accurate.'**
  String get kitchenCountingConfirms;

  /// No description provided for @kitchenUseAmount.
  ///
  /// In en, this message translates to:
  /// **'Use {amount}'**
  String kitchenUseAmount(String amount);

  /// No description provided for @kitchenAddAmount.
  ///
  /// In en, this message translates to:
  /// **'Add {amount}'**
  String kitchenAddAmount(String amount);

  /// No description provided for @kitchenDiscardAmount.
  ///
  /// In en, this message translates to:
  /// **'Discard {amount}'**
  String kitchenDiscardAmount(String amount);

  /// No description provided for @kitchenSetToAmount.
  ///
  /// In en, this message translates to:
  /// **'Set to {amount}'**
  String kitchenSetToAmount(String amount);

  /// No description provided for @kitchenMarkFinished.
  ///
  /// In en, this message translates to:
  /// **'Mark as finished'**
  String get kitchenMarkFinished;

  /// No description provided for @kitchenCommandTryHint.
  ///
  /// In en, this message translates to:
  /// **'Try \"I used two eggs\" or \"add 1 kg flour\".'**
  String get kitchenCommandTryHint;

  /// No description provided for @kitchenVoiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Voice isn\'t available. You can type instead — or use your keyboard\'s dictation.'**
  String get kitchenVoiceUnavailable;

  /// No description provided for @kitchenCommandExamples.
  ///
  /// In en, this message translates to:
  /// **'\"I used two eggs\" · \"we\'re out of milk\" · \"add 1 kg flour\"'**
  String get kitchenCommandExamples;

  /// No description provided for @kitchenCommandFieldHint.
  ///
  /// In en, this message translates to:
  /// **'What happened in the kitchen?'**
  String get kitchenCommandFieldHint;

  /// No description provided for @kitchenListening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get kitchenListening;

  /// No description provided for @kitchenSpeak.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get kitchenSpeak;

  /// No description provided for @kitchenCouldNotFind.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find \"{query}\"'**
  String kitchenCouldNotFind(String query);

  /// No description provided for @kitchenHereIsWhatWillHappen.
  ///
  /// In en, this message translates to:
  /// **'Here\'s what will happen'**
  String get kitchenHereIsWhatWillHappen;

  /// No description provided for @kitchenTrySimplerName.
  ///
  /// In en, this message translates to:
  /// **'Try a simpler name, or add it from the Kitchen tab.'**
  String get kitchenTrySimplerName;

  /// No description provided for @kitchenNoAmountSaid.
  ///
  /// In en, this message translates to:
  /// **'You didn\'t say how much — check the amount:'**
  String get kitchenNoAmountSaid;

  /// No description provided for @kitchenQuoted.
  ///
  /// In en, this message translates to:
  /// **'\"{text}\"'**
  String kitchenQuoted(String text);

  /// No description provided for @kitchenCommandMarkEmpty.
  ///
  /// In en, this message translates to:
  /// **'Mark {what} as used up'**
  String kitchenCommandMarkEmpty(String what);

  /// No description provided for @kitchenCommandSetCount.
  ///
  /// In en, this message translates to:
  /// **'Set {what} to {amount}'**
  String kitchenCommandSetCount(String what, String amount);

  /// No description provided for @kitchenCommandAction.
  ///
  /// In en, this message translates to:
  /// **'{action} {amount} {what}'**
  String kitchenCommandAction(String action, String amount, String what);

  /// No description provided for @kitchenConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get kitchenConfirm;

  /// No description provided for @kitchenRenamePlace.
  ///
  /// In en, this message translates to:
  /// **'Rename place'**
  String get kitchenRenamePlace;

  /// No description provided for @kitchenPlacesTitle.
  ///
  /// In en, this message translates to:
  /// **'Places in your kitchen'**
  String get kitchenPlacesTitle;

  /// No description provided for @kitchenPlacesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add spots like a garage freezer or a wine fridge.'**
  String get kitchenPlacesSubtitle;

  /// No description provided for @kitchenBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get kitchenBuiltIn;

  /// No description provided for @kitchenKeptLike.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, fridge{Kept like a fridge} freezer{Kept like a freezer} pantry{Kept like a pantry} other{Kept like a other}}'**
  String kitchenKeptLike(String kind);

  /// No description provided for @kitchenRenameTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rename {place}'**
  String kitchenRenameTooltip(String place);

  /// No description provided for @kitchenRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove {place}'**
  String kitchenRemoveTooltip(String place);

  /// No description provided for @kitchenRemovedPlace.
  ///
  /// In en, this message translates to:
  /// **'Removed {place}.'**
  String kitchenRemovedPlace(String place);

  /// No description provided for @kitchenAddedPlace.
  ///
  /// In en, this message translates to:
  /// **'Added {place}.'**
  String kitchenAddedPlace(String place);

  /// No description provided for @kitchenNewPlace.
  ///
  /// In en, this message translates to:
  /// **'New place'**
  String get kitchenNewPlace;

  /// No description provided for @kitchenNewPlaceHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Garage freezer'**
  String get kitchenNewPlaceHint;

  /// No description provided for @kitchenKeptLikeHeader.
  ///
  /// In en, this message translates to:
  /// **'Kept like a…'**
  String get kitchenKeptLikeHeader;

  /// No description provided for @kitchenAddPlace.
  ///
  /// In en, this message translates to:
  /// **'Add place'**
  String get kitchenAddPlace;

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

  /// No description provided for @tag15Minute.
  ///
  /// In en, this message translates to:
  /// **'15 minutes'**
  String get tag15Minute;

  /// No description provided for @tagHighProtein.
  ///
  /// In en, this message translates to:
  /// **'High protein'**
  String get tagHighProtein;

  /// No description provided for @tagVegan.
  ///
  /// In en, this message translates to:
  /// **'Vegan'**
  String get tagVegan;

  /// No description provided for @tagVegetarian.
  ///
  /// In en, this message translates to:
  /// **'Vegetarian'**
  String get tagVegetarian;

  /// No description provided for @tagBatch.
  ///
  /// In en, this message translates to:
  /// **'Batch cooking'**
  String get tagBatch;

  /// No description provided for @tagComfort.
  ///
  /// In en, this message translates to:
  /// **'Comfort'**
  String get tagComfort;

  /// No description provided for @tagMakeAhead.
  ///
  /// In en, this message translates to:
  /// **'Make ahead'**
  String get tagMakeAhead;

  /// No description provided for @tagNoCook.
  ///
  /// In en, this message translates to:
  /// **'No cooking'**
  String get tagNoCook;

  /// No description provided for @availabilityAllOnHand.
  ///
  /// In en, this message translates to:
  /// **'Everything on hand'**
  String get availabilityAllOnHand;

  /// No description provided for @availabilityToBuy.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 ingredient to buy} other{{count} ingredients to buy}}'**
  String availabilityToBuy(int count);

  /// No description provided for @morningStepWake.
  ///
  /// In en, this message translates to:
  /// **'Wake'**
  String get morningStepWake;

  /// No description provided for @morningStepGetReady.
  ///
  /// In en, this message translates to:
  /// **'Get ready'**
  String get morningStepGetReady;

  /// No description provided for @morningStepMake.
  ///
  /// In en, this message translates to:
  /// **'Make {recipe}'**
  String morningStepMake(String recipe);

  /// No description provided for @morningStepEat.
  ///
  /// In en, this message translates to:
  /// **'Eat'**
  String get morningStepEat;

  /// No description provided for @morningStepTidy.
  ///
  /// In en, this message translates to:
  /// **'Tidy up'**
  String get morningStepTidy;

  /// No description provided for @morningStepLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get morningStepLeave;

  /// No description provided for @morningEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Mornings'**
  String get morningEyebrow;

  /// No description provided for @morningSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'A calmer morning'**
  String get morningSetupTitle;

  /// No description provided for @morningSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us when you wake and when you leave. We\'ll plan the bit in between.'**
  String get morningSetupSubtitle;

  /// No description provided for @morningOnTheseDays.
  ///
  /// In en, this message translates to:
  /// **'On these days'**
  String get morningOnTheseDays;

  /// No description provided for @morningWakeUp.
  ///
  /// In en, this message translates to:
  /// **'Wake up'**
  String get morningWakeUp;

  /// No description provided for @morningOutTheDoorBy.
  ///
  /// In en, this message translates to:
  /// **'Out the door by'**
  String get morningOutTheDoorBy;

  /// No description provided for @morningBufferValue.
  ///
  /// In en, this message translates to:
  /// **'Buffer before leaving: {minutes} min'**
  String morningBufferValue(int minutes);

  /// No description provided for @morningBuffer.
  ///
  /// In en, this message translates to:
  /// **'Buffer before leaving'**
  String get morningBuffer;

  /// No description provided for @morningMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String morningMinutesShort(int minutes);

  /// No description provided for @morningInvalidTimes.
  ///
  /// In en, this message translates to:
  /// **'Your departure time needs to be after your wake time plus the buffer.'**
  String get morningInvalidTimes;

  /// No description provided for @morningTimeLeft.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, other{That leaves {minutes} minutes for getting ready and breakfast.}}'**
  String morningTimeLeft(int minutes);

  /// No description provided for @morningBreakfastStyle.
  ///
  /// In en, this message translates to:
  /// **'Breakfast style'**
  String get morningBreakfastStyle;

  /// No description provided for @morningStyleQuick.
  ///
  /// In en, this message translates to:
  /// **'Quick & simple'**
  String get morningStyleQuick;

  /// No description provided for @morningStyleCooked.
  ///
  /// In en, this message translates to:
  /// **'Something warm'**
  String get morningStyleCooked;

  /// No description provided for @morningStyleNoCook.
  ///
  /// In en, this message translates to:
  /// **'No cooking'**
  String get morningStyleNoCook;

  /// No description provided for @morningStyleGrabAndGo.
  ///
  /// In en, this message translates to:
  /// **'Grab and go'**
  String get morningStyleGrabAndGo;

  /// No description provided for @morningNotificationsOff.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off for Chefii. Turn them on in Settings to use alarms.'**
  String get morningNotificationsOff;

  /// No description provided for @morningAlarmNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'Your morning plan is ready.'**
  String get morningAlarmNotificationBody;

  /// No description provided for @morningPreviewNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow\'s breakfast'**
  String get morningPreviewNotificationTitle;

  /// No description provided for @morningPreviewNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'Take a look at tomorrow morning\'s plan.'**
  String get morningPreviewNotificationBody;

  /// No description provided for @morningAlarmAt.
  ///
  /// In en, this message translates to:
  /// **'Alarm at {time}'**
  String morningAlarmAt(String time);

  /// No description provided for @morningPreviewAt.
  ///
  /// In en, this message translates to:
  /// **'Evening preview at {time}'**
  String morningPreviewAt(String time);

  /// No description provided for @morningAlarmTitle.
  ///
  /// In en, this message translates to:
  /// **'Alarm & reminders'**
  String get morningAlarmTitle;

  /// No description provided for @morningSaveSchedule.
  ///
  /// In en, this message translates to:
  /// **'Save schedule'**
  String get morningSaveSchedule;

  /// No description provided for @morningWakeWithChefii.
  ///
  /// In en, this message translates to:
  /// **'Wake me with Chefii'**
  String get morningWakeWithChefii;

  /// No description provided for @morningWakeWithChefiiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'An alarm at {time} that opens your morning plan'**
  String morningWakeWithChefiiSubtitle(String time);

  /// No description provided for @morningEveningPreview.
  ///
  /// In en, this message translates to:
  /// **'Evening preview'**
  String get morningEveningPreview;

  /// No description provided for @morningEveningPreviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A gentle note at {time} with tomorrow\'s breakfast'**
  String morningEveningPreviewSubtitle(String time);

  /// No description provided for @morningPlatformNote.
  ///
  /// In en, this message translates to:
  /// **'On Android, Chefii uses a system alarm clock entry. On iPhone, it uses a time-sensitive notification that respects Focus settings; it isn\'t a replacement for the Clock app, so keep a backup alarm for anything critical.'**
  String get morningPlatformNote;

  /// No description provided for @morningAllOff.
  ///
  /// In en, this message translates to:
  /// **'All morning notifications are off.'**
  String get morningAllOff;

  /// No description provided for @morningScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled: {items}'**
  String morningScheduled(String items);

  /// No description provided for @morningSeeTomorrow.
  ///
  /// In en, this message translates to:
  /// **'See tomorrow\'s plan'**
  String get morningSeeTomorrow;

  /// No description provided for @morningSetUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your mornings'**
  String get morningSetUpTitle;

  /// No description provided for @morningSetUpMessage.
  ///
  /// In en, this message translates to:
  /// **'Chefii can plan breakfast around your wake and leave times.'**
  String get morningSetUpMessage;

  /// No description provided for @morningSetUp.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get morningSetUp;

  /// No description provided for @morningPlannedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your morning, planned'**
  String get morningPlannedTitle;

  /// No description provided for @morningDayOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow is a day off'**
  String get morningDayOffTitle;

  /// No description provided for @morningWindow.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes from {wake} to {leave}'**
  String morningWindow(int minutes, String wake, String leave);

  /// No description provided for @morningEditRoutine.
  ///
  /// In en, this message translates to:
  /// **'Edit routine'**
  String get morningEditRoutine;

  /// No description provided for @morningSoundsGood.
  ///
  /// In en, this message translates to:
  /// **'Sounds good'**
  String get morningSoundsGood;

  /// No description provided for @morningBreakfastSet.
  ///
  /// In en, this message translates to:
  /// **'Breakfast is set for tomorrow.'**
  String get morningBreakfastSet;

  /// No description provided for @morningNoBreakfastFits.
  ///
  /// In en, this message translates to:
  /// **'No breakfast fits'**
  String get morningNoBreakfastFits;

  /// No description provided for @morningNoBreakfastFitsMessage.
  ///
  /// In en, this message translates to:
  /// **'Try a longer morning or a different breakfast style.'**
  String get morningNoBreakfastFitsMessage;

  /// No description provided for @morningMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing: {items}'**
  String morningMissing(String items);

  /// No description provided for @morningTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get morningTimeline;

  /// No description provided for @morningOrChoose.
  ///
  /// In en, this message translates to:
  /// **'Or choose'**
  String get morningOrChoose;

  /// No description provided for @morningItIs.
  ///
  /// In en, this message translates to:
  /// **'It is {time}'**
  String morningItIs(String time);

  /// No description provided for @morningImUp.
  ///
  /// In en, this message translates to:
  /// **'I\'m up'**
  String get morningImUp;

  /// No description provided for @morningSnooze.
  ///
  /// In en, this message translates to:
  /// **'Snooze 9 minutes'**
  String get morningSnooze;

  /// No description provided for @morningSnoozeTitle.
  ///
  /// In en, this message translates to:
  /// **'Time to get up'**
  String get morningSnoozeTitle;

  /// No description provided for @morningSnoozeBody.
  ///
  /// In en, this message translates to:
  /// **'Snooze is over. Your morning plan is waiting.'**
  String get morningSnoozeBody;

  /// No description provided for @morningThisMorning.
  ///
  /// In en, this message translates to:
  /// **'This morning'**
  String get morningThisMorning;

  /// No description provided for @morningTimeToGo.
  ///
  /// In en, this message translates to:
  /// **'Time to go'**
  String get morningTimeToGo;

  /// No description provided for @morningUntilYouLeave.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min until you leave'**
  String morningUntilYouLeave(int minutes);

  /// No description provided for @morningRunningBehind.
  ///
  /// In en, this message translates to:
  /// **'Running behind? See faster options'**
  String get morningRunningBehind;

  /// No description provided for @morningRunningLate.
  ///
  /// In en, this message translates to:
  /// **'I\'m running late'**
  String get morningRunningLate;

  /// No description provided for @morningNoStress.
  ///
  /// In en, this message translates to:
  /// **'No stress'**
  String get morningNoStress;

  /// No description provided for @morningMinutesLeft.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, other{{minutes} minutes left}}'**
  String morningMinutesLeft(int minutes);

  /// No description provided for @morningWhatStillWorks.
  ///
  /// In en, this message translates to:
  /// **'Here\'s what still works.'**
  String get morningWhatStillWorks;

  /// No description provided for @morningSkipBreakfast.
  ///
  /// In en, this message translates to:
  /// **'Skip breakfast today'**
  String get morningSkipBreakfast;

  /// No description provided for @morningSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped. Nothing in your kitchen was changed.'**
  String get morningSkipped;

  /// No description provided for @morningNoCookNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing no-cook fits your kitchen right now.'**
  String get morningNoCookNone;

  /// No description provided for @morningTenMinutes.
  ///
  /// In en, this message translates to:
  /// **'Ten minutes or less'**
  String get morningTenMinutes;

  /// No description provided for @morningNothingElse.
  ///
  /// In en, this message translates to:
  /// **'Nothing else fits in ten minutes.'**
  String get morningNothingElse;

  /// No description provided for @onboardingSkipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get onboardingSkipForNow;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String onboardingStepOf(int step, int total);

  /// No description provided for @onboardingWelcomeArtLabel.
  ///
  /// In en, this message translates to:
  /// **'A beautifully set kitchen table'**
  String get onboardingWelcomeArtLabel;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Your kitchen,\nbeautifully taken care of.'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Chefii knows what\'s in your kitchen, suggests what to make, guides you through it — and keeps everything in order.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get onboardingHaveAccount;

  /// No description provided for @onboardingMeetTitle.
  ///
  /// In en, this message translates to:
  /// **'Meet your chef'**
  String get onboardingMeetTitle;

  /// No description provided for @onboardingMeetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Three things Chefii does for you, every day.'**
  String get onboardingMeetSubtitle;

  /// No description provided for @onboardingBenefitKitchenTitle.
  ///
  /// In en, this message translates to:
  /// **'Knows your kitchen'**
  String get onboardingBenefitKitchenTitle;

  /// No description provided for @onboardingBenefitKitchenBody.
  ///
  /// In en, this message translates to:
  /// **'Scan a receipt and your pantry, fridge and freezer stay up to date — with almost no typing.'**
  String get onboardingBenefitKitchenBody;

  /// No description provided for @onboardingBenefitDecideTitle.
  ///
  /// In en, this message translates to:
  /// **'Decides what to make'**
  String get onboardingBenefitDecideTitle;

  /// No description provided for @onboardingBenefitDecideBody.
  ///
  /// In en, this message translates to:
  /// **'Recipes matched to what you have, how much time you have, and everyone\'s dietary needs.'**
  String get onboardingBenefitDecideBody;

  /// No description provided for @onboardingBenefitGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Guides you calmly'**
  String get onboardingBenefitGuideTitle;

  /// No description provided for @onboardingBenefitGuideBody.
  ///
  /// In en, this message translates to:
  /// **'Step-by-step cooking with timers, then one tap to update your kitchen.'**
  String get onboardingBenefitGuideBody;

  /// No description provided for @onboardingTasteHeader.
  ///
  /// In en, this message translates to:
  /// **'A taste'**
  String get onboardingTasteHeader;

  /// No description provided for @onboardingExample.
  ///
  /// In en, this message translates to:
  /// **'Example'**
  String get onboardingExample;

  /// No description provided for @onboardingConsentRequired.
  ///
  /// In en, this message translates to:
  /// **'Please accept the Terms and Privacy Policy to continue.'**
  String get onboardingConsentRequired;

  /// No description provided for @onboardingDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Friend'**
  String get onboardingDefaultName;

  /// No description provided for @onboardingWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get onboardingWelcomeBack;

  /// No description provided for @onboardingSignInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your kitchen.'**
  String get onboardingSignInSubtitle;

  /// No description provided for @onboardingCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get onboardingCreateTitle;

  /// No description provided for @onboardingCreateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your kitchen stays private to you and the people you invite.'**
  String get onboardingCreateSubtitle;

  /// No description provided for @onboardingSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get onboardingSignIn;

  /// No description provided for @onboardingCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get onboardingCreateAccount;

  /// No description provided for @onboardingDemoBanner.
  ///
  /// In en, this message translates to:
  /// **'Demo mode: your account and data stay on this device only.'**
  String get onboardingDemoBanner;

  /// No description provided for @onboardingDemoAccount.
  ///
  /// In en, this message translates to:
  /// **'Continue with a demo account'**
  String get onboardingDemoAccount;

  /// No description provided for @onboardingContinueApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get onboardingContinueApple;

  /// No description provided for @onboardingContinueGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get onboardingContinueGoogle;

  /// No description provided for @onboardingOrEmail.
  ///
  /// In en, this message translates to:
  /// **'or with email'**
  String get onboardingOrEmail;

  /// No description provided for @onboardingFirstNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Your first name'**
  String get onboardingFirstNameLabel;

  /// No description provided for @onboardingFirstNameError.
  ///
  /// In en, this message translates to:
  /// **'Please tell us what to call you'**
  String get onboardingFirstNameError;

  /// No description provided for @onboardingEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get onboardingEmailLabel;

  /// No description provided for @onboardingEmailError.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get onboardingEmailError;

  /// No description provided for @onboardingPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get onboardingPasswordLabel;

  /// No description provided for @onboardingPasswordError.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get onboardingPasswordError;

  /// No description provided for @onboardingEnterEmailFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter your email first.'**
  String get onboardingEnterEmailFirst;

  /// No description provided for @onboardingResetSent.
  ///
  /// In en, this message translates to:
  /// **'If that email has an account, a reset link is on its way.'**
  String get onboardingResetSent;

  /// No description provided for @onboardingForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get onboardingForgotPassword;

  /// No description provided for @onboardingConsentLabel.
  ///
  /// In en, this message translates to:
  /// **'I agree to the Terms of Service and Privacy Policy'**
  String get onboardingConsentLabel;

  /// No description provided for @onboardingReadThem.
  ///
  /// In en, this message translates to:
  /// **'Read them'**
  String get onboardingReadThem;

  /// No description provided for @onboardingSwitchToCreate.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account'**
  String get onboardingSwitchToCreate;

  /// No description provided for @onboardingSwitchToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get onboardingSwitchToSignIn;

  /// No description provided for @onboardingDefaultHouseholdName.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s kitchen'**
  String onboardingDefaultHouseholdName(String name);

  /// No description provided for @onboardingInviteCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get onboardingInviteCodeTitle;

  /// No description provided for @onboardingInviteCodeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 7KQ2M9XA'**
  String get onboardingInviteCodeHint;

  /// No description provided for @onboardingJoin.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get onboardingJoin;

  /// No description provided for @onboardingJoinNeedsOnline.
  ///
  /// In en, this message translates to:
  /// **'Joining another household needs the online version of Chefii.'**
  String get onboardingJoinNeedsOnline;

  /// No description provided for @onboardingJoinFailed.
  ///
  /// In en, this message translates to:
  /// **'That code didn\'t work.'**
  String get onboardingJoinFailed;

  /// No description provided for @onboardingHouseholdTitle.
  ///
  /// In en, this message translates to:
  /// **'Your household'**
  String get onboardingHouseholdTitle;

  /// No description provided for @onboardingHouseholdSubtitle.
  ///
  /// In en, this message translates to:
  /// **'So portions and planning fit the way you live.'**
  String get onboardingHouseholdSubtitle;

  /// No description provided for @onboardingOptionSelected.
  ///
  /// In en, this message translates to:
  /// **'{option}, selected'**
  String onboardingOptionSelected(String option);

  /// No description provided for @onboardingPortionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Usual portions per meal'**
  String get onboardingPortionsTitle;

  /// No description provided for @onboardingFewerPortions.
  ///
  /// In en, this message translates to:
  /// **'Fewer portions'**
  String get onboardingFewerPortions;

  /// No description provided for @onboardingMorePortions.
  ///
  /// In en, this message translates to:
  /// **'More portions'**
  String get onboardingMorePortions;

  /// No description provided for @onboardingHouseholdNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Household name (optional)'**
  String get onboardingHouseholdNameLabel;

  /// No description provided for @onboardingHouseholdNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. The Laurier kitchen'**
  String get onboardingHouseholdNameHint;

  /// No description provided for @onboardingHouseholdPrivacy.
  ///
  /// In en, this message translates to:
  /// **'You can invite others to share the kitchen later. Each person\'s health and journal stay private to them.'**
  String get onboardingHouseholdPrivacy;

  /// No description provided for @onboardingJoinWithCode.
  ///
  /// In en, this message translates to:
  /// **'Join a household with an invite code'**
  String get onboardingJoinWithCode;

  /// No description provided for @onboardingAllergyQuestion.
  ///
  /// In en, this message translates to:
  /// **'Do you have any food allergies?'**
  String get onboardingAllergyQuestion;

  /// No description provided for @onboardingAllergyNoneKnown.
  ///
  /// In en, this message translates to:
  /// **'None that I know of'**
  String get onboardingAllergyNoneKnown;

  /// No description provided for @onboardingAllergyPreferNot.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get onboardingAllergyPreferNot;

  /// No description provided for @onboardingCrossContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Warn me about cross-contact'**
  String get onboardingCrossContactTitle;

  /// No description provided for @onboardingCrossContactSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reminders about \"may contain\" labels and shared equipment'**
  String get onboardingCrossContactSubtitle;

  /// No description provided for @onboardingNoAllergyAssumption.
  ///
  /// In en, this message translates to:
  /// **'We won\'t assume you have no allergies — recipes will remind you to check ingredients.'**
  String get onboardingNoAllergyAssumption;

  /// No description provided for @onboardingIntolerances.
  ///
  /// In en, this message translates to:
  /// **'Intolerances'**
  String get onboardingIntolerances;

  /// No description provided for @onboardingDietaryPattern.
  ///
  /// In en, this message translates to:
  /// **'Dietary pattern'**
  String get onboardingDietaryPattern;

  /// No description provided for @onboardingDislikes.
  ///
  /// In en, this message translates to:
  /// **'Foods you\'d rather avoid'**
  String get onboardingDislikes;

  /// No description provided for @onboardingAddFoodLabel.
  ///
  /// In en, this message translates to:
  /// **'Add a food (e.g. cilantro)'**
  String get onboardingAddFoodLabel;

  /// No description provided for @onboardingAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get onboardingAdd;

  /// No description provided for @onboardingDietaryNotice.
  ///
  /// In en, this message translates to:
  /// **'Chefii screens every recipe against these, but it can\'t see inside packaged foods. Always check labels. Allergies you list are shared with your household only to keep shared meals safe.'**
  String get onboardingDietaryNotice;

  /// No description provided for @onboardingDietaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Dietary safety'**
  String get onboardingDietaryTitle;

  /// No description provided for @onboardingDietaryEditSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Allergies, intolerances and preferences.'**
  String get onboardingDietaryEditSubtitle;

  /// No description provided for @onboardingDietarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'The most important thing we\'ll ask. You can change it any time.'**
  String get onboardingDietarySubtitle;

  /// No description provided for @onboardingCuisineItalian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get onboardingCuisineItalian;

  /// No description provided for @onboardingCuisineFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get onboardingCuisineFrench;

  /// No description provided for @onboardingCuisineMediterranean.
  ///
  /// In en, this message translates to:
  /// **'Mediterranean'**
  String get onboardingCuisineMediterranean;

  /// No description provided for @onboardingCuisineMiddleEastern.
  ///
  /// In en, this message translates to:
  /// **'Middle Eastern'**
  String get onboardingCuisineMiddleEastern;

  /// No description provided for @onboardingCuisineIndian.
  ///
  /// In en, this message translates to:
  /// **'Indian'**
  String get onboardingCuisineIndian;

  /// No description provided for @onboardingCuisineJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get onboardingCuisineJapanese;

  /// No description provided for @onboardingCuisineChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get onboardingCuisineChinese;

  /// No description provided for @onboardingCuisineThai.
  ///
  /// In en, this message translates to:
  /// **'Thai'**
  String get onboardingCuisineThai;

  /// No description provided for @onboardingCuisineKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get onboardingCuisineKorean;

  /// No description provided for @onboardingCuisineMexican.
  ///
  /// In en, this message translates to:
  /// **'Mexican'**
  String get onboardingCuisineMexican;

  /// No description provided for @onboardingCuisineGreek.
  ///
  /// In en, this message translates to:
  /// **'Greek'**
  String get onboardingCuisineGreek;

  /// No description provided for @onboardingCuisineNordic.
  ///
  /// In en, this message translates to:
  /// **'Nordic'**
  String get onboardingCuisineNordic;

  /// No description provided for @onboardingCuisineCanadian.
  ///
  /// In en, this message translates to:
  /// **'Canadian'**
  String get onboardingCuisineCanadian;

  /// No description provided for @onboardingFoodSalmon.
  ///
  /// In en, this message translates to:
  /// **'Salmon'**
  String get onboardingFoodSalmon;

  /// No description provided for @onboardingFoodChicken.
  ///
  /// In en, this message translates to:
  /// **'Chicken'**
  String get onboardingFoodChicken;

  /// No description provided for @onboardingFoodPasta.
  ///
  /// In en, this message translates to:
  /// **'Pasta'**
  String get onboardingFoodPasta;

  /// No description provided for @onboardingFoodEggs.
  ///
  /// In en, this message translates to:
  /// **'Eggs'**
  String get onboardingFoodEggs;

  /// No description provided for @onboardingFoodTofu.
  ///
  /// In en, this message translates to:
  /// **'Tofu'**
  String get onboardingFoodTofu;

  /// No description provided for @onboardingFoodLentils.
  ///
  /// In en, this message translates to:
  /// **'Lentils'**
  String get onboardingFoodLentils;

  /// No description provided for @onboardingFoodVegetables.
  ///
  /// In en, this message translates to:
  /// **'Vegetables'**
  String get onboardingFoodVegetables;

  /// No description provided for @onboardingFoodSalads.
  ///
  /// In en, this message translates to:
  /// **'Salads'**
  String get onboardingFoodSalads;

  /// No description provided for @onboardingFoodSoups.
  ///
  /// In en, this message translates to:
  /// **'Soups'**
  String get onboardingFoodSoups;

  /// No description provided for @onboardingFoodRiceBowls.
  ///
  /// In en, this message translates to:
  /// **'Rice bowls'**
  String get onboardingFoodRiceBowls;

  /// No description provided for @onboardingFoodBaking.
  ///
  /// In en, this message translates to:
  /// **'Baking'**
  String get onboardingFoodBaking;

  /// No description provided for @onboardingEquipmentOven.
  ///
  /// In en, this message translates to:
  /// **'Oven'**
  String get onboardingEquipmentOven;

  /// No description provided for @onboardingEquipmentStovetop.
  ///
  /// In en, this message translates to:
  /// **'Stovetop'**
  String get onboardingEquipmentStovetop;

  /// No description provided for @onboardingEquipmentAirFryer.
  ///
  /// In en, this message translates to:
  /// **'Air fryer'**
  String get onboardingEquipmentAirFryer;

  /// No description provided for @onboardingEquipmentSlowCooker.
  ///
  /// In en, this message translates to:
  /// **'Slow cooker'**
  String get onboardingEquipmentSlowCooker;

  /// No description provided for @onboardingEquipmentInstantPot.
  ///
  /// In en, this message translates to:
  /// **'Instant Pot'**
  String get onboardingEquipmentInstantPot;

  /// No description provided for @onboardingEquipmentBlender.
  ///
  /// In en, this message translates to:
  /// **'Blender'**
  String get onboardingEquipmentBlender;

  /// No description provided for @onboardingEquipmentMicrowave.
  ///
  /// In en, this message translates to:
  /// **'Microwave'**
  String get onboardingEquipmentMicrowave;

  /// No description provided for @onboardingEquipmentGrill.
  ///
  /// In en, this message translates to:
  /// **'Grill'**
  String get onboardingEquipmentGrill;

  /// No description provided for @onboardingSpiceNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get onboardingSpiceNone;

  /// No description provided for @onboardingSpiceMild.
  ///
  /// In en, this message translates to:
  /// **'Mild'**
  String get onboardingSpiceMild;

  /// No description provided for @onboardingSpiceMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get onboardingSpiceMedium;

  /// No description provided for @onboardingSpiceWarm.
  ///
  /// In en, this message translates to:
  /// **'Warm'**
  String get onboardingSpiceWarm;

  /// No description provided for @onboardingSpiceHot.
  ///
  /// In en, this message translates to:
  /// **'Hot'**
  String get onboardingSpiceHot;

  /// No description provided for @onboardingCuisinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Cuisines you love'**
  String get onboardingCuisinesTitle;

  /// No description provided for @onboardingFavouriteFoods.
  ///
  /// In en, this message translates to:
  /// **'Favourite foods'**
  String get onboardingFavouriteFoods;

  /// No description provided for @onboardingCookingConfidence.
  ///
  /// In en, this message translates to:
  /// **'Cooking confidence'**
  String get onboardingCookingConfidence;

  /// No description provided for @onboardingSpice.
  ///
  /// In en, this message translates to:
  /// **'Spice'**
  String get onboardingSpice;

  /// No description provided for @onboardingSpiceLevel.
  ///
  /// In en, this message translates to:
  /// **'Spice level'**
  String get onboardingSpiceLevel;

  /// No description provided for @onboardingSpiceValue.
  ///
  /// In en, this message translates to:
  /// **'Spice: {level}'**
  String onboardingSpiceValue(String level);

  /// No description provided for @onboardingWeeknightTime.
  ///
  /// In en, this message translates to:
  /// **'Weeknight time'**
  String get onboardingWeeknightTime;

  /// No description provided for @onboardingYourEquipment.
  ///
  /// In en, this message translates to:
  /// **'Your equipment'**
  String get onboardingYourEquipment;

  /// No description provided for @onboardingCulinaryEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Culinary preferences'**
  String get onboardingCulinaryEditTitle;

  /// No description provided for @onboardingCulinaryTitle.
  ///
  /// In en, this message translates to:
  /// **'What you love to eat'**
  String get onboardingCulinaryTitle;

  /// No description provided for @onboardingCulinarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick as many or as few as you like.'**
  String get onboardingCulinarySubtitle;

  /// No description provided for @onboardingInterestBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced meals'**
  String get onboardingInterestBalanced;

  /// No description provided for @onboardingInterestProtein.
  ///
  /// In en, this message translates to:
  /// **'More protein'**
  String get onboardingInterestProtein;

  /// No description provided for @onboardingInterestVariety.
  ///
  /// In en, this message translates to:
  /// **'More variety'**
  String get onboardingInterestVariety;

  /// No description provided for @onboardingInterestPlants.
  ///
  /// In en, this message translates to:
  /// **'More vegetables & plants'**
  String get onboardingInterestPlants;

  /// No description provided for @onboardingInterestEducation.
  ///
  /// In en, this message translates to:
  /// **'Learn about nutrition'**
  String get onboardingInterestEducation;

  /// No description provided for @onboardingWellnessQuestion.
  ///
  /// In en, this message translates to:
  /// **'Anything you\'d like help with?'**
  String get onboardingWellnessQuestion;

  /// No description provided for @onboardingShowNutritionTitle.
  ///
  /// In en, this message translates to:
  /// **'Show nutrition on recipes'**
  String get onboardingShowNutritionTitle;

  /// No description provided for @onboardingShowNutritionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Estimated protein, fibre and more'**
  String get onboardingShowNutritionSubtitle;

  /// No description provided for @onboardingTrackCaloriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Track calories'**
  String get onboardingTrackCaloriesTitle;

  /// No description provided for @onboardingTrackCaloriesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Off by default. Chefii never sets targets for you.'**
  String get onboardingTrackCaloriesSubtitle;

  /// No description provided for @onboardingSmileTitle.
  ///
  /// In en, this message translates to:
  /// **'Smile & Food'**
  String get onboardingSmileTitle;

  /// No description provided for @onboardingSmileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Education about sugar and acid exposure for your teeth'**
  String get onboardingSmileSubtitle;

  /// No description provided for @onboardingWellnessDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Chefii offers food and nutrition education. It isn\'t medical advice and doesn\'t diagnose or treat any condition.'**
  String get onboardingWellnessDisclaimer;

  /// No description provided for @onboardingWellnessEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Wellness preferences'**
  String get onboardingWellnessEditTitle;

  /// No description provided for @onboardingWellnessTitle.
  ///
  /// In en, this message translates to:
  /// **'Wellness, your way'**
  String get onboardingWellnessTitle;

  /// No description provided for @onboardingWellnessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Entirely optional — and never about guilt.'**
  String get onboardingWellnessSubtitle;

  /// No description provided for @onboardingKitchenTitle.
  ///
  /// In en, this message translates to:
  /// **'Build your kitchen'**
  String get onboardingKitchenTitle;

  /// No description provided for @onboardingKitchenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The fastest way is your last grocery receipt.'**
  String get onboardingKitchenSubtitle;

  /// No description provided for @onboardingKitchenLater.
  ///
  /// In en, this message translates to:
  /// **'I\'ll do this later'**
  String get onboardingKitchenLater;

  /// No description provided for @onboardingOptionSemantics.
  ///
  /// In en, this message translates to:
  /// **'{title}. {body}'**
  String onboardingOptionSemantics(String title, String body);

  /// No description provided for @onboardingScanReceiptTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a receipt'**
  String get onboardingScanReceiptTitle;

  /// No description provided for @onboardingScanReceiptBody.
  ///
  /// In en, this message translates to:
  /// **'Everything you bought, in about a minute'**
  String get onboardingScanReceiptBody;

  /// No description provided for @onboardingScanFridgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan your fridge or pantry'**
  String get onboardingScanFridgeTitle;

  /// No description provided for @onboardingScanFridgeBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm what we spot'**
  String get onboardingScanFridgeBody;

  /// No description provided for @onboardingAddManualTitle.
  ///
  /// In en, this message translates to:
  /// **'Add items manually'**
  String get onboardingAddManualTitle;

  /// No description provided for @onboardingAddManualBody.
  ///
  /// In en, this message translates to:
  /// **'Search, scan a barcode or speak'**
  String get onboardingAddManualBody;

  /// No description provided for @onboardingExampleKitchenTitle.
  ///
  /// In en, this message translates to:
  /// **'Start with example ingredients'**
  String get onboardingExampleKitchenTitle;

  /// No description provided for @onboardingExampleKitchenBody.
  ///
  /// In en, this message translates to:
  /// **'Explore Chefii with a sample kitchen'**
  String get onboardingExampleKitchenBody;

  /// No description provided for @planningEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get planningEyebrow;

  /// No description provided for @planningWeekTitle.
  ///
  /// In en, this message translates to:
  /// **'Your week'**
  String get planningWeekTitle;

  /// No description provided for @planningPreviousWeek.
  ///
  /// In en, this message translates to:
  /// **'Previous week'**
  String get planningPreviousWeek;

  /// No description provided for @planningNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get planningNextWeek;

  /// No description provided for @planningLeftoversBatch.
  ///
  /// In en, this message translates to:
  /// **'Leftovers & batch cooking'**
  String get planningLeftoversBatch;

  /// No description provided for @planningBuildShoppingList.
  ///
  /// In en, this message translates to:
  /// **'Build shopping list'**
  String get planningBuildShoppingList;

  /// No description provided for @planningHaveEverything.
  ///
  /// In en, this message translates to:
  /// **'You have everything this week needs.'**
  String get planningHaveEverything;

  /// No description provided for @planningItemsAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item added to your list} other{{count} items added to your list}}'**
  String planningItemsAdded(int count);

  /// No description provided for @planningDayToday.
  ///
  /// In en, this message translates to:
  /// **'{day} · today'**
  String planningDayToday(String day);

  /// No description provided for @planningAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get planningAdd;

  /// No description provided for @planningOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get planningOptions;

  /// No description provided for @planningOpenRecipe.
  ///
  /// In en, this message translates to:
  /// **'Open recipe'**
  String get planningOpenRecipe;

  /// No description provided for @planningAddToPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Add to your plan'**
  String get planningAddToPlanTitle;

  /// No description provided for @planningChooseRecipe.
  ///
  /// In en, this message translates to:
  /// **'Choose a recipe'**
  String get planningChooseRecipe;

  /// No description provided for @planningPlanMeal.
  ///
  /// In en, this message translates to:
  /// **'Plan {day} {meal}'**
  String planningPlanMeal(String day, String meal);

  /// No description provided for @planningPlanned.
  ///
  /// In en, this message translates to:
  /// **'{title} planned'**
  String planningPlanned(String title);

  /// No description provided for @planningChangeRecipe.
  ///
  /// In en, this message translates to:
  /// **'Change recipe'**
  String get planningChangeRecipe;

  /// No description provided for @planningToBuy.
  ///
  /// In en, this message translates to:
  /// **'To buy: {items}'**
  String planningToBuy(String items);

  /// No description provided for @planningSearchRecipes.
  ///
  /// In en, this message translates to:
  /// **'Search recipes'**
  String get planningSearchRecipes;

  /// No description provided for @planningLeftoversSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cook once, eat well all week.'**
  String get planningLeftoversSubtitle;

  /// No description provided for @planningInYourFridge.
  ///
  /// In en, this message translates to:
  /// **'In your fridge'**
  String get planningInYourFridge;

  /// No description provided for @planningNoLeftovers.
  ///
  /// In en, this message translates to:
  /// **'No saved leftovers. When you finish cooking, Chefii can save extra portions here.'**
  String get planningNoLeftovers;

  /// No description provided for @planningLeftoverPortions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 portion} other{{count} portions}}'**
  String planningLeftoverPortions(int count);

  /// No description provided for @planningMadeOn.
  ///
  /// In en, this message translates to:
  /// **'made {day}'**
  String planningMadeOn(String day);

  /// No description provided for @planningEatWithin.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{eat within ~1 day} other{eat within ~{count} days}}'**
  String planningEatWithin(int count);

  /// No description provided for @planningEatPortion.
  ///
  /// In en, this message translates to:
  /// **'Eat a portion'**
  String get planningEatPortion;

  /// No description provided for @planningFreeze.
  ///
  /// In en, this message translates to:
  /// **'Freeze'**
  String get planningFreeze;

  /// No description provided for @planningItemDetails.
  ///
  /// In en, this message translates to:
  /// **'Item details'**
  String get planningItemDetails;

  /// No description provided for @planningGoodForBatch.
  ///
  /// In en, this message translates to:
  /// **'Good for batch cooking'**
  String get planningGoodForBatch;

  /// No description provided for @planningLeftoversEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} (leftovers)'**
  String planningLeftoversEntryTitle(String name);

  /// No description provided for @planningKitchenEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get planningKitchenEyebrow;

  /// No description provided for @planningShoppingTitle.
  ///
  /// In en, this message translates to:
  /// **'Shopping list'**
  String get planningShoppingTitle;

  /// No description provided for @planningToBuyCount.
  ///
  /// In en, this message translates to:
  /// **'{count} to buy'**
  String planningToBuyCount(int count);

  /// No description provided for @planningPutAway.
  ///
  /// In en, this message translates to:
  /// **'Put {count} away in kitchen'**
  String planningPutAway(int count);

  /// No description provided for @planningAddAmountsFirst.
  ///
  /// In en, this message translates to:
  /// **'Add amounts to checked items first, or scan your receipt instead.'**
  String get planningAddAmountsFirst;

  /// No description provided for @planningAddItemHint.
  ///
  /// In en, this message translates to:
  /// **'Add an item'**
  String get planningAddItemHint;

  /// No description provided for @planningFromMealPlan.
  ///
  /// In en, this message translates to:
  /// **'From meal plan'**
  String get planningFromMealPlan;

  /// No description provided for @planningClearChecked.
  ///
  /// In en, this message translates to:
  /// **'Clear checked'**
  String get planningClearChecked;

  /// No description provided for @planningListEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your list is empty'**
  String get planningListEmptyTitle;

  /// No description provided for @planningListEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Plan a few meals and Chefii will add exactly what\'s missing.'**
  String get planningListEmptyMessage;

  /// No description provided for @planningInBasket.
  ///
  /// In en, this message translates to:
  /// **'In the basket'**
  String get planningInBasket;

  /// No description provided for @planningAfterShopping.
  ///
  /// In en, this message translates to:
  /// **'After shopping, scan your receipt for exact amounts and prices — or put checked items away now.'**
  String get planningAfterShopping;

  /// No description provided for @planningForRecipes.
  ///
  /// In en, this message translates to:
  /// **'for {titles}'**
  String planningForRecipes(String titles);

  /// No description provided for @planningRunningLow.
  ///
  /// In en, this message translates to:
  /// **'running low'**
  String get planningRunningLow;

  /// No description provided for @planningDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get planningDetails;

  /// No description provided for @planningItemRemovedTitle.
  ///
  /// In en, this message translates to:
  /// **'Item removed'**
  String get planningItemRemovedTitle;

  /// No description provided for @planningItemRemovedMessage.
  ///
  /// In en, this message translates to:
  /// **'It may have been bought or removed.'**
  String get planningItemRemovedMessage;

  /// No description provided for @planningPortions.
  ///
  /// In en, this message translates to:
  /// **'Portions'**
  String get planningPortions;

  /// No description provided for @planningQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get planningQuantity;

  /// No description provided for @planningPreferredProduct.
  ///
  /// In en, this message translates to:
  /// **'Preferred brand or product'**
  String get planningPreferredProduct;

  /// No description provided for @planningExpectedPrice.
  ///
  /// In en, this message translates to:
  /// **'Expected price (\$)'**
  String get planningExpectedPrice;

  /// No description provided for @planningLastPaid.
  ///
  /// In en, this message translates to:
  /// **'Last paid {price} on a scanned receipt'**
  String planningLastPaid(String price);

  /// No description provided for @planningNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get planningNote;

  /// No description provided for @planningAlternatives.
  ///
  /// In en, this message translates to:
  /// **'Alternatives'**
  String get planningAlternatives;

  /// No description provided for @planningNeededFor.
  ///
  /// In en, this message translates to:
  /// **'Needed for'**
  String get planningNeededFor;

  /// No description provided for @planningSpendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Spending & waste'**
  String get planningSpendingTitle;

  /// No description provided for @planningGroceriesThisMonth.
  ///
  /// In en, this message translates to:
  /// **'groceries this month'**
  String get planningGroceriesThisMonth;

  /// No description provided for @planningItemsDiscarded.
  ///
  /// In en, this message translates to:
  /// **'items discarded recently'**
  String get planningItemsDiscarded;

  /// No description provided for @planningLastSixWeeks.
  ///
  /// In en, this message translates to:
  /// **'Last six weeks'**
  String get planningLastSixWeeks;

  /// No description provided for @planningScanReceiptsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Scan receipts to see spending trends.'**
  String get planningScanReceiptsEmpty;

  /// No description provided for @planningThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get planningThisWeek;

  /// No description provided for @planningWeeksAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 week ago} other{{count} weeks ago}}'**
  String planningWeeksAgo(int count);

  /// No description provided for @planningWeeksAgoShort.
  ///
  /// In en, this message translates to:
  /// **'{count} wk ago'**
  String planningWeeksAgoShort(int count);

  /// No description provided for @planningWeekAmount.
  ///
  /// In en, this message translates to:
  /// **'{week}: {amount}'**
  String planningWeekAmount(String week, String amount);

  /// No description provided for @planningRecentlyDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Recently discarded'**
  String get planningRecentlyDiscarded;

  /// No description provided for @planningNothingDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Nothing thrown out recently. Lovely.'**
  String get planningNothingDiscarded;

  /// No description provided for @planningSpendingFootnote.
  ///
  /// In en, this message translates to:
  /// **'Spending comes from scanned receipts only. Waste counts items you marked as discarded.'**
  String get planningSpendingFootnote;

  /// No description provided for @prosEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Professionals'**
  String get prosEyebrow;

  /// No description provided for @prosCircleTitle.
  ///
  /// In en, this message translates to:
  /// **'My nutrition circle'**
  String get prosCircleTitle;

  /// No description provided for @prosCircleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share exactly what you choose, for as long as you choose, with verified dietitians and dental professionals.'**
  String get prosCircleSubtitle;

  /// No description provided for @prosInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite a professional'**
  String get prosInvite;

  /// No description provided for @prosCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Their Chefii code'**
  String get prosCodeHint;

  /// No description provided for @prosFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get prosFind;

  /// No description provided for @prosNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No verified professional has that code. Check it with them.'**
  String get prosNoMatch;

  /// No description provided for @prosDemoSample.
  ///
  /// In en, this message translates to:
  /// **'Demo: use a sample dietitian'**
  String get prosDemoSample;

  /// No description provided for @prosWhoCanSee.
  ///
  /// In en, this message translates to:
  /// **'Who can see what'**
  String get prosWhoCanSee;

  /// No description provided for @prosNothingShared.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t shared anything. Nothing is visible to anyone.'**
  String get prosNothingShared;

  /// No description provided for @prosGrantUntil.
  ///
  /// In en, this message translates to:
  /// **'{categories}\nUntil {date}'**
  String prosGrantUntil(String categories, String date);

  /// No description provided for @prosRevokedOn.
  ///
  /// In en, this message translates to:
  /// **'Access revoked {date}'**
  String prosRevokedOn(String date);

  /// No description provided for @prosRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access revoked'**
  String get prosRevoked;

  /// No description provided for @prosExpired.
  ///
  /// In en, this message translates to:
  /// **'Access expired'**
  String get prosExpired;

  /// No description provided for @prosActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get prosActive;

  /// No description provided for @prosEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get prosEnded;

  /// No description provided for @prosReviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get prosReviews;

  /// No description provided for @prosReadOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'Professionals see read-only copies of what you share. They can\'t change your meals, kitchen or plans.'**
  String get prosReadOnlyNote;

  /// No description provided for @prosCredentialsVerified.
  ///
  /// In en, this message translates to:
  /// **'{body} · #{number} · verified'**
  String prosCredentialsVerified(String body, String number);

  /// No description provided for @prosCredentialsNotVerified.
  ///
  /// In en, this message translates to:
  /// **'{body} · #{number} · not verified'**
  String prosCredentialsNotVerified(String body, String number);

  /// No description provided for @prosUpdateSharing.
  ///
  /// In en, this message translates to:
  /// **'Update sharing'**
  String get prosUpdateSharing;

  /// No description provided for @prosShareWith.
  ///
  /// In en, this message translates to:
  /// **'Share with {name}'**
  String prosShareWith(String name);

  /// No description provided for @prosShareWithQuestion.
  ///
  /// In en, this message translates to:
  /// **'Share with {name}?'**
  String prosShareWithQuestion(String name);

  /// No description provided for @prosShareConfirm.
  ///
  /// In en, this message translates to:
  /// **'{categories} from the last {days} days, until {date}. You can revoke any time.'**
  String prosShareConfirm(String categories, int days, String date);

  /// No description provided for @prosShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get prosShare;

  /// No description provided for @prosSharedWith.
  ///
  /// In en, this message translates to:
  /// **'Shared with {name}'**
  String prosSharedWith(String name);

  /// No description provided for @prosWhatToShare.
  ///
  /// In en, this message translates to:
  /// **'What to share'**
  String get prosWhatToShare;

  /// No description provided for @prosHowFarBack.
  ///
  /// In en, this message translates to:
  /// **'How far back'**
  String get prosHowFarBack;

  /// No description provided for @prosOneYear.
  ///
  /// In en, this message translates to:
  /// **'1 year'**
  String get prosOneYear;

  /// No description provided for @prosDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String prosDays(int count);

  /// No description provided for @prosAccessEndsAfter.
  ///
  /// In en, this message translates to:
  /// **'Access ends after'**
  String get prosAccessEndsAfter;

  /// No description provided for @prosRevokeNow.
  ///
  /// In en, this message translates to:
  /// **'Revoke access now'**
  String get prosRevokeNow;

  /// No description provided for @prosRevokeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Revoke access?'**
  String get prosRevokeQuestion;

  /// No description provided for @prosRevokeMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} will immediately lose access to everything you shared.'**
  String prosRevokeMessage(String name);

  /// No description provided for @prosRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get prosRevoke;

  /// No description provided for @prosAccessHistory.
  ///
  /// In en, this message translates to:
  /// **'Access history'**
  String get prosAccessHistory;

  /// No description provided for @prosNotViewedYet.
  ///
  /// In en, this message translates to:
  /// **'{name} hasn\'t viewed anything yet.'**
  String prosNotViewedYet(String name);

  /// No description provided for @prosViewed.
  ///
  /// In en, this message translates to:
  /// **'Viewed {what}'**
  String prosViewed(String what);

  /// No description provided for @prosProfessionalReview.
  ///
  /// In en, this message translates to:
  /// **'Professional review'**
  String get prosProfessionalReview;

  /// No description provided for @prosAcceptRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Accept recommendations'**
  String get prosAcceptRecommendations;

  /// No description provided for @prosRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Recommendations'**
  String get prosRecommendations;

  /// No description provided for @prosAcceptNote.
  ///
  /// In en, this message translates to:
  /// **'Accepting keeps these on your profile. Nothing in your plan or kitchen changes unless you change it.'**
  String get prosAcceptNote;

  /// No description provided for @prosDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get prosDecline;

  /// No description provided for @prosOpenPlanner.
  ///
  /// In en, this message translates to:
  /// **'Open meal planner'**
  String get prosOpenPlanner;

  /// No description provided for @prosPortal.
  ///
  /// In en, this message translates to:
  /// **'Professional portal'**
  String get prosPortal;

  /// No description provided for @prosVerificationPending.
  ///
  /// In en, this message translates to:
  /// **'Verification pending'**
  String get prosVerificationPending;

  /// No description provided for @prosVerificationPendingBody.
  ///
  /// In en, this message translates to:
  /// **'We\'re confirming your registration with {body}. You\'ll be able to see clients\' shared records once verified.'**
  String prosVerificationPendingBody(String body);

  /// No description provided for @prosDemoVerify.
  ///
  /// In en, this message translates to:
  /// **'Demo: simulate verification'**
  String get prosDemoVerify;

  /// No description provided for @prosClients.
  ///
  /// In en, this message translates to:
  /// **'Clients'**
  String get prosClients;

  /// No description provided for @prosClientCode.
  ///
  /// In en, this message translates to:
  /// **'Your client code: {code}'**
  String prosClientCode(String code);

  /// No description provided for @prosNoClients.
  ///
  /// In en, this message translates to:
  /// **'No active clients'**
  String get prosNoClients;

  /// No description provided for @prosNoClientsMessage.
  ///
  /// In en, this message translates to:
  /// **'Clients who share with you appear here while their access is active.'**
  String get prosNoClientsMessage;

  /// No description provided for @prosClientAccessUntil.
  ///
  /// In en, this message translates to:
  /// **'{categories}\nAccess until {date}'**
  String prosClientAccessUntil(String categories, String date);

  /// No description provided for @prosRecordsNote.
  ///
  /// In en, this message translates to:
  /// **'Records are read-only and every view is logged for your client to see.'**
  String get prosRecordsNote;

  /// No description provided for @prosJoinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join as a professional'**
  String get prosJoinTitle;

  /// No description provided for @prosJoinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'For regulated health professionals. We verify every registration.'**
  String get prosJoinSubtitle;

  /// No description provided for @prosSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit for verification'**
  String get prosSubmit;

  /// No description provided for @prosProfession.
  ///
  /// In en, this message translates to:
  /// **'Profession'**
  String get prosProfession;

  /// No description provided for @prosRegulatoryCollege.
  ///
  /// In en, this message translates to:
  /// **'Regulatory college'**
  String get prosRegulatoryCollege;

  /// No description provided for @prosRegulatoryCollegeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. College of Dietitians of Ontario'**
  String get prosRegulatoryCollegeHint;

  /// No description provided for @prosRegistrationNumber.
  ///
  /// In en, this message translates to:
  /// **'Registration number'**
  String get prosRegistrationNumber;

  /// No description provided for @prosProvince.
  ///
  /// In en, this message translates to:
  /// **'Province'**
  String get prosProvince;

  /// No description provided for @prosAccessEnded.
  ///
  /// In en, this message translates to:
  /// **'Access has ended'**
  String get prosAccessEnded;

  /// No description provided for @prosAccessEndedMessage.
  ///
  /// In en, this message translates to:
  /// **'This client\'s sharing has expired or been revoked.'**
  String get prosAccessEndedMessage;

  /// No description provided for @prosClient.
  ///
  /// In en, this message translates to:
  /// **'Client'**
  String get prosClient;

  /// No description provided for @prosSharedSince.
  ///
  /// In en, this message translates to:
  /// **'Shared since {date} · read-only'**
  String prosSharedSince(String date);

  /// No description provided for @prosWriteAssessment.
  ///
  /// In en, this message translates to:
  /// **'Write assessment'**
  String get prosWriteAssessment;

  /// No description provided for @prosChooseCategory.
  ///
  /// In en, this message translates to:
  /// **'Choose a category to view.'**
  String get prosChooseCategory;

  /// No description provided for @prosNoRecords.
  ///
  /// In en, this message translates to:
  /// **'No records in the shared range.'**
  String get prosNoRecords;

  /// No description provided for @prosRecordMeal.
  ///
  /// In en, this message translates to:
  /// **'{title} · {meal} · {portions} portion(s)'**
  String prosRecordMeal(String title, String meal, String portions);

  /// No description provided for @prosRecordMealKcal.
  ///
  /// In en, this message translates to:
  /// **'{title} · {meal} · {portions} portion(s) · ≈ {kcal} kcal'**
  String prosRecordMealKcal(
    String title,
    String meal,
    String portions,
    String kcal,
  );

  /// No description provided for @prosRecordGlucose.
  ///
  /// In en, this message translates to:
  /// **'{value} mmol/L · {context}'**
  String prosRecordGlucose(String value, String context);

  /// No description provided for @prosGlucoseContext.
  ///
  /// In en, this message translates to:
  /// **'{context, select, other{{context}}}'**
  String prosGlucoseContext(String context);

  /// No description provided for @prosRecordConcern.
  ///
  /// In en, this message translates to:
  /// **'{area}: {description} ({severity}/5)'**
  String prosRecordConcern(String area, String description, String severity);

  /// No description provided for @prosConcernArea.
  ///
  /// In en, this message translates to:
  /// **'{area, select, other{{area}}}'**
  String prosConcernArea(String area);

  /// No description provided for @prosRecordDietary.
  ///
  /// In en, this message translates to:
  /// **'Allergies: {allergies} · Restrictions: {restrictions}'**
  String prosRecordDietary(String allergies, String restrictions);

  /// No description provided for @prosAssessment.
  ///
  /// In en, this message translates to:
  /// **'Assessment'**
  String get prosAssessment;

  /// No description provided for @prosReviewing.
  ///
  /// In en, this message translates to:
  /// **'Reviewing {date} – today'**
  String prosReviewing(String date);

  /// No description provided for @prosShareWithClient.
  ///
  /// In en, this message translates to:
  /// **'Share with client'**
  String get prosShareWithClient;

  /// No description provided for @prosSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get prosSummary;

  /// No description provided for @prosAddRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Add a recommendation'**
  String get prosAddRecommendation;

  /// No description provided for @prosAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get prosAdd;

  /// No description provided for @prosSignedNote.
  ///
  /// In en, this message translates to:
  /// **'Your client must accept before anything changes. Signed as {name}, {kind}.'**
  String prosSignedNote(String name, String kind);

  /// No description provided for @prosSaveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save as draft'**
  String get prosSaveDraft;

  /// No description provided for @prosDraftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved'**
  String get prosDraftSaved;

  /// No description provided for @receiptsEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receiptsEyebrow;

  /// No description provided for @receiptsCaptureTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a receipt'**
  String get receiptsCaptureTitle;

  /// No description provided for @receiptsCaptureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lay it flat in good light. Long receipts can be captured in a few pages.'**
  String get receiptsCaptureSubtitle;

  /// No description provided for @receiptsScanReceipt.
  ///
  /// In en, this message translates to:
  /// **'Scan receipt'**
  String get receiptsScanReceipt;

  /// No description provided for @receiptsTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get receiptsTakePhoto;

  /// No description provided for @receiptsDemoCapture.
  ///
  /// In en, this message translates to:
  /// **'Demo mode: any photo works — we\'ll show a labelled sample receipt instead of reading it.'**
  String get receiptsDemoCapture;

  /// No description provided for @receiptsCameraPermission.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get receiptsCameraPermission;

  /// No description provided for @receiptsCameraWhy.
  ///
  /// In en, this message translates to:
  /// **'Allow camera access in Settings to scan receipts, or import a photo you already took.'**
  String get receiptsCameraWhy;

  /// No description provided for @receiptsImportPhoto.
  ///
  /// In en, this message translates to:
  /// **'Import a photo'**
  String get receiptsImportPhoto;

  /// No description provided for @receiptsArtworkLabel.
  ///
  /// In en, this message translates to:
  /// **'Receipt on a kitchen counter'**
  String get receiptsArtworkLabel;

  /// No description provided for @receiptsTipLight.
  ///
  /// In en, this message translates to:
  /// **'Bright, even light — avoid shadows across the paper'**
  String get receiptsTipLight;

  /// No description provided for @receiptsTipFrame.
  ///
  /// In en, this message translates to:
  /// **'Include the store name at the top and the total at the bottom'**
  String get receiptsTipFrame;

  /// No description provided for @receiptsTipPages.
  ///
  /// In en, this message translates to:
  /// **'For long receipts, capture each section as its own page'**
  String get receiptsTipPages;

  /// No description provided for @receiptsTipPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Photos are stored privately for your household and used only to read your purchases'**
  String get receiptsTipPrivacy;

  /// No description provided for @receiptsRegularCamera.
  ///
  /// In en, this message translates to:
  /// **'Use the regular camera'**
  String get receiptsRegularCamera;

  /// No description provided for @receiptsImportFromPhotos.
  ///
  /// In en, this message translates to:
  /// **'Import from photos'**
  String get receiptsImportFromPhotos;

  /// No description provided for @receiptsAiFeature.
  ///
  /// In en, this message translates to:
  /// **'reading receipts'**
  String get receiptsAiFeature;

  /// No description provided for @receiptsPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your photo'**
  String get receiptsPreviewTitle;

  /// No description provided for @receiptsPreviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}. Make sure the text is sharp.'**
  String receiptsPreviewSubtitle(int count);

  /// No description provided for @receiptsAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze receipt'**
  String get receiptsAnalyze;

  /// No description provided for @receiptsNoPagesTitle.
  ///
  /// In en, this message translates to:
  /// **'No pages yet'**
  String get receiptsNoPagesTitle;

  /// No description provided for @receiptsNoPagesMessage.
  ///
  /// In en, this message translates to:
  /// **'Capture your receipt to continue.'**
  String get receiptsNoPagesMessage;

  /// No description provided for @receiptsCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get receiptsCapture;

  /// No description provided for @receiptsPageSemantics.
  ///
  /// In en, this message translates to:
  /// **'Receipt page {number}'**
  String receiptsPageSemantics(int number);

  /// No description provided for @receiptsPageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String receiptsPageLabel(int number);

  /// No description provided for @receiptsRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get receiptsRotate;

  /// No description provided for @receiptsRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get receiptsRetake;

  /// No description provided for @receiptsRemovePage.
  ///
  /// In en, this message translates to:
  /// **'Remove page'**
  String get receiptsRemovePage;

  /// No description provided for @receiptsAddPage.
  ///
  /// In en, this message translates to:
  /// **'Add another page'**
  String get receiptsAddPage;

  /// No description provided for @receiptsStepUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading securely'**
  String get receiptsStepUploading;

  /// No description provided for @receiptsStepReading.
  ///
  /// In en, this message translates to:
  /// **'Reading every line'**
  String get receiptsStepReading;

  /// No description provided for @receiptsStepChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking totals and duplicates'**
  String get receiptsStepChecking;

  /// No description provided for @receiptsStepMatching.
  ///
  /// In en, this message translates to:
  /// **'Matching to your kitchen'**
  String get receiptsStepMatching;

  /// No description provided for @receiptsProcessingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reading your receipt'**
  String get receiptsProcessingTitle;

  /// No description provided for @receiptsProcessingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This usually takes under a minute. You can leave — we\'ll keep going.'**
  String get receiptsProcessingSubtitle;

  /// No description provided for @receiptsProgressSemantics.
  ///
  /// In en, this message translates to:
  /// **'Progress {percent} percent'**
  String receiptsProgressSemantics(int percent);

  /// No description provided for @receiptsContinueBackground.
  ///
  /// In en, this message translates to:
  /// **'Continue in the background'**
  String get receiptsContinueBackground;

  /// No description provided for @receiptsNotFound.
  ///
  /// In en, this message translates to:
  /// **'Receipt not found.'**
  String get receiptsNotFound;

  /// No description provided for @receiptsAlreadyInKitchenTitle.
  ///
  /// In en, this message translates to:
  /// **'Already in your kitchen'**
  String get receiptsAlreadyInKitchenTitle;

  /// No description provided for @receiptsAlreadyImportedMessage.
  ///
  /// In en, this message translates to:
  /// **'This receipt was imported.'**
  String get receiptsAlreadyImportedMessage;

  /// No description provided for @receiptsSeeSummary.
  ///
  /// In en, this message translates to:
  /// **'See summary'**
  String get receiptsSeeSummary;

  /// No description provided for @receiptsReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review purchases'**
  String get receiptsReviewTitle;

  /// No description provided for @receiptsReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String receiptsReviewSubtitle(int count);

  /// No description provided for @receiptsReviewSubtitleToCheck.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}} · {review} to check'**
  String receiptsReviewSubtitleToCheck(int count, int review);

  /// No description provided for @receiptsResolveItems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Resolve 1 item} other{Resolve {count} items}}'**
  String receiptsResolveItems(int count);

  /// No description provided for @receiptsDemoReview.
  ///
  /// In en, this message translates to:
  /// **'Demo: this is a built-in sample receipt, not your photo.'**
  String get receiptsDemoReview;

  /// No description provided for @receiptsTotalsMatch.
  ///
  /// In en, this message translates to:
  /// **'Items add up to the receipt subtotal.'**
  String get receiptsTotalsMatch;

  /// No description provided for @receiptsTotalsMatchWithTotal.
  ///
  /// In en, this message translates to:
  /// **'Items add up to the receipt subtotal · total {total}.'**
  String receiptsTotalsMatchWithTotal(String total);

  /// No description provided for @receiptsTotalsMismatch.
  ///
  /// In en, this message translates to:
  /// **'Items add up to {linesTotal} but the subtotal reads {subtotal}. A line may be missing — you can add it.'**
  String receiptsTotalsMismatch(String linesTotal, String subtotal);

  /// No description provided for @receiptsAddMissingItem.
  ///
  /// In en, this message translates to:
  /// **'Add a missing item'**
  String get receiptsAddMissingItem;

  /// No description provided for @receiptsUnknownItem.
  ///
  /// In en, this message translates to:
  /// **'Unknown item'**
  String get receiptsUnknownItem;

  /// No description provided for @receiptsAmountNeeded.
  ///
  /// In en, this message translates to:
  /// **'Amount needed'**
  String get receiptsAmountNeeded;

  /// No description provided for @receiptsNotFood.
  ///
  /// In en, this message translates to:
  /// **'Not food'**
  String get receiptsNotFood;

  /// No description provided for @receiptsChecked.
  ///
  /// In en, this message translates to:
  /// **'Checked'**
  String get receiptsChecked;

  /// No description provided for @receiptsPleaseCheck.
  ///
  /// In en, this message translates to:
  /// **'Please check'**
  String get receiptsPleaseCheck;

  /// No description provided for @receiptsExcludedSemantics.
  ///
  /// In en, this message translates to:
  /// **'Excluded. Tap to include'**
  String get receiptsExcludedSemantics;

  /// No description provided for @receiptsIncludedSemantics.
  ///
  /// In en, this message translates to:
  /// **'Included. Tap to exclude'**
  String get receiptsIncludedSemantics;

  /// No description provided for @receiptsAddedByYou.
  ///
  /// In en, this message translates to:
  /// **'(added by you)'**
  String get receiptsAddedByYou;

  /// No description provided for @receiptsAddItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Add an item'**
  String get receiptsAddItemTitle;

  /// No description provided for @receiptsCorrectItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Correct item'**
  String get receiptsCorrectItemTitle;

  /// No description provided for @receiptsReceiptSays.
  ///
  /// In en, this message translates to:
  /// **'Receipt says: {text}'**
  String receiptsReceiptSays(String text);

  /// No description provided for @receiptsIsFood.
  ///
  /// In en, this message translates to:
  /// **'This is food'**
  String get receiptsIsFood;

  /// No description provided for @receiptsIsFoodSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Non-food purchases are not added to your kitchen'**
  String get receiptsIsFoodSubtitle;

  /// No description provided for @receiptsProductName.
  ///
  /// In en, this message translates to:
  /// **'Product name'**
  String get receiptsProductName;

  /// No description provided for @receiptsBrandOptional.
  ///
  /// In en, this message translates to:
  /// **'Brand (optional)'**
  String get receiptsBrandOptional;

  /// No description provided for @receiptsPackageOptional.
  ///
  /// In en, this message translates to:
  /// **'Package size (optional)'**
  String get receiptsPackageOptional;

  /// No description provided for @receiptsPackageHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 750 g tub'**
  String get receiptsPackageHint;

  /// No description provided for @receiptsQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get receiptsQuantity;

  /// No description provided for @receiptsCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get receiptsCategory;

  /// No description provided for @receiptsStoreIn.
  ///
  /// In en, this message translates to:
  /// **'Store in'**
  String get receiptsStoreIn;

  /// No description provided for @receiptsUnknownTitle.
  ///
  /// In en, this message translates to:
  /// **'A few to check'**
  String get receiptsUnknownTitle;

  /// No description provided for @receiptsAllResolved.
  ///
  /// In en, this message translates to:
  /// **'All resolved.'**
  String get receiptsAllResolved;

  /// No description provided for @receiptsUnknownSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us what these are, or leave them out.'**
  String get receiptsUnknownSubtitle;

  /// No description provided for @receiptsStillNeedNameAmount.
  ///
  /// In en, this message translates to:
  /// **'{count} still need a name and amount'**
  String receiptsStillNeedNameAmount(int count);

  /// No description provided for @receiptsNothingLeftTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing left to check'**
  String get receiptsNothingLeftTitle;

  /// No description provided for @receiptsNothingLeftMessage.
  ///
  /// In en, this message translates to:
  /// **'Everything has a name and an amount.'**
  String get receiptsNothingLeftMessage;

  /// No description provided for @receiptsCouldntTell.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t tell what this is'**
  String get receiptsCouldntTell;

  /// No description provided for @receiptsLooksLikeUnknownAmount.
  ///
  /// In en, this message translates to:
  /// **'Looks like: {name} (amount unknown)'**
  String receiptsLooksLikeUnknownAmount(String name);

  /// No description provided for @receiptsLooksLikeWithAmount.
  ///
  /// In en, this message translates to:
  /// **'Looks like: {name} · {quantity}'**
  String receiptsLooksLikeWithAmount(String name, String quantity);

  /// No description provided for @receiptsFix.
  ///
  /// In en, this message translates to:
  /// **'Fix'**
  String get receiptsFix;

  /// No description provided for @receiptsLooksRight.
  ///
  /// In en, this message translates to:
  /// **'Looks right'**
  String get receiptsLooksRight;

  /// No description provided for @receiptsLeaveOut.
  ///
  /// In en, this message translates to:
  /// **'Leave out'**
  String get receiptsLeaveOut;

  /// No description provided for @receiptsStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'Where does it go?'**
  String get receiptsStorageTitle;

  /// No description provided for @receiptsStorageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ve suggested a spot for each. Tap to change.'**
  String get receiptsStorageSubtitle;

  /// No description provided for @receiptsAddToKitchen.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Add 1 item to kitchen} other{Add {count} items to kitchen}}'**
  String receiptsAddToKitchen(int count);

  /// No description provided for @receiptsChangeStorage.
  ///
  /// In en, this message translates to:
  /// **'Change storage'**
  String get receiptsChangeStorage;

  /// No description provided for @receiptsDuplicateTitle.
  ///
  /// In en, this message translates to:
  /// **'Already scanned?'**
  String get receiptsDuplicateTitle;

  /// No description provided for @receiptsViewEarlier.
  ///
  /// In en, this message translates to:
  /// **'View the earlier receipt'**
  String get receiptsViewEarlier;

  /// No description provided for @receiptsDuplicateHeadline.
  ///
  /// In en, this message translates to:
  /// **'This looks like a receipt you\'ve already added'**
  String get receiptsDuplicateHeadline;

  /// No description provided for @receiptsDuplicateMessage.
  ///
  /// In en, this message translates to:
  /// **'To avoid counting groceries twice, we stopped here.'**
  String get receiptsDuplicateMessage;

  /// No description provided for @receiptsDuplicateMessageWithDate.
  ///
  /// In en, this message translates to:
  /// **'To avoid counting groceries twice, we stopped here. Earlier scan: {date}.'**
  String receiptsDuplicateMessageWithDate(String date);

  /// No description provided for @receiptsDifferentReceipt.
  ///
  /// In en, this message translates to:
  /// **'It\'s a different receipt — continue'**
  String get receiptsDifferentReceipt;

  /// No description provided for @receiptsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t read that one'**
  String get receiptsErrorTitle;

  /// No description provided for @receiptsRetakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Retake photo'**
  String get receiptsRetakePhoto;

  /// No description provided for @receiptsSomethingWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get receiptsSomethingWrong;

  /// No description provided for @receiptsQualityMessage.
  ///
  /// In en, this message translates to:
  /// **'The photo may be blurry, too dark or cut off. Lay the receipt flat in bright light and include the whole thing.'**
  String get receiptsQualityMessage;

  /// No description provided for @receiptsSafeRetry.
  ///
  /// In en, this message translates to:
  /// **'Nothing was added to your kitchen, so it\'s safe to retry.'**
  String get receiptsSafeRetry;

  /// No description provided for @receiptsAddByHand.
  ///
  /// In en, this message translates to:
  /// **'Add items by hand instead'**
  String get receiptsAddByHand;

  /// No description provided for @receiptsDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Your kitchen is up to date'**
  String get receiptsDoneTitle;

  /// No description provided for @receiptsViewKitchen.
  ///
  /// In en, this message translates to:
  /// **'View kitchen'**
  String get receiptsViewKitchen;

  /// No description provided for @receiptsMetricAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{items added}}'**
  String receiptsMetricAdded(int count);

  /// No description provided for @receiptsMetricLeftOut.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{left out}}'**
  String receiptsMetricLeftOut(int count);

  /// No description provided for @receiptsMetricTotal.
  ///
  /// In en, this message translates to:
  /// **'total'**
  String get receiptsMetricTotal;

  /// No description provided for @receiptsEstimatedNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item is marked as estimated. Chefii will ask you to confirm next time you\'re in the kitchen.} other{{count} items are marked as estimated. Chefii will ask you to confirm next time you\'re in the kitchen.}}'**
  String receiptsEstimatedNote(int count);

  /// No description provided for @receiptsUndoImportButton.
  ///
  /// In en, this message translates to:
  /// **'Undo this import'**
  String get receiptsUndoImportButton;

  /// No description provided for @receiptsUndoImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Undo import?'**
  String get receiptsUndoImportTitle;

  /// No description provided for @receiptsUndoImportMessage.
  ///
  /// In en, this message translates to:
  /// **'Removes these items from your kitchen. Anything already used stays recorded.'**
  String get receiptsUndoImportMessage;

  /// No description provided for @receiptsUndoImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Undo import'**
  String get receiptsUndoImportConfirm;

  /// No description provided for @receiptsScanAnother.
  ///
  /// In en, this message translates to:
  /// **'Scan another receipt'**
  String get receiptsScanAnother;

  /// No description provided for @receiptsListEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get receiptsListEyebrow;

  /// No description provided for @receiptsListTitle.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get receiptsListTitle;

  /// No description provided for @receiptsListEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No receipts yet'**
  String get receiptsListEmptyTitle;

  /// No description provided for @receiptsListEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Scanned receipts appear here.'**
  String get receiptsListEmptyMessage;

  /// No description provided for @sharedAiConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Use AI for {feature}?'**
  String sharedAiConsentTitle(String feature);

  /// No description provided for @sharedAiConsentMessage.
  ///
  /// In en, this message translates to:
  /// **'To do this, Chefii sends the photo or text to its AI provider (Google Gemini) through our secure servers in Canada. It isn\'t used to train their models under our agreements, and you can turn this off any time in Privacy & data.'**
  String get sharedAiConsentMessage;

  /// No description provided for @sharedAiConsentAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get sharedAiConsentAllow;

  /// No description provided for @sharedAiConsentNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get sharedAiConsentNotNow;

  /// No description provided for @sharedTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get sharedTakePhoto;

  /// No description provided for @sharedChooseFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Choose from library'**
  String get sharedChooseFromLibrary;

  /// No description provided for @todayNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get todayNotifications;

  /// No description provided for @todayUnreadNotifications.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread notification} other{{count} unread notifications}}'**
  String todayUnreadNotifications(int count);

  /// No description provided for @todayGreeting.
  ///
  /// In en, this message translates to:
  /// **'{greeting}.'**
  String todayGreeting(String greeting);

  /// No description provided for @todayGreetingName.
  ///
  /// In en, this message translates to:
  /// **'{greeting},\n{name}.'**
  String todayGreetingName(String greeting, String name);

  /// No description provided for @todayScanReceipt.
  ///
  /// In en, this message translates to:
  /// **'Scan a receipt'**
  String get todayScanReceipt;

  /// No description provided for @todayStartCooking.
  ///
  /// In en, this message translates to:
  /// **'Start cooking'**
  String get todayStartCooking;

  /// No description provided for @todayReceiptReady.
  ///
  /// In en, this message translates to:
  /// **'Your receipt is ready to review'**
  String get todayReceiptReady;

  /// No description provided for @todayReceiptReading.
  ///
  /// In en, this message translates to:
  /// **'Reading your receipt…'**
  String get todayReceiptReading;

  /// No description provided for @todayPlannedFor.
  ///
  /// In en, this message translates to:
  /// **'{mealType, select, other{Planned for {meal}}}'**
  String todayPlannedFor(String mealType, String meal);

  /// No description provided for @todayFor.
  ///
  /// In en, this message translates to:
  /// **'{mealType, select, other{For {meal}}}'**
  String todayFor(String mealType, String meal);

  /// No description provided for @todayMinutesChip.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String todayMinutesChip(int minutes);

  /// No description provided for @todayUsesExpiring.
  ///
  /// In en, this message translates to:
  /// **'Uses ingredients that need eating soon.'**
  String get todayUsesExpiring;

  /// No description provided for @todayNothingFits.
  ///
  /// In en, this message translates to:
  /// **'Nothing fits in {minutes} minutes'**
  String todayNothingFits(int minutes);

  /// No description provided for @todayNothingFitsMessage.
  ///
  /// In en, this message translates to:
  /// **'Try more time, or ask your chef for an idea.'**
  String get todayNothingFitsMessage;

  /// No description provided for @todayAskChef.
  ///
  /// In en, this message translates to:
  /// **'Ask the chef'**
  String get todayAskChef;

  /// No description provided for @todayDailyBriefing.
  ///
  /// In en, this message translates to:
  /// **'Daily briefing'**
  String get todayDailyBriefing;

  /// No description provided for @todayYourKitchen.
  ///
  /// In en, this message translates to:
  /// **'Your kitchen'**
  String get todayYourKitchen;

  /// No description provided for @todayTileItems.
  ///
  /// In en, this message translates to:
  /// **'items'**
  String get todayTileItems;

  /// No description provided for @todayTileUseSoon.
  ///
  /// In en, this message translates to:
  /// **'use soon'**
  String get todayTileUseSoon;

  /// No description provided for @todayTileToVerify.
  ///
  /// In en, this message translates to:
  /// **'to verify'**
  String get todayTileToVerify;

  /// No description provided for @todayScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get todayScan;

  /// No description provided for @todayIUsed.
  ///
  /// In en, this message translates to:
  /// **'I used…'**
  String get todayIUsed;

  /// No description provided for @todayReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get todayReminders;

  /// No description provided for @todayUseSoon.
  ///
  /// In en, this message translates to:
  /// **'Use {name} soon'**
  String todayUseSoon(String name);

  /// No description provided for @todayEstimatedFromPurchase.
  ///
  /// In en, this message translates to:
  /// **'Estimated from purchase date'**
  String get todayEstimatedFromPurchase;

  /// No description provided for @todayRecordedDate.
  ///
  /// In en, this message translates to:
  /// **'Recorded date {date}'**
  String todayRecordedDate(String date);

  /// No description provided for @todayRunningLow.
  ///
  /// In en, this message translates to:
  /// **'Running low on {name}'**
  String todayRunningLow(String name);

  /// No description provided for @todayAddedToShopping.
  ///
  /// In en, this message translates to:
  /// **'{name} added to your shopping list'**
  String todayAddedToShopping(String name);

  /// No description provided for @todayAddToList.
  ///
  /// In en, this message translates to:
  /// **'Add to list'**
  String get todayAddToList;

  /// No description provided for @todayAvailability.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Everything on hand} =1{1 ingredient to buy} other{{count} ingredients to buy}}'**
  String todayAvailability(int count);

  /// No description provided for @todayPrepStart.
  ///
  /// In en, this message translates to:
  /// **'Start {recipe} ({duration})'**
  String todayPrepStart(String recipe, String duration);

  /// No description provided for @todayYourDayInFood.
  ///
  /// In en, this message translates to:
  /// **'Your day in food'**
  String get todayYourDayInFood;

  /// No description provided for @todayPlanMeals.
  ///
  /// In en, this message translates to:
  /// **'Plan today\'s meals'**
  String get todayPlanMeals;

  /// No description provided for @todayMeals.
  ///
  /// In en, this message translates to:
  /// **'Meals'**
  String get todayMeals;

  /// No description provided for @todayNothingPlanned.
  ///
  /// In en, this message translates to:
  /// **'Nothing planned yet — Today will suggest something at each meal.'**
  String get todayNothingPlanned;

  /// No description provided for @todayPortions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 portion} other{{count} portions}}'**
  String todayPortions(int count);

  /// No description provided for @todayPreparation.
  ///
  /// In en, this message translates to:
  /// **'Preparation'**
  String get todayPreparation;

  /// No description provided for @todayAround.
  ///
  /// In en, this message translates to:
  /// **'around {time}'**
  String todayAround(String time);

  /// No description provided for @todayKitchenAlerts.
  ///
  /// In en, this message translates to:
  /// **'Kitchen alerts'**
  String get todayKitchenAlerts;

  /// No description provided for @todayNothingUrgent.
  ///
  /// In en, this message translates to:
  /// **'Nothing urgent.'**
  String get todayNothingUrgent;

  /// No description provided for @todayUseTodayIfYouCan.
  ///
  /// In en, this message translates to:
  /// **'{quantity} · use today if you can'**
  String todayUseTodayIfYouCan(String quantity);

  /// No description provided for @todayTomorrowMorning.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow morning'**
  String get todayTomorrowMorning;

  /// No description provided for @todayMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get todayMarkAllRead;

  /// No description provided for @todayAllCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up'**
  String get todayAllCaughtUp;

  /// No description provided for @todayAllCaughtUpMessage.
  ///
  /// In en, this message translates to:
  /// **'Receipt results, sharing invitations and reviews will appear here.'**
  String get todayAllCaughtUpMessage;
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
