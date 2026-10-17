import '../units/units.dart';
import 'codec.dart';
import 'nutrition.dart';
import 'recipe.dart';

enum CookingStatus { preparing, cooking, confirming, completed, abandoned }

/// One planned ingredient deduction inside a cooking session.
class IngredientConsumption {
  const IngredientConsumption({
    required this.ingredientName,
    this.productId,
    this.planned,
    this.actual,
    this.skipped = false,
    this.substitutedWithProductId,
    this.substitutedWithName,
    this.lotId,
  });

  final String ingredientName;
  final String? productId;
  final Quantity? planned;

  /// What the user confirms they actually used.
  final Quantity? actual;
  final bool skipped;
  final String? substitutedWithProductId;
  final String? substitutedWithName;
  final String? lotId;

  String? get effectiveProductId => substitutedWithProductId ?? productId;
  Quantity? get effectiveQuantity => skipped ? null : (actual ?? planned);

  IngredientConsumption copyWith({Quantity? actual, bool? skipped, String? substitutedWithProductId, String? substitutedWithName}) =>
      IngredientConsumption(
        ingredientName: ingredientName,
        productId: productId,
        planned: planned,
        actual: actual ?? this.actual,
        skipped: skipped ?? this.skipped,
        substitutedWithProductId: substitutedWithProductId ?? this.substitutedWithProductId,
        substitutedWithName: substitutedWithName ?? this.substitutedWithName,
        lotId: lotId,
      );

  Map<String, dynamic> toMap() => {
        'ingredientName': ingredientName,
        if (productId != null) 'productId': productId,
        if (planned != null) 'planned': planned!.toMap(),
        if (actual != null) 'actual': actual!.toMap(),
        'skipped': skipped,
        if (substitutedWithProductId != null) 'substitutedWithProductId': substitutedWithProductId,
        if (substitutedWithName != null) 'substitutedWithName': substitutedWithName,
        if (lotId != null) 'lotId': lotId,
      };

  static IngredientConsumption fromMap(Map<String, dynamic> m) => IngredientConsumption(
        ingredientName: readString(m, 'ingredientName'),
        productId: m['productId'] as String?,
        planned: m['planned'] == null ? null : Quantity.fromMap(readMap(m['planned'])),
        actual: m['actual'] == null ? null : Quantity.fromMap(readMap(m['actual'])),
        skipped: m['skipped'] as bool? ?? false,
        substitutedWithProductId: m['substitutedWithProductId'] as String?,
        substitutedWithName: m['substitutedWithName'] as String?,
        lotId: m['lotId'] as String?,
      );
}

class CookingSession {
  const CookingSession({
    required this.id,
    required this.householdId,
    required this.uid,
    required this.recipe,
    required this.servings,
    required this.status,
    required this.startedAt,
    this.currentStep = 0,
    this.consumptions = const [],
    this.completedAt,
    this.inventoryOperationId,
    this.rating,
    this.portionsEaten,
    this.leftoverPortions,
    this.mealPlanEntryId,
  });

  final String id;
  final String householdId;
  final String uid;
  final Recipe recipe;
  final int servings;
  final CookingStatus status;
  final DateTime startedAt;
  final int currentStep;
  final List<IngredientConsumption> consumptions;
  final DateTime? completedAt;
  final String? inventoryOperationId;
  final int? rating;
  final double? portionsEaten;
  final int? leftoverPortions;
  final String? mealPlanEntryId;

  CookingSession copyWith({
    CookingStatus? status,
    int? currentStep,
    List<IngredientConsumption>? consumptions,
    DateTime? completedAt,
    String? inventoryOperationId,
    int? rating,
    double? portionsEaten,
    int? leftoverPortions,
  }) =>
      CookingSession(
        id: id,
        householdId: householdId,
        uid: uid,
        recipe: recipe,
        servings: servings,
        status: status ?? this.status,
        startedAt: startedAt,
        currentStep: currentStep ?? this.currentStep,
        consumptions: consumptions ?? this.consumptions,
        completedAt: completedAt ?? this.completedAt,
        inventoryOperationId: inventoryOperationId ?? this.inventoryOperationId,
        rating: rating ?? this.rating,
        portionsEaten: portionsEaten ?? this.portionsEaten,
        leftoverPortions: leftoverPortions ?? this.leftoverPortions,
        mealPlanEntryId: mealPlanEntryId,
      );

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'uid': uid,
        'recipeId': recipe.id,
        'recipe': recipe.toMap(),
        'servings': servings,
        'status': status.name,
        'startedAt': startedAt,
        'currentStep': currentStep,
        'consumptions': consumptions.map((c) => c.toMap()).toList(),
        if (completedAt != null) 'completedAt': completedAt,
        if (inventoryOperationId != null) 'inventoryOperationId': inventoryOperationId,
        if (rating != null) 'rating': rating,
        if (portionsEaten != null) 'portionsEaten': portionsEaten,
        if (leftoverPortions != null) 'leftoverPortions': leftoverPortions,
        if (mealPlanEntryId != null) 'mealPlanEntryId': mealPlanEntryId,
      };

  static CookingSession fromMap(String id, Map<String, dynamic> m) => CookingSession(
        id: id,
        householdId: readString(m, 'householdId'),
        uid: readString(m, 'uid'),
        recipe: Recipe.fromMap(readString(m, 'recipeId'), readMap(m['recipe'])),
        servings: readInt(m, 'servings', 2),
        status: readEnum(CookingStatus.values, m['status'], CookingStatus.preparing),
        startedAt: readDate(m['startedAt']),
        currentStep: readInt(m, 'currentStep', 0),
        consumptions: readMaps(m['consumptions']).map(IngredientConsumption.fromMap).toList(),
        completedAt: readDateOrNull(m['completedAt']),
        inventoryOperationId: m['inventoryOperationId'] as String?,
        rating: (m['rating'] as num?)?.toInt(),
        portionsEaten: (m['portionsEaten'] as num?)?.toDouble(),
        leftoverPortions: (m['leftoverPortions'] as num?)?.toInt(),
        mealPlanEntryId: m['mealPlanEntryId'] as String?,
      );
}

enum MealEntrySource { cooked, recipe, quickEntry, photo, voice, leftovers, repeat }

/// A meal the user actually ate (private journal entry).
class MealConsumption {
  const MealConsumption({
    required this.id,
    required this.uid,
    required this.title,
    required this.mealType,
    required this.eatenAt,
    required this.portions,
    required this.source,
    required this.createdAt,
    this.recipeId,
    this.cookingSessionId,
    this.nutrition = NutrientProfile.empty,
    this.notes,
    this.isDemo = false,
  });

  final String id;
  final String uid;
  final String title;
  final MealType mealType;
  final DateTime eatenAt;
  final double portions;
  final MealEntrySource source;
  final DateTime createdAt;
  final String? recipeId;
  final String? cookingSessionId;

  /// Total for the portions eaten (estimate).
  final NutrientProfile nutrition;
  final String? notes;
  final bool isDemo;

  MealConsumption copyWith({String? title, MealType? mealType, DateTime? eatenAt, double? portions, NutrientProfile? nutrition, String? notes}) =>
      MealConsumption(
        id: id,
        uid: uid,
        title: title ?? this.title,
        mealType: mealType ?? this.mealType,
        eatenAt: eatenAt ?? this.eatenAt,
        portions: portions ?? this.portions,
        source: source,
        createdAt: createdAt,
        recipeId: recipeId,
        cookingSessionId: cookingSessionId,
        nutrition: nutrition ?? this.nutrition,
        notes: notes ?? this.notes,
        isDemo: isDemo,
      );

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'title': title,
        'mealType': mealType.name,
        'eatenAt': eatenAt,
        'portions': portions,
        'source': source.name,
        'createdAt': createdAt,
        if (recipeId != null) 'recipeId': recipeId,
        if (cookingSessionId != null) 'cookingSessionId': cookingSessionId,
        'nutrition': nutrition.toMap(),
        if (notes != null) 'notes': notes,
        'isDemo': isDemo,
      };

  static MealConsumption fromMap(String id, Map<String, dynamic> m) => MealConsumption(
        id: id,
        uid: readString(m, 'uid'),
        title: readString(m, 'title'),
        mealType: readEnum(MealType.values, m['mealType'], MealType.dinner),
        eatenAt: readDate(m['eatenAt']),
        portions: readDouble(m, 'portions', 1),
        source: readEnum(MealEntrySource.values, m['source'], MealEntrySource.quickEntry),
        createdAt: readDate(m['createdAt'] ?? m['eatenAt']),
        recipeId: m['recipeId'] as String?,
        cookingSessionId: m['cookingSessionId'] as String?,
        nutrition: NutrientProfile.fromMap(m['nutrition']),
        notes: m['notes'] as String?,
        isDemo: m['isDemo'] as bool? ?? false,
      );
}
