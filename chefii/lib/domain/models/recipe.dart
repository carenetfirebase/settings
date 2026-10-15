import '../units/units.dart';
import 'codec.dart';
import 'nutrition.dart';

enum MealType {
  breakfast('Breakfast'),
  lunch('Lunch'),
  dinner('Dinner'),
  snack('Snack');

  const MealType(this.label);
  final String label;
}

enum Difficulty {
  easy('Easy'),
  medium('Medium'),
  involved('Involved');

  const Difficulty(this.label);
  final String label;
}

enum RecipeOrigin {
  curated('Chefii kitchen'),
  ai('Created by your AI chef'),
  user('Your recipe'),
  professional('From your professional');

  const RecipeOrigin(this.label);
  final String label;
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.name,
    this.productId,
    this.quantity,
    this.preparation,
    this.optional = false,
    this.nutrientRefId,
    this.bridge = UnitBridge.none,
  });

  final String name;

  /// Catalogue id used to match inventory, e.g. 'egg'.
  final String? productId;

  /// Null for "to taste" style amounts that are never deducted.
  final Quantity? quantity;
  final String? preparation;
  final bool optional;
  final String? nutrientRefId;
  final UnitBridge bridge;

  String get display {
    final q = quantity == null ? '' : '${quantity!.format()} ';
    final prep = preparation == null ? '' : ', $preparation';
    return '$q$name$prep';
  }

  RecipeIngredient scaled(double f) => RecipeIngredient(
        name: name,
        productId: productId,
        quantity: quantity == null ? null : quantity! * f,
        preparation: preparation,
        optional: optional,
        nutrientRefId: nutrientRefId,
        bridge: bridge,
      );

  RecipeIngredient copyWith({String? name, String? productId, Quantity? quantity, String? nutrientRefId}) =>
      RecipeIngredient(
        name: name ?? this.name,
        productId: productId ?? this.productId,
        quantity: quantity ?? this.quantity,
        preparation: preparation,
        optional: optional,
        nutrientRefId: nutrientRefId ?? this.nutrientRefId,
        bridge: bridge,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        if (productId != null) 'productId': productId,
        if (quantity != null) 'quantity': quantity!.toMap(),
        if (preparation != null) 'preparation': preparation,
        'optional': optional,
        if (nutrientRefId != null) 'nutrientRefId': nutrientRefId,
        'bridge': bridge.toMap(),
      };

  static RecipeIngredient fromMap(Map<String, dynamic> m) => RecipeIngredient(
        name: readString(m, 'name'),
        productId: m['productId'] as String?,
        quantity: m['quantity'] == null ? null : Quantity.fromMap(readMap(m['quantity'])),
        preparation: m['preparation'] as String?,
        optional: m['optional'] as bool? ?? false,
        nutrientRefId: m['nutrientRefId'] as String?,
        bridge: UnitBridge.fromMap(m['bridge'] == null ? null : readMap(m['bridge'])),
      );
}

class RecipeStep {
  const RecipeStep({required this.text, this.timerSeconds, this.timerLabel, this.tip});

  final String text;
  final int? timerSeconds;
  final String? timerLabel;
  final String? tip;

  Map<String, dynamic> toMap() => {
        'text': text,
        if (timerSeconds != null) 'timerSeconds': timerSeconds,
        if (timerLabel != null) 'timerLabel': timerLabel,
        if (tip != null) 'tip': tip,
      };

  static RecipeStep fromMap(Map<String, dynamic> m) => RecipeStep(
        text: readString(m, 'text'),
        timerSeconds: (m['timerSeconds'] as num?)?.toInt(),
        timerLabel: m['timerLabel'] as String?,
        tip: m['tip'] as String?,
      );
}

class RecipeSubstitution {
  const RecipeSubstitution({
    required this.originalName,
    required this.substitute,
    required this.note,
    this.availableInKitchen = false,
  });

  final String originalName;
  final RecipeIngredient substitute;
  final String note;
  final bool availableInKitchen;
}

class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.summary,
    required this.cuisine,
    required this.mealTypes,
    required this.servings,
    required this.prepMinutes,
    required this.cookMinutes,
    required this.difficulty,
    required this.ingredients,
    required this.steps,
    required this.origin,
    this.tags = const [],
    this.equipment = const [],
    this.nutritionPerServing = NutrientProfile.empty,
    this.imageKey,
    this.storageNotes,
    this.createdAt,
    this.aiModel,
  });

  final String id;
  final String title;
  final String summary;
  final String cuisine;
  final List<MealType> mealTypes;
  final int servings;
  final int prepMinutes;
  final int cookMinutes;
  final Difficulty difficulty;
  final List<RecipeIngredient> ingredients;
  final List<RecipeStep> steps;
  final RecipeOrigin origin;
  final List<String> tags;
  final List<String> equipment;
  final NutrientProfile nutritionPerServing;

  /// Key to an illustration palette; never a fake photo of the user's dish.
  final String? imageKey;
  final String? storageNotes;
  final DateTime? createdAt;
  final String? aiModel;

  int get totalMinutes => prepMinutes + cookMinutes;

  /// Returns a copy scaled to [newServings]; nutrition per serving unchanged.
  Recipe scaledTo(int newServings) {
    if (newServings == servings || newServings <= 0) return this;
    final f = newServings / servings;
    return Recipe(
      id: id,
      title: title,
      summary: summary,
      cuisine: cuisine,
      mealTypes: mealTypes,
      servings: newServings,
      prepMinutes: prepMinutes,
      cookMinutes: cookMinutes,
      difficulty: difficulty,
      ingredients: ingredients.map((i) => i.scaled(f)).toList(),
      steps: steps,
      origin: origin,
      tags: tags,
      equipment: equipment,
      nutritionPerServing: nutritionPerServing,
      imageKey: imageKey,
      storageNotes: storageNotes,
      createdAt: createdAt,
      aiModel: aiModel,
    );
  }

  Recipe withIngredients(List<RecipeIngredient> next, {NutrientProfile? nutrition}) => Recipe(
        id: id,
        title: title,
        summary: summary,
        cuisine: cuisine,
        mealTypes: mealTypes,
        servings: servings,
        prepMinutes: prepMinutes,
        cookMinutes: cookMinutes,
        difficulty: difficulty,
        ingredients: next,
        steps: steps,
        origin: origin,
        tags: tags,
        equipment: equipment,
        nutritionPerServing: nutrition ?? nutritionPerServing,
        imageKey: imageKey,
        storageNotes: storageNotes,
        createdAt: createdAt,
        aiModel: aiModel,
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'summary': summary,
        'cuisine': cuisine,
        'mealTypes': mealTypes.map((m) => m.name).toList(),
        'servings': servings,
        'prepMinutes': prepMinutes,
        'cookMinutes': cookMinutes,
        'difficulty': difficulty.name,
        'ingredients': ingredients.map((i) => i.toMap()).toList(),
        'steps': steps.map((s) => s.toMap()).toList(),
        'origin': origin.name,
        'tags': tags,
        'equipment': equipment,
        'nutritionPerServing': nutritionPerServing.toMap(),
        if (imageKey != null) 'imageKey': imageKey,
        if (storageNotes != null) 'storageNotes': storageNotes,
        if (createdAt != null) 'createdAt': createdAt,
        if (aiModel != null) 'aiModel': aiModel,
      };

  static Recipe fromMap(String id, Map<String, dynamic> m) => Recipe(
        id: id,
        title: readString(m, 'title'),
        summary: readString(m, 'summary', ''),
        cuisine: readString(m, 'cuisine', 'Modern'),
        mealTypes: readStrings(m['mealTypes']).map((s) => readEnum(MealType.values, s, MealType.dinner)).toList(),
        servings: readInt(m, 'servings', 2),
        prepMinutes: readInt(m, 'prepMinutes', 0),
        cookMinutes: readInt(m, 'cookMinutes', 0),
        difficulty: readEnum(Difficulty.values, m['difficulty'], Difficulty.easy),
        ingredients: readMaps(m['ingredients']).map(RecipeIngredient.fromMap).toList(),
        steps: readMaps(m['steps']).map(RecipeStep.fromMap).toList(),
        origin: readEnum(RecipeOrigin.values, m['origin'], RecipeOrigin.user),
        tags: readStrings(m['tags']),
        equipment: readStrings(m['equipment']),
        nutritionPerServing: NutrientProfile.fromMap(m['nutritionPerServing']),
        imageKey: m['imageKey'] as String?,
        storageNotes: m['storageNotes'] as String?,
        createdAt: readDateOrNull(m['createdAt']),
        aiModel: m['aiModel'] as String?,
      );
}
