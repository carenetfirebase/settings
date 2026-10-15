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
///
/// Terms are English and Canadian French (labels are bilingual). Matching folds
/// accents, so "crème", "œufs" and "blé" match "creme", "oeuf" and "ble".
/// Every addition should come with a case in test/fixtures/allergen_redteam.json.
const allergens = <AllergenInfo>[
  AllergenInfo('peanut', 'Peanuts', [
    'peanut', 'groundnut', 'arachis', 'satay', 'monkey nut', 'beer nut', 'mixed nuts',
    'arachide', 'cacahuete', "beurre d'arachide",
  ]),
  AllergenInfo('tree_nut', 'Tree nuts', [
    'almond', 'cashew', 'walnut', 'pecan', 'pistachio', 'hazelnut', 'filbert', 'macadamia',
    'brazil nut', 'pine nut', 'pignoli', 'praline', 'marzipan', 'gianduja', 'nutella', 'frangipane',
    'nut', 'nuts', 'pesto', 'nougat', 'chestnut', 'baklava', 'amaretti',
    'amande', 'noix', 'noisette', 'pistache', 'pacane', 'pignon', 'massepain',
  ], exclusions: [
    'nutmeg', 'coconut', 'butternut', 'doughnut', 'water chestnut', 'nut-free', 'nut free',
    'noix de coco', 'noix de muscade', 'beurre noisette', 'sans noix',
  ]),
  AllergenInfo('sesame', 'Sesame', [
    'sesame', 'tahini', 'tahina', 'benne', 'gomasio', 'gomashio', 'halva', 'halvah', "za'atar", 'zaatar',
    'hummus', 'houmous', 'hoummos', 'baba ganoush', 'baba ghanoush', 'furikake', 'dukkah',
  ]),
  AllergenInfo(
    'milk',
    'Milk',
    [
      'milk', 'butter', 'cream', 'cheese', 'yogurt', 'yoghurt', 'yogourt', 'whey', 'casein', 'caseinate', 'ghee',
      'parmesan', 'parmigiano', 'mozzarella', 'ricotta', 'feta', 'burrata', 'creme fraiche', 'kefir',
      'labneh', 'paneer', 'buttermilk', 'mascarpone', 'halloumi', 'brie', 'cheddar', 'gruyere', 'pecorino',
      'goat cheese', 'skyr', 'custard', 'gelato', 'ice cream', 'lactose', 'curd', 'quark', 'half-and-half',
      'dulce de leche', 'queso', 'tzatziki', 'raita', 'bechamel', 'alfredo', 'lassi', 'pesto', 'camembert',
      'gouda', 'emmental', 'provolone', 'bocconcini', 'brioche',
      'lait', 'beurre', 'creme', 'fromage', 'yaourt', 'lactoserum', 'babeurre', 'petit-lait',
    ],
    exclusions: [
      'coconut milk', 'coconut cream', 'almond milk', 'oat milk', 'soy milk', 'soya milk', 'rice milk',
      'cashew milk', 'peanut butter', 'cocoa butter', 'nut butter', 'almond butter', 'butternut',
      'apple butter', 'shea butter', 'cream of tartar', 'dairy-free', 'vegan butter', 'vegan cheese',
      'butter bean', 'butter lettuce', 'bean curd',
      'lait de coco', "lait d'amande", "lait d'avoine", 'lait de soja', 'lait de riz', 'creme de coco',
      'creme de tartre', "beurre d'arachide", 'beurre de cacao', "beurre d'amande", 'sans lactose',
    ],
  ),
  AllergenInfo(
    'egg',
    'Eggs',
    [
      'egg', 'eggs', 'mayonnaise', 'mayo', 'meringue', 'aioli', 'albumen', 'albumin', 'hollandaise', 'bearnaise',
      'custard', 'frittata', 'omelette', 'omelet', 'quiche', 'brioche', 'challah', 'carbonara', 'tartar sauce',
      'eggnog', 'nougat', 'pavlova', 'souffle', 'caesar dressing', 'lemon curd',
      'oeuf', 'oeufs',
    ],
    exclusions: ['eggplant', 'egg-free', 'vegan mayo', 'sans oeuf', 'sans oeufs'],
  ),
  AllergenInfo('fish', 'Fish', [
    'fish', 'salmon', 'tuna', 'cod', 'halibut', 'trout', 'sardine', 'anchovy', 'anchovies', 'mackerel',
    'haddock', 'tilapia', 'sea bass', 'snapper', 'char', 'pollock', 'sole', 'worcestershire', 'bonito',
    'dashi', 'caesar dressing', 'surimi', 'nam pla', 'nuoc mam', 'lox', 'caviar', 'roe', 'herring', 'pickerel',
    'walleye', 'perch', 'pike', 'catfish', 'swordfish', 'mahi', 'kipper', 'bottarga', 'seafood',
    'poisson', 'saumon', 'thon', 'morue', 'fletan', 'truite', 'anchois', 'maquereau', 'aiglefin', 'omble',
    'hareng', 'fruits de mer',
  ], exclusions: ['swiss chard', 'charred', 'char-grilled', 'fish-free']),
  AllergenInfo('shellfish', 'Crustaceans & molluscs', [
    'shrimp', 'prawn', 'crab', 'lobster', 'crayfish', 'crawfish', 'langoustine', 'langostino', 'scampi', 'krill',
    'scallop', 'clam', 'mussel', 'oyster', 'squid', 'calamari', 'octopus', 'shellfish', 'oyster sauce',
    'abalone', 'cockle', 'whelk', 'snail', 'escargot', 'conch', 'xo sauce', 'shrimp paste', 'seafood',
    'crevette', 'homard', 'crabe', 'petoncle', 'palourde', 'moule', 'huitre', 'calmar', 'pieuvre', 'poulpe',
    'langouste', 'ecrevisse', 'fruits de mer',
  ], exclusions: ['oyster mushroom', 'pleurote']),
  AllergenInfo('soy', 'Soy', [
    'soy', 'soya', 'tofu', 'edamame', 'miso', 'tempeh', 'tamari', 'shoyu', 'lecithin', 'natto', 'yuba',
    'textured vegetable protein', 'tvp', 'hoisin', 'teriyaki', 'ponzu', 'gochujang', 'doenjang', 'black bean sauce',
    'bean curd', 'soja', 'lecithine',
  ], exclusions: ['soy-free', 'sans soja']),
  AllergenInfo(
    'wheat',
    'Wheat & triticale',
    [
      'wheat', 'flour', 'bread', 'pasta', 'spaghetti', 'linguine', 'penne', 'fettuccine', 'noodle', 'couscous',
      'bulgur', 'semolina', 'farro', 'spelt', 'seitan', 'panko', 'breadcrumb', 'tortilla', 'soy sauce',
      'triticale', 'pita', 'naan', 'baguette', 'croissant', 'brioche', 'orzo', 'gnocchi', 'udon', 'ramen',
      'cracker', 'biscuit', 'cake', 'cupcake', 'cookie', 'muffin', 'bagel', 'roux', 'dumpling', 'wonton',
      'lasagna', 'lasagne', 'macaroni', 'ravioli', 'tortellini', 'rigatoni', 'fusilli', 'tagliatelle',
      'pappardelle', 'farfalle', 'ziti', 'vermicelli', 'pastry', 'phyllo', 'filo', 'crouton', 'pancake',
      'waffle', 'durum', 'einkorn', 'emmer', 'kamut', 'freekeh', 'graham', 'matzo', 'matzah', 'bran',
      'wheat germ', 'hoisin', 'teriyaki', 'gochujang', 'roti', 'chapati', 'paratha', 'bao', 'soba', 'dough',
      'sourdough', 'pizza', 'flatbread', 'shortbread', 'cornbread', 'gingerbread', 'wholewheat', 'stuffing',
      'pretzel', 'crumpet', 'scone', 'tempura', 'batter', 'seitan', 'beer',
      'ble', 'farine', 'pain', 'pate', 'nouille', 'semoule', 'chapelure', 'epeautre', 'biscuit', 'gateau',
    ],
    exclusions: [
      'almond flour', 'rice flour', 'coconut flour', 'chickpea flour', 'oat flour', 'corn tortilla',
      'rice noodle', 'rice vermicelli', 'gluten-free', 'buckwheat', 'tamari', 'cassava flour', 'corn flour',
      'cornflour', 'potato flour', 'tapioca flour', 'rice paper', 'oat bran', 'rice bran',
      'farine de riz', "farine d'amande", 'farine de noix de coco', 'farine de pois chiche', 'farine de mais',
      'farine de sarrasin', 'ble noir', 'sarrasin', 'nouilles de riz', 'sans gluten',
    ],
  ),
  AllergenInfo('mustard', 'Mustard', ['mustard', 'dijon', 'moutarde']),
  AllergenInfo('sulphites', 'Sulphites', [
    'sulphite', 'sulfite', 'metabisulphite', 'metabisulfite', 'wine', 'dried apricot', 'dried fruit', 'raisin',
    'balsamic', 'vin', 'abricots secs', 'fruits secs',
  ]),
  AllergenInfo('gluten', 'Gluten (wheat, barley, rye, oats)', [
    'wheat', 'flour', 'bread', 'pasta', 'spaghetti', 'noodle', 'couscous', 'bulgur', 'semolina', 'farro',
    'spelt', 'seitan', 'panko', 'breadcrumb', 'barley', 'rye', 'malt', 'triticale', 'oat', 'oats', 'oatmeal',
    'beer', 'soy sauce', 'orzo', 'gnocchi', 'udon', 'ramen', 'pita', 'naan', 'tortilla', 'granola', 'muesli',
    'pumpernickel', "brewer's yeast",
    'orge', 'seigle', 'avoine', 'biere',
  ], exclusions: [
    'gluten-free', 'buckwheat', 'rice flour', 'almond flour', 'coconut flour', 'chickpea flour',
    'corn tortilla', 'rice noodle', 'tamari', 'cassava flour', 'corn flour', 'cornflour', 'sans gluten',
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

const _porkTerms = [
  'pork', 'bacon', 'ham', 'prosciutto', 'pancetta', 'lard', 'chorizo', 'guanciale', 'salami', 'pepperoni',
  'porc', 'jambon', 'lardon', 'saucisson',
];
const _alcoholTerms = [
  'wine', 'beer', 'rum', 'brandy', 'vodka', 'sake', 'mirin', 'sherry', 'bourbon', 'liqueur', 'cognac', 'whisky',
  'whiskey', 'gin', 'tequila', 'vin', 'biere', 'rhum',
];
const _meatTerms = [
  ..._porkTerms, 'beef', 'steak', 'sausage', 'chicken', 'turkey', 'duck', 'lamb', 'veal', 'venison', 'gelatin',
  'gelatine', 'mince', 'meatball', 'bone broth', 'chicken stock', 'beef stock', 'chicken broth', 'beef broth',
  'boeuf', 'poulet', 'dinde', 'canard', 'agneau', 'veau', 'saucisse', 'bouillon de poulet', 'bouillon de boeuf',
];
const _meatExclusions = ['plant-based', 'vegetable stock', 'vegetable broth', 'mushroom bacon', 'vegan sausage'];

const restrictions = <DietaryRestriction>[
  DietaryRestriction('vegetarian', 'Vegetarian', ['fish', 'shellfish'], _meatTerms, exclusions: _meatExclusions),
  DietaryRestriction('vegan', 'Vegan', ['fish', 'shellfish', 'milk', 'egg'], [..._meatTerms, 'honey', 'miel'],
      exclusions: _meatExclusions),
  DietaryRestriction('pescatarian', 'Pescatarian', [], _meatTerms, exclusions: _meatExclusions),
  DietaryRestriction('halal', 'Halal', [], [..._porkTerms, ..._alcoholTerms, 'gelatin', 'gelatine']),
  DietaryRestriction('kosher_style', 'Kosher-style', ['shellfish'], _porkTerms),
  DietaryRestriction('no_pork', 'No pork', [], _porkTerms),
  DietaryRestriction('no_alcohol', 'No alcohol', [], _alcoholTerms),
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

  /// Lower-case, fold accents and ligatures, keep letters, digits, apostrophes
  /// and hyphens, collapse spaces, and pad with spaces for boundary matching.
  static String normalise(String s) {
    final folded = s.toLowerCase().split('').map((c) => _fold[c] ?? c).join();
    return ' ${folded.replaceAll(RegExp(r"[’‘`]"), "'").replaceAll(RegExp(r"[^a-z0-9'\- ]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  }

  static String _normalise(String s) => normalise(s);

  static const _fold = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ÿ': 'y', 'æ': 'ae', 'œ': 'oe', 'ß': 'ss',
  };

  /// Whole-word (simple plural allowed) match of any term, after removing
  /// exclusion phrases. Exclusions are also removed only at word boundaries,
  /// so "oat milk" never erases part of "goat milk".
  static bool _containsAny(String normalisedText, List<String> terms, List<String> exclusions) {
    var text = normalisedText;
    for (final ex in exclusions) {
      text = text.replaceAllMapped(_wordPattern(ex), (m) => '${m[1]} ');
    }
    for (final t in terms) {
      if (_wordPattern(t).hasMatch(text)) return true;
    }
    return false;
  }

  static final Map<String, RegExp> _patterns = {};

  static RegExp _wordPattern(String term) => _patterns.putIfAbsent(term, () {
        final t = normalise(term).trim();
        return RegExp('(^|[^a-z])${RegExp.escape(t)}(?:s|es)?(?=[^a-z]|\$)');
      });
}
