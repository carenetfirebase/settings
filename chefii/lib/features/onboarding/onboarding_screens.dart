import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/actions.dart';
import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../core/services/analytics.dart';
import '../../data/auth/auth_service.dart';
import '../../domain/models/profile.dart';
import '../../domain/recipes/curated_recipes.dart';
import '../../domain/safety/allergen_guard.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

const termsVersion = '2026-10';

/// Shared frame: progress, title, content, one primary action, optional skip.
class OnboardingFrame extends StatelessWidget {
  const OnboardingFrame({
    super.key,
    required this.step,
    required this.title,
    this.subtitle,
    required this.children,
    required this.primaryLabel,
    required this.onPrimary,
    this.loading = false,
    this.onSkip,
    this.skipLabel,
  });

  final int step;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool loading;
  final VoidCallback? onSkip;
  final String? skipLabel;

  static const total = 7;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final stepLabel = l.onboardingStepOf(step, total);
    return PremiumAppScaffold(
      actions: [if (onSkip != null) TextButton(onPressed: onSkip, child: Text(skipLabel ?? l.onboardingSkipForNow))],
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: stepLabel,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: step / total, minHeight: 4),
            ),
          ),
          const SizedBox(height: Space.l),
          EditorialPageHeader(eyebrow: stepLabel, title: title, subtitle: subtitle),
        ],
      ),
      primaryAction: PrimaryActionButton(label: primaryLabel, onPressed: onPrimary, loading: loading),
      children: children,
    );
  }
}

// ---------------------------------------------------------------- 01 Welcome

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(Space.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Space.l),
                    Text('CHEFII', style: context.text.labelSmall?.copyWith(color: p.accent, letterSpacing: 4)), // l10n-ignore
                    const SizedBox(height: Space.l),
                    FoodArtwork(artKey: 'herb', height: 280, radius: Radii.xl, label: l.onboardingWelcomeArtLabel),
                    const SizedBox(height: Space.xl),
                    Semantics(header: true, child: Text(l.onboardingWelcomeTitle, style: context.text.displayMedium)),
                    const SizedBox(height: Space.m),
                    Text(
                      l.onboardingWelcomeBody,
                      style: context.text.bodyLarge?.copyWith(color: p.muted),
                    ),
                    const SizedBox(height: Space.xxl),
                    PrimaryActionButton(label: l.onboardingGetStarted, onPressed: () => context.go('/onboarding/meet')),
                    const SizedBox(height: Space.s),
                    SecondaryActionButton(label: l.onboardingHaveAccount, onPressed: () => context.go('/onboarding/account?mode=signin')),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------- 02 Meet your chef

class MeetChefScreen extends StatelessWidget {
  const MeetChefScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sample = curatedById['lemon-herb-salmon']!;
    Widget benefit(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: context.colors.primary),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: context.text.titleMedium),
                  Text(body, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                ]),
              ),
            ],
          ),
        );
    final l = context.l10n;
    return OnboardingFrame(
      step: 1,
      title: l.onboardingMeetTitle,
      subtitle: l.onboardingMeetSubtitle,
      onSkip: () => context.go('/onboarding/account'),
      skipLabel: l.onboardingSkip,
      primaryLabel: l.commonContinue,
      onPrimary: () => context.go('/onboarding/account'),
      children: [
        benefit(Icons.kitchen_outlined, l.onboardingBenefitKitchenTitle, l.onboardingBenefitKitchenBody),
        benefit(Icons.restaurant_menu, l.onboardingBenefitDecideTitle, l.onboardingBenefitDecideBody),
        benefit(Icons.self_improvement, l.onboardingBenefitGuideTitle, l.onboardingBenefitGuideBody),
        SectionHeader(l.onboardingTasteHeader),
        LuxuryRecipeCard(recipe: sample, availabilityLabel: l.onboardingExample, compact: true),
      ],
    );
  }
}

// ---------------------------------------------------------------- 03 Account

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key, this.signInMode = false});
  final bool signInMode;

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late bool _signIn = widget.signInMode;
  bool _consent = false;
  bool _busy = false;
  String? _error;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AppUser> Function() f) async {
    if (!_signIn && !_consent) {
      setState(() => _error = context.l10n.onboardingConsentRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final defaultName = context.l10n.onboardingDefaultName;
    try {
      final user = await f();
      final profiles = ref.read(profileRepoProvider);
      final profile = await profiles.ensureProfile(
        uid: user.uid,
        displayName: user.displayName ?? (_name.text.trim().isEmpty ? defaultName : _name.text.trim()),
        email: user.email,
      );
      if (!_signIn || profile.termsAcceptedVersion == null) {
        await profiles.recordConsent(user.uid, purpose: 'terms', granted: true, version: termsVersion);
        await profiles.recordConsent(user.uid, purpose: 'privacy', granted: true, version: termsVersion);
        await profiles.updateProfileFields(user.uid, {'termsAcceptedVersion': termsVersion});
      }
      ref.read(analyticsProvider).log(AnalyticsEvents.onboardingStep, {'step': 3});
      // The router redirects based on onboarding state.
      if (mounted) context.go(profile.onboardingComplete ? '/today' : '/onboarding/household');
    } on AuthException catch (e) {
      if (!e.cancelled && mounted) setState(() => _error = ErrorState.describeIn(context, e));
    } catch (e) {
      if (mounted) setState(() => _error = ErrorState.describeIn(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);
    final methods = auth.availableMethods;
    final isDemo = ref.watch(appConfigProvider).isDemo;
    final l = context.l10n;
    return OnboardingFrame(
      step: 2,
      title: _signIn ? l.onboardingWelcomeBack : l.onboardingCreateTitle,
      subtitle: _signIn ? l.onboardingSignInSubtitle : l.onboardingCreateSubtitle,
      primaryLabel: _signIn ? l.onboardingSignIn : l.onboardingCreateAccount,
      loading: _busy,
      onPrimary: () {
        if (!(_form.currentState?.validate() ?? false)) return;
        _run(() => _signIn
            ? auth.signInWithEmail(_email.text, _password.text)
            : auth.createAccountWithEmail(_email.text, _password.text, _name.text));
      },
      children: [
        if (isDemo) ...[
          DemoBanner(message: l.onboardingDemoBanner),
          SecondaryActionButton(
            icon: Icons.play_circle_outline,
            label: l.onboardingDemoAccount,
            onPressed: _busy
                ? null
                : () => _run(() => (auth as DemoAuthService).signInDemo(_name.text.trim().isEmpty ? 'Alex' : _name.text.trim())), // l10n-ignore: demo person name
          ),
          const SizedBox(height: Space.m),
        ],
        if (methods.contains(AuthMethod.apple)) ...[
          SecondaryActionButton(icon: Icons.apple, label: l.onboardingContinueApple, onPressed: _busy ? null : () => _run(auth.signInWithApple)),
          const SizedBox(height: Space.xs),
        ],
        if (methods.contains(AuthMethod.google)) ...[
          SecondaryActionButton(icon: Icons.g_mobiledata, label: l.onboardingContinueGoogle, onPressed: _busy ? null : () => _run(auth.signInWithGoogle)),
          const SizedBox(height: Space.m),
        ],
        Row(children: [
          const Expanded(child: Divider()),
          Padding(padding: const EdgeInsets.symmetric(horizontal: Space.s), child: Text(l.onboardingOrEmail, style: context.text.bodySmall)),
          const Expanded(child: Divider()),
        ]),
        const SizedBox(height: Space.m),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(children: [
              if (!_signIn) ...[
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.givenName],
                  decoration: InputDecoration(labelText: l.onboardingFirstNameLabel),
                  validator: (v) => (v ?? '').trim().isEmpty ? l.onboardingFirstNameError : null,
                ),
                const SizedBox(height: Space.s),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(labelText: l.onboardingEmailLabel),
                validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : l.onboardingEmailError,
              ),
              const SizedBox(height: Space.s),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: [_signIn ? AutofillHints.password : AutofillHints.newPassword],
                decoration: InputDecoration(labelText: l.onboardingPasswordLabel),
                validator: (v) => (v ?? '').length < 8 ? l.onboardingPasswordError : null,
              ),
            ]),
          ),
        ),
        if (_signIn)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                if (_email.text.trim().isEmpty) {
                  setState(() => _error = l.onboardingEnterEmailFirst);
                  return;
                }
                await auth.sendPasswordReset(_email.text);
                if (context.mounted) showMessage(context, l.onboardingResetSent);
              },
              child: Text(l.onboardingForgotPassword),
            ),
          ),
        if (!_signIn) ...[
          const SizedBox(height: Space.m),
          CheckboxListTile(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(l.onboardingConsentLabel, style: context.text.bodyMedium),
            subtitle: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              onPressed: () => context.push('/you/legal'),
              child: Text(l.onboardingReadThem),
            ),
          ),
        ],
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text(_error!, style: context.text.bodyMedium?.copyWith(color: context.palette.error)),
            ),
          ),
        const SizedBox(height: Space.m),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _signIn = !_signIn;
              _error = null;
            }),
            child: Text(_signIn ? l.onboardingSwitchToCreate : l.onboardingSwitchToSignIn),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 04 Household

class HouseholdSetupScreen extends ConsumerStatefulWidget {
  const HouseholdSetupScreen({super.key});

  @override
  ConsumerState<HouseholdSetupScreen> createState() => _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends ConsumerState<HouseholdSetupScreen> {
  HouseholdType _type = HouseholdType.couple;
  int _portions = 2;
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final profile = ref.read(profileProvider).value;
    final uid = ref.read(uidProvider);
    if (uid == null || profile == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(householdRepoProvider);
      final name = _name.text.trim().isEmpty ? context.l10n.onboardingDefaultHouseholdName(profile.firstName) : _name.text.trim();
      if (profile.householdId == null) {
        await repo.createHousehold(uid: uid, ownerName: profile.displayName, name: name, type: _type, portions: _portions);
      } else {
        final h = ref.read(householdProvider).value;
        if (h != null) await repo.updateHousehold(h.copyWith(name: name, type: _type, portions: _portions));
      }
      await ref.read(profileRepoProvider).updateProfileFields(uid, {'onboardingStep': 4});
      ref.read(analyticsProvider).log(AnalyticsEvents.onboardingStep, {'step': 4});
      if (mounted) context.go('/onboarding/dietary');
    } catch (e) {
      if (mounted) showMessage(context, ErrorState.describeIn(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final c = TextEditingController();
    final l = context.l10n;
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.onboardingInviteCodeTitle),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(hintText: l.onboardingInviteCodeHint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(l.onboardingJoin)),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    if (ref.read(appConfigProvider).isDemo) {
      showMessage(context, l.onboardingJoinNeedsOnline);
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'northamerica-northeast1').httpsCallable('acceptHouseholdInvite').call<Map<String, dynamic>>({'code': code});
      final uid = ref.read(uidProvider)!;
      await ref.read(profileRepoProvider).updateProfileFields(uid, {'onboardingStep': 4});
      if (mounted) context.go('/onboarding/dietary');
    } on FirebaseFunctionsException catch (e) {
      if (mounted) showMessage(context, ErrorState.describeIn(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return OnboardingFrame(
      step: 3,
      title: l.onboardingHouseholdTitle,
      subtitle: l.onboardingHouseholdSubtitle,
      primaryLabel: l.commonContinue,
      loading: _busy,
      onPrimary: _save,
      children: [
        for (final t in HouseholdType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: SoftCard(
              color: _type == t ? context.palette.surfaceSoft : null,
              onTap: () => setState(() {
                _type = t;
                _portions = switch (t) { HouseholdType.single => 1, HouseholdType.couple => 2, HouseholdType.family => 4 };
              }),
              semanticLabel: _type == t ? l.onboardingOptionSelected(context.labelOf(t)) : context.labelOf(t),
              child: Row(children: [
                Icon(switch (t) { HouseholdType.single => Icons.person_outline, HouseholdType.couple => Icons.people_outline, HouseholdType.family => Icons.family_restroom }),
                const SizedBox(width: Space.m),
                Expanded(child: Text(context.labelOf(t), style: context.text.titleMedium)),
                if (_type == t) Icon(Icons.check_circle, color: context.colors.primary),
              ]),
            ),
          ),
        const SizedBox(height: Space.l),
        Text(l.onboardingPortionsTitle, style: context.text.titleMedium),
        const SizedBox(height: Space.xs),
        Row(children: [
          IconButton.filledTonal(tooltip: l.onboardingFewerPortions, onPressed: _portions > 1 ? () => setState(() => _portions--) : null, icon: const Icon(Icons.remove)),
          SizedBox(width: 56, child: Text('$_portions', textAlign: TextAlign.center, style: context.text.headlineMedium)), // l10n-ignore: number
          IconButton.filledTonal(tooltip: l.onboardingMorePortions, onPressed: _portions < 12 ? () => setState(() => _portions++) : null, icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: Space.l),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: l.onboardingHouseholdNameLabel, hintText: l.onboardingHouseholdNameHint)),
        const SizedBox(height: Space.m),
        Text(l.onboardingHouseholdPrivacy, style: context.text.bodySmall),
        const SizedBox(height: Space.s),
        TextButton.icon(icon: const Icon(Icons.vpn_key_outlined), label: Text(l.onboardingJoinWithCode), onPressed: _join),
      ],
    );
  }
}

// ---------------------------------------------------------------- 05 Dietary safety

class DietarySafetyScreen extends ConsumerStatefulWidget {
  const DietarySafetyScreen({super.key, this.editing = false});
  final bool editing;

  @override
  ConsumerState<DietarySafetyScreen> createState() => _DietarySafetyScreenState();
}

class _DietarySafetyScreenState extends ConsumerState<DietarySafetyScreen> {
  DietaryProfile? _p;
  final _dislike = TextEditingController();
  bool _busy = false;

  static const _allergenKeys = ['peanut', 'tree_nut', 'sesame', 'milk', 'egg', 'fish', 'shellfish', 'soy', 'wheat', 'mustard', 'sulphites'];

  @override
  void dispose() {
    _dislike.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uid = ref.read(uidProvider);
    final p = _p;
    if (uid == null || p == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(profileRepoProvider).saveDietary(uid, p);
      final hid = ref.read(householdIdProvider);
      if (hid != null) await ref.read(householdRepoProvider).setSharedAllergens(hid, uid, p.allergies);
      if (!widget.editing) {
        await ref.read(profileRepoProvider).updateProfileFields(uid, {'onboardingStep': 5});
        ref.read(analyticsProvider).log(AnalyticsEvents.onboardingStep, {'step': 5});
      }
      if (!mounted) return;
      widget.editing ? context.pop() : context.go('/onboarding/culinary');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(dietaryProvider).value;
    final p = _p ??= loaded;
    if (p == null) return const Scaffold(body: LoadingState());
    void set(DietaryProfile n) => setState(() => _p = n);
    final l = context.l10n;

    final content = [
      Text(l.onboardingAllergyQuestion, style: context.text.titleMedium),
      const SizedBox(height: Space.xs),
      Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
        for (final s in [DisclosureStatus.provided, DisclosureStatus.noneKnown, DisclosureStatus.preferNotToSay])
          ChoiceChip(
            label: Text(switch (s) { DisclosureStatus.provided => l.commonYes, DisclosureStatus.noneKnown => l.onboardingAllergyNoneKnown, _ => l.onboardingAllergyPreferNot }),
            selected: p.allergyStatus == s,
            onSelected: (_) => set(p.copyWith(allergyStatus: s, allergies: s == DisclosureStatus.provided ? p.allergies : const [])),
          ),
      ]),
      if (p.allergyStatus == DisclosureStatus.provided) ...[
        const SizedBox(height: Space.m),
        ChoiceChipGroup(
          options: _allergenKeys,
          labelOf: context.allergenLabel,
          selected: p.allergies.toSet(),
          onChanged: (s) => set(p.copyWith(allergies: s.toList())),
        ),
        const SizedBox(height: Space.s),
        ToggleTile(
          title: l.onboardingCrossContactTitle,
          subtitle: l.onboardingCrossContactSubtitle,
          value: p.avoidCrossContact,
          onChanged: (v) => set(p.copyWith(avoidCrossContact: v)),
        ),
      ],
      if (p.allergyStatus == DisclosureStatus.preferNotToSay || p.allergyStatus == DisclosureStatus.notAsked)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Text(l.onboardingNoAllergyAssumption, style: context.text.bodySmall),
        ),
      SectionHeader(l.onboardingIntolerances),
      ChoiceChipGroup(
        options: intoleranceLabels.keys.toList(),
        labelOf: context.intoleranceLabel,
        selected: p.intolerances.toSet(),
        onChanged: (s) => set(p.copyWith(intolerances: s.toList())),
      ),
      SectionHeader(l.onboardingDietaryPattern),
      ChoiceChipGroup(
        options: restrictions.map((r) => r.key).toList(),
        labelOf: context.restrictionLabel,
        selected: p.restrictions.toSet(),
        onChanged: (s) => set(p.copyWith(restrictions: s.toList())),
      ),
      SectionHeader(l.onboardingDislikes),
      Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
        for (final d in p.dislikes) InputChip(label: Text(d), onDeleted: () => set(p.copyWith(dislikes: [...p.dislikes]..remove(d)))),
      ]),
      const SizedBox(height: Space.xs),
      TextField(
        controller: _dislike,
        decoration: InputDecoration(
          labelText: l.onboardingAddFoodLabel,
          suffixIcon: IconButton(
            tooltip: l.onboardingAdd,
            icon: const Icon(Icons.add),
            onPressed: () {
              final v = _dislike.text.trim();
              if (v.isEmpty) return;
              set(p.copyWith(dislikes: {...p.dislikes, v.toLowerCase()}.toList()));
              _dislike.clear();
            },
          ),
        ),
        onSubmitted: (v) {
          if (v.trim().isEmpty) return;
          set(p.copyWith(dislikes: {...p.dislikes, v.trim().toLowerCase()}.toList()));
          _dislike.clear();
        },
      ),
      const SizedBox(height: Space.l),
      Card(
        color: context.palette.infoSoft,
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Text(
            l.onboardingDietaryNotice,
            style: context.text.bodySmall?.copyWith(color: context.palette.ink),
          ),
        ),
      ),
    ];

    if (widget.editing) {
      return PremiumAppScaffold(
        header: EditorialPageHeader(title: l.onboardingDietaryTitle, subtitle: l.onboardingDietaryEditSubtitle),
        primaryAction: PrimaryActionButton(label: l.commonSave, onPressed: _save, loading: _busy),
        children: content,
      );
    }
    return OnboardingFrame(
      step: 4,
      title: l.onboardingDietaryTitle,
      subtitle: l.onboardingDietarySubtitle,
      primaryLabel: l.commonContinue,
      loading: _busy,
      onPrimary: p.allergyStatus == DisclosureStatus.notAsked ? null : _save,
      children: content,
    );
  }
}

// ---------------------------------------------------------------- 06 Culinary

class CulinaryPreferencesScreen extends ConsumerStatefulWidget {
  const CulinaryPreferencesScreen({super.key, this.editing = false});
  final bool editing;

  @override
  ConsumerState<CulinaryPreferencesScreen> createState() => _CulinaryPreferencesScreenState();
}

class _CulinaryPreferencesScreenState extends ConsumerState<CulinaryPreferencesScreen> {
  CulinaryPreferences? _c;
  bool _busy = false;

  // Stored values (saved to the profile in English); shown via _optionLabel.
  static const cuisines = ['Italian', 'French', 'Mediterranean', 'Middle Eastern', 'Indian', 'Japanese', 'Chinese', 'Thai', 'Korean', 'Mexican', 'Greek', 'Nordic', 'Canadian']; // l10n-ignore: stored keys
  static const foods = ['Salmon', 'Chicken', 'Pasta', 'Eggs', 'Tofu', 'Lentils', 'Vegetables', 'Salads', 'Soups', 'Rice bowls', 'Baking']; // l10n-ignore: stored keys
  static const equipment = ['Oven', 'Stovetop', 'Air fryer', 'Slow cooker', 'Instant Pot', 'Blender', 'Microwave', 'Grill']; // l10n-ignore: stored keys

  static List<String> spiceLabels(AppLocalizations l) =>
      [l.onboardingSpiceNone, l.onboardingSpiceMild, l.onboardingSpiceMedium, l.onboardingSpiceWarm, l.onboardingSpiceHot];

  /// Translated label for a stored cuisine / food / equipment value; values
  /// not in the lists (older or custom data) are shown as stored.
  static String _optionLabel(AppLocalizations l, String v) => switch (v) {
        'Italian' => l.onboardingCuisineItalian,
        'French' => l.onboardingCuisineFrench,
        'Mediterranean' => l.onboardingCuisineMediterranean,
        'Middle Eastern' => l.onboardingCuisineMiddleEastern,
        'Indian' => l.onboardingCuisineIndian,
        'Japanese' => l.onboardingCuisineJapanese,
        'Chinese' => l.onboardingCuisineChinese,
        'Thai' => l.onboardingCuisineThai,
        'Korean' => l.onboardingCuisineKorean,
        'Mexican' => l.onboardingCuisineMexican,
        'Greek' => l.onboardingCuisineGreek,
        'Nordic' => l.onboardingCuisineNordic,
        'Canadian' => l.onboardingCuisineCanadian,
        'Salmon' => l.onboardingFoodSalmon,
        'Chicken' => l.onboardingFoodChicken,
        'Pasta' => l.onboardingFoodPasta,
        'Eggs' => l.onboardingFoodEggs,
        'Tofu' => l.onboardingFoodTofu,
        'Lentils' => l.onboardingFoodLentils,
        'Vegetables' => l.onboardingFoodVegetables,
        'Salads' => l.onboardingFoodSalads,
        'Soups' => l.onboardingFoodSoups,
        'Rice bowls' => l.onboardingFoodRiceBowls,
        'Baking' => l.onboardingFoodBaking,
        'Oven' => l.onboardingEquipmentOven,
        'Stovetop' => l.onboardingEquipmentStovetop,
        'Air fryer' => l.onboardingEquipmentAirFryer,
        'Slow cooker' => l.onboardingEquipmentSlowCooker,
        'Instant Pot' => l.onboardingEquipmentInstantPot,
        'Blender' => l.onboardingEquipmentBlender,
        'Microwave' => l.onboardingEquipmentMicrowave,
        'Grill' => l.onboardingEquipmentGrill,
        _ => v,
      };

  Future<void> _save() async {
    final uid = ref.read(uidProvider);
    final profile = ref.read(profileProvider).value;
    if (uid == null || profile == null || _c == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(profileRepoProvider).saveProfile(profile.copyWith(culinary: _c, onboardingStep: widget.editing ? null : 6));
      ref.read(analyticsProvider).log(AnalyticsEvents.onboardingStep, {'step': 6});
      if (!mounted) return;
      widget.editing ? context.pop() : context.go('/onboarding/wellness');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final c = _c ??= profile?.culinary;
    if (c == null) return const Scaffold(body: LoadingState());
    void set(CulinaryPreferences n) => setState(() => _c = n);
    final l = context.l10n;
    final spice = spiceLabels(l);
    String optionLabel(String v) => _optionLabel(l, v);
    final content = [
      Text(l.onboardingCuisinesTitle, style: context.text.titleMedium),
      const SizedBox(height: Space.xs),
      ChoiceChipGroup(options: cuisines, labelOf: optionLabel, selected: c.cuisines.toSet(), onChanged: (s) => set(c.copyWith(cuisines: s.toList()))),
      SectionHeader(l.onboardingFavouriteFoods),
      ChoiceChipGroup(options: foods, labelOf: optionLabel, selected: c.favouriteFoods.toSet(), onChanged: (s) => set(c.copyWith(favouriteFoods: s.toList()))),
      SectionHeader(l.onboardingCookingConfidence),
      ChoiceChipGroup(
        single: true,
        options: CookingConfidence.values.map((e) => e.name).toList(),
        labelOf: (n) => context.labelOf(CookingConfidence.values.byName(n)),
        selected: {c.confidence.name},
        onChanged: (s) => s.isEmpty ? null : set(c.copyWith(confidence: CookingConfidence.values.byName(s.first))),
      ),
      SectionHeader(l.onboardingSpice),
      Semantics(label: l.onboardingSpiceLevel, child: Slider(
        value: c.spiceLevel.toDouble(),
        max: 4,
        divisions: 4,
        label: spice[c.spiceLevel],
        semanticFormatterCallback: (v) => spice[v.round()],
        onChanged: (v) => set(c.copyWith(spiceLevel: v.round())),
      )),
      Text(l.onboardingSpiceValue(spice[c.spiceLevel]), style: context.text.bodySmall),
      SectionHeader(l.onboardingWeeknightTime),
      ChoiceChipGroup(
        single: true,
        options: const ['15', '20', '30', '45', '60'],
        labelOf: (m) => formatMinutes(int.parse(m)),
        selected: {'${c.weeknightMinutes}'},
        onChanged: (s) => s.isEmpty ? null : set(c.copyWith(weeknightMinutes: int.parse(s.first))),
      ),
      SectionHeader(l.onboardingYourEquipment),
      ChoiceChipGroup(options: equipment, labelOf: optionLabel, selected: c.equipment.toSet(), onChanged: (s) => set(c.copyWith(equipment: s.toList()))),
    ];
    if (widget.editing) {
      return PremiumAppScaffold(
        header: EditorialPageHeader(title: l.onboardingCulinaryEditTitle),
        primaryAction: PrimaryActionButton(label: l.commonSave, onPressed: _save, loading: _busy),
        children: content,
      );
    }
    return OnboardingFrame(
      step: 5,
      title: l.onboardingCulinaryTitle,
      subtitle: l.onboardingCulinarySubtitle,
      primaryLabel: l.commonContinue,
      loading: _busy,
      onPrimary: _save,
      onSkip: () => context.go('/onboarding/wellness'),
      children: content,
    );
  }
}

// ---------------------------------------------------------------- 07 Wellness

class WellnessPreferencesScreen extends ConsumerStatefulWidget {
  const WellnessPreferencesScreen({super.key, this.editing = false});
  final bool editing;

  @override
  ConsumerState<WellnessPreferencesScreen> createState() => _WellnessPreferencesScreenState();
}

class _WellnessPreferencesScreenState extends ConsumerState<WellnessPreferencesScreen> {
  WellnessPreferences? _w;
  bool _busy = false;

  static const interests = ['balanced', 'protein', 'variety', 'plants', 'education'];

  static String interestLabel(AppLocalizations l, String key) => switch (key) {
        'balanced' => l.onboardingInterestBalanced,
        'protein' => l.onboardingInterestProtein,
        'variety' => l.onboardingInterestVariety,
        'plants' => l.onboardingInterestPlants,
        'education' => l.onboardingInterestEducation,
        _ => key,
      };

  Future<void> _save() async {
    final uid = ref.read(uidProvider);
    if (uid == null || _w == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(profileRepoProvider).saveWellness(uid, _w!);
      if (!widget.editing) await ref.read(profileRepoProvider).updateProfileFields(uid, {'onboardingStep': 7});
      ref.read(analyticsProvider).log(AnalyticsEvents.onboardingStep, {'step': 7});
      if (!mounted) return;
      widget.editing ? context.pop() : context.go('/onboarding/kitchen');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _w ??= ref.watch(wellnessProvider).value;
    if (w == null) return const Scaffold(body: LoadingState());
    void set(WellnessPreferences n) => setState(() => _w = n);
    final l = context.l10n;
    final content = [
      Text(l.onboardingWellnessQuestion, style: context.text.titleMedium),
      const SizedBox(height: Space.xs),
      ChoiceChipGroup(
        options: interests,
        labelOf: (k) => interestLabel(l, k),
        selected: w.interests.toSet(),
        onChanged: (s) => set(w.copyWith(interests: s.toList())),
      ),
      const SizedBox(height: Space.l),
      ToggleTile(
        title: l.onboardingShowNutritionTitle,
        subtitle: l.onboardingShowNutritionSubtitle,
        value: w.showNutritionOnRecipes,
        onChanged: (v) => set(w.copyWith(showNutritionOnRecipes: v)),
      ),
      ToggleTile(
        title: l.onboardingTrackCaloriesTitle,
        subtitle: l.onboardingTrackCaloriesSubtitle,
        value: w.calorieTracking,
        onChanged: (v) => set(w.copyWith(calorieTracking: v)),
      ),
      ToggleTile(
        title: l.onboardingSmileTitle,
        subtitle: l.onboardingSmileSubtitle,
        value: w.smileAndFood,
        onChanged: (v) => set(w.copyWith(smileAndFood: v)),
      ),
      const SizedBox(height: Space.m),
      Text(
        l.onboardingWellnessDisclaimer,
        style: context.text.bodySmall,
      ),
    ];
    if (widget.editing) {
      return PremiumAppScaffold(
        header: EditorialPageHeader(title: l.onboardingWellnessEditTitle),
        primaryAction: PrimaryActionButton(label: l.commonSave, onPressed: _save, loading: _busy),
        children: content,
      );
    }
    return OnboardingFrame(
      step: 6,
      title: l.onboardingWellnessTitle,
      subtitle: l.onboardingWellnessSubtitle,
      primaryLabel: l.commonContinue,
      loading: _busy,
      onPrimary: _save,
      onSkip: () => context.go('/onboarding/kitchen'),
      children: content,
    );
  }
}

// ---------------------------------------------------------------- 08 Build your kitchen

class BuildKitchenScreen extends ConsumerStatefulWidget {
  const BuildKitchenScreen({super.key});

  @override
  ConsumerState<BuildKitchenScreen> createState() => _BuildKitchenScreenState();
}

class _BuildKitchenScreenState extends ConsumerState<BuildKitchenScreen> {
  bool _busy = false;

  Future<void> _finish(String then) async {
    final uid = ref.read(uidProvider);
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      if (then == 'example') await ref.read(actionsProvider).seedExampleKitchen();
      await ref.read(profileRepoProvider).updateProfileFields(uid, {'onboardingComplete': true, 'onboardingStep': 8});
      ref.read(analyticsProvider).log(AnalyticsEvents.onboardingComplete, {'method': then});
      if (!mounted) return;
      context.go('/today');
      if (then == 'receipt') context.push('/receipt/capture');
      if (then == 'scan') context.push('/kitchen/scan');
      if (then == 'manual') context.push('/kitchen/add');
    } catch (e) {
      if (mounted) showMessage(context, ErrorState.describeIn(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget option(IconData icon, String title, String body, String key) => Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: SoftCard(
            onTap: _busy ? null : () => _finish(key),
            semanticLabel: context.l10n.onboardingOptionSemantics(title, body),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: context.palette.surfaceSoft, borderRadius: BorderRadius.circular(Radii.m)),
                child: Icon(icon, color: context.colors.primary),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: context.text.titleMedium),
                  Text(body, style: context.text.bodySmall),
                ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        );
    final l = context.l10n;
    return OnboardingFrame(
      step: 7,
      title: l.onboardingKitchenTitle,
      subtitle: l.onboardingKitchenSubtitle,
      primaryLabel: l.onboardingKitchenLater,
      loading: _busy,
      onPrimary: () => _finish('later'),
      children: [
        option(Icons.receipt_long_outlined, l.onboardingScanReceiptTitle, l.onboardingScanReceiptBody, 'receipt'),
        option(Icons.photo_camera_outlined, l.onboardingScanFridgeTitle, l.onboardingScanFridgeBody, 'scan'),
        option(Icons.edit_note, l.onboardingAddManualTitle, l.onboardingAddManualBody, 'manual'),
        option(Icons.auto_awesome_outlined, l.onboardingExampleKitchenTitle, l.onboardingExampleKitchenBody, 'example'),
      ],
    );
  }
}
