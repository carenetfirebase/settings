import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../data/auth/auth_service.dart';
import '../../data/repositories/export_service.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/store/memory_doc_store.dart';
import '../../domain/models/profile.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

const supportEmail = 'support@chefii.app';

String _roleLabel(AppLocalizations l, HouseholdRole r) => switch (r) {
      HouseholdRole.owner => l.accountRoleOwner,
      HouseholdRole.adult => l.accountRoleAdult,
      HouseholdRole.member => l.accountRoleMember,
    };

// ---------------------------------------------------------------- 71 Profile & account (You tab)

class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final profile = ref.watch(profileProvider).value;
    final user = ref.watch(authUserProvider).value;
    final household = ref.watch(householdProvider).value;
    final dietary = ref.watch(dietaryProvider).value ?? const DietaryProfile();
    final wellness = ref.watch(wellnessProvider).value ?? const WellnessPreferences();
    final isPro = ref.watch(myProfessionalProfileProvider).value != null || (user?.isProfessional ?? false);

    Widget tile(IconData icon, String title, String route, {String? subtitle}) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(route),
        );

    return PremiumAppScaffold(
      showBack: false,
      header: EditorialPageHeader(eyebrow: l.accountEyebrow, title: profile?.displayName ?? l.accountTitleFallback, subtitle: [profile?.email, household?.name].whereType<String>().join(' · ')),
      children: [
        Row(children: [
          Expanded(
            child: TextButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: Text(l.accountEditName),
              onPressed: () async {
                final c = TextEditingController(text: profile?.displayName);
                final name = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(l.accountYourName),
                    content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)), TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(l.commonSave))],
                  ),
                );
                if (name != null && name.isNotEmpty && profile != null) await ref.read(profileRepoProvider).saveProfile(profile.copyWith(displayName: name));
              },
            ),
          ),
        ]),
        SectionHeader(l.accountSectionPreferences, topSpacing: Space.s),
        tile(Icons.health_and_safety_outlined, l.accountDietarySafety, '/you/dietary',
            subtitle: dietary.allergiesKnown
                ? (dietary.allergies.isEmpty ? l.accountNoAllergies : dietary.allergies.map(context.allergenLabel).join(', '))
                : l.accountNotProvidedYet),
        tile(Icons.restaurant_menu, l.accountCulinaryPreferences, '/you/culinary'),
        tile(Icons.spa_outlined, l.accountWellnessPreferences, '/you/wellness'),
        tile(Icons.wb_twilight, l.accountMorningRoutine, '/morning/setup'),
        tile(Icons.notifications_active_outlined, l.accountMealReminders, '/journal/reminders'),
        SectionHeader(l.accountSectionHealth),
        tile(Icons.insights_outlined, l.accountNutrition, '/you/nutrition'),
        tile(Icons.lightbulb_outline, l.accountNutritionInsights, '/you/nutrition/intelligence'),
        if (wellness.smileAndFood) tile(Icons.sentiment_satisfied_alt_outlined, l.accountSmileAndFood, '/you/smile'),
        tile(Icons.water_drop_outlined, l.accountGlucoseJournal, wellness.diabetesFeatures ? '/you/glucose' : '/you/diabetes', subtitle: wellness.diabetesFeatures ? null : l.accountOptional),
        tile(Icons.group_outlined, l.accountNutritionCircle, '/you/circle'),
        SectionHeader(l.accountSectionHousehold),
        tile(Icons.family_restroom, l.accountHouseholdMembers, '/you/household'),
        tile(Icons.privacy_tip_outlined, l.accountPrivacyData, '/you/privacy'),
        tile(Icons.hub_outlined, l.accountConnectedServices, '/you/connected'),
        tile(Icons.workspace_premium_outlined, l.accountMembership, '/you/membership'),
        tile(Icons.accessibility_new, l.accountAccessibilityLanguage, '/you/accessibility'),
        tile(Icons.lock_outline, l.accountSecuritySessions, '/you/security'),
        tile(Icons.help_outline, l.accountHelpSupport, '/you/help'),
        tile(Icons.gavel_outlined, l.accountLegalEvidence, '/you/legal'),
        tile(Icons.download_outlined, l.accountExportOrDelete, '/you/data'),
        if (isPro || kIsWeb) tile(Icons.badge_outlined, l.accountProPortal, '/pro'),
        const SizedBox(height: Space.l),
        SecondaryActionButton(
          icon: Icons.logout,
          label: l.accountSignOut,
          onPressed: () async {
            await ref.read(authServiceProvider).signOut();
            if (context.mounted) context.go('/welcome');
          },
        ),
        const SizedBox(height: Space.m),
        Center(child: Text(ref.watch(appConfigProvider).isDemo ? l.accountFooterDemo : l.accountFooterEarlyAccess, style: context.text.bodySmall)),
      ],
    );
  }
}

// ---------------------------------------------------------------- 72 Household members

class HouseholdMembersScreen extends ConsumerWidget {
  const HouseholdMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final household = ref.watch(householdProvider).value;
    final members = ref.watch(membersProvider).value ?? const <HouseholdMember>[];
    final invites = household == null ? const <Map<String, dynamic>>[] : (ref.watch(_invitesProvider(household.id)).value ?? const []);
    final uid = ref.watch(uidProvider);
    final isOwner = household?.ownerUid == uid;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.accountHousehold, title: household?.name ?? l.accountHousehold, subtitle: l.accountUsualPortions(household?.portions ?? 2)),
      primaryAction: isOwner
          ? PrimaryActionButton(
              icon: Icons.person_add_alt,
              label: l.accountInviteSomeone,
              onPressed: () async {
                final code = await ref.read(householdRepoProvider).createInvite(household!.id, uid!);
                await SharePlus.instance.share(ShareParams(text: l.accountInviteShareText(code), subject: l.accountInviteShareSubject));
              },
            )
          : null,
      children: [
        for (final m in members)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(
              leading: CircleAvatar(child: Text(m.displayName.isEmpty ? '?' : m.displayName[0])),
              title: Text(m.uid == uid ? l.accountMemberYou(m.displayName) : m.displayName),
              subtitle: Text(l.accountMemberSubtitle(_roleLabel(l, m.role), formatDay(context, m.joinedAt))),
              trailing: isOwner && m.uid != uid
                  ? IconButton(
                      tooltip: l.commonRemove,
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () async {
                        final ok = await showConfirmActionSheet(context, title: l.accountRemoveMemberTitle(m.displayName), message: l.accountRemoveMemberMessage, confirmLabel: l.commonRemove, destructive: true);
                        if (ok) await ref.read(householdRepoProvider).removeMember(household!.id, m.uid);
                      },
                    )
                  : null,
            ),
          ),
        if (invites.isNotEmpty) ...[
          SectionHeader(l.accountOpenInvitations),
          for (final i in invites) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.mail_outline), title: Text(l.accountInviteCode('${i['code']}')), subtitle: Text(l.accountInviteValidity)),
        ],
        SectionHeader(l.accountWhatMembersShare),
        Text(l.accountMembersShareBody, style: context.text.bodyMedium),
      ],
    );
  }
}

final _invitesProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, hid) => ref.watch(householdRepoProvider).watchInvites(hid));

// ---------------------------------------------------------------- 73 Privacy & data controls

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(settingsProvider).value ?? const AppSettings();
    final consents = ref.watch(consentsProvider).value ?? const <ConsentRecord>[];
    final uid = ref.watch(uidProvider);
    Future<void> save(AppSettings n, {String? consentPurpose, bool? granted}) async {
      await ref.read(profileRepoProvider).saveSettings(uid!, n);
      if (consentPurpose != null) await ref.read(profileRepoProvider).recordConsent(uid, purpose: consentPurpose, granted: granted!);
      ref.read(analyticsProvider).enabled = n.analyticsConsent;
    }

    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.accountPrivacyEyebrow, title: l.accountPrivacyTitle, subtitle: l.accountPrivacySubtitle),
      children: [
        ToggleTile(
          icon: Icons.auto_awesome_outlined,
          title: l.accountAiProcessing,
          subtitle: l.accountAiProcessingBody,
          value: s.aiProcessingConsent,
          onChanged: (v) => save(s.copyWith(aiProcessingConsent: v), consentPurpose: 'ai_processing', granted: v),
        ),
        ToggleTile(
          icon: Icons.chat_outlined,
          title: l.accountOptionalAiProvider,
          subtitle: l.accountOptionalAiProviderBody,
          value: s.allowOptionalAiProvider,
          onChanged: s.aiProcessingConsent ? (v) => save(s.copyWith(allowOptionalAiProvider: v), consentPurpose: 'ai_optional_provider', granted: v) : null,
        ),
        ToggleTile(
          icon: Icons.query_stats,
          title: l.accountAnalytics,
          subtitle: l.accountAnalyticsBody,
          value: s.analyticsConsent,
          onChanged: (v) => save(s.copyWith(analyticsConsent: v), consentPurpose: 'analytics', granted: v),
        ),
        const SizedBox(height: Space.s),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.group_outlined), title: Text(l.accountProfessionalSharing), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/circle')),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.download_outlined), title: Text(l.accountExportOrDelete), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/data')),
        SectionHeader(l.accountConsentHistory),
        if (consents.isEmpty) Text(l.accountNoConsents, style: context.text.bodySmall),
        for (final c in consents.take(20))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(c.granted ? Icons.check_circle_outline : Icons.cancel_outlined, size: 20),
            // The purpose is a stored identifier ('ai_processing', 'share:…'), shown as-is.
            title: Text(c.granted ? l.accountConsentGranted(c.purpose) : l.accountConsentWithdrawn(c.purpose)),
            subtitle: Text(l.accountConsentVersion(formatDay(context, c.recordedAt), c.version)),
          ),
        const SizedBox(height: Space.m),
        Text(l.accountDataResidency, style: context.text.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- 74 Connected services

class ConnectedServicesScreen extends ConsumerWidget {
  const ConnectedServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final ai = ref.watch(aiGatewayProvider);
    final config = ref.watch(appConfigProvider);
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.accountServicesEyebrow, title: l.accountConnectedServices),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(l.accountNotifications),
            subtitle: Text(l.accountNotificationsBody),
            trailing: TextButton(
              onPressed: () async {
                final ok = await ref.read(notificationServiceProvider).requestPermission();
                if (context.mounted) showMessage(context, ok ? l.accountNotificationsOn : l.accountNotificationsOff);
              },
              child: Text(l.accountCheck),
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: Text(l.accountKitchenAi),
            subtitle: Text(ai.isDemo ? l.accountKitchenAiDemo : l.accountKitchenAiConnected),
          ),
        ),
        const SizedBox(height: Space.xs),
        Card(
          child: ListTile(
            leading: const Icon(Icons.favorite_border),
            title: Text(l.accountHealthApps),
            subtitle: Text(l.accountHealthAppsBody),
          ),
        ),
        const SizedBox(height: Space.xs),
        Card(
          child: ListTile(
            leading: const Icon(Icons.group_outlined),
            title: Text(l.accountProfessionals),
            subtitle: Text(l.accountProfessionalsBody),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/you/circle'),
          ),
        ),
        const SizedBox(height: Space.m),
        Text(
          config.isDemo
              ? l.accountBackendDemo
              : config.useEmulators
                  ? l.accountBackendEmulators
                  : l.accountBackendFirebase,
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 75 Subscription & membership

class MembershipScreen extends StatelessWidget {
  const MembershipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.accountMembership, title: l.accountEarlyAccess, subtitle: l.accountMembershipSubtitle),
      children: [
        SoftCard(
          color: context.palette.accentSoft,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.accountMembershipName, style: context.text.headlineSmall),
            const SizedBox(height: Space.xs),
            Text(l.accountMembershipBody, style: context.text.bodyMedium),
          ]),
        ),
        SectionHeader(l.accountIncludedNow),
        for (final f in [l.accountFeatureScanning, l.accountFeatureChef, l.accountFeaturePlanning, l.accountFeatureJournal, l.accountFeatureCircle])
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check), title: Text(f)),
        const SizedBox(height: Space.m),
        Text(l.accountBillingNote, style: context.text.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- 76 Accessibility & language

class AccessibilityScreen extends ConsumerWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(settingsProvider).value ?? const AppSettings();
    Future<void> save(AppSettings n) => ref.read(profileRepoProvider).saveSettings(ref.read(uidProvider)!, n);
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.accountSettingsEyebrow, title: l.accountAccessibilityLanguage),
      children: [
        Text(l.accountTextSize, style: context.text.titleMedium),
        Semantics(label: l.accountTextSize, child: Slider(
          value: s.textScale,
          min: 0.9,
          max: 1.6,
          divisions: 7,
          label: l.accountTextScaleValue((s.textScale * 100).round()),
          semanticFormatterCallback: (v) => l.accountTextScaleSemantic((v * 100).round()),
          onChanged: (v) => save(s.copyWith(textScale: v)),
        )),
        Text(l.accountTextPreview, style: context.text.bodyLarge),
        Text(l.accountDeviceTextSize, style: context.text.bodySmall),
        const SizedBox(height: Space.m),
        ToggleTile(icon: Icons.motion_photos_off_outlined, title: l.accountReduceMotion, subtitle: l.accountReduceMotionBody, value: s.reduceMotion, onChanged: (v) => save(s.copyWith(reduceMotion: v))),
        ToggleTile(icon: Icons.record_voice_over_outlined, title: l.accountReadStepsAloud, subtitle: l.accountReadStepsAloudBody, value: s.voiceGuidance, onChanged: (v) => save(s.copyWith(voiceGuidance: v))),
        SectionHeader(l.accountLanguage),
        RadioGroup<String>(
          groupValue: s.language,
          onChanged: (v) => v == null ? null : save(s.copyWith(language: v)),
          child: Column(children: [
            RadioListTile(value: 'system', title: Text(l.accountLanguageSystem)),
            // Language names are always shown in their own language.
            const RadioListTile(value: 'en-CA', title: Text('English (Canada)')), // l10n-ignore
            const RadioListTile(value: 'fr-CA', title: Text('Français (Canada)')), // l10n-ignore
          ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 77 Security & sessions

class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final user = ref.watch(authUserProvider).value;
    final isDemo = ref.watch(appConfigProvider).isDemo;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.accountSettingsEyebrow, title: l.accountSecuritySessions),
      children: [
        Card(child: ListTile(leading: const Icon(Icons.person_outline), title: Text(user?.email ?? (isDemo ? l.accountDemoAccount : l.accountSignedIn)), subtitle: Text(isDemo ? l.accountStoredOnDevice : l.accountIdShort('${user?.uid.substring(0, 6)}')))),
        const SizedBox(height: Space.xs),
        if (!isDemo && user?.email != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.password),
              title: Text(l.accountResetPassword),
              onTap: () async {
                await ref.read(authServiceProvider).sendPasswordReset(user!.email!);
                if (context.mounted) showMessage(context, l.accountResetPasswordSent);
              },
            ),
          ),
        if (!isDemo)
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices_other),
              title: Text(l.accountSignOutAll),
              subtitle: Text(l.accountSignOutAllBody),
              onTap: () async {
                final ok = await showConfirmActionSheet(context, title: l.accountSignOutEverywhereTitle, message: l.accountSignOutEverywhereMessage, confirmLabel: l.accountSignOutEverywhere, destructive: true);
                if (!ok) return;
                try {
                  await ref.read(authServiceProvider).reauthenticate();
                  await FirebaseFunctions.instanceFor(region: 'northamerica-northeast1').httpsCallable('revokeSessions').call<void>();
                  await ref.read(authServiceProvider).signOut();
                  if (context.mounted) context.go('/welcome');
                } on AuthException catch (e) {
                  if (context.mounted) showMessage(context, e.message, error: true);
                } catch (e) {
                  if (context.mounted) showMessage(context, ErrorState.describe(e), error: true);
                }
              },
            ),
          ),
        const SizedBox(height: Space.m),
        Text(l.accountReauthNote, style: context.text.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- 78 Help & support

class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _msg = TextEditingController();
  String _kind = 'feedback';

  static List<(String, String)> faqs(AppLocalizations l) => [
        (l.accountFaqAccuracyQ, l.accountFaqAccuracyA),
        (l.accountFaqUntrackedQ, l.accountFaqUntrackedA),
        (l.accountFaqFreshnessQ, l.accountFaqFreshnessA),
        (l.accountFaqMedicalQ, l.accountFaqMedicalA),
        (l.accountFaqHealthDataQ, l.accountFaqHealthDataA),
      ];

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.accountHelpEyebrow, title: l.accountHelpTitle),
      primaryAction: PrimaryActionButton(
        label: l.accountSend,
        onPressed: () async {
          if (_msg.text.trim().isEmpty) return;
          await ref.read(profileRepoProvider).submitFeedback(ref.read(uidProvider)!, kind: _kind, message: _msg.text.trim());
          _msg.clear();
          if (context.mounted) showMessage(context, l.accountFeedbackThanks);
        },
      ),
      children: [
        for (final (q, a) in faqs(l)) ExpansionTile(tilePadding: EdgeInsets.zero, title: Text(q), children: [Padding(padding: const EdgeInsets.only(bottom: Space.m), child: Text(a))]),
        SectionHeader(l.accountWriteToUs),
        SegmentedButton<String>(
          segments: [ButtonSegment(value: 'feedback', label: Text(l.accountFeedback)), ButtonSegment(value: 'bug', label: Text(l.accountReportProblem))],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: Space.s),
        TextField(controller: _msg, minLines: 4, maxLines: 8, decoration: InputDecoration(hintText: l.accountFeedbackHint)),
        TextButton.icon(
          icon: const Icon(Icons.mail_outline),
          label: Text(l.accountEmailSupport),
          onPressed: () => launchUrl(Uri(scheme: 'mailto', path: supportEmail, query: 'subject=${l.accountSupportEmailSubject}')),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 79 Legal & evidence disclosures

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  static List<(String, String)> sections(AppLocalizations l) => [
        (l.accountLegalTermsTitle, l.accountLegalTermsBody),
        (l.accountLegalPrivacyTitle, l.accountLegalPrivacyBody),
        (l.accountLegalMedicalTitle, l.accountLegalMedicalBody),
        (l.accountLegalFoodSafetyTitle, l.accountLegalFoodSafetyBody),
        (l.accountLegalEvidenceTitle, l.accountLegalEvidenceBody),
        (l.accountLegalAiTitle, l.accountLegalAiBody),
      ];

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.accountLegalEyebrow, title: l.accountLegalTitle),
      children: [
        for (final (t, b) in sections(l)) ExpansionTile(tilePadding: EdgeInsets.zero, title: Text(t), children: [Padding(padding: const EdgeInsets.only(bottom: Space.m), child: Text(b))]),
        ListTile(contentPadding: EdgeInsets.zero, title: Text(l.accountEvidenceLibrary), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/nutrition/evidence')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.accountLicences),
          subtitle: Text(l.accountLicencesBody),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(context: context, applicationName: 'Chefii'), // l10n-ignore
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 80 Data export & account deletion

class DataControlsScreen extends ConsumerStatefulWidget {
  const DataControlsScreen({super.key});

  @override
  ConsumerState<DataControlsScreen> createState() => _DataControlsScreenState();
}

class _DataControlsScreenState extends ConsumerState<DataControlsScreen> {
  bool _busy = false;
  final _confirm = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _confirm.dispose();
    _password.dispose();
    super.dispose();
  }

  /// The confirmation word is the one shown in the current language
  /// (DELETE / SUPPRIMER).
  bool get _confirmed => _confirm.text.trim().toUpperCase() == context.l10n.accountDeleteConfirmWord;

  Future<void> _export() async {
    final subject = context.l10n.accountExportShareSubject;
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).reauthenticate(password: _password.text.isEmpty ? null : _password.text);
      final uid = ref.read(uidProvider)!;
      final json = await DataExportService(ref.read(docStoreProvider)).toJson(uid, householdId: ref.read(householdIdProvider));
      await ref.read(profileRepoProvider).audit(uid, action: 'export.created', target: uid);
      final file = XFile.fromData(Uint8List.fromList(utf8.encode(json)), mimeType: 'application/json', name: 'chefii-export.json');
      await SharePlus.instance.share(ShareParams(files: [file], subject: subject));
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, ErrorState.describe(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!_confirmed) return;
    setState(() => _busy = true);
    try {
      final auth = ref.read(authServiceProvider);
      await auth.reauthenticate(password: _password.text.isEmpty ? null : _password.text);
      final store = ref.read(docStoreProvider);
      if (store is MemoryDocStore) {
        store.clear(); // demo: everything lives on this device
      } else {
        // Server deletes Firestore + Storage data (and household if sole owner),
        // keeping only records we must retain by law, then the auth user.
        await FirebaseFunctions.instanceFor(region: 'northamerica-northeast1').httpsCallable('deleteAccountData').call<void>();
      }
      await auth.deleteAccount();
      if (mounted) context.go('/welcome');
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, ErrorState.describe(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final isDemo = ref.watch(appConfigProvider).isDemo;
    final hasPassword = !isDemo && (ref.watch(authUserProvider).value?.email != null);
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.accountDataEyebrow, title: l.accountDataTitle),
      children: [
        Text(l.accountExport, style: context.text.titleMedium),
        const SizedBox(height: Space.xs),
        Text(l.accountExportBody, style: context.text.bodyMedium),
        if (hasPassword) ...[
          const SizedBox(height: Space.s),
          TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: l.accountPasswordConfirm)),
        ],
        const SizedBox(height: Space.s),
        SecondaryActionButton(icon: Icons.download_outlined, label: l.accountExportMyData, onPressed: _busy ? null : _export),
        SectionHeader(l.accountDeleteAccount),
        Text(l.accountDeleteBody, style: context.text.bodyMedium),
        const SizedBox(height: Space.s),
        TextField(controller: _confirm, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: l.accountDeleteConfirmLabel(l.accountDeleteConfirmWord))),
        const SizedBox(height: Space.s),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.palette.error, foregroundColor: Colors.white),
            onPressed: _busy || !_confirmed ? null : _delete,
            child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(l.accountDeleteMyAccount),
          ),
        ),
      ],
    );
  }
}

/// Re-exported for account screens.
bool hasConsent(List<ConsentRecord> c, String p) => ProfileRepository.hasConsent(c, p);
