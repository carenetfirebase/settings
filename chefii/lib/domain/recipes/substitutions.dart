import '../catalog/catalog.dart';
import '../models/profile.dart';
import '../models/recipe.dart';
import '../safety/allergen_guard.dart';

/// A culinary swap between catalogue products with an amount ratio.
class SubstitutionRule {
  const SubstitutionRule(this.toProductId, this.ratio, this.note);
  final String toProductId;
  final double ratio;
  final String note;
}

/// Curated, deterministic swaps. AI may *suggest* others, but every swap is
/// re-checked by [AllergenGuard] before it is offered.
const substitutionRules = <String, List<SubstitutionRule>>{
  'butter': [SubstitutionRule('olive_oil', 0.8, 'Use a little less; best for sautéing, not baking.')],
  'milk': [SubstitutionRule('coconut_milk', 1, 'Richer and dairy-free; adds a gentle coconut note.')],
  'cream': [
    SubstitutionRule('coconut_milk', 1, 'Dairy-free and silky in sauces and soups.'),
    SubstitutionRule('greek_yogurt', 1, 'Stir in off the heat so it doesn\'t split.'),
  ],
  'greek_yogurt': [SubstitutionRule('cream', 0.5, 'Use half as much for richness.')],
  'parmesan': [
    SubstitutionRule('cheddar', 1, 'Aged cheddar gives a similar savoury depth.'),
    SubstitutionRule('feta', 1, 'Saltier and tangier — season carefully.'),
  ],
  'lemon': [SubstitutionRule('lime', 1, 'Bright and slightly more floral.')],
  'lime': [SubstitutionRule('lemon', 1, 'Bright and a touch sweeter.')],
  'spinach': [SubstitutionRule('kale', 1, 'Remove stems and cook a minute or two longer.')],
  'kale': [SubstitutionRule('spinach', 1, 'Wilts in seconds — add at the end.')],
  'rice': [SubstitutionRule('quinoa', 1, 'More protein; cook 15 minutes in twice its volume of water.')],
  'quinoa': [SubstitutionRule('rice', 1, 'Basmati works well; adjust cooking time.')],
  'chickpeas': [SubstitutionRule('black_beans', 1, 'Softer texture, earthier flavour.')],
  'black_beans': [SubstitutionRule('chickpeas', 1, 'Nuttier and firmer.')],
  'salmon': [SubstitutionRule('cod', 1, 'Leaner; shorten cooking by a few minutes.')],
  'cod': [SubstitutionRule('salmon', 1, 'Richer; cook to 70 °C (158 °F).')],
  'chicken_breast': [SubstitutionRule('tofu', 1, 'Press first for a golden crust.')],
  'tofu': [SubstitutionRule('chicken_breast', 1, 'Cook through to 74 °C (165 °F).')],
  'ground_beef': [SubstitutionRule('lentils', 0.45, 'Use dry red lentils and an extra cup of liquid.')],
  'shrimp': [
    SubstitutionRule('chicken_breast', 1, 'Slice thinly; cook through to 74 °C (165 °F).'),
    SubstitutionRule('tofu', 1, 'A plant-based swap; sear until golden.'),
  ],
  'basil': [SubstitutionRule('parsley', 1, 'Fresher, less sweet.')],
  'cilantro': [SubstitutionRule('parsley', 1, 'A good option if cilantro tastes soapy to you.')],
  'parsley': [SubstitutionRule('basil', 1, 'Sweeter and more aromatic.')],
  'honey': [SubstitutionRule('maple_syrup', 1, 'Vegan-friendly; slightly thinner.')],
  'maple_syrup': [SubstitutionRule('honey', 1, 'A touch sweeter and thicker.')],
  'sugar': [SubstitutionRule('maple_syrup', 0.75, 'Reduce other liquid slightly.')],
  'tortilla': [SubstitutionRule('bread', 1, 'Serve as open sandwiches instead.')],
  'almonds': [SubstitutionRule('walnuts', 1, 'Softer, a little bitter.')],
  'walnuts': [SubstitutionRule('almonds', 1, 'Crunchier and milder.')],
  'peanut_butter': [SubstitutionRule('tahini', 1, 'Peanut-free; nuttier and less sweet. Contains sesame.')],
  'tahini': [SubstitutionRule('peanut_butter', 1, 'Sweeter and richer. Contains peanuts.')],
  'sweet_potato': [SubstitutionRule('potato', 1.0, 'Less sweet; similar roasting time.')],
  'potato': [SubstitutionRule('sweet_potato', 1.0, 'Sweeter; roasts a little faster.')],
  'bell_pepper': [SubstitutionRule('zucchini', 1, 'Milder; cook until just tender.')],
  'pasta': [SubstitutionRule('quinoa', 0.8, 'Gluten-free grain bowl instead of pasta.')],
};

class SubstitutionOption {
  const SubstitutionOption({required this.original, required this.replacement, required this.note, required this.safety});

  final RecipeIngredient original;
  final RecipeIngredient replacement;
  final String note;
  final SafetyReport safety;

  bool get isSafe => !safety.isBlocked;
}

class SubstitutionFinder {
  const SubstitutionFinder();

  List<SubstitutionOption> optionsFor(RecipeIngredient ing, DietaryProfile dietary) {
    final pid = ing.productId;
    if (pid == null) return const [];
    const guard = AllergenGuard();
    final out = <SubstitutionOption>[];
    for (final rule in substitutionRules[pid] ?? const <SubstitutionRule>[]) {
      final p = catalogById[rule.toProductId]?.product;
      if (p == null) continue;
      final qty = ing.quantity == null
          ? null
          : (ing.quantity!.tryConvert(p.defaultUnit, p.bridge)?.quantity ?? ing.quantity!) * rule.ratio;
      final replacement = RecipeIngredient(
        name: p.name.toLowerCase(),
        productId: p.id,
        nutrientRefId: p.id,
        quantity: qty,
        preparation: ing.preparation,
        optional: ing.optional,
      );
      out.add(SubstitutionOption(
        original: ing,
        replacement: replacement,
        note: rule.note,
        safety: guard.checkIngredients([(p.name, p.allergens)], dietary),
      ));
    }
    return out;
  }

  /// Returns a copy of [r] with one ingredient replaced. The id records the
  /// change so the modified recipe never overwrites the original.
  Recipe apply(Recipe r, SubstitutionOption o) {
    final next = [for (final i in r.ingredients) identical(i, o.original) || (i.name == o.original.name && i.productId == o.original.productId) ? o.replacement : i];
    final modified = Recipe(
      id: '${r.id}~${o.replacement.productId}',
      title: r.title,
      summary: r.summary,
      cuisine: r.cuisine,
      mealTypes: r.mealTypes,
      servings: r.servings,
      prepMinutes: r.prepMinutes,
      cookMinutes: r.cookMinutes,
      difficulty: r.difficulty,
      ingredients: next,
      steps: r.steps,
      origin: r.origin == RecipeOrigin.curated ? RecipeOrigin.user : r.origin,
      tags: r.tags,
      equipment: r.equipment,
      imageKey: r.imageKey,
      storageNotes: r.storageNotes,
    );
    return modified;
  }
}
