import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/recipe_availability.dart';
import '../../domain/safety/allergen_guard.dart';

/// Main meal for a local time of day.
MealType mealTypeFor(DateTime local) {
  final m = local.hour * 60 + local.minute;
  if (m < 10 * 60 + 30) return MealType.breakfast;
  if (m < 14 * 60 + 30) return MealType.lunch;
  return MealType.dinner;
}

typedef RecipeQuery = ({MealType? mealType, int? maxMinutes, String? tag});

/// Recipes that pass the household's dietary screen, ranked by what's in
/// the kitchen (cookable first, then those rescuing food that's due).
final rankedRecipesProvider = Provider.family<List<AvailabilityReport>, RecipeQuery>((ref, q) {
  if (!ref.watch(householdDietaryLoadedProvider)) return const [];
  final dietary = ref.watch(householdDietaryProvider);
  final lots = ref.watch(lotsProvider).value ?? const [];
  final today = ref.watch(todayProvider);
  const guard = AllergenGuard();
  final pool = ref.watch(allRecipesProvider).where((r) {
    if (q.mealType != null && !r.mealTypes.contains(q.mealType)) return false;
    if (q.maxMinutes != null && r.totalMinutes > q.maxMinutes!) return false;
    if (q.tag != null && !r.tags.contains(q.tag)) return false;
    return !guard.checkRecipe(r, dietary, productAllergens: catalogAllergens).isBlocked;
  });
  return const RecipeAvailability().rank(pool, lots, today: today);
});

/// Safety report for one recipe against the household.
final recipeSafetyProvider = Provider.family<SafetyReport, Recipe>((ref, r) {
  final dietary = ref.watch(householdDietaryProvider);
  return const AllergenGuard().checkRecipe(r, dietary, productAllergens: catalogAllergens);
});

/// [r] if it may be featured for this user: the household diet has loaded
/// and the recipe passes it. Planned recipes need this too, because another
/// member planned them without seeing this user's private allergies.
Recipe? showableRecipe(WidgetRef ref, Recipe? r) {
  if (r == null || !ref.watch(householdDietaryLoadedProvider)) return null;
  return ref.watch(recipeSafetyProvider(r)).isBlocked ? null : r;
}

final recipeAvailabilityProvider = Provider.family<AvailabilityReport, Recipe>((ref, r) {
  final lots = ref.watch(lotsProvider).value ?? const [];
  return const RecipeAvailability().check(r, lots, today: ref.watch(todayProvider));
});
