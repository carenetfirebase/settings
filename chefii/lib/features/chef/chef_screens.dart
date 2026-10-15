import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/actions.dart';
import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../core/services/analytics.dart';
import '../../data/ai/ai_gateway.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/models/planning.dart';
import '../../domain/models/recipe.dart';
import '../../domain/nutrition/nutrition_calculator.dart';
import '../../domain/recipes/recipe_availability.dart';
import '../../domain/recipes/substitutions.dart';
import '../../domain/safety/allergen_guard.dart';
import '../shared/ai_consent.dart';
import '../shared/recipe_logic.dart';

// ---------------------------------------------------------------- chat state

class ChefChat extends Notifier<List<ChefMessage>> {
  bool busy = false;

  @override
  List<ChefMessage> build() => const [];

  Future<void> send(String text) async {
    if (text.trim().isEmpty || busy) return;
    final hid = ref.read(householdIdProvider);
    if (hid == null) return;
    busy = true;
    state = [...state, ChefMessage(fromUser: true, text: text.trim(), at: DateTime.now().toUtc())];
    ref.read(analyticsProvider).log(AnalyticsEvents.chefMessage);
    try {
      final reply = await ref.read(aiGatewayProvider).chat(householdId: hid, history: state);
      ref.read(recipeCacheProvider.notifier).putAll(reply.recipes);
      state = [...state, reply];
    } on AiUnavailableException catch (e) {
      state = [...state, ChefMessage(fromUser: false, text: '${e.message} Your curated recipes are still available in Discover.')];
    } catch (_) {
      state = [...state, const ChefMessage(fromUser: false, text: 'I couldn\'t reach the kitchen assistant just now. Please try again.')];
    } finally {
      busy = false;
      ref.notifyListeners();
    }
  }

  void clear() => state = const [];
}

final chefChatProvider = NotifierProvider<ChefChat, List<ChefMessage>>(ChefChat.new);

// ---------------------------------------------------------------- 29 Chef home

class ChefHomeScreen extends ConsumerStatefulWidget {
  const ChefHomeScreen({super.key});

  @override
  ConsumerState<ChefHomeScreen> createState() => _ChefHomeScreenState();
}

class _ChefHomeScreenState extends ConsumerState<ChefHomeScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const prompts = [
    'Something quick for dinner',
    'A high-protein breakfast',
    'What can I make with what I have?',
    'A comforting vegetarian meal',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    if (!await ensureAiConsent(context, ref, feature: 'your AI chef')) return;
    _input.clear();
    await ref.read(chefChatProvider.notifier).send(text);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.medium, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chefChatProvider);
    final busy = ref.read(chefChatProvider.notifier).busy;
    final isDemo = ref.watch(aiGatewayProvider).isDemo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your chef'),
        actions: [
          IconButton(tooltip: 'Preferences', onPressed: () => context.push('/chef/preferences'), icon: const Icon(Icons.tune)),
          if (messages.isNotEmpty) IconButton(tooltip: 'New conversation', onPressed: ref.read(chefChatProvider.notifier).clear, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.l),
            children: [
              if (isDemo) const DemoBanner(message: 'Demo: replies use the curated recipe library, not AI.'),
              if (messages.isEmpty) ...[
                const EditorialPageHeader(eyebrow: 'Chefii', title: 'What shall we cook?', subtitle: 'Ask for anything — I know what\'s in your kitchen and what everyone can eat.'),
                for (final p in prompts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: SoftCard(
                      onTap: () => _send(p),
                      child: Row(children: [
                        Icon(Icons.auto_awesome_outlined, color: context.palette.accent),
                        const SizedBox(width: Space.s),
                        Expanded(child: Text(p, style: context.text.bodyLarge)),
                      ]),
                    ),
                  ),
                const SizedBox(height: Space.s),
                SecondaryActionButton(icon: Icons.tune, label: 'Choose time, portions and more', onPressed: () => context.push('/chef/preferences')),
              ],
              for (final m in messages)
                ChefConversationBubble(
                  fromUser: m.fromUser,
                  text: m.text,
                  recipes: m.recipes,
                  isDemo: m.isDemo,
                  onRecipeTap: (r) => context.push('/recipe/${r.id}'),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: Space.s),
                  child: Align(alignment: Alignment.centerLeft, child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: const InputDecoration(hintText: 'Ask your chef…'),
                ),
              ),
              const SizedBox(width: Space.xs),
              IconButton.filled(tooltip: 'Send', onPressed: busy ? null : () => _send(_input.text), icon: const Icon(Icons.arrow_upward)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- 30 Chef preferences

class ChefRequestState extends Notifier<ChefRequest?> {
  @override
  ChefRequest? build() => null;
  void set(ChefRequest r) => state = r;
}

final chefRequestProvider = NotifierProvider<ChefRequestState, ChefRequest?>(ChefRequestState.new);

class ChefPreferencesScreen extends ConsumerStatefulWidget {
  const ChefPreferencesScreen({super.key});

  @override
  ConsumerState<ChefPreferencesScreen> createState() => _ChefPreferencesScreenState();
}

class _ChefPreferencesScreenState extends ConsumerState<ChefPreferencesScreen> {
  MealType? _meal;
  int _minutes = 30;
  int _servings = 2;
  bool _useWhatIHave = true;
  String? _focus;
  final _cuisines = <String>{};
  final _equipment = <String>{};
  final _exclusions = TextEditingController();
  bool _init = false;

  @override
  void dispose() {
    _exclusions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final household = ref.watch(householdProvider).value;
    if (!_init && profile != null) {
      _init = true;
      _minutes = profile.culinary.weeknightMinutes;
      _servings = household?.portions ?? 2;
      _equipment.addAll(profile.culinary.equipment);
      _meal = mealTypeFor(DateTime.now());
    }
    final dietary = ref.watch(householdDietaryProvider);
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Chef', title: 'Tonight, I\'d like…'),
      primaryAction: PrimaryActionButton(
        label: 'Show me recipes',
        onPressed: () async {
          if (!await ensureAiConsent(context, ref, feature: 'your AI chef')) return;
          final hid = ref.read(householdIdProvider);
          if (hid == null) return;
          ref.read(chefRequestProvider.notifier).set(ChefRequest(
                householdId: hid,
                mealType: _meal,
                maxMinutes: _minutes,
                servings: _servings,
                cuisines: _cuisines.toList(),
                useWhatIHave: _useWhatIHave,
                equipment: _equipment.toList(),
                nutritionFocus: _focus,
                exclusions: _exclusions.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
              ));
          if (context.mounted) context.push('/chef/results');
        },
      ),
      children: [
        Text('Meal', style: context.text.titleMedium),
        Wrap(spacing: Space.xs, children: [
          for (final m in MealType.values) ChoiceChip(label: Text(m.label), selected: _meal == m, onSelected: (_) => setState(() => _meal = m)),
        ]),
        const SectionHeader('Time available'),
        Slider(
          value: _minutes.toDouble(),
          min: 10,
          max: 90,
          divisions: 16,
          label: formatMinutes(_minutes),
          semanticFormatterCallback: (v) => formatMinutes(v.round()),
          onChanged: (v) => setState(() => _minutes = v.round()),
        ),
        Text('Up to ${formatMinutes(_minutes)}', style: context.text.bodySmall),
        const SectionHeader('Portions'),
        Row(children: [
          IconButton.filledTonal(tooltip: 'Fewer', onPressed: _servings > 1 ? () => setState(() => _servings--) : null, icon: const Icon(Icons.remove)),
          SizedBox(width: 48, child: Text('$_servings', textAlign: TextAlign.center, style: context.text.headlineSmall)),
          IconButton.filledTonal(tooltip: 'More', onPressed: _servings < 12 ? () => setState(() => _servings++) : null, icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: Space.m),
        ToggleTile(title: 'Use what I have', subtitle: 'Prefer recipes I can make now', value: _useWhatIHave, onChanged: (v) => setState(() => _useWhatIHave = v)),
        const SectionHeader('Nutrition'),
        ChoiceChipGroup(
          single: true,
          options: const ['more protein', 'more vegetables', 'lighter', 'more fibre'],
          selected: {?_focus},
          onChanged: (s) => setState(() => _focus = s.firstOrNull),
        ),
        const SectionHeader('Cuisine'),
        ChoiceChipGroup(options: const ['Italian', 'French', 'Mediterranean', 'Indian', 'Middle Eastern', 'Mexican', 'Japanese', 'Chinese', 'Modern'], selected: _cuisines, onChanged: (s) => setState(() => _cuisines
          ..clear()
          ..addAll(s))),
        const SectionHeader('Equipment'),
        ChoiceChipGroup(options: const ['Oven', 'Stovetop', 'Air fryer', 'Slow cooker', 'Instant Pot', 'Blender', 'Microwave'], selected: _equipment, onChanged: (s) => setState(() => _equipment
          ..clear()
          ..addAll(s))),
        const SectionHeader('Leave out'),
        TextField(controller: _exclusions, decoration: const InputDecoration(hintText: 'e.g. mushrooms, olives')),
        const SizedBox(height: Space.m),
        Text(
          dietary.allergiesKnown
              ? 'Always respected: ${[...dietary.allergies.map((a) => AllergenGuard.byKey[a]?.label ?? a), ...dietary.restrictions.map((r) => AllergenGuard.restrictionByKey[r]?.label ?? r)].join(', ').ifEmpty('no allergies or restrictions recorded')}.'
              : 'Add your allergies in Profile so I can screen every recipe.',
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

// ---------------------------------------------------------------- 31 Recommendations

final chefResultsProvider = FutureProvider.autoDispose.family<ChefResult, (ChefRequest, int)>((ref, args) async {
  final (req, round) = args;
  final result = await ref.read(aiGatewayProvider).recommend(req.copyWith(prompt: round == 0 ? req.prompt : '${req.prompt ?? ''} (different ideas, round $round)'));
  ref.read(recipeCacheProvider.notifier).putAll(result.suggestions.map((s) => s.recipe));
  return result;
});

class RecipeResultsScreen extends ConsumerStatefulWidget {
  const RecipeResultsScreen({super.key});

  @override
  ConsumerState<RecipeResultsScreen> createState() => _RecipeResultsScreenState();
}

class _RecipeResultsScreenState extends ConsumerState<RecipeResultsScreen> {
  int _round = 0;
  final _seen = <String>{};

  @override
  Widget build(BuildContext context) {
    final req = ref.watch(chefRequestProvider);
    if (req == null) {
      return PremiumAppScaffold(children: [
        EmptyState(icon: Icons.tune, title: 'Tell me what you\'d like', message: 'Choose time and portions first.', actionLabel: 'Set preferences', onAction: () => context.pushReplacement('/chef/preferences')),
      ]);
    }
    final async = ref.watch(chefResultsProvider((req.copyWith(), _round)));
    final result = async.value;
    final suggestions = result?.suggestions.where((s) => _round == 0 || !_seen.contains(s.recipe.id)).toList() ?? const <ChefSuggestion>[];
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'Chef', title: 'For you', subtitle: '${req.mealType?.label ?? 'Any meal'} · up to ${formatMinutes(req.maxMinutes ?? 60)} · ${req.servings} portions'),
      primaryAction: SecondaryActionButton(
        icon: Icons.refresh,
        label: 'Try another',
        onPressed: async.isLoading
            ? null
            : () => setState(() {
                  _seen.addAll(result?.suggestions.map((s) => s.recipe.id) ?? const []);
                  _round++;
                }),
      ),
      children: [
        if (result?.isDemo == true) const DemoBanner(message: 'Demo: ranked from the curated library, not generated by AI.'),
        if (async.isLoading) const LoadingState(message: 'Considering your kitchen…'),
        if (async.hasError)
          ErrorState(message: async.error is AiUnavailableException ? (async.error as AiUnavailableException).message : ErrorState.describe(async.error!), onRetry: () => ref.invalidate(chefResultsProvider)),
        if (result != null && suggestions.isEmpty && !async.isLoading)
          EmptyState(icon: Icons.search_off, title: 'No more ideas with these settings', message: 'Try a longer time or fewer restrictions.', actionLabel: 'Adjust', onAction: () => context.pop()),
        if (result != null && result.filteredForSafety > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Text('${result.filteredForSafety} idea${result.filteredForSafety == 1 ? ' was' : 's were'} left out for your household\'s dietary needs.', style: context.text.bodySmall),
          ),
        for (final s in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Consumer(builder: (context, ref, _) {
              final report = ref.watch(recipeAvailabilityProvider(s.recipe));
              return LuxuryRecipeCard(
                recipe: s.recipe,
                rationale: s.rationale,
                availabilityLabel: report.label,
                canCookNow: report.canCookNow,
                showNutrition: ref.watch(wellnessProvider).value?.showNutritionOnRecipes ?? true,
                onTap: () => context.push('/recipe/${s.recipe.id}'),
              );
            }),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 32 Recipe details

class RecipeDetailScreen extends ConsumerStatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipeId, this.planEntryId});
  final String recipeId;
  final String? planEntryId;

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  int? _servings;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).log(AnalyticsEvents.recipeViewed);
  }

  @override
  Widget build(BuildContext context) {
    final base = ref.watch(recipeByIdProvider(widget.recipeId));
    if (base == null) {
      return PremiumAppScaffold(children: [
        EmptyState(icon: Icons.menu_book_outlined, title: 'Recipe unavailable', message: 'This suggestion wasn\'t saved. Ask your chef again or browse Discover.', actionLabel: 'Discover', onAction: () => context.go('/discover')),
      ]);
    }
    final household = ref.watch(householdProvider).value;
    final servings = _servings ?? household?.portions ?? base.servings;
    final recipe = base.scaledTo(servings);
    final safety = ref.watch(recipeSafetyProvider(base));
    final availability = ref.watch(recipeAvailabilityProvider(recipe));
    final favs = ref.watch(favouritesProvider).value ?? const <String>{};
    final wellness = ref.watch(wellnessProvider).value;
    final isAi = base.origin == RecipeOrigin.ai;
    final saved = (ref.watch(savedRecipesProvider).value ?? const <Recipe>[]).any((r) => r.id == base.id);
    final checkByName = {for (final c in availability.checks) c.ingredient.name: c};

    return PremiumAppScaffold(
      padding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: favs.contains(base.id) ? 'Remove from favourites' : 'Save to favourites',
          onPressed: () async {
            final uid = ref.read(uidProvider)!;
            if (isAi && !saved) await ref.read(recipeRepoProvider).save(ref.read(householdIdProvider)!, base);
            await ref.read(profileRepoProvider).setFavourite(uid, base.id, !favs.contains(base.id));
          },
          icon: Icon(favs.contains(base.id) ? Icons.favorite : Icons.favorite_border),
        ),
        IconButton(tooltip: 'Add to meal plan', onPressed: () => context.push('/plan/assign?recipe=${base.id}'), icon: const Icon(Icons.calendar_month_outlined)),
      ],
      primaryAction: PrimaryActionButton(
        icon: Icons.play_arrow_rounded,
        label: safety.isBlocked ? 'Not safe for your household' : 'Start cooking',
        loading: _busy,
        onPressed: safety.isBlocked
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  final s = await ref.read(actionsProvider).startCooking(base, servings, mealPlanEntryId: widget.planEntryId);
                  if (context.mounted) context.push('/cook/${s.id}/prep');
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      ),
      children: [
        FoodArtwork(artKey: recipe.imageKey, height: 240, radius: 0, label: recipe.title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: Space.l),
            Text('${recipe.cuisine} · ${recipe.origin.label}'.toUpperCase(), style: context.text.labelSmall?.copyWith(color: context.palette.accent)),
            const SizedBox(height: Space.xs),
            Semantics(header: true, child: Text(recipe.title, style: context.text.displaySmall)),
            const SizedBox(height: Space.xs),
            Text(recipe.summary, style: context.text.bodyLarge?.copyWith(color: context.palette.muted)),
            const SizedBox(height: Space.m),
            Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
              TagPill('${formatMinutes(recipe.totalMinutes)} total', icon: Icons.schedule),
              TagPill(recipe.difficulty.label, icon: Icons.restaurant),
              for (final t in recipe.tags.take(4)) TagPill(t),
            ]),
            if (isAi) ...[
              const SizedBox(height: Space.s),
              Text('Created by AI for you${recipe.aiModel == null ? '' : ' (${recipe.aiModel})'}. Check cooking temperatures and your own judgement.', style: context.text.bodySmall),
            ],
            if (safety.isBlocked || safety.hasWarnings || safety.notices.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              SoftCard(
                color: safety.isBlocked ? context.palette.errorSoft : context.palette.warningSoft,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(safety.isBlocked ? Icons.block : Icons.warning_amber_rounded, color: safety.isBlocked ? context.palette.error : context.palette.warning),
                    const SizedBox(width: Space.xs),
                    Expanded(child: Text(safety.isBlocked ? 'Conflicts with your household\'s needs' : 'Worth a look', style: context.text.titleSmall)),
                  ]),
                  const SizedBox(height: Space.xs),
                  for (final c in safety.conflicts) Text('• ${c.ingredient}: ${c.reason}', style: context.text.bodySmall?.copyWith(color: context.palette.ink)),
                  for (final n in safety.notices) Text('• $n', style: context.text.bodySmall?.copyWith(color: context.palette.ink)),
                  if (safety.conflicts.isNotEmpty)
                    TextButton(onPressed: () => showSubstitutionsSheet(context, base), child: const Text('See substitutions')),
                ]),
              ),
            ],
            const SectionHeader('Ingredients'),
            Row(children: [
              Text('Servings', style: context.text.bodyMedium),
              const Spacer(),
              IconButton(tooltip: 'Fewer servings', onPressed: servings > 1 ? () => setState(() => _servings = servings - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$servings', style: context.text.titleLarge),
              IconButton(tooltip: 'More servings', onPressed: servings < 16 ? () => setState(() => _servings = servings + 1) : null, icon: const Icon(Icons.add_circle_outline)),
            ]),
            for (final i in recipe.ingredients)
              _IngredientRow(ingredient: i, check: checkByName[i.name]),
            if (availability.missing.isNotEmpty) ...[
              const SizedBox(height: Space.s),
              Row(children: [
                Expanded(
                  child: SecondaryActionButton(
                    icon: Icons.add_shopping_cart,
                    label: 'Add ${availability.missing.length} to list',
                    onPressed: () async {
                      final hid = ref.read(householdIdProvider)!;
                      for (final c in availability.missing) {
                        await ref.read(planningRepoProvider).addShoppingItem(
                              householdId: hid,
                              name: c.ingredient.name,
                              productId: c.ingredient.productId,
                              quantity: c.shortBy,
                              reason: ShoppingReason.missingForRecipe,
                              forRecipes: [recipe.title],
                            );
                      }
                      if (context.mounted) showMessage(context, 'Added to your shopping list');
                    },
                  ),
                ),
                const SizedBox(width: Space.xs),
                Expanded(child: SecondaryActionButton(icon: Icons.swap_horiz, label: 'Substitutions', onPressed: () => showSubstitutionsSheet(context, base))),
              ]),
            ],
            if (wellness?.showNutritionOnRecipes ?? true) ...[
              const SectionHeader('Nutrition'),
              NutritionSummaryCard(nutrition: recipe.nutritionPerServing, showCalories: true),
            ],
            if (recipe.equipment.isNotEmpty) ...[
              const SectionHeader('Equipment'),
              Text(recipe.equipment.join(' · '), style: context.text.bodyMedium),
            ],
            const SectionHeader('Method'),
            for (var s = 0; s < recipe.steps.length; s++)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.m),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 32, child: Text('${s + 1}', style: context.text.headlineSmall?.copyWith(color: context.palette.accent))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(recipe.steps[s].text, style: context.text.bodyLarge),
                      if (recipe.steps[s].timerSeconds != null)
                        Padding(padding: const EdgeInsets.only(top: 4), child: TagPill(formatMinutes((recipe.steps[s].timerSeconds! / 60).round()), icon: Icons.timer_outlined)),
                      if (recipe.steps[s].tip != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(recipe.steps[s].tip!, style: context.text.bodySmall)),
                    ]),
                  ),
                ]),
              ),
            if (recipe.storageNotes != null) ...[
              const SectionHeader('Storing'),
              Text(recipe.storageNotes!, style: context.text.bodyMedium),
            ],
            if (isAi && !saved)
              Padding(
                padding: const EdgeInsets.only(top: Space.m),
                child: TextButton.icon(
                  onPressed: () async {
                    await ref.read(recipeRepoProvider).save(ref.read(householdIdProvider)!, base);
                    if (context.mounted) showMessage(context, 'Saved to your recipes');
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Save this recipe'),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient, this.check});
  final RecipeIngredient ingredient;
  final IngredientCheck? check;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (IconData icon, Color color, String label) = switch (check?.availability) {
      IngredientAvailability.available => (Icons.check_circle, p.success, 'in your kitchen'),
      IngredientAvailability.partial => (Icons.timelapse, p.warning, 'need ${check!.shortBy?.format() ?? 'more'}'),
      IngredientAvailability.missing => (Icons.add_shopping_cart, p.muted, 'to buy'),
      _ => (Icons.circle_outlined, p.hairline, ''),
    };
    return Semantics(
      label: '${ingredient.display}${label.isEmpty ? '' : ', $label'}${ingredient.optional ? ', optional' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.s),
          Expanded(child: Text(ingredient.display + (ingredient.optional ? ' (optional)' : ''), style: context.text.bodyLarge)),
          if (label.isNotEmpty && check?.availability != IngredientAvailability.available) Text(label, style: context.text.bodySmall),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- 33 Smart substitutions

Future<void> showSubstitutionsSheet(BuildContext context, Recipe recipe) =>
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => SubstitutionsSheet(recipe: recipe));

class SubstitutionsSheet extends ConsumerWidget {
  const SubstitutionsSheet({super.key, required this.recipe});
  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dietary = ref.watch(householdDietaryProvider);
    final lots = ref.watch(lotsProvider).value ?? const [];
    final stock = RecipeAvailability.stockByProduct(lots);
    final safety = ref.watch(recipeSafetyProvider(recipe));
    final availability = ref.watch(recipeAvailabilityProvider(recipe));
    final relevant = {
      ...safety.conflicts.map((c) => c.ingredient),
      ...availability.missing.map((c) => c.ingredient.name),
    };
    const finder = SubstitutionFinder();
    const calc = NutritionCalculator();
    final rows = <SubstitutionOption>[];
    for (final i in recipe.ingredients.where((i) => relevant.isEmpty || relevant.contains(i.name))) {
      rows.addAll(finder.optionsFor(i, dietary).where((o) => o.isSafe));
    }
    final baseProtein = recipe.nutritionPerServing[Nutrient.protein];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
          children: [
            Text('Smart substitutions', style: context.text.headlineSmall),
            Text('Every swap is checked against your household\'s allergies and diet.', style: context.text.bodySmall),
            const SizedBox(height: Space.m),
            if (rows.isEmpty) const EmptyState(compact: true, icon: Icons.swap_horiz, title: 'No safe swaps we\'re confident about', message: 'Try asking your chef for a different recipe.'),
            for (final o in rows)
              Card(
                margin: const EdgeInsets.only(bottom: Space.xs),
                child: Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${o.original.name} → ${o.replacement.display}', style: context.text.titleMedium),
                    Text(o.note, style: context.text.bodySmall),
                    const SizedBox(height: Space.xs),
                    Wrap(spacing: Space.xs, children: [
                      if (stock.containsKey(o.replacement.productId)) TagPill('In your kitchen', icon: Icons.check, color: context.palette.success, background: context.palette.successSoft),
                      Builder(builder: (context) {
                        final next = finder.apply(recipe, o);
                        final protein = calc.perServing(next)[Nutrient.protein];
                        final diff = protein - baseProtein;
                        return TagPill('Protein ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(0)} g / serving');
                      }),
                    ]),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          final next = calc.withNutrition(finder.apply(recipe, o));
                          ref.read(recipeCacheProvider.notifier).putAll([next]);
                          Navigator.pop(context);
                          context.pushReplacement('/recipe/${next.id}');
                        },
                        child: const Text('Use this'),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
