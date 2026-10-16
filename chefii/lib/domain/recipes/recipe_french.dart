import '../models/recipe.dart';

/// Canadian French text for a curated recipe. Lists are parallel to the
/// English recipe (same order, same length) — enforced by
/// test/l10n/recipe_french_test.dart, which also checks that allergen
/// screening finds exactly the same allergens in both languages.
///
/// Only human-readable text is translated. Ids, product ids, quantities,
/// units, timers, tags and nutrition stay as they are.
class RecipeFrench {
  const RecipeFrench({
    required this.title,
    required this.summary,
    required this.cuisine,
    required this.ingredients,
    required this.steps,
    this.equipment = const [],
    this.storageNotes,
  });

  final String title;
  final String summary;
  final String cuisine;
  final List<IngredientFrench> ingredients;
  final List<StepFrench> steps;
  final List<String> equipment;
  final String? storageNotes;
}

class IngredientFrench {
  const IngredientFrench(this.name, [this.preparation]);
  final String name;
  final String? preparation;
}

class StepFrench {
  const StepFrench(this.text, {this.timerLabel, this.tip});
  final String text;
  final String? timerLabel;
  final String? tip;
}

/// Applies [fr] to [r]. Returns [r] unchanged if the shapes don't match, so a
/// partial translation can never drop or misalign an ingredient or step.
Recipe applyFrench(Recipe r, RecipeFrench? fr) {
  if (fr == null || fr.ingredients.length != r.ingredients.length || fr.steps.length != r.steps.length) return r;
  return Recipe(
    id: r.id,
    title: fr.title,
    summary: fr.summary,
    cuisine: fr.cuisine,
    mealTypes: r.mealTypes,
    servings: r.servings,
    prepMinutes: r.prepMinutes,
    cookMinutes: r.cookMinutes,
    difficulty: r.difficulty,
    ingredients: [
      for (var i = 0; i < r.ingredients.length; i++)
        RecipeIngredient(
          name: fr.ingredients[i].name,
          productId: r.ingredients[i].productId,
          nutrientRefId: r.ingredients[i].nutrientRefId,
          quantity: r.ingredients[i].quantity,
          preparation: r.ingredients[i].preparation == null ? null : (fr.ingredients[i].preparation ?? r.ingredients[i].preparation),
          optional: r.ingredients[i].optional,
          bridge: r.ingredients[i].bridge,
        ),
    ],
    steps: [
      for (var i = 0; i < r.steps.length; i++)
        RecipeStep(
          text: fr.steps[i].text,
          timerSeconds: r.steps[i].timerSeconds,
          timerLabel: r.steps[i].timerLabel == null ? null : (fr.steps[i].timerLabel ?? r.steps[i].timerLabel),
          tip: r.steps[i].tip == null ? null : (fr.steps[i].tip ?? r.steps[i].tip),
        ),
    ],
    origin: r.origin,
    tags: r.tags,
    equipment: fr.equipment.length == r.equipment.length ? fr.equipment : r.equipment,
    nutritionPerServing: r.nutritionPerServing,
    imageKey: r.imageKey,
    storageNotes: r.storageNotes == null ? null : (fr.storageNotes ?? r.storageNotes),
    createdAt: r.createdAt,
    aiModel: r.aiModel,
  );
}
