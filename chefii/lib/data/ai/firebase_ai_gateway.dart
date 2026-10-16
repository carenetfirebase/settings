import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/catalog/catalog.dart';
import '../../domain/models/inventory.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/recipe.dart';
import '../../domain/nutrition/nutrition_calculator.dart';
import '../../domain/safety/allergen_guard.dart';
import '../../domain/units/units.dart';
import 'ai_gateway.dart';

/// Production gateway: authenticated callable Cloud Functions. Provider keys
/// live in Secret Manager and never reach the device. App Check tokens are
/// attached automatically by the Functions SDK when App Check is active.
///
/// Recipes returned by the server are re-screened here by [AllergenGuard]
/// (defence in depth) and nutrition is recomputed from reference data when
/// the ingredients can be mapped.
class FirebaseAiGateway implements AiGateway {
  FirebaseAiGateway(this._functions, {required this.dietaryOf});

  final FirebaseFunctions _functions;
  final Future<DietaryProfile> Function() dietaryOf;

  static const _timeout = Duration(seconds: 90);

  @override
  bool get isDemo => false;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final res = await _functions
          .httpsCallable(name, options: HttpsCallableOptions(timeout: _timeout))
          .call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(res.data);
    } on FirebaseFunctionsException catch (e) {
      final retryable = e.code == 'unavailable' || e.code == 'deadline-exceeded' || e.code == 'resource-exhausted';
      throw AiUnavailableException(e.message ?? 'The kitchen assistant is unavailable right now.', retryable: retryable, detail: e.message);
    }
  }

  @override
  Future<void> processReceipt({required String householdId, required String receiptId}) async {
    await _call('processReceipt', {'householdId': householdId, 'receiptId': receiptId});
  }

  @override
  Future<ChefResult> recommend(ChefRequest request) async {
    final data = await _call('chefRecommend', request.toJson());
    final dietary = await dietaryOf();
    final recipes = _parseRecipes(data['recipes']);
    final rationales = (data['rationales'] as List?)?.cast<String>() ?? const [];
    const guard = AllergenGuard();
    final out = <ChefSuggestion>[];
    var filtered = (data['filteredForSafety'] as num?)?.toInt() ?? 0;
    for (var i = 0; i < recipes.length; i++) {
      if (guard.checkRecipe(recipes[i], dietary, productAllergens: catalogAllergens).isBlocked) {
        filtered++;
        continue;
      }
      out.add(ChefSuggestion(recipe: recipes[i], rationale: i < rationales.length ? rationales[i] : ''));
    }
    return ChefResult(suggestions: out, isDemo: false, filteredForSafety: filtered, provider: data['provider'] as String?);
  }

  @override
  Future<ChefMessage> chat({required String householdId, required List<ChefMessage> history}) async {
    final data = await _call('chefChat', {
      'householdId': householdId,
      'messages': history.take(20).map((m) => m.toJson()).toList(),
    });
    final dietary = await dietaryOf();
    const guard = AllergenGuard();
    final recipes = _parseRecipes(data['recipes'])
        .where((r) => !guard.checkRecipe(r, dietary, productAllergens: catalogAllergens).isBlocked)
        .toList();
    return ChefMessage(fromUser: false, text: data['text'] as String? ?? '', recipes: recipes, at: DateTime.now().toUtc());
  }

  @override
  Future<ScanResult> scanStorage({required String householdId, required Uint8List image, required StorageKind location}) async {
    final data = await _call('scanStorage', {
      'householdId': householdId,
      'location': location.name,
      'imageBase64': base64Encode(image),
    });
    final items = (data['items'] as List? ?? const []).cast<Map>().map((m) {
      final count = m['visibleCount'] as num?;
      return ScanSuggestion(
        name: m['name'] as String,
        confidence: (m['confidence'] as num).toDouble(),
        category: FoodCategory.values.firstWhere((c) => c.name == m['category'], orElse: () => FoodCategory.other),
        productId: m['productId'] as String?,
        visibleCount: count == null ? null : Quantity(count.toDouble(), Unit.piece),
        storage: location,
        note: m['note'] as String?,
      );
    }).toList();
    return ScanResult(suggestions: items, isDemo: false, message: data['message'] as String?);
  }

  @override
  Future<MealEstimate> estimateMeal({required String description, Uint8List? photo}) async {
    final data = await _call('estimateMeal', {
      'description': description,
      if (photo != null) 'imageBase64': base64Encode(photo),
    });
    return MealEstimate(
      title: data['title'] as String? ?? description,
      nutrition: NutrientProfile.fromMap(data['nutrition']),
      items: (data['items'] as List?)?.cast<String>() ?? const [],
      note: data['note'] as String?,
      isDemo: false,
    );
  }

  static List<Recipe> _parseRecipes(Object? raw) {
    const calc = NutritionCalculator();
    final list = (raw as List? ?? const []).cast<Map>();
    return [
      for (final m in list)
        () {
          final r = Recipe.fromMap(m['id'] as String, Map<String, dynamic>.from(m));
          final computed = calc.perServing(r);
          // Prefer our reference-data estimate when most ingredients mapped.
          return computed.completeness >= 0.7 ? r.withIngredients(r.ingredients, nutrition: computed) : r;
        }(),
    ];
  }
}

class FirebaseImageUploader implements ImageUploader {
  FirebaseImageUploader(this._storage);
  final FirebaseStorage _storage;

  @override
  Future<String> uploadReceiptPage({
    required String householdId,
    required String receiptId,
    required int page,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final path = 'households/$householdId/receipts/$receiptId/page_$page';
    await _storage.ref(path).putData(bytes, SettableMetadata(contentType: contentType));
    return path;
  }
}
