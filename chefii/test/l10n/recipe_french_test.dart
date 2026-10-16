import 'package:chefii/domain/catalog/catalog.dart';
import 'package:chefii/domain/recipes/curated_recipes.dart';
import 'package:chefii/domain/recipes/curated_recipes_fr.dart';
import 'package:chefii/domain/recipes/recipe_french.dart';
import 'package:chefii/domain/safety/allergen_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// French recipe content must match the English recipe's shape and, above
/// all, must never hide or add an allergen.
void main() {
  const guard = AllergenGuard();

  test('every curated recipe has a French translation', () {
    expect(curatedFrench.keys.toSet(), curatedById.keys.toSet());
  });

  for (final r in curatedRecipes) {
    test('${r.id}: same shape and same allergens in French', () {
      final fr = curatedFrench[r.id];
      if (fr == null) return; // reported by the coverage test above
      expect(fr.ingredients.length, r.ingredients.length, reason: 'ingredient count');
      expect(fr.steps.length, r.steps.length, reason: 'step count');
      expect(fr.equipment.length, r.equipment.length, reason: 'equipment count');
      expect(fr.title.trim(), isNotEmpty);
      expect(fr.summary.trim(), isNotEmpty);
      for (var i = 0; i < r.ingredients.length; i++) {
        final en = r.ingredients[i];
        final productAllergens = catalogById[en.productId]?.product.allergens ?? const <String>[];
        expect(
          guard.detect(fr.ingredients[i].name, productAllergens: productAllergens),
          guard.detect(en.name, productAllergens: productAllergens),
          reason: '${r.id} ingredient $i: "${en.name}" vs "${fr.ingredients[i].name}"',
        );
      }
      final applied = applyFrench(r, fr);
      expect(applied.title, fr.title, reason: 'shape mismatch made applyFrench fall back to English');
      expect(applied.ingredients.map((i) => i.productId), r.ingredients.map((i) => i.productId));
      expect(applied.ingredients.map((i) => i.quantity), r.ingredients.map((i) => i.quantity));
      expect(applied.steps.map((s) => s.timerSeconds), r.steps.map((s) => s.timerSeconds));
    });
  }
}
