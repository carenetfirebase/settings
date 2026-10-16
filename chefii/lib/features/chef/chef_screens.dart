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
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';
import '../shared/ai_consent.dart';
import '../shared/recipe_logic.dart';

// ---------------------------------------------------------------- chat state

class ChefChat extends Notifier<List<ChefMessage>> {
  bool busy = false;

  @override
  List<ChefMessage> build() => const [];

  Future<void> send(String text, AppLocalizations l) async {
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
      state = [...state, ChefMessage(fromUser: false, text: l.chefChatUnavailable(ErrorState.describeWith(l, e)))];
    } catch (_) {
      state = [...state, ChefMessage(fromUser: false, text: l.chefChatError)];
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

  static List<String> prompts(AppLocalizations l) => [
        l.chefPromptQuickDinner,
        l.chefPromptProteinBreakfast,
        l.chefPromptUseWhatIHave,
        l.chefPromptVegetarian,
      ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    if (!await ensureAiConsent(context, ref, feature: context.l10n.chefAiFeature)) return;
    if (!mounted) return;
    _input.clear();
    await ref.read(chefChatProvider.notifier).send(text, context.l10n);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.medium, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chefChatProvider);
    final busy = ref.read(chefChatProvider.notifier).busy;
    final isDemo = ref.watch(aiGatewayProvider).isDemo;
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.chefHomeTitle),
        actions: [
          IconButton(tooltip: l.chefPreferencesTooltip, onPressed: () => context.push('/chef/preferences'), icon: const Icon(Icons.tune)),
          if (messages.isNotEmpty) IconButton(tooltip: l.chefNewConversation, onPressed: ref.read(chefChatProvider.notifier).clear, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.l),
            children: [
              if (isDemo) DemoBanner(message: l.chefDemoChat),
              if (messages.isEmpty) ...[
                EditorialPageHeader(eyebrow: 'Chefii', title: l.chefHomeHeadline, subtitle: l.chefHomeSubtitle), // l10n-ignore
                for (final p in prompts(l))
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
                SecondaryActionButton(icon: Icons.tune, label: l.chefChooseOptions, onPressed: () => context.push('/chef/preferences')),
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
                  decoration: InputDecoration(hintText: l.chefAskHint),
                ),
              ),
              const SizedBox(width: Space.xs),
              IconButton.filled(tooltip: l.chefSend, onPressed: busy ? null : () => _send(_input.text), icon: const Icon(Icons.arrow_upward)),
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
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.chefEyebrow, title: l.chefPreferencesTitle),
      primaryAction: PrimaryActionButton(
        label: l.chefShowRecipes,
        onPressed: () async {
          if (!await ensureAiConsent(context, ref, feature: l.chefAiFeature)) return;
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
        Text(l.chefMeal, style: context.text.titleMedium),
        Wrap(spacing: Space.xs, children: [
          for (final m in MealType.values) ChoiceChip(label: Text(context.labelOf(m)), selected: _meal == m, onSelected: (_) => setState(() => _meal = m)),
        ]),
        SectionHeader(l.chefTimeAvailable),
        Semantics(label: l.chefTimeAvailableSemantics, child: Slider(
          value: _minutes.toDouble(),
          min: 10,
          max: 90,
          divisions: 16,
          label: formatMinutes(_minutes),
          semanticFormatterCallback: (v) => formatMinutes(v.round()),
          onChanged: (v) => setState(() => _minutes = v.round()),
        )),
        Text(l.chefUpTo(formatMinutes(_minutes)), style: context.text.bodySmall),
        SectionHeader(l.chefPortions),
        Row(children: [
          IconButton.filledTonal(tooltip: l.chefFewer, onPressed: _servings > 1 ? () => setState(() => _servings--) : null, icon: const Icon(Icons.remove)),
          SizedBox(width: 48, child: Text('$_servings', textAlign: TextAlign.center, style: context.text.headlineSmall)), // l10n-ignore
          IconButton.filledTonal(tooltip: l.chefMore, onPressed: _servings < 12 ? () => setState(() => _servings++) : null, icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: Space.m),
        ToggleTile(title: l.chefUseWhatIHave, subtitle: l.chefUseWhatIHaveSubtitle, value: _useWhatIHave, onChanged: (v) => setState(() => _useWhatIHave = v)),
        SectionHeader(l.chefNutrition),
        ChoiceChipGroup(
          single: true,
          options: const ['more protein', 'more vegetables', 'lighter', 'more fibre'],
          labelOf: (o) => _focusLabel(l, o),
          selected: {?_focus},
          onChanged: (s) => setState(() => _focus = s.firstOrNull),
        ),
        SectionHeader(l.chefCuisine),
        ChoiceChipGroup(options: const ['Italian', 'French', 'Mediterranean', 'Indian', 'Middle Eastern', 'Mexican', 'Japanese', 'Chinese', 'Modern'], labelOf: (o) => _cuisineLabel(l, o), selected: _cuisines, onChanged: (s) => setState(() => _cuisines
          ..clear()
          ..addAll(s))),
        SectionHeader(l.chefEquipment),
        ChoiceChipGroup(options: const ['Oven', 'Stovetop', 'Air fryer', 'Slow cooker', 'Instant Pot', 'Blender', 'Microwave'], labelOf: (o) => _equipmentLabel(l, o), selected: _equipment, onChanged: (s) => setState(() => _equipment
          ..clear()
          ..addAll(s))),
        SectionHeader(l.chefLeaveOut),
        TextField(controller: _exclusions, decoration: InputDecoration(hintText: l.chefLeaveOutHint)),
        const SizedBox(height: Space.m),
        Text(
          dietary.allergiesKnown
              ? l.chefAlwaysRespected([...dietary.allergies.map(context.allergenLabel), ...dietary.restrictions.map(context.restrictionLabel)].join(', ').ifEmpty(l.chefNoAllergiesRecorded))
              : l.chefAddAllergies,
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

String _focusLabel(AppLocalizations l, String o) => switch (o) {
      'more protein' => l.chefFocusMoreProtein,
      'more vegetables' => l.chefFocusMoreVegetables,
      'lighter' => l.chefFocusLighter,
      'more fibre' => l.chefFocusMoreFibre,
      _ => o,
    };

String _cuisineLabel(AppLocalizations l, String o) => switch (o) {
      'Italian' => l.chefCuisineItalian,
      'French' => l.chefCuisineFrench,
      'Mediterranean' => l.chefCuisineMediterranean,
      'Indian' => l.chefCuisineIndian,
      'Middle Eastern' => l.chefCuisineMiddleEastern,
      'Mexican' => l.chefCuisineMexican,
      'Japanese' => l.chefCuisineJapanese,
      'Chinese' => l.chefCuisineChinese,
      'Modern' => l.chefCuisineModern,
      _ => o,
    };

String _equipmentLabel(AppLocalizations l, String o) => switch (o) {
      'Oven' => l.chefEquipmentOven,
      'Stovetop' => l.chefEquipmentStovetop,
      'Air fryer' => l.chefEquipmentAirFryer,
      'Slow cooker' => l.chefEquipmentSlowCooker,
      'Instant Pot' => l.chefEquipmentInstantPot,
      'Blender' => l.chefEquipmentBlender,
      'Microwave' => l.chefEquipmentMicrowave,
      _ => o,
    };

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
    final l = context.l10n;
    if (req == null) {
      return PremiumAppScaffold(children: [
        EmptyState(icon: Icons.tune, title: l.chefNoRequestTitle, message: l.chefNoRequestMessage, actionLabel: l.chefSetPreferences, onAction: () => context.pushReplacement('/chef/preferences')),
      ]);
    }
    final async = ref.watch(chefResultsProvider((req.copyWith(), _round)));
    final result = async.value;
    final suggestions = result?.suggestions.where((s) => _round == 0 || !_seen.contains(s.recipe.id)).toList() ?? const <ChefSuggestion>[];
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.chefEyebrow, title: l.chefResultsTitle, subtitle: l.chefResultsSubtitle(req.mealType == null ? l.chefAnyMeal : context.labelOf(req.mealType!), formatMinutes(req.maxMinutes ?? 60), req.servings)),
      primaryAction: SecondaryActionButton(
        icon: Icons.refresh,
        label: l.chefTryAnother,
        onPressed: async.isLoading
            ? null
            : () => setState(() {
                  _seen.addAll(result?.suggestions.map((s) => s.recipe.id) ?? const []);
                  _round++;
                }),
      ),
      children: [
        if (result?.isDemo == true) DemoBanner(message: l.chefDemoResults),
        if (async.isLoading) LoadingState(message: l.chefConsidering),
        if (async.hasError)
          ErrorState(message: ErrorState.describeIn(context, async.error!), onRetry: () => ref.invalidate(chefResultsProvider)),
        if (result != null && suggestions.isEmpty && !async.isLoading)
          EmptyState(icon: Icons.search_off, title: l.chefNoMoreIdeasTitle, message: l.chefNoMoreIdeasMessage, actionLabel: l.chefAdjust, onAction: () => context.pop()),
        if (result != null && result.filteredForSafety > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Text(l.chefFilteredForSafety(result.filteredForSafety), style: context.text.bodySmall),
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
    final l = context.l10n;
    if (base == null) {
      return PremiumAppScaffold(children: [
        EmptyState(icon: Icons.menu_book_outlined, title: l.chefRecipeUnavailableTitle, message: l.chefRecipeUnavailableMessage, actionLabel: l.chefDiscover, onAction: () => context.go('/discover')),
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
          tooltip: favs.contains(base.id) ? l.chefRemoveFavourite : l.chefSaveFavourite,
          onPressed: () async {
            final uid = ref.read(uidProvider)!;
            if (isAi && !saved) await ref.read(recipeRepoProvider).save(ref.read(householdIdProvider)!, base);
            await ref.read(profileRepoProvider).setFavourite(uid, base.id, !favs.contains(base.id));
          },
          icon: Icon(favs.contains(base.id) ? Icons.favorite : Icons.favorite_border),
        ),
        IconButton(tooltip: l.chefAddToPlan, onPressed: () => context.push('/plan/assign?recipe=${base.id}'), icon: const Icon(Icons.calendar_month_outlined)),
      ],
      primaryAction: PrimaryActionButton(
        icon: Icons.play_arrow_rounded,
        label: safety.isBlocked ? l.chefNotSafe : l.chefStartCooking,
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
            Text('${recipe.cuisine} · ${context.labelOf(recipe.origin)}'.toUpperCase(), style: context.text.labelSmall?.copyWith(color: context.palette.accent)), // l10n-ignore
            const SizedBox(height: Space.xs),
            Semantics(header: true, child: Text(recipe.title, style: context.text.displaySmall)),
            const SizedBox(height: Space.xs),
            Text(recipe.summary, style: context.text.bodyLarge?.copyWith(color: context.palette.muted)),
            const SizedBox(height: Space.m),
            Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
              TagPill(l.chefTotalTime(formatMinutes(recipe.totalMinutes)), icon: Icons.schedule),
              TagPill(context.labelOf(recipe.difficulty), icon: Icons.restaurant),
              for (final t in recipe.tags.take(4)) TagPill(t),
            ]),
            if (isAi) ...[
              const SizedBox(height: Space.s),
              Text(recipe.aiModel == null ? l.chefAiCreated : l.chefAiCreatedWithModel(recipe.aiModel!), style: context.text.bodySmall),
            ],
            if (safety.isBlocked || safety.hasWarnings || safety.notices.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              SoftCard(
                color: safety.isBlocked ? context.palette.errorSoft : context.palette.warningSoft,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(safety.isBlocked ? Icons.block : Icons.warning_amber_rounded, color: safety.isBlocked ? context.palette.error : context.palette.warning),
                    const SizedBox(width: Space.xs),
                    Expanded(child: Text(safety.isBlocked ? l.chefConflicts : l.chefWorthALook, style: context.text.titleSmall)),
                  ]),
                  const SizedBox(height: Space.xs),
                  for (final c in safety.conflicts) Text(l.chefConflictLine(c.ingredient, c.reason), style: context.text.bodySmall?.copyWith(color: context.palette.ink)),
                  for (final n in safety.notices) Text('• $n', style: context.text.bodySmall?.copyWith(color: context.palette.ink)),
                  if (safety.conflicts.isNotEmpty)
                    TextButton(onPressed: () => showSubstitutionsSheet(context, base), child: Text(l.chefSeeSubstitutions)),
                ]),
              ),
            ],
            SectionHeader(l.chefIngredients),
            Row(children: [
              Expanded(child: Text(l.chefServings, style: context.text.bodyMedium)),
              IconButton(tooltip: l.chefFewerServings, onPressed: servings > 1 ? () => setState(() => _servings = servings - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$servings', style: context.text.titleLarge), // l10n-ignore
              IconButton(tooltip: l.chefMoreServings, onPressed: servings < 16 ? () => setState(() => _servings = servings + 1) : null, icon: const Icon(Icons.add_circle_outline)),
            ]),
            for (final i in recipe.ingredients)
              _IngredientRow(ingredient: i, check: checkByName[i.name]),
            if (availability.missing.isNotEmpty) ...[
              const SizedBox(height: Space.s),
              _ButtonPair(
                first: SecondaryActionButton(
                    icon: Icons.add_shopping_cart,
                    label: l.chefAddMissingToList(availability.missing.length),
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
                      if (context.mounted) showMessage(context, context.l10n.chefAddedToList);
                    },
                  ),
                second: SecondaryActionButton(icon: Icons.swap_horiz, label: l.chefSubstitutions, onPressed: () => showSubstitutionsSheet(context, base)),
              ),
            ],
            if (wellness?.showNutritionOnRecipes ?? true) ...[
              SectionHeader(l.chefNutrition),
              NutritionSummaryCard(nutrition: recipe.nutritionPerServing, showCalories: true),
            ],
            if (recipe.equipment.isNotEmpty) ...[
              SectionHeader(l.chefEquipment),
              Text(recipe.equipment.join(' · '), style: context.text.bodyMedium),
            ],
            SectionHeader(l.chefMethod),
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
              SectionHeader(l.chefStoring),
              Text(recipe.storageNotes!, style: context.text.bodyMedium),
            ],
            if (isAi && !saved)
              Padding(
                padding: const EdgeInsets.only(top: Space.m),
                child: TextButton.icon(
                  onPressed: () async {
                    await ref.read(recipeRepoProvider).save(ref.read(householdIdProvider)!, base);
                    if (context.mounted) showMessage(context, context.l10n.chefSavedToRecipes);
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(l.chefSaveRecipe),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

/// Two buttons side by side, stacked when the user's text size is large.
class _ButtonPair extends StatelessWidget {
  const _ButtonPair({required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [first, const SizedBox(height: Space.xs), second]);
    }
    return Row(children: [Expanded(child: first), const SizedBox(width: Space.xs), Expanded(child: second)]);
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient, this.check});
  final RecipeIngredient ingredient;
  final IngredientCheck? check;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final short = check?.shortBy;
    final (IconData icon, Color color, String label) = switch (check?.availability) {
      IngredientAvailability.available => (Icons.check_circle, p.success, l.chefInYourKitchenLower),
      IngredientAvailability.partial => (Icons.timelapse, p.warning, short == null ? l.chefNeedMore : l.chefNeedQuantity(context.formatQty(short))),
      IngredientAvailability.missing => (Icons.add_shopping_cart, p.muted, l.chefToBuy),
      _ => (Icons.circle_outlined, p.hairline, ''),
    };
    return Semantics(
      label: '${ingredient.display}${label.isEmpty ? '' : ', $label'}${ingredient.optional ? ', ${l.chefOptional}' : ''}', // l10n-ignore
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.s),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ingredient.optional ? l.chefOptionalIngredient(ingredient.display) : ingredient.display, style: context.text.bodyLarge),
              if (label.isNotEmpty && check?.availability != IngredientAvailability.available) Text(label, style: context.text.bodySmall),
            ]),
          ),
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
    final l = context.l10n;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
          children: [
            Text(l.chefSmartSubstitutions, style: context.text.headlineSmall),
            Text(l.chefSubstitutionsNote, style: context.text.bodySmall),
            const SizedBox(height: Space.m),
            if (rows.isEmpty) EmptyState(compact: true, icon: Icons.swap_horiz, title: l.chefNoSafeSwapsTitle, message: l.chefNoSafeSwapsMessage),
            for (final o in rows)
              Card(
                margin: const EdgeInsets.only(bottom: Space.xs),
                child: Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${o.original.name} → ${o.replacement.display}', style: context.text.titleMedium), // l10n-ignore
                    Text(o.note, style: context.text.bodySmall),
                    const SizedBox(height: Space.xs),
                    Wrap(spacing: Space.xs, children: [
                      if (stock.containsKey(o.replacement.productId)) TagPill(l.chefInYourKitchen, icon: Icons.check, color: context.palette.success, background: context.palette.successSoft),
                      Builder(builder: (context) {
                        final next = finder.apply(recipe, o);
                        final protein = calc.perServing(next)[Nutrient.protein];
                        final diff = protein - baseProtein;
                        return TagPill(l.chefProteinDiff('${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(0)}'));
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
                        child: Text(l.chefUseThis),
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
