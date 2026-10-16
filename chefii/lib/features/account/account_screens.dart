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
import '../../domain/safety/allergen_guard.dart';

const supportEmail = 'support@chefii.app';

// ---------------------------------------------------------------- 71 Profile & account (You tab)

class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      header: EditorialPageHeader(eyebrow: 'You', title: profile?.displayName ?? 'Your account', subtitle: [profile?.email, household?.name].whereType<String>().join(' · ')),
      children: [
        Row(children: [
          Expanded(
            child: TextButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit name'),
              onPressed: () async {
                final c = TextEditingController(text: profile?.displayName);
                final name = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Your name'),
                    content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save'))],
                  ),
                );
                if (name != null && name.isNotEmpty && profile != null) await ref.read(profileRepoProvider).saveProfile(profile.copyWith(displayName: name));
              },
            ),
          ),
        ]),
        const SectionHeader('Preferences', topSpacing: Space.s),
        tile(Icons.health_and_safety_outlined, 'Dietary safety', '/you/dietary',
            subtitle: dietary.allergiesKnown
                ? (dietary.allergies.isEmpty ? 'No allergies recorded' : dietary.allergies.map((a) => AllergenGuard.byKey[a]?.label ?? a).join(', '))
                : 'Not provided yet'),
        tile(Icons.restaurant_menu, 'Culinary preferences', '/you/culinary'),
        tile(Icons.spa_outlined, 'Wellness preferences', '/you/wellness'),
        tile(Icons.wb_twilight, 'Morning routine', '/morning/setup'),
        tile(Icons.notifications_active_outlined, 'Meal reminders', '/journal/reminders'),
        const SectionHeader('Health & nutrition'),
        tile(Icons.insights_outlined, 'Nutrition', '/you/nutrition'),
        tile(Icons.lightbulb_outline, 'Nutrition insights', '/you/nutrition/intelligence'),
        if (wellness.smileAndFood) tile(Icons.sentiment_satisfied_alt_outlined, 'Smile & Food', '/you/smile'),
        tile(Icons.water_drop_outlined, 'Glucose journal', wellness.diabetesFeatures ? '/you/glucose' : '/you/diabetes', subtitle: wellness.diabetesFeatures ? null : 'Optional'),
        tile(Icons.group_outlined, 'My nutrition circle', '/you/circle'),
        const SectionHeader('Household & account'),
        tile(Icons.family_restroom, 'Household members', '/you/household'),
        tile(Icons.privacy_tip_outlined, 'Privacy & data', '/you/privacy'),
        tile(Icons.hub_outlined, 'Connected services', '/you/connected'),
        tile(Icons.workspace_premium_outlined, 'Membership', '/you/membership'),
        tile(Icons.accessibility_new, 'Accessibility & language', '/you/accessibility'),
        tile(Icons.lock_outline, 'Security & sessions', '/you/security'),
        tile(Icons.help_outline, 'Help & support', '/you/help'),
        tile(Icons.gavel_outlined, 'Legal & evidence', '/you/legal'),
        tile(Icons.download_outlined, 'Export or delete your data', '/you/data'),
        if (isPro || kIsWeb) tile(Icons.badge_outlined, 'Professional portal', '/pro'),
        const SizedBox(height: Space.l),
        SecondaryActionButton(
          icon: Icons.logout,
          label: 'Sign out',
          onPressed: () async {
            await ref.read(authServiceProvider).signOut();
            if (context.mounted) context.go('/welcome');
          },
        ),
        const SizedBox(height: Space.m),
        Center(child: Text('Chefii · ${ref.watch(appConfigProvider).isDemo ? 'Demo mode' : 'Early access'}', style: context.text.bodySmall)),
      ],
    );
  }
}

// ---------------------------------------------------------------- 72 Household members

class HouseholdMembersScreen extends ConsumerWidget {
  const HouseholdMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider).value;
    final members = ref.watch(membersProvider).value ?? const <HouseholdMember>[];
    final invites = household == null ? const <Map<String, dynamic>>[] : (ref.watch(_invitesProvider(household.id)).value ?? const []);
    final uid = ref.watch(uidProvider);
    final isOwner = household?.ownerUid == uid;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'Household', title: household?.name ?? 'Household', subtitle: '${household?.portions ?? 2} usual portions'),
      primaryAction: isOwner
          ? PrimaryActionButton(
              icon: Icons.person_add_alt,
              label: 'Invite someone',
              onPressed: () async {
                final code = await ref.read(householdRepoProvider).createInvite(household!.id, uid!);
                await SharePlus.instance.share(ShareParams(text: 'Join our kitchen on Chefii with code $code (valid for 7 days).', subject: 'Join my Chefii kitchen'));
              },
            )
          : null,
      children: [
        for (final m in members)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(
              leading: CircleAvatar(child: Text(m.displayName.isEmpty ? '?' : m.displayName[0])),
              title: Text(m.uid == uid ? '${m.displayName} (you)' : m.displayName),
              subtitle: Text('${m.role.name[0].toUpperCase()}${m.role.name.substring(1)} · since ${formatDay(context, m.joinedAt)}'),
              trailing: isOwner && m.uid != uid
                  ? IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () async {
                        final ok = await showConfirmActionSheet(context, title: 'Remove ${m.displayName}?', message: 'They\'ll lose access to the shared kitchen. Their private journal stays theirs.', confirmLabel: 'Remove', destructive: true);
                        if (ok) await ref.read(householdRepoProvider).removeMember(household!.id, m.uid);
                      },
                    )
                  : null,
            ),
          ),
        if (invites.isNotEmpty) ...[
          const SectionHeader('Open invitations'),
          for (final i in invites) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.mail_outline), title: Text('Code ${i['code']}'), subtitle: const Text('Valid for 7 days, single use')),
        ],
        const SectionHeader('What members share'),
        Text(
          'Everyone shares the kitchen, shopping list, meal plan and saved recipes. Each person\'s journal, nutrition, glucose, Smile & Food log and professional reviews stay private. '
          'Allergies are shared with the household only so shared meals stay safe.',
          style: context.text.bodyMedium,
        ),
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
    final s = ref.watch(settingsProvider).value ?? const AppSettings();
    final consents = ref.watch(consentsProvider).value ?? const <ConsentRecord>[];
    final uid = ref.watch(uidProvider);
    Future<void> save(AppSettings n, {String? consentPurpose, bool? granted}) async {
      await ref.read(profileRepoProvider).saveSettings(uid!, n);
      if (consentPurpose != null) await ref.read(profileRepoProvider).recordConsent(uid, purpose: consentPurpose, granted: granted!);
      ref.read(analyticsProvider).enabled = n.analyticsConsent;
    }

    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Privacy', title: 'Your data, your choice', subtitle: 'Chefii never sells your data or uses your health records for advertising.'),
      children: [
        ToggleTile(
          icon: Icons.auto_awesome_outlined,
          title: 'AI processing',
          subtitle: 'Send receipt and fridge photos, and chef requests, to our AI providers (Google Gemini; OpenAI if enabled below) through our secure servers. Providers may not train on your data under our agreements.',
          value: s.aiProcessingConsent,
          onChanged: (v) => save(s.copyWith(aiProcessingConsent: v), consentPurpose: 'ai_processing', granted: v),
        ),
        ToggleTile(
          icon: Icons.chat_outlined,
          title: 'Optional second AI provider',
          subtitle: 'Allow OpenAI for conversation and recipe writing. Off means Gemini only.',
          value: s.allowOptionalAiProvider,
          onChanged: s.aiProcessingConsent ? (v) => save(s.copyWith(allowOptionalAiProvider: v), consentPurpose: 'ai_optional_provider', granted: v) : null,
        ),
        ToggleTile(
          icon: Icons.query_stats,
          title: 'Product analytics',
          subtitle: 'Anonymous usage events (e.g. "receipt imported"). Never food names, health data or free text.',
          value: s.analyticsConsent,
          onChanged: (v) => save(s.copyWith(analyticsConsent: v), consentPurpose: 'analytics', granted: v),
        ),
        const SizedBox(height: Space.s),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.group_outlined), title: const Text('Professional sharing'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/circle')),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.download_outlined), title: const Text('Export or delete your data'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/data')),
        const SectionHeader('Consent history'),
        if (consents.isEmpty) Text('No consents recorded.', style: context.text.bodySmall),
        for (final c in consents.take(20))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(c.granted ? Icons.check_circle_outline : Icons.cancel_outlined, size: 20),
            title: Text('${c.purpose} · ${c.granted ? 'granted' : 'withdrawn'}'),
            subtitle: Text('${formatDay(context, c.recordedAt)} · version ${c.version}'),
          ),
        const SizedBox(height: Space.m),
        Text('Data is stored in Canada (Google Cloud, Montréal region) where supported. See the Privacy Policy for details.', style: context.text.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- 74 Connected services

class ConnectedServicesScreen extends ConsumerWidget {
  const ConnectedServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(aiGatewayProvider);
    final config = ref.watch(appConfigProvider);
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Services', title: 'Connected services'),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('For reminders, timers and your morning alarm'),
            trailing: TextButton(
              onPressed: () async {
                final ok = await ref.read(notificationServiceProvider).requestPermission();
                if (context.mounted) showMessage(context, ok ? 'Notifications are on' : 'Notifications are off — you can change this in system Settings.');
              },
              child: const Text('Check'),
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Kitchen AI'),
            subtitle: Text(ai.isDemo ? 'Demo mode — sample results, no AI provider connected' : 'Connected through Chefii\'s secure servers'),
          ),
        ),
        const SizedBox(height: Space.xs),
        const Card(
          child: ListTile(
            leading: Icon(Icons.favorite_border),
            title: Text('Apple Health / Health Connect'),
            subtitle: Text('Coming later: read-only glucose import with clear provenance. Not available yet.'),
          ),
        ),
        const SizedBox(height: Space.xs),
        Card(
          child: ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Professionals'),
            subtitle: const Text('Manage who can see your records'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/you/circle'),
          ),
        ),
        const SizedBox(height: Space.m),
        Text('Backend: ${config.isDemo ? 'local demo storage on this device' : 'Firebase${config.useEmulators ? ' (emulators)' : ''}'}', style: context.text.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- 75 Subscription & membership

class MembershipScreen extends StatelessWidget {
  const MembershipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Membership', title: 'Early access', subtitle: 'Every Chefii feature is included while we\'re in early access.'),
      children: [
        SoftCard(
          color: context.palette.accentSoft,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Chefii Membership', style: context.text.headlineSmall),
            const SizedBox(height: Space.xs),
            Text('Paid plans aren\'t available yet. When they launch, you\'ll be told the price in advance and nothing will be charged without your confirmation through the App Store or Google Play.', style: context.text.bodyMedium),
          ]),
        ),
        const SectionHeader('Included now'),
        for (final f in ['Receipt and fridge scanning', 'AI chef and guided cooking', 'Meal planning and smart shopping', 'Nutrition journal and insights', 'Sharing with your nutrition circle'])
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check), title: Text(f)),
        const SizedBox(height: Space.m),
        Text('Receipts and billing history will appear here once memberships launch.', style: context.text.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- 76 Accessibility & language

class AccessibilityScreen extends ConsumerWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const AppSettings();
    Future<void> save(AppSettings n) => ref.read(profileRepoProvider).saveSettings(ref.read(uidProvider)!, n);
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Settings', title: 'Accessibility & language'),
      children: [
        Text('Text size', style: context.text.titleMedium),
        Semantics(label: 'Text size', child: Slider(
          value: s.textScale,
          min: 0.9,
          max: 1.6,
          divisions: 7,
          label: '${(s.textScale * 100).round()}%',
          semanticFormatterCallback: (v) => '${(v * 100).round()} percent',
          onChanged: (v) => save(s.copyWith(textScale: v)),
        )),
        Text('Preview: Simmer gently until the lentils collapse.', style: context.text.bodyLarge),
        Text('Chefii also follows your device\'s text size.', style: context.text.bodySmall),
        const SizedBox(height: Space.m),
        ToggleTile(icon: Icons.motion_photos_off_outlined, title: 'Reduce motion', subtitle: 'Fewer animations and transitions', value: s.reduceMotion, onChanged: (v) => save(s.copyWith(reduceMotion: v))),
        ToggleTile(icon: Icons.record_voice_over_outlined, title: 'Read cooking steps aloud', subtitle: 'In guided cooking', value: s.voiceGuidance, onChanged: (v) => save(s.copyWith(voiceGuidance: v))),
        const SectionHeader('Language'),
        RadioGroup<String>(
          groupValue: s.language,
          onChanged: (v) => v == null ? null : save(s.copyWith(language: v)),
          child: const Column(children: [
            RadioListTile(value: 'system', title: Text('Same as my device')),
            // Language names are always shown in their own language.
            RadioListTile(value: 'en-CA', title: Text('English (Canada)')),
            RadioListTile(value: 'fr-CA', title: Text('Français (Canada)')),
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
    final user = ref.watch(authUserProvider).value;
    final isDemo = ref.watch(appConfigProvider).isDemo;
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Settings', title: 'Security & sessions'),
      children: [
        Card(child: ListTile(leading: const Icon(Icons.person_outline), title: Text(user?.email ?? (isDemo ? 'Demo account' : 'Signed in')), subtitle: Text(isDemo ? 'Stored only on this device' : 'Account ID ${user?.uid.substring(0, 6)}…'))),
        const SizedBox(height: Space.xs),
        if (!isDemo && user?.email != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Reset password'),
              onTap: () async {
                await ref.read(authServiceProvider).sendPasswordReset(user!.email!);
                if (context.mounted) showMessage(context, 'Password reset email sent');
              },
            ),
          ),
        if (!isDemo)
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices_other),
              title: const Text('Sign out of all devices'),
              subtitle: const Text('Ends every session, including this one'),
              onTap: () async {
                final ok = await showConfirmActionSheet(context, title: 'Sign out everywhere?', message: 'You\'ll need to sign in again on each device.', confirmLabel: 'Sign out everywhere', destructive: true);
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
        Text('Sensitive actions such as deleting your account or exporting health data ask you to confirm your identity again.', style: context.text.bodySmall),
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

  static const faqs = [
    ('How accurate is my kitchen?', 'Items from receipts you reviewed are confirmed. Amounts after cooking are deducted from what you confirm. Anything estimated is labelled, and Chefii occasionally asks you to verify.'),
    ('What if I use something without telling Chefii?', 'Use the "I used…" button or tap − on an item. If counts drift, Quick check lets you fix several items in seconds.'),
    ('Are freshness dates safe to rely on?', 'No — they\'re estimates from typical storage times. Always follow the package date and your own judgement.'),
    ('Does Chefii give medical advice?', 'No. Nutrition features are education. For personal advice, share your records with a registered dietitian in My nutrition circle.'),
    ('Who can see my health data?', 'Only you, plus any professional you explicitly share with, for the time you choose. Household members never see your journal or health records.'),
  ];

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Help', title: 'How can we help?'),
      primaryAction: PrimaryActionButton(
        label: 'Send',
        onPressed: () async {
          if (_msg.text.trim().isEmpty) return;
          await ref.read(profileRepoProvider).submitFeedback(ref.read(uidProvider)!, kind: _kind, message: _msg.text.trim());
          _msg.clear();
          if (context.mounted) showMessage(context, 'Thank you — we read every message.');
        },
      ),
      children: [
        for (final (q, a) in faqs) ExpansionTile(tilePadding: EdgeInsets.zero, title: Text(q), children: [Padding(padding: const EdgeInsets.only(bottom: Space.m), child: Text(a))]),
        const SectionHeader('Write to us'),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'feedback', label: Text('Feedback')), ButtonSegment(value: 'bug', label: Text('Report a problem'))],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: Space.s),
        TextField(controller: _msg, minLines: 4, maxLines: 8, decoration: const InputDecoration(hintText: 'Tell us what happened or what you\'d love to see. Please don\'t include health details.')),
        TextButton.icon(
          icon: const Icon(Icons.mail_outline),
          label: const Text('Email support'),
          onPressed: () => launchUrl(Uri(scheme: 'mailto', path: supportEmail, query: 'subject=Chefii support')),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 79 Legal & evidence disclosures

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  static const sections = [
    ('Terms of Service (summary)', 'Chefii is provided for household kitchen organisation, cooking guidance and general nutrition education. You\'re responsible for food safety decisions in your home. Full terms will be published before public launch and require legal review.'),
    ('Privacy Policy (summary)', 'We collect what you enter or scan to run Chefii: kitchen items, receipts, recipes, meal records, and optional health information you choose to add. We process data in Canada where possible, use AI providers only with your consent and under data-processing agreements, never sell personal information, and let you export or delete your data at any time. Prepared to meet PIPEDA and applicable provincial health privacy laws; full policy subject to legal review.'),
    ('Medical limitations', 'Chefii does not diagnose, treat, cure or prevent any disease, and is not a medical device. Nutrition values are estimates. Glucose features are a personal journal and do not replace medical devices, alarms or your care team. Allergy screening relies on ingredient names and labels you check; it cannot guarantee a food is free of an allergen.'),
    ('Food safety', 'Freshness indicators are estimates based on typical storage times. Always follow package dates, safe storage temperatures and safe internal cooking temperatures.'),
    ('Evidence methodology', 'Nutrition statements come from national guidelines and authoritative references. Each shows its sources, evidence strength, limitations and review status. AI may rephrase approved statements but may not create new health claims.'),
    ('AI disclosure', 'Recipes marked "Created by your AI chef", receipt readings and photo suggestions are generated by AI and may contain mistakes. Illustrations are not photographs of your food.'),
  ];

  @override
  Widget build(BuildContext context) {
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Legal', title: 'Legal & disclosures'),
      children: [
        for (final (t, b) in sections) ExpansionTile(tilePadding: EdgeInsets.zero, title: Text(t), children: [Padding(padding: const EdgeInsets.only(bottom: Space.m), child: Text(b))]),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Evidence library'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/nutrition/evidence')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Open-source licences'),
          subtitle: const Text('Including Cormorant Garamond and Inter (SIL Open Font License)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(context: context, applicationName: 'Chefii'),
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

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).reauthenticate(password: _password.text.isEmpty ? null : _password.text);
      final uid = ref.read(uidProvider)!;
      final json = await DataExportService(ref.read(docStoreProvider)).toJson(uid, householdId: ref.read(householdIdProvider));
      await ref.read(profileRepoProvider).audit(uid, action: 'export.created', target: uid);
      final file = XFile.fromData(Uint8List.fromList(utf8.encode(json)), mimeType: 'application/json', name: 'chefii-export.json');
      await SharePlus.instance.share(ShareParams(files: [file], subject: 'Your Chefii data'));
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, ErrorState.describe(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_confirm.text.trim().toUpperCase() != 'DELETE') return;
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
    final isDemo = ref.watch(appConfigProvider).isDemo;
    final hasPassword = !isDemo && (ref.watch(authUserProvider).value?.email != null);
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Your data', title: 'Export or delete'),
      children: [
        Text('Export', style: context.text.titleMedium),
        const SizedBox(height: Space.xs),
        Text('A complete copy of your profile, kitchen, journal, health records, consents and sharing history as a JSON file.', style: context.text.bodyMedium),
        if (hasPassword) ...[
          const SizedBox(height: Space.s),
          TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password (to confirm it\'s you)')),
        ],
        const SizedBox(height: Space.s),
        SecondaryActionButton(icon: Icons.download_outlined, label: 'Export my data', onPressed: _busy ? null : _export),
        const SectionHeader('Delete account'),
        Text(
          'Permanently deletes your account, journal, health records and sharing grants. If you\'re the only member of your household, its kitchen is deleted too. '
          'Some records may be kept where the law requires (for example, purchase receipts for membership billing). This can\'t be undone.',
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: Space.s),
        TextField(controller: _confirm, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Type DELETE to confirm')),
        const SizedBox(height: Space.s),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.palette.error, foregroundColor: Colors.white),
            onPressed: _busy || _confirm.text.trim().toUpperCase() != 'DELETE' ? null : _delete,
            child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Delete my account'),
          ),
        ),
      ],
    );
  }
}

/// Re-exported for account screens.
bool hasConsent(List<ConsentRecord> c, String p) => ProfileRepository.hasConsent(c, p);
