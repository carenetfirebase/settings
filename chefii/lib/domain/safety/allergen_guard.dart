import '../models/profile.dart';
import '../models/recipe.dart';

/// Deterministic dietary-safety screening.
///
/// Every recipe shown to a user — curated, AI-generated or substituted — goes
/// through this guard. AI output is never trusted to have respected allergies
/// on its own. The guard is intentionally conservative: false positives
/// (flagging something safe) are acceptable; false negatives are not.
///
/// This is a screening aid, not a guarantee. Packaged products can contain
/// allergens not implied by their names, so the UI always reminds users to
/// check labels. A mirror of this lexicon runs server-side
/// (functions/src/safety/allergens.ts); keep them in sync.
class AllergenInfo {
  const AllergenInfo(this.key, this.label, this.terms, {this.exclusions = const []});

  final String key;
  final String label;
  final List<String> terms;

  /// Phrases that contain a term but are not the allergen ("coconut milk").
  final List<String> exclusions;
}

/// Health Canada's priority food allergens, plus gluten sources.
const allergens = <AllergenInfo>[
  AllergenInfo('peanut', 'Peanuts', ['peanut', 'groundnut', 'arachis', 'satay']),
  AllergenInfo('tree_nut', 'Tree nuts', [
    'almond', 'cashew', 'walnut', 'pecan', 'pistachio', 'hazelnut', 'filbert', 'macadamia',
    'brazil nut', 'pine nut', 'pignoli', 'praline', 'marzipan', 'gianduja', 'nutella', 'frangipane',
  ]),
  AllergenInfo('sesame', 'Sesame', ['sesame', 'tahini', 'benne', 'gomasio', 'halva', 'halvah', 'za\'atar', 'zaatar']),
  AllergenInfo(
    'milk',
    'Milk',
    [
      'milk', 'butter', 'cream', 'cheese', 'yogurt', 'yoghurt', 'whey', 'casein', 'ghee', 'parmesan',
      'parmigiano', 'mozzarella', 'ricotta', 'feta', 'burrata', 'creme fraiche', 'crème fraîche', 'kefir',
      'labneh', 'paneer', 'buttermilk', 'mascarpone', 'halloumi', 'brie', 'cheddar', 'gruyere', 'gruyère', 'pecorino',
      'goat cheese', 'skyr', 'custard', 'gelato', 'ice cream', 'lactose',
    ],
    exclusions: [
      'coconut milk', 'coconut cream', 'almond milk', 'oat milk', 'soy milk', 'soya milk', 'rice milk',
      'cashew milk', 'peanut butter', 'cocoa butter', 'nut butter', 'almond butter', 'butternut',
      'apple butter', 'shea butter', 'cream of tartar', 'dairy-free', 'vegan butter', 'vegan cheese',
      'butter bean', 'butter lettuce',
    ],
  ),
  AllergenInfo(
    'egg',
    'Eggs',
    ['egg', 'eggs', 'mayonnaise', 'mayo', 'meringue', 'aioli', 'albumen', 'hollandaise', 'custard'],
    exclusions: ['eggplant', 'egg-free', 'vegan mayo'],
  ),
  AllergenInfo('fish', 'Fish', [
    'fish', 'salmon', 'tuna', 'cod', 'halibut', 'trout', 'sardine', 'anchovy', 'anchovies', 'mackerel',
    'haddock', 'tilapia', 'sea bass', 'snapper', 'char', 'pollock', 'sole', 'worcestershire', 'bonito',
    'dashi', 'caesar dressing',
  ], exclusions: ['swiss chard', 'charred', 'char-grilled']),
  AllergenInfo('shellfish', 'Crustaceans & molluscs', [
    'shrimp', 'prawn', 'crab', 'lobster', 'crayfish', 'langoustine', 'scallop', 'clam', 'mussel', 'oyster',
    'squid', 'calamari', 'octopus', 'shellfish', 'oyster sauce',
  ], exclusions: ['oyster mushroom']),
  AllergenInfo('soy', 'Soy', ['soy', 'soya', 'tofu', 'edamame', 'miso', 'tempeh', 'tamari', 'shoyu']),
  AllergenInfo(
    'wheat',
    'Wheat & triticale',
    [
      'wheat', 'flour', 'bread', 'pasta', 'spaghetti', 'linguine', 'penne', 'fettuccine', 'noodle', 'couscous',
      'bulgur', 'semolina', 'farro', 'spelt', 'seitan', 'panko', 'breadcrumb', 'tortilla', 'soy sauce',
      'triticale', 'pita', 'naan', 'baguette', 'croissant', 'brioche', 'orzo', 'gnocchi', 'udon', 'ramen',
    ],
    exclusions: [
      'almond flour', 'rice flour', 'coconut flour', 'chickpea flour', 'oat flour', 'corn tortilla',
      'rice noodle', 'gluten-free', 'buckwheat', 'tamari', 'cassava flour', 'corn flour', 'cornflour',
    ],
  ),
  AllergenInfo('mustard', 'Mustard', ['mustard', 'dijon']),
  AllergenInfo('sulphites', 'Sulphites', ['sulphite', 'sulfite', 'wine', 'dried apricot', 'dried fruit']),
  AllergenInfo('gluten', 'Gluten (wheat, barley, rye, oats)', [
    'wheat', 'flour', 'bread', 'pasta', 'spaghetti', 'noodle', 'couscous', 'bulgur', 'semolina', 'farro',
    'spelt', 'seitan', 'panko', 'breadcrumb', 'barley', 'rye', 'malt', 'triticale', 'oat', 'beer', 'soy sauce',
    'orzo', 'gnocchi', 'udon', 'ramen', 'pita', 'naan', 'tortilla',
  ], exclusions: [
    'gluten-free', 'buckwheat', 'rice flour', 'almond flour', 'coconut flour', 'chickpea flour',
    'corn tortilla', 'rice noodle', 'tamari', 'cassava flour', 'corn flour', 'cornflour',
  ]),
];

/// Intolerances map onto allergen lexicons with a softer severity.
const intoleranceToAllergen = {'lactose': 'milk', 'gluten': 'gluten', 'egg': 'egg', 'soy': 'soy'};

const intoleranceLabels = {'lactose': 'Lactose', 'gluten': 'Gluten', 'egg': 'Eggs', 'soy': 'Soy'};

class DietaryRestriction {
  const DietaryRestriction(this.key, this.label, this.excludedAllergens, this.excludedTerms,
      {this.exclusions = const []});

  final String key;
  final String label;
  final List<String> excludedAllergens;
  final List<String> excludedTerms;
  final List<String> exclusions;
}

const _meatTerms = [
  'beef', 'steak', 'pork', 'bacon', 'ham', 'prosciutto', 'pancetta', 'chorizo', 'salami', 'sausage',
  'chicken', 'turkey', 'duck', 'lamb', 'veal', 'venison', 'gelatin', 'gelatine', 'lard', 'mince',
  'meatball', 'pepperoni', 'guanciale', 'bone broth', 'chicken stock', 'beef stock', 'chicken broth',
  'beef broth',
];
const _meatExclusions = ['plant-based', 'vegetable stock', 'vegetable broth', 'mushroom bacon', 'vegan sausage'];

const restrictions = <DietaryRestriction>[
  DietaryRestriction('vegetarian', 'Vegetarian', ['fish', 'shellfish'], _meatTerms, exclusions: _meatExclusions),
  DietaryRestriction('vegan', 'Vegan', ['fish', 'shellfish', 'milk', 'egg'], [..._meatTerms, 'honey'],
      exclusions: _meatExclusions),
  DietaryRestriction('pescatarian', 'Pescatarian', [], _meatTerms, exclusions: _meatExclusions),
  DietaryRestriction('halal', 'Halal', [], ['pork', 'bacon', 'ham', 'prosciutto', 'pancetta', 'lard', 'gelatin', 'gelatine', 'wine', 'beer', 'rum', 'brandy', 'chorizo', 'salami', 'pepperoni', 'guanciale']),
  DietaryRestriction('kosher_style', 'Kosher-style', ['shellfish'], ['pork', 'bacon', 'ham', 'prosciutto', 'pancetta', 'lard', 'chorizo', 'guanciale']),
  DietaryRestriction('no_pork', 'No pork', [], ['pork', 'bacon', 'ham', 'prosciutto', 'pancetta', 'lard', 'chorizo', 'guanciale', 'salami', 'pepperoni']),
  DietaryRestriction('no_alcohol', 'No alcohol', [], ['wine', 'beer', 'rum', 'brandy', 'vodka', 'sake', 'mirin', 'sherry', 'bourbon', 'liqueur', 'cognac']),
  DietaryRestriction('gluten_free', 'Gluten-free', ['gluten'], []),
  DietaryRestriction('dairy_free', 'Dairy-free', ['milk'], []),
];

enum ConflictSeverity { allergy, intolerance, restriction, dislike }

class DietaryConflict {
  const DietaryConflict({required this.ingredient, required this.reason, required this.severity, required this.key});

  final String ingredient;
  final String reason;
  final ConflictSeverity severity;
  final String key;

  bool get isBlocking => severity == ConflictSeverity.allergy || severity == ConflictSeverity.restriction;
}

class SafetyReport {
  const SafetyReport({required this.conflicts, required this.notices});

  final List<DietaryConflict> conflicts;

  /// Informational notices (unknown allergy status, cross-contact reminder).
  final List<String> notices;

  bool get isBlocked => conflicts.any((c) => c.isBlocking);
  bool get hasWarnings => conflicts.isNotEmpty;
  Iterable<DietaryConflict> get blocking => conflicts.where((c) => c.isBlocking);
}

class AllergenGuard {
  const AllergenGuard();

  static final Map<String, AllergenInfo> byKey = {for (final a in allergens) a.key: a};
  static final Map<String, DietaryRestriction> restrictionByKey = {for (final r in restrictions) r.key: r};

  /// Allergen keys detected in a free-text ingredient name.
  Set<String> detect(String ingredientText, {List<String> productAllergens = const []}) {
    final text = _normalise(ingredientText);
    final found = <String>{...productAllergens};
    for (final a in allergens) {
      if (_containsAny(text, a.terms, a.exclusions)) found.add(a.key);
    }
    // Gluten is implied by wheat.
    if (found.contains('wheat')) found.add('gluten');
    return found;
  }

  SafetyReport checkRecipe(Recipe recipe, DietaryProfile profile, {Map<String, List<String>> productAllergens = const {}}) =>
      checkIngredients(
        recipe.ingredients.map((i) => (i.name, productAllergens[i.productId] ?? const <String>[])).toList(),
        profile,
      );

  SafetyReport checkIngredients(List<(String, List<String>)> ingredients, DietaryProfile profile) {
    final conflicts = <DietaryConflict>[];
    final notices = <String>[];

    if (!profile.allergiesKnown) {
      notices.add('You haven\'t told us about allergies yet, so we can\'t screen for them.');
    }
    if (profile.avoidCrossContact && profile.allergies.isNotEmpty) {
      notices.add('Check labels for "may contain" warnings and use clean equipment.');
    }

    for (final (name, productTags) in ingredients) {
      final detected = detect(name, productAllergens: productTags);
      final text = _normalise(name);
      for (final key in profile.allergies) {
        if (detected.contains(key)) {
          conflicts.add(DietaryConflict(
            ingredient: name,
            reason: 'Contains ${byKey[key]?.label ?? key}',
            severity: ConflictSeverity.allergy,
            key: key,
          ));
        }
      }
      for (final key in profile.intolerances) {
        final allergen = intoleranceToAllergen[key];
        if (allergen != null && detected.contains(allergen)) {
          conflicts.add(DietaryConflict(
            ingredient: name,
            reason: 'May not suit your ${intoleranceLabels[key] ?? key} intolerance',
            severity: ConflictSeverity.intolerance,
            key: key,
          ));
        }
      }
      for (final key in profile.restrictions) {
        final r = restrictionByKey[key];
        if (r == null) continue;
        final hitsAllergen = r.excludedAllergens.any(detected.contains);
        final hitsTerm = _containsAny(text, r.excludedTerms, r.exclusions);
        if (hitsAllergen || hitsTerm) {
          conflicts.add(DietaryConflict(
            ingredient: name,
            reason: 'Not ${r.label.toLowerCase()}',
            severity: ConflictSeverity.restriction,
            key: key,
          ));
        }
      }
      for (final dislike in profile.dislikes) {
        final d = _normalise(dislike).trim();
        if (d.isNotEmpty && _containsAny(text, [d], const [])) {
          conflicts.add(DietaryConflict(
            ingredient: name,
            reason: 'You prefer to avoid $dislike',
            severity: ConflictSeverity.dislike,
            key: dislike,
          ));
        }
      }
    }
    return SafetyReport(conflicts: conflicts, notices: notices);
  }

  static String _normalise(String s) => ' ${s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9àâçéèêëîïôûùüÿñæœ'\- ]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';

  static bool _containsAny(String normalisedText, List<String> terms, List<String> exclusions) {
    var text = normalisedText;
    for (final ex in exclusions) {
      text = text.replaceAll(ex.toLowerCase(), ' ');
    }
    for (final t in terms) {
      final term = t.toLowerCase();
      // Word-start match, allowing simple plurals ("almonds", "noodles").
      final re = RegExp('(^|[^a-z])${RegExp.escape(term)}(s|es)?([^a-z]|\$)');
      if (re.hasMatch(text)) return true;
    }
    return false;
  }
}
