import '../models/inventory.dart';
import '../models/nutrition.dart';
import '../units/units.dart';
import 'catalog_fr.dart';

/// Built-in starter catalogue.
///
/// Nutrient values are per 100 g, rounded from USDA FoodData Central
/// (SR Legacy / Foundation Foods). They are reference *estimates*; real
/// products vary. Shelf-life values are typical quality windows from common
/// food-storage guidance and are only ever shown as estimates — never as a
/// safety determination. Before launch, a registered dietitian should review
/// this table (see docs/CLINICAL_SAFETY.md).
const _src = 'USDA FoodData Central, rounded';

class CatalogEntry {
  const CatalogEntry(this.product, this.nutrients);
  final FoodProduct product;

  /// [kcal, protein, carbs, fat, fibre, sugars, sodium mg, saturated fat]
  final List<double> nutrients;

  NutrientReference get reference => NutrientReference(
        id: product.id,
        name: product.name,
        source: _src,
        per100g: NutrientProfile({
          Nutrient.energyKcal: nutrients[0],
          Nutrient.protein: nutrients[1],
          Nutrient.carbohydrate: nutrients[2],
          Nutrient.fat: nutrients[3],
          Nutrient.fibre: nutrients[4],
          Nutrient.sugars: nutrients[5],
          Nutrient.sodium: nutrients[6],
          Nutrient.saturatedFat: nutrients[7],
        }),
      );
}

CatalogEntry _e(
  String id,
  String name,
  FoodCategory cat,
  Unit unit,
  StorageKind storage,
  List<double> n, {
  double? perPiece,
  double? perMl,
  int? shelf,
  List<String> allergens = const [],
  List<String> aliases = const [],
  Quantity? lowStock,
}) =>
    CatalogEntry(
      FoodProduct(
        id: id,
        name: name,
        category: cat,
        defaultUnit: unit,
        defaultStorage: storage,
        bridge: UnitBridge(gramsPerPiece: perPiece, gramsPerMl: perMl),
        typicalShelfLifeDays: shelf,
        allergens: allergens,
        // French names and receipt spellings match too (Québec receipts, voice).
        aliases: [...aliases, if (catalogFrench[id] case final fr?) ...[fr.name, ...fr.aliases]],
        nutrientRefId: id,
        lowStockThreshold: lowStock,
      ),
      n,
    );

const _f = StorageKind.fridge;
const _z = StorageKind.freezer;
const _p = StorageKind.pantry;

final List<CatalogEntry> catalog = [
  // Dairy & eggs
  _e('egg', 'Eggs', FoodCategory.dairy, Unit.piece, _f, [143, 12.6, 0.7, 9.5, 0, 0.4, 142, 3.1],
      perPiece: 50, shelf: 28, allergens: ['egg'], aliases: ['lg eggs', 'large eggs', 'eggs dozen', 'omega 3 eggs', 'free run eggs'], lowStock: const Quantity(3, Unit.piece)),
  _e('milk', 'Milk (2%)', FoodCategory.dairy, Unit.ml, _f, [50, 3.3, 4.8, 2.0, 0, 5.1, 44, 1.3],
      perMl: 1.03, shelf: 10, allergens: ['milk'], aliases: ['mlk 2%', '2% milk', 'milk 2 pct', 'partly skimmed milk'], lowStock: const Quantity(500, Unit.ml)),
  _e('butter', 'Butter', FoodCategory.dairy, Unit.g, _f, [717, 0.9, 0.1, 81, 0, 0.1, 11, 51],
      perMl: 0.91, shelf: 60, allergens: ['milk'], aliases: ['unsalted butter', 'salted butter', 'btr']),
  _e('greek_yogurt', 'Greek yogurt', FoodCategory.dairy, Unit.g, _f, [73, 9.9, 3.9, 2.0, 0, 3.6, 34, 1.3],
      perMl: 1.05, shelf: 14, allergens: ['milk'], aliases: ['greek yog', 'plain greek yogurt', 'yogurt greek 2%']),
  _e('cheddar', 'Aged cheddar', FoodCategory.dairy, Unit.g, _f, [403, 24.9, 1.3, 33.1, 0, 0.5, 621, 21],
      shelf: 30, allergens: ['milk'], aliases: ['old cheddar', 'chdr', 'cheddar cheese']),
  _e('parmesan', 'Parmigiano Reggiano', FoodCategory.dairy, Unit.g, _f, [431, 38, 4.1, 29, 0, 0.9, 1529, 19],
      shelf: 60, allergens: ['milk'], aliases: ['parmesan', 'parm reg', 'parmigiano']),
  _e('feta', 'Feta', FoodCategory.dairy, Unit.g, _f, [264, 14.2, 4.1, 21.3, 0, 4.1, 1116, 14.9],
      shelf: 21, allergens: ['milk'], aliases: ['feta cheese']),
  _e('ricotta', 'Ricotta', FoodCategory.dairy, Unit.g, _f, [174, 11.3, 3.0, 13.0, 0, 0.3, 84, 8.3],
      shelf: 7, allergens: ['milk']),
  _e('cream', 'Whipping cream (35%)', FoodCategory.dairy, Unit.ml, _f, [340, 2.8, 2.7, 36, 0, 2.9, 27, 23],
      perMl: 1.0, shelf: 10, allergens: ['milk'], aliases: ['whip cream 35', 'heavy cream', 'whipping cream']),
  // Meat & seafood
  _e('chicken_breast', 'Chicken breast', FoodCategory.meat, Unit.g, _f, [120, 22.5, 0, 2.6, 0, 0, 45, 0.6],
      perPiece: 200, shelf: 2, aliases: ['bnls sknls chkn brst', 'chicken breast boneless', 'chkn brst']),
  _e('ground_beef', 'Lean ground beef', FoodCategory.meat, Unit.g, _f, [215, 18.6, 0, 15, 0, 0, 66, 5.9],
      shelf: 2, aliases: ['lean grnd beef', 'ground beef lean', 'grd beef']),
  _e('salmon', 'Salmon fillet', FoodCategory.seafood, Unit.g, _f, [208, 20.4, 0, 13.4, 0, 0, 59, 3.1],
      perPiece: 150, shelf: 2, allergens: ['fish'], aliases: ['atl salmon fillet', 'salmon portions', 'salmon fil']),
  _e('shrimp', 'Shrimp', FoodCategory.seafood, Unit.g, _z, [85, 20.1, 0, 0.5, 0, 0, 119, 0.1],
      shelf: 90, allergens: ['shellfish'], aliases: ['frz shrimp', 'raw shrimp', 'shrimp 31/40']),
  _e('cod', 'Cod fillet', FoodCategory.seafood, Unit.g, _f, [82, 17.8, 0, 0.7, 0, 0, 54, 0.1],
      perPiece: 150, shelf: 2, allergens: ['fish']),
  _e('smoked_salmon', 'Smoked salmon', FoodCategory.seafood, Unit.g, _f, [117, 18.3, 0, 4.3, 0, 0, 2000, 0.9],
      shelf: 10, allergens: ['fish'], aliases: ['smkd salmon', 'lox']),
  // Plant proteins & legumes
  _e('tofu', 'Firm tofu', FoodCategory.pantry, Unit.g, _f, [144, 17.3, 2.8, 8.7, 2.3, 0.6, 14, 1.3],
      shelf: 14, allergens: ['soy'], aliases: ['tofu firm', 'extra firm tofu']),
  _e('chickpeas', 'Chickpeas (cooked)', FoodCategory.pantry, Unit.g, _p, [164, 8.9, 27.4, 2.6, 7.6, 4.8, 7, 0.3],
      shelf: 730, aliases: ['chick peas', 'garbanzo', 'chickpeas 540ml']),
  _e('black_beans', 'Black beans (cooked)', FoodCategory.pantry, Unit.g, _p, [132, 8.9, 23.7, 0.5, 8.7, 0.3, 1, 0.1],
      shelf: 730, aliases: ['blk beans', 'black beans 540ml']),
  _e('lentils', 'Red lentils (dry)', FoodCategory.grains, Unit.g, _p, [358, 24, 63, 2.2, 10.8, 1.5, 7, 0.3],
      shelf: 365, aliases: ['red lentils', 'split red lentils']),
  // Grains
  _e('rice', 'Basmati rice', FoodCategory.grains, Unit.g, _p, [365, 7.1, 80, 0.7, 1.3, 0.1, 5, 0.2],
      perMl: 0.85, shelf: 730, aliases: ['basmati', 'white rice', 'jasmine rice']),
  _e('pasta', 'Dried pasta', FoodCategory.grains, Unit.g, _p, [371, 13, 74.7, 1.5, 3.2, 2.7, 6, 0.3],
      shelf: 730, allergens: ['wheat', 'gluten'], aliases: ['spaghetti', 'penne', 'linguine', 'rigatoni']),
  _e('oats', 'Rolled oats', FoodCategory.grains, Unit.g, _p, [379, 13.2, 67.7, 6.5, 10.1, 1, 6, 1.1],
      perMl: 0.41, shelf: 365, allergens: ['gluten'], aliases: ['large flake oats', 'quick oats', 'rolled oats']),
  _e('quinoa', 'Quinoa', FoodCategory.grains, Unit.g, _p, [368, 14.1, 64.2, 6.1, 7.0, 0, 5, 0.7],
      perMl: 0.72, shelf: 730),
  _e('bread', 'Sourdough bread', FoodCategory.bakery, Unit.g, _p, [265, 9, 49, 3.2, 2.7, 5, 490, 0.7],
      perPiece: 40, shelf: 4, allergens: ['wheat', 'gluten'], aliases: ['sourdough', 'bread loaf', 'ww bread', 'whole wheat bread']),
  _e('flour', 'All-purpose flour', FoodCategory.pantry, Unit.g, _p, [364, 10.3, 76.3, 1, 2.7, 0.3, 2, 0.2],
      perMl: 0.53, shelf: 365, allergens: ['wheat', 'gluten'], aliases: ['ap flour', 'all purpose flour']),
  _e('tortilla', 'Corn tortillas', FoodCategory.bakery, Unit.piece, _f, [218, 5.7, 44.6, 2.9, 6.3, 0.9, 45, 0.4],
      perPiece: 26, shelf: 14, aliases: ['corn tortilla']),
  // Produce
  _e('spinach', 'Baby spinach', FoodCategory.produce, Unit.g, _f, [23, 2.9, 3.6, 0.4, 2.2, 0.4, 79, 0.1],
      shelf: 5, aliases: ['bby spinach', 'spinach 142g', 'organic spinach']),
  _e('kale', 'Kale', FoodCategory.produce, Unit.g, _f, [49, 4.3, 8.8, 0.9, 3.6, 2.3, 38, 0.1], shelf: 6),
  _e('tomato', 'Tomatoes', FoodCategory.produce, Unit.piece, _p, [18, 0.9, 3.9, 0.2, 1.2, 2.6, 5, 0],
      perPiece: 120, shelf: 6, aliases: ['tomatoes on vine', 'tov', 'roma tomatoes']),
  _e('cherry_tomato', 'Cherry tomatoes', FoodCategory.produce, Unit.g, _f, [18, 0.9, 3.9, 0.2, 1.2, 2.6, 5, 0],
      perPiece: 17, shelf: 7, aliases: ['cherry tom', 'grape tomatoes']),
  _e('crushed_tomato', 'Crushed tomatoes (can)', FoodCategory.pantry, Unit.ml, _p, [32, 1.6, 7.3, 0.3, 1.9, 4.4, 186, 0],
      perMl: 1.05, shelf: 730, aliases: ['crushed tomatoes 796ml', 'canned tomatoes']),
  _e('onion', 'Yellow onions', FoodCategory.produce, Unit.piece, _p, [40, 1.1, 9.3, 0.1, 1.7, 4.2, 4, 0],
      perPiece: 150, shelf: 30, aliases: ['ylw onions', 'cooking onions', 'onions 3lb']),
  _e('garlic', 'Garlic', FoodCategory.produce, Unit.piece, _p, [149, 6.4, 33.1, 0.5, 2.1, 1, 17, 0.1],
      perPiece: 5, shelf: 60, aliases: ['garlic bulb', 'garlic 3pk']),
  _e('carrot', 'Carrots', FoodCategory.produce, Unit.g, _f, [41, 0.9, 9.6, 0.2, 2.8, 4.7, 69, 0],
      perPiece: 60, shelf: 21, aliases: ['carrots 2lb']),
  _e('bell_pepper', 'Red bell pepper', FoodCategory.produce, Unit.piece, _f, [31, 1, 6, 0.3, 2.1, 4.2, 4, 0],
      perPiece: 150, shelf: 10, aliases: ['red pepper', 'sweet pepper red', 'peppers red']),
  _e('broccoli', 'Broccoli', FoodCategory.produce, Unit.g, _f, [34, 2.8, 6.6, 0.4, 2.6, 1.7, 33, 0], shelf: 7,
      aliases: ['broccoli crown', 'brocc']),
  _e('zucchini', 'Zucchini', FoodCategory.produce, Unit.piece, _f, [17, 1.2, 3.1, 0.3, 1, 2.5, 8, 0.1],
      perPiece: 200, shelf: 7, aliases: ['zucchini green']),
  _e('mushroom', 'Cremini mushrooms', FoodCategory.produce, Unit.g, _f, [22, 3.1, 3.3, 0.3, 1, 2, 5, 0], shelf: 6,
      aliases: ['mushrooms', 'cremini', 'brown mushrooms']),
  _e('potato', 'Yukon Gold potatoes', FoodCategory.produce, Unit.g, _p, [77, 2, 17.5, 0.1, 2.2, 0.8, 6, 0],
      perPiece: 170, shelf: 30, aliases: ['yukon gold', 'potatoes 5lb']),
  _e('sweet_potato', 'Sweet potato', FoodCategory.produce, Unit.piece, _p, [86, 1.6, 20.1, 0.1, 3, 4.2, 55, 0],
      perPiece: 200, shelf: 21),
  _e('avocado', 'Avocados', FoodCategory.produce, Unit.piece, _p, [160, 2, 8.5, 14.7, 6.7, 0.7, 7, 2.1],
      perPiece: 150, shelf: 5, aliases: ['avocado hass', 'hass avocado']),
  _e('lemon', 'Lemons', FoodCategory.produce, Unit.piece, _f, [22, 0.4, 6.9, 0.2, 0.3, 2.5, 1, 0],
      perPiece: 58, shelf: 21, aliases: ['lemon']),
  _e('lime', 'Limes', FoodCategory.produce, Unit.piece, _f, [25, 0.4, 8.4, 0.1, 0.4, 1.7, 2, 0],
      perPiece: 44, shelf: 21),
  _e('apple', 'Apples', FoodCategory.produce, Unit.piece, _f, [52, 0.3, 13.8, 0.2, 2.4, 10.4, 1, 0],
      perPiece: 180, shelf: 30, aliases: ['honeycrisp', 'gala apples', 'apples 3lb']),
  _e('banana', 'Bananas', FoodCategory.produce, Unit.piece, _p, [89, 1.1, 22.8, 0.3, 2.6, 12.2, 1, 0.1],
      perPiece: 118, shelf: 5, aliases: ['bananas', 'banana']),
  _e('blueberries', 'Blueberries', FoodCategory.produce, Unit.g, _f, [57, 0.7, 14.5, 0.3, 2.4, 10, 1, 0],
      shelf: 7, aliases: ['blueberry 1pt', 'bluebrry']),
  _e('strawberries', 'Strawberries', FoodCategory.produce, Unit.g, _f, [32, 0.7, 7.7, 0.3, 2, 4.9, 1, 0], shelf: 4,
      aliases: ['strawberry 1lb']),
  _e('cucumber', 'English cucumber', FoodCategory.produce, Unit.piece, _f, [15, 0.7, 3.6, 0.1, 0.5, 1.7, 2, 0],
      perPiece: 300, shelf: 7, aliases: ['eng cucumber', 'cucumber eng']),
  _e('greens', 'Mixed greens', FoodCategory.produce, Unit.g, _f, [15, 1.4, 2.9, 0.2, 1.3, 0.8, 28, 0], shelf: 5,
      aliases: ['spring mix', 'mesclun']),
  _e('ginger', 'Fresh ginger', FoodCategory.produce, Unit.g, _f, [80, 1.8, 17.8, 0.8, 2, 1.7, 13, 0.2], shelf: 21),
  _e('parsley', 'Flat-leaf parsley', FoodCategory.produce, Unit.g, _f, [36, 3, 6.3, 0.8, 3.3, 0.9, 56, 0.1],
      shelf: 7, aliases: ['italian parsley']),
  _e('basil', 'Fresh basil', FoodCategory.produce, Unit.g, _f, [23, 3.2, 2.7, 0.6, 1.6, 0.3, 4, 0], shelf: 5),
  _e('cilantro', 'Cilantro', FoodCategory.produce, Unit.g, _f, [23, 2.1, 3.7, 0.5, 2.8, 0.9, 46, 0], shelf: 6),
  _e('peas', 'Frozen peas', FoodCategory.frozen, Unit.g, _z, [81, 5.4, 14.5, 0.4, 5.1, 5.7, 5, 0.1], shelf: 240,
      aliases: ['frz peas', 'green peas']),
  // Pantry
  _e('olive_oil', 'Extra-virgin olive oil', FoodCategory.pantry, Unit.ml, _p, [884, 0, 0, 100, 0, 0, 2, 14],
      perMl: 0.91, shelf: 365, aliases: ['evoo', 'olive oil extra virgin']),
  _e('sesame_oil', 'Toasted sesame oil', FoodCategory.condiments, Unit.ml, _p, [884, 0, 0, 100, 0, 0, 0, 14],
      perMl: 0.92, shelf: 365, allergens: ['sesame']),
  _e('soy_sauce', 'Soy sauce', FoodCategory.condiments, Unit.ml, _p, [53, 8.1, 4.9, 0.6, 0.8, 0.4, 5493, 0.1],
      perMl: 1.15, shelf: 730, allergens: ['soy', 'wheat', 'gluten']),
  _e('miso', 'White miso', FoodCategory.condiments, Unit.g, _f, [199, 12.8, 25.4, 6, 5.4, 6.2, 3728, 1],
      shelf: 180, allergens: ['soy']),
  _e('tahini', 'Tahini', FoodCategory.condiments, Unit.g, _p, [595, 17, 21.2, 53.8, 9.3, 0.5, 115, 7.5],
      perMl: 0.96, shelf: 180, allergens: ['sesame']),
  _e('coconut_milk', 'Coconut milk (can)', FoodCategory.pantry, Unit.ml, _p, [230, 2.3, 5.5, 23.8, 2.2, 3.3, 15, 21],
      perMl: 0.97, shelf: 730, aliases: ['coconut milk 400ml']),
  _e('stock', 'Low-sodium vegetable stock', FoodCategory.pantry, Unit.ml, _p, [15, 1.5, 1, 0.5, 0, 0.5, 340, 0],
      perMl: 1.0, shelf: 365, aliases: ['veg broth', 'vegetable broth', 'stock 900ml']),
  _e('honey', 'Honey', FoodCategory.pantry, Unit.ml, _p, [304, 0.3, 82.4, 0, 0.2, 82.1, 4, 0],
      perMl: 1.42, shelf: 730),
  _e('maple_syrup', 'Maple syrup', FoodCategory.pantry, Unit.ml, _p, [260, 0, 67, 0.1, 0, 60.5, 12, 0],
      perMl: 1.32, shelf: 365, aliases: ['pure maple syrup']),
  _e('sugar', 'Granulated sugar', FoodCategory.pantry, Unit.g, _p, [387, 0, 100, 0, 0, 100, 1, 0],
      perMl: 0.85, shelf: 730),
  _e('salt', 'Sea salt', FoodCategory.spices, Unit.g, _p, [0, 0, 0, 0, 0, 0, 38758, 0], perMl: 1.2, shelf: 3650),
  _e('black_pepper', 'Black pepper', FoodCategory.spices, Unit.g, _p, [251, 10.4, 64, 3.3, 25.3, 0.6, 20, 1.4],
      perMl: 0.46, shelf: 730),
  _e('cumin', 'Ground cumin', FoodCategory.spices, Unit.g, _p, [375, 17.8, 44.2, 22.3, 10.5, 2.3, 168, 1.5],
      perMl: 0.4, shelf: 730),
  _e('chili_flakes', 'Chili flakes', FoodCategory.spices, Unit.g, _p, [318, 12, 56.6, 17.3, 27.2, 10.3, 30, 3.3],
      perMl: 0.4, shelf: 730),
  _e('almonds', 'Almonds', FoodCategory.snacks, Unit.g, _p, [579, 21.2, 21.6, 49.9, 12.5, 4.4, 1, 3.8],
      shelf: 180, allergens: ['tree_nut']),
  _e('walnuts', 'Walnuts', FoodCategory.snacks, Unit.g, _p, [654, 15.2, 13.7, 65.2, 6.7, 2.6, 2, 6.1],
      shelf: 180, allergens: ['tree_nut']),
  _e('peanut_butter', 'Natural peanut butter', FoodCategory.pantry, Unit.g, _p, [588, 25, 20, 50, 6, 9.2, 430, 10],
      perMl: 1.08, shelf: 90, allergens: ['peanut'], aliases: ['pb natural', 'peanut butter']),
  _e('chia', 'Chia seeds', FoodCategory.pantry, Unit.g, _p, [486, 16.5, 42.1, 30.7, 34.4, 0, 16, 3.3],
      perMl: 0.65, shelf: 365),
  _e('dark_chocolate', 'Dark chocolate (70%)', FoodCategory.snacks, Unit.g, _p, [598, 7.8, 45.9, 42.6, 10.9, 24, 20, 24.5],
      shelf: 365, allergens: ['milk'], aliases: ['dark choc 70']),
  _e('balsamic', 'Balsamic vinegar', FoodCategory.condiments, Unit.ml, _p, [88, 0.5, 17, 0, 0, 15, 23, 0],
      perMl: 1.06, shelf: 1095, allergens: ['sulphites']),
  _e('dijon', 'Dijon mustard', FoodCategory.condiments, Unit.g, _f, [66, 4.4, 5.8, 4, 3.3, 0.9, 1135, 0.2],
      perMl: 1.05, shelf: 365, allergens: ['mustard']),
  _e('orange_juice', 'Orange juice', FoodCategory.beverages, Unit.ml, _f, [45, 0.7, 10.4, 0.2, 0.2, 8.4, 1, 0],
      perMl: 1.04, shelf: 10, aliases: ['oj', 'orange jc']),
  _e('sparkling_water', 'Sparkling water', FoodCategory.beverages, Unit.ml, _p, [0, 0, 0, 0, 0, 0, 2, 0],
      perMl: 1.0, shelf: 365, aliases: ['soda water', 'mineral water']),
];

final Map<String, CatalogEntry> catalogById = {for (final e in catalog) e.product.id: e};

final Map<String, NutrientReference> nutrientReferences = {for (final e in catalog) e.product.id: e.reference};

/// productId -> allergen tags, for AllergenGuard.checkRecipe.
final Map<String, List<String>> catalogAllergens = {
  for (final e in catalog)
    if (e.product.allergens.isNotEmpty) e.product.id: e.product.allergens,
};
