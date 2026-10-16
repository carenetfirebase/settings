import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/recipe_availability.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';
import '../shared/recipe_logic.dart';

// ---------------------------------------------------------------- 53 Discover

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key, this.initialFilter, this.ingredient});
  final String? initialFilter;
  final String? ingredient;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  // Filter ids (also accepted from the ?filter= route parameter); the chips show filterLabel().
  static const filters = ['Available now', 'Breakfast', 'Lunch', 'Dinner', 'Snacks', '15-minute', 'High-protein', 'Vegetarian', 'Comfort', 'World cuisines']; // l10n-ignore

  static String filterLabel(AppLocalizations l, String id) => switch (id) {
        'Available now' => l.discoverFilterAvailableNow,
        'Breakfast' => l.discoverFilterBreakfast,
        'Lunch' => l.discoverFilterLunch,
        'Dinner' => l.discoverFilterDinner,
        'Snacks' => l.discoverFilterSnacks,
        '15-minute' => l.discoverFilter15Minute,
        'High-protein' => l.discoverFilterHighProtein,
        'Vegetarian' => l.discoverFilterVegetarian,
        'Comfort' => l.discoverFilterComfort,
        'World cuisines' => l.discoverFilterWorldCuisines,
        _ => id,
      };
  late String? _filter = widget.initialFilter == 'expiring' ? 'Available now' : (filters.contains(widget.initialFilter) ? widget.initialFilter : null);
  String _query = '';

  bool _matches(AvailabilityReport a) {
    final r = a.recipe;
    if (widget.ingredient != null && !r.ingredients.any((i) => i.productId == widget.ingredient)) return false;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      final hit = r.title.toLowerCase().contains(q) || r.cuisine.toLowerCase().contains(q) || r.ingredients.any((i) => i.name.toLowerCase().contains(q));
      if (!hit) return false;
    }
    return switch (_filter) {
      'Available now' => a.canCookNow || a.score >= 0.75,
      'Breakfast' => r.mealTypes.contains(MealType.breakfast),
      'Lunch' => r.mealTypes.contains(MealType.lunch),
      'Dinner' => r.mealTypes.contains(MealType.dinner),
      'Snacks' => r.mealTypes.contains(MealType.snack),
      '15-minute' => r.tags.contains('15-minute'),
      'High-protein' => r.tags.contains('high-protein'),
      'Vegetarian' => r.tags.contains('vegetarian'),
      'Comfort' => r.tags.contains('comfort'),
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(rankedRecipesProvider((mealType: null, maxMinutes: null, tag: null)));
    final results = all.where(_matches).toList();
    if (widget.initialFilter == 'expiring') results.sort((a, b) => (b.usesExpiringItems ? 1 : 0) - (a.usesExpiringItems ? 1 : 0));
    final favs = ref.watch(favouritesProvider).value ?? const <String>{};
    final showNutrition = ref.watch(wellnessProvider).value?.showNutritionOnRecipes ?? true;
    final ingredientName = widget.ingredient == null ? null : catalogById[widget.ingredient] == null ? null : context.productName(widget.ingredient!, catalogById[widget.ingredient]!.product.name);
    final l = context.l10n;
    final labels = {for (final f in filters) filterLabel(l, f): f};

    Widget card(AvailabilityReport a) => Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: LuxuryRecipeCard(
            recipe: a.recipe,
            availabilityLabel: a.label,
            canCookNow: a.canCookNow,
            showNutrition: showNutrition,
            rationale: a.usesExpiringItems ? l.discoverUsesExpiring : null,
            trailing: favs.contains(a.recipe.id) ? Icon(Icons.favorite, color: context.palette.accent, size: 20) : null,
            onTap: () => context.push('/recipe/${a.recipe.id}'),
          ),
        );

    final byCuisine = <String, List<AvailabilityReport>>{};
    if (_filter == 'World cuisines') {
      for (final a in results) {
        byCuisine.putIfAbsent(a.recipe.cuisine, () => []).add(a);
      }
    }

    return PremiumAppScaffold(
      showBack: widget.ingredient != null || widget.initialFilter != null,
      actions: [
        IconButton(tooltip: l.discoverMealPlanner, onPressed: () => context.push('/plan'), icon: const Icon(Icons.calendar_month_outlined)),
        IconButton(tooltip: l.discoverAskChef, onPressed: () => context.push('/chef'), icon: const Icon(Icons.auto_awesome_outlined)),
      ],
      header: EditorialPageHeader(
        eyebrow: l.discoverEyebrow,
        title: ingredientName == null ? l.discoverTitle : l.discoverCookWith(ingredientName.toLowerCase()),
        subtitle: l.discoverSubtitle,
      ),
      children: [
        SearchFilterBar(
          hint: l.discoverSearchHint,
          onQuery: (q) => setState(() => _query = q),
          filters: labels.keys.toList(),
          selected: _filter == null ? null : filterLabel(l, _filter!),
          onFilter: (f) => setState(() => _filter = f == null ? null : labels[f]),
        ),
        const SizedBox(height: Space.m),
        if (results.isEmpty)
          EmptyState(icon: Icons.search_off, title: l.discoverNoMatchTitle, message: l.discoverNoMatchMessage, actionLabel: l.discoverAskChef, onAction: () => context.push('/chef')),
        if (_filter == 'World cuisines')
          for (final c in (byCuisine.keys.toList()..sort())) ...[
            SectionHeader(c, topSpacing: Space.s),
            for (final a in byCuisine[c]!) card(a),
          ]
        else
          for (final a in results) card(a),
        if (results.isNotEmpty)
          Text(showNutrition ? l.discoverNutritionFootnote(25) : l.discoverNutritionFootnoteHidden(25), style: context.text.bodySmall),
      ],
    );
  }
}

String proteinLabel(AppLocalizations l, Recipe r) => l.discoverProteinLabel(r.nutritionPerServing[Nutrient.protein].round());
