import 'dart:typed_data';

import '../../domain/models/inventory.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/models/recipe.dart';
import '../../domain/units/units.dart';

/// What the user asked the chef for.
class ChefRequest {
  const ChefRequest({
    required this.householdId,
    this.prompt,
    this.mealType,
    this.maxMinutes,
    this.servings = 2,
    this.cuisines = const [],
    this.useWhatIHave = true,
    this.equipment = const [],
    this.nutritionFocus,
    this.exclusions = const [],
    this.count = 3,
  });

  final String householdId;
  final String? prompt;
  final MealType? mealType;
  final int? maxMinutes;
  final int servings;
  final List<String> cuisines;
  final bool useWhatIHave;
  final List<String> equipment;

  /// e.g. 'more protein', 'more vegetables', 'lighter'.
  final String? nutritionFocus;
  final List<String> exclusions;
  final int count;

  ChefRequest copyWith({String? prompt, MealType? mealType, int? maxMinutes, int? servings, List<String>? cuisines,
          bool? useWhatIHave, List<String>? equipment, String? nutritionFocus, List<String>? exclusions}) =>
      ChefRequest(
        householdId: householdId,
        prompt: prompt ?? this.prompt,
        mealType: mealType ?? this.mealType,
        maxMinutes: maxMinutes ?? this.maxMinutes,
        servings: servings ?? this.servings,
        cuisines: cuisines ?? this.cuisines,
        useWhatIHave: useWhatIHave ?? this.useWhatIHave,
        equipment: equipment ?? this.equipment,
        nutritionFocus: nutritionFocus ?? this.nutritionFocus,
        exclusions: exclusions ?? this.exclusions,
        count: count,
      );

  Map<String, dynamic> toJson() => {
        'householdId': householdId,
        if (prompt != null) 'prompt': prompt,
        if (mealType != null) 'mealType': mealType!.name,
        if (maxMinutes != null) 'maxMinutes': maxMinutes,
        'servings': servings,
        'cuisines': cuisines,
        'useWhatIHave': useWhatIHave,
        'equipment': equipment,
        if (nutritionFocus != null) 'nutritionFocus': nutritionFocus,
        'exclusions': exclusions,
        'count': count,
      };
}

class ChefSuggestion {
  const ChefSuggestion({required this.recipe, required this.rationale});
  final Recipe recipe;
  final String rationale;
}

class ChefResult {
  const ChefResult({required this.suggestions, required this.isDemo, this.filteredForSafety = 0, this.provider});

  final List<ChefSuggestion> suggestions;
  final bool isDemo;

  /// How many generated recipes were removed by the allergen guard.
  final int filteredForSafety;
  final String? provider;
}

class ChefMessage {
  const ChefMessage({required this.fromUser, required this.text, this.recipes = const [], this.isDemo = false, this.at});

  final bool fromUser;
  final String text;
  final List<Recipe> recipes;
  final bool isDemo;
  final DateTime? at;

  Map<String, dynamic> toJson() => {'role': fromUser ? 'user' : 'assistant', 'text': text};
}

/// Items recognised in a fridge/pantry photo. Quantities are only present
/// when the count was clearly visible; otherwise the user supplies them.
class ScanSuggestion {
  const ScanSuggestion({
    required this.name,
    required this.confidence,
    required this.category,
    this.productId,
    this.visibleCount,
    this.storage = StorageKind.fridge,
    this.note,
  });

  final String name;
  final double confidence;
  final FoodCategory category;
  final String? productId;
  final Quantity? visibleCount;
  final StorageKind storage;
  final String? note;
}

class ScanResult {
  const ScanResult({required this.suggestions, required this.isDemo, this.message});
  final List<ScanSuggestion> suggestions;
  final bool isDemo;
  final String? message;
}

class MealEstimate {
  const MealEstimate({required this.title, required this.nutrition, required this.isDemo, this.items = const [], this.note});

  final String title;
  final NutrientProfile nutrition;
  final bool isDemo;
  final List<String> items;
  final String? note;
}

class AiUnavailableException implements Exception {
  AiUnavailableException(this.message, {this.retryable = true});
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

/// Every AI capability the app uses. Implementations never expose provider
/// keys: production calls authenticated Cloud Functions.
abstract class AiGateway {
  bool get isDemo;

  /// Kicks off server-side extraction; progress arrives on the receipt doc.
  Future<void> processReceipt({required String householdId, required String receiptId});

  Future<ChefResult> recommend(ChefRequest request);

  Future<ChefMessage> chat({required String householdId, required List<ChefMessage> history});

  Future<ScanResult> scanStorage({required String householdId, required Uint8List image, required StorageKind location});

  Future<MealEstimate> estimateMeal({required String description, Uint8List? photo});
}

/// Uploads images. Production: Cloud Storage under the household path.
abstract class ImageUploader {
  Future<String> uploadReceiptPage({
    required String householdId,
    required String receiptId,
    required int page,
    required Uint8List bytes,
    required String contentType,
  });
}
