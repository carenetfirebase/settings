import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/recipe_availability.dart';
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
  static const filters = ['Available now', 'Breakfast', 'Lunch', 'Dinner', 'Snacks', '15-minute', 'High-protein', 'Vegetarian', 'Comfort', 'World cuisines'];
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
    final ingredientName = widget.ingredient == null ? null : catalogById[widget.ingredient]?.product.name;

    Widget card(AvailabilityReport a) => Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: LuxuryRecipeCard(
            recipe: a.recipe,
            availabilityLabel: a.label,
            canCookNow: a.canCookNow,
            showNutrition: showNutrition,
            rationale: a.usesExpiringItems ? 'Uses something that needs eating soon' : null,
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
        IconButton(tooltip: 'Meal planner', onPressed: () => context.push('/plan'), icon: const Icon(Icons.calendar_month_outlined)),
        IconButton(tooltip: 'Ask the chef', onPressed: () => context.push('/chef'), icon: const Icon(Icons.auto_awesome_outlined)),
      ],
      header: EditorialPageHeader(
        eyebrow: 'Discover',
        title: ingredientName == null ? 'Something delicious' : 'Cook with ${ingredientName.toLowerCase()}',
        subtitle: 'Every recipe here suits your household\'s dietary needs.',
      ),
      children: [
        SearchFilterBar(hint: 'Search recipes or ingredients', onQuery: (q) => setState(() => _query = q), filters: filters, selected: _filter, onFilter: (f) => setState(() => _filter = f)),
        const SizedBox(height: Space.m),
        if (results.isEmpty)
          EmptyState(icon: Icons.search_off, title: 'No recipes match', message: 'Try another filter, or ask your chef to create something.', actionLabel: 'Ask the chef', onAction: () => context.push('/chef')),
        if (_filter == 'World cuisines')
          for (final c in (byCuisine.keys.toList()..sort())) ...[
            SectionHeader(c, topSpacing: Space.s),
            for (final a in byCuisine[c]!) card(a),
          ]
        else
          for (final a in results) card(a),
        if (results.isNotEmpty)
          Text('Nutrition is estimated per serving from reference data${showNutrition ? '' : ' (hidden in your preferences)'}. Protein-rich means at least ${25} g per serving.',
              style: context.text.bodySmall),
      ],
    );
  }
}

String proteinLabel(Recipe r) => '${r.nutritionPerServing[Nutrient.protein].round()} g protein';
