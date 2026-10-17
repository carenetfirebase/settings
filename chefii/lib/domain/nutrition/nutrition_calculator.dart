import '../catalog/catalog.dart';
import '../models/nutrition.dart';
import '../models/recipe.dart';
import '../units/units.dart';

/// Estimates nutrition from ingredient quantities and reference data.
///
/// Ingredients without reference data, or whose amount cannot be converted to
/// grams, reduce [NutrientProfile.completeness] instead of being guessed.
class NutritionCalculator {
  const NutritionCalculator({Map<String, NutrientReference>? references}) : _refs = references;

  final Map<String, NutrientReference>? _refs;
  Map<String, NutrientReference> get refs => _refs ?? nutrientReferences;

  /// Grams for an ingredient, or null if unknown.
  double? gramsFor(RecipeIngredient i) {
    final q = i.quantity;
    if (q == null) return null;
    final bridge = _bridgeFor(i);
    return q.tryConvert(Unit.g, bridge)?.quantity.amount;
  }

  UnitBridge _bridgeFor(RecipeIngredient i) {
    if (i.bridge.gramsPerMl != null || i.bridge.gramsPerPiece != null) return i.bridge;
    final id = i.productId ?? i.nutrientRefId;
    return id == null ? UnitBridge.none : (catalogById[id]?.product.bridge ?? UnitBridge.none);
  }

  /// Total nutrients for the full ingredient list.
  NutrientProfile total(List<RecipeIngredient> ingredients) {
    final out = <Nutrient, double>{};
    var counted = 0;
    var considered = 0;
    for (final i in ingredients) {
      if (i.quantity == null) continue; // "to taste": negligible, not counted
      considered++;
      final ref = refs[i.nutrientRefId ?? i.productId];
      final grams = gramsFor(i);
      if (ref == null || grams == null) continue;
      counted++;
      ref.per100g.values.forEach((n, v) => out[n] = (out[n] ?? 0) + v * grams / 100);
    }
    return NutrientProfile(out, completeness: considered == 0 ? 0 : counted / considered);
  }

  NutrientProfile perServing(Recipe r) {
    final t = total(r.ingredients);
    return t.scale(1 / (r.servings <= 0 ? 1 : r.servings));
  }

  /// Returns the recipe with freshly computed per-serving nutrition.
  Recipe withNutrition(Recipe r) => r.withIngredients(r.ingredients, nutrition: perServing(r));
}
