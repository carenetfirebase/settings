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
    this.skipLabel = 'Skip for now',
  });

  final int step;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool loading;
  final VoidCallback? onSkip;
  final String skipLabel;

  static const total = 7;

  @override
  Widget build(BuildContext context) {
    return PremiumAppScaffold(
      actions: [if (onSkip != null) TextButton(onPressed: onSkip, child: Text(skipLabel))],
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: 'Step $step of $total',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: step / total, minHeight: 4),
            ),
          ),
          const SizedBox(height: Space.l),
          EditorialPageHeader(eyebrow: 'Step $step of $total', title: title, subtitle: subtitle),
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
                    Text('CHEFII', style: context.text.labelSmall?.copyWith(color: p.accent, letterSpacing: 4)),
                    const SizedBox(height: Space.l),
                    const FoodArtwork(artKey: 'herb', height: 280, radius: Radii.xl, label: 'A beautifully set kitchen table'),
                    const SizedBox(height: Space.xl),
                    Semantics(header: true, child: Text('Your kitchen,\nbeautifully taken care of.', style: context.text.displayMedium)),
                    const SizedBox(height: Space.m),
                    Text(
                      'Chefii knows what\'s in your kitchen, suggests what to make, guides you through it — and keeps everything in order.',
                      style: context.text.bodyLarge?.copyWith(color: p.muted),
                    ),
                    const SizedBox(height: Space.xxl),
                    PrimaryActionButton(label: 'Get started', onPressed: () => context.go('/onboarding/meet')),
                    const SizedBox(height: Space.s),
                    SecondaryActionButton(label: 'I already have an account', onPressed: () => context.go('/onboarding/account?mode=signin')),
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
    return OnboardingFrame(
      step: 1,
      title: 'Meet your chef',
      subtitle: 'Three things Chefii does for you, every day.',
      onSkip: () => context.go('/onboarding/account'),
      skipLabel: 'Skip',
      primaryLabel: 'Continue',
      onPrimary: () => context.go('/onboarding/account'),
      children: [
        benefit(Icons.kitchen_outlined, 'Knows your kitchen', 'Scan a receipt and your pantry, fridge and freezer stay up to date — with almost no typing.'),
        benefit(Icons.restaurant_menu, 'Decides what to make', 'Recipes matched to what you have, how much time you have, and everyone\'s dietary needs.'),
        benefit(Icons.self_improvement, 'Guides you calmly', 'Step-by-step cooking with timers, then one tap to update your kitchen.'),
        const SectionHeader('A taste'),
        LuxuryRecipeCard(recipe: sample, availabilityLabel: 'Example', compact: true),
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
      setState(() => _error = 'Please accept the Terms and Privacy Policy to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await f();
      final profiles = ref.read(profileRepoProvider);
      final profile = await profiles.ensureProfile(
        uid: user.uid,
        displayName: user.displayName ?? (_name.text.trim().isEmpty ? 'Friend' : _name.text.trim()),
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
      if (!e.cancelled && mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorState.describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);
    final methods = auth.availableMethods;
    final isDemo = ref.watch(appConfigProvider).isDemo;
    return OnboardingFrame(
      step: 2,
      title: _signIn ? 'Welcome back' : 'Create your account',
      subtitle: _signIn ? 'Sign in to your kitchen.' : 'Your kitchen stays private to you and the people you invite.',
      primaryLabel: _signIn ? 'Sign in' : 'Create account',
      loading: _busy,
      onPrimary: () {
        if (!(_form.currentState?.validate() ?? false)) return;
        _run(() => _signIn
            ? auth.signInWithEmail(_email.text, _password.text)
            : auth.createAccountWithEmail(_email.text, _password.text, _name.text));
      },
      children: [
        if (isDemo) ...[
          const DemoBanner(message: 'Demo mode: your account and data stay on this device only.'),
          SecondaryActionButton(
            icon: Icons.play_circle_outline,
            label: 'Continue with a demo account',
            onPressed: _busy
                ? null
                : () => _run(() => (auth as DemoAuthService).signInDemo(_name.text.trim().isEmpty ? 'Alex' : _name.text.trim())),
          ),
          const SizedBox(height: Space.m),
        ],
        if (methods.contains(AuthMethod.apple)) ...[
          SecondaryActionButton(icon: Icons.apple, label: 'Continue with Apple', onPressed: _busy ? null : () => _run(auth.signInWithApple)),
          const SizedBox(height: Space.xs),
        ],
        if (methods.contains(AuthMethod.google)) ...[
          SecondaryActionButton(icon: Icons.g_mobiledata, label: 'Continue with Google', onPressed: _busy ? null : () => _run(auth.signInWithGoogle)),
          const SizedBox(height: Space.m),
        ],
        Row(children: [
          const Expanded(child: Divider()),
          Padding(padding: const EdgeInsets.symmetric(horizontal: Space.s), child: Text('or with email', style: context.text.bodySmall)),
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
                  decoration: const InputDecoration(labelText: 'Your first name'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Please tell us what to call you' : null,
                ),
                const SizedBox(height: Space.s),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
              ),
              const SizedBox(height: Space.s),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: [_signIn ? AutofillHints.password : AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
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
                  setState(() => _error = 'Enter your email first.');
                  return;
                }
                await auth.sendPasswordReset(_email.text);
                if (context.mounted) showMessage(context, 'If that email has an account, a reset link is on its way.');
              },
              child: const Text('Forgot password?'),
            ),
          ),
        if (!_signIn) ...[
          const SizedBox(height: Space.m),
          CheckboxListTile(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text('I agree to the Terms of Service and Privacy Policy', style: context.text.bodyMedium),
            subtitle: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              onPressed: () => context.push('/you/legal'),
              child: const Text('Read them'),
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
            child: Text(_signIn ? 'New here? Create an account' : 'Already have an account? Sign in'),
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
      final name = _name.text.trim().isEmpty ? '${profile.firstName}\'s kitchen' : _name.text.trim();
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
      if (mounted) showMessage(context, ErrorState.describe(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingFrame(
      step: 3,
      title: 'Your household',
      subtitle: 'So portions and planning fit the way you live.',
      primaryLabel: 'Continue',
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
              semanticLabel: '${t.label}${_type == t ? ', selected' : ''}',
              child: Row(children: [
                Icon(switch (t) { HouseholdType.single => Icons.person_outline, HouseholdType.couple => Icons.people_outline, HouseholdType.family => Icons.family_restroom }),
                const SizedBox(width: Space.m),
                Expanded(child: Text(t.label, style: context.text.titleMedium)),
                if (_type == t) Icon(Icons.check_circle, color: context.colors.primary),
              ]),
            ),
          ),
        const SizedBox(height: Space.l),
        Text('Usual portions per meal', style: context.text.titleMedium),
        const SizedBox(height: Space.xs),
        Row(children: [
          IconButton.filledTonal(tooltip: 'Fewer portions', onPressed: _portions > 1 ? () => setState(() => _portions--) : null, icon: const Icon(Icons.remove)),
          SizedBox(width: 56, child: Text('$_portions', textAlign: TextAlign.center, style: context.text.headlineMedium)),
          IconButton.filledTonal(tooltip: 'More portions', onPressed: _portions < 12 ? () => setState(() => _portions++) : null, icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: Space.l),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Household name (optional)', hintText: 'e.g. The Laurier kitchen')),
        const SizedBox(height: Space.m),
        Text('You can invite others to share the kitchen later. Each person\'s health and journal stay private to them.', style: context.text.bodySmall),
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

    final content = [
      Text('Do you have any food allergies?', style: context.text.titleMedium),
      const SizedBox(height: Space.xs),
      Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
        for (final s in [DisclosureStatus.provided, DisclosureStatus.noneKnown, DisclosureStatus.preferNotToSay])
          ChoiceChip(
            label: Text(switch (s) { DisclosureStatus.provided => 'Yes', DisclosureStatus.noneKnown => 'None that I know of', _ => 'Prefer not to say' }),
            selected: p.allergyStatus == s,
            onSelected: (_) => set(p.copyWith(allergyStatus: s, allergies: s == DisclosureStatus.provided ? p.allergies : const [])),
          ),
      ]),
      if (p.allergyStatus == DisclosureStatus.provided) ...[
        const SizedBox(height: Space.m),
        ChoiceChipGroup(
          options: _allergenKeys,
          labelOf: (k) => AllergenGuard.byKey[k]!.label,
          selected: p.allergies.toSet(),
          onChanged: (s) => set(p.copyWith(allergies: s.toList())),
        ),
        const SizedBox(height: Space.s),
        ToggleTile(
          title: 'Warn me about cross-contact',
          subtitle: 'Reminders about "may contain" labels and shared equipment',
          value: p.avoidCrossContact,
          onChanged: (v) => set(p.copyWith(avoidCrossContact: v)),
        ),
      ],
      if (p.allergyStatus == DisclosureStatus.preferNotToSay || p.allergyStatus == DisclosureStatus.notAsked)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Text('We won\'t assume you have no allergies — recipes will remind you to check ingredients.', style: context.text.bodySmall),
        ),
      const SectionHeader('Intolerances'),
      ChoiceChipGroup(
        options: intoleranceLabels.keys.toList(),
        labelOf: (k) => intoleranceLabels[k]!,
        selected: p.intolerances.toSet(),
        onChanged: (s) => set(p.copyWith(intolerances: s.toList())),
      ),
      const SectionHeader('Dietary pattern'),
      ChoiceChipGroup(
        options: restrictions.map((r) => r.key).toList(),
        labelOf: (k) => AllergenGuard.restrictionByKey[k]!.label,
        selected: p.restrictions.toSet(),
        onChanged: (s) => set(p.copyWith(restrictions: s.toList())),
      ),
      const SectionHeader('Foods you\'d rather avoid'),
      Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
        for (final d in p.dislikes) InputChip(label: Text(d), onDeleted: () => set(p.copyWith(dislikes: [...p.dislikes]..remove(d)))),
      ]),
      const SizedBox(height: Space.xs),
      TextField(
        controller: _dislike,
        decoration: InputDecoration(
          labelText: 'Add a food (e.g. cilantro)',
          suffixIcon: IconButton(
            tooltip: 'Add',
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
            'Chefii screens every recipe against these, but it can\'t see inside packaged foods. Always check labels. '
            'Allergies you list are shared with your household only to keep shared meals safe.',
            style: context.text.bodySmall?.copyWith(color: context.palette.ink),
          ),
        ),
      ),
    ];

    if (widget.editing) {
      return PremiumAppScaffold(
        header: const EditorialPageHeader(title: 'Dietary safety', subtitle: 'Allergies, intolerances and preferences.'),
        primaryAction: PrimaryActionButton(label: 'Save', onPressed: _save, loading: _busy),
        children: content,
      );
    }
    return OnboardingFrame(
      step: 4,
      title: 'Dietary safety',
      subtitle: 'The most important thing we\'ll ask. You can change it any time.',
      primaryLabel: 'Continue',
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

  static const cuisines = ['Italian', 'French', 'Mediterranean', 'Middle Eastern', 'Indian', 'Japanese', 'Chinese', 'Thai', 'Korean', 'Mexican', 'Greek', 'Nordic', 'Canadian'];
  static const foods = ['Salmon', 'Chicken', 'Pasta', 'Eggs', 'Tofu', 'Lentils', 'Vegetables', 'Salads', 'Soups', 'Rice bowls', 'Baking'];
  static const equipment = ['Oven', 'Stovetop', 'Air fryer', 'Slow cooker', 'Instant Pot', 'Blender', 'Microwave', 'Grill'];
  static const spice = ['None', 'Mild', 'Medium', 'Warm', 'Hot'];

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
    final content = [
      Text('Cuisines you love', style: context.text.titleMedium),
      const SizedBox(height: Space.xs),
      ChoiceChipGroup(options: cuisines, selected: c.cuisines.toSet(), onChanged: (s) => set(c.copyWith(cuisines: s.toList()))),
      const SectionHeader('Favourite foods'),
      ChoiceChipGroup(options: foods, selected: c.favouriteFoods.toSet(), onChanged: (s) => set(c.copyWith(favouriteFoods: s.toList()))),
      const SectionHeader('Cooking confidence'),
      ChoiceChipGroup(
        single: true,
        options: CookingConfidence.values.map((e) => e.name).toList(),
        labelOf: (n) => CookingConfidence.values.byName(n).label,
        selected: {c.confidence.name},
        onChanged: (s) => s.isEmpty ? null : set(c.copyWith(confidence: CookingConfidence.values.byName(s.first))),
      ),
      const SectionHeader('Spice'),
      Slider(
        value: c.spiceLevel.toDouble(),
        max: 4,
        divisions: 4,
        label: spice[c.spiceLevel],
        semanticFormatterCallback: (v) => spice[v.round()],
        onChanged: (v) => set(c.copyWith(spiceLevel: v.round())),
      ),
      Text('Spice: ${spice[c.spiceLevel]}', style: context.text.bodySmall),
      const SectionHeader('Weeknight time'),
      ChoiceChipGroup(
        single: true,
        options: const ['15', '20', '30', '45', '60'],
        labelOf: (m) => '$m min',
        selected: {'${c.weeknightMinutes}'},
        onChanged: (s) => s.isEmpty ? null : set(c.copyWith(weeknightMinutes: int.parse(s.first))),
      ),
      const SectionHeader('Your equipment'),
      ChoiceChipGroup(options: equipment, selected: c.equipment.toSet(), onChanged: (s) => set(c.copyWith(equipment: s.toList()))),
    ];
    if (widget.editing) {
      return PremiumAppScaffold(
        header: const EditorialPageHeader(title: 'Culinary preferences'),
        primaryAction: PrimaryActionButton(label: 'Save', onPressed: _save, loading: _busy),
        children: content,
      );
    }
    return OnboardingFrame(
      step: 5,
      title: 'What you love to eat',
      subtitle: 'Pick as many or as few as you like.',
      primaryLabel: 'Continue',
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

  static const interests = {
    'balanced': 'Balanced meals',
    'protein': 'More protein',
    'variety': 'More variety',
    'plants': 'More vegetables & plants',
    'education': 'Learn about nutrition',
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
    final content = [
      Text('Anything you\'d like help with?', style: context.text.titleMedium),
      const SizedBox(height: Space.xs),
      ChoiceChipGroup(
        options: interests.keys.toList(),
        labelOf: (k) => interests[k]!,
        selected: w.interests.toSet(),
        onChanged: (s) => set(w.copyWith(interests: s.toList())),
      ),
      const SizedBox(height: Space.l),
      ToggleTile(
        title: 'Show nutrition on recipes',
        subtitle: 'Estimated protein, fibre and more',
        value: w.showNutritionOnRecipes,
        onChanged: (v) => set(w.copyWith(showNutritionOnRecipes: v)),
      ),
      ToggleTile(
        title: 'Track calories',
        subtitle: 'Off by default. Chefii never sets targets for you.',
        value: w.calorieTracking,
        onChanged: (v) => set(w.copyWith(calorieTracking: v)),
      ),
      ToggleTile(
        title: 'Smile & Food',
        subtitle: 'Education about sugar and acid exposure for your teeth',
        value: w.smileAndFood,
        onChanged: (v) => set(w.copyWith(smileAndFood: v)),
      ),
      const SizedBox(height: Space.m),
      Text(
        'Chefii offers food and nutrition education. It isn\'t medical advice and doesn\'t diagnose or treat any condition.',
        style: context.text.bodySmall,
      ),
    ];
    if (widget.editing) {
      return PremiumAppScaffold(
        header: const EditorialPageHeader(title: 'Wellness preferences'),
        primaryAction: PrimaryActionButton(label: 'Save', onPressed: _save, loading: _busy),
        children: content,
      );
    }
    return OnboardingFrame(
      step: 6,
      title: 'Wellness, your way',
      subtitle: 'Entirely optional — and never about guilt.',
      primaryLabel: 'Continue',
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
      if (mounted) showMessage(context, ErrorState.describe(e), error: true);
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
            semanticLabel: '$title. $body',
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
    return OnboardingFrame(
      step: 7,
      title: 'Build your kitchen',
      subtitle: 'The fastest way is your last grocery receipt.',
      primaryLabel: 'I\'ll do this later',
      loading: _busy,
      onPrimary: () => _finish('later'),
      children: [
        option(Icons.receipt_long_outlined, 'Scan a receipt', 'Everything you bought, in about a minute', 'receipt'),
        option(Icons.photo_camera_outlined, 'Scan your fridge or pantry', 'Confirm what we spot', 'scan'),
        option(Icons.edit_note, 'Add items manually', 'Search, scan a barcode or speak', 'manual'),
        option(Icons.auto_awesome_outlined, 'Start with example ingredients', 'Explore Chefii with a sample kitchen', 'example'),
      ],
    );
  }
}
