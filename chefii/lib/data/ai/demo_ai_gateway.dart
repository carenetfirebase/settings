import 'dart:typed_data';

import '../../domain/catalog/catalog.dart';
import '../../domain/catalog/product_matcher.dart';
import '../../domain/models/codec.dart';
import '../../domain/models/inventory.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/curated_recipes.dart';
import '../../domain/recipes/recipe_availability.dart';
import '../../domain/safety/allergen_guard.dart';
import '../../domain/units/units.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/receipt_repository.dart';
import 'ai_gateway.dart';

/// Offline stand-in used when no AI backend is configured.
///
/// DEMO ONLY. Receipt and scan results are a fixed, labelled sample — they
/// do not come from the user's photo, and every screen that shows them says
/// so. Recipe suggestions come from the curated library, ranked against the
/// user's real inventory and screened by [AllergenGuard].
class DemoAiGateway implements AiGateway {
  DemoAiGateway({
    required this.receipts,
    required this.inventory,
    required this.dietaryOf,
    this.latency = const Duration(milliseconds: 900),
  });

  final ReceiptRepository receipts;
  final InventoryRepository inventory;
  final Future<DietaryProfile> Function() dietaryOf;
  final Duration latency;

  static const demoModel = 'demo-sample (no AI)';

  @override
  bool get isDemo => true;

  @override
  Future<void> processReceipt({required String householdId, required String receiptId}) async {
    if (!await receipts.writeExtraction(householdId, receiptId, {'status': ReceiptStatus.processing.name, 'progress': 0.2})) return;
    await Future<void>.delayed(latency);
    if (!await receipts.writeExtraction(householdId, receiptId, {'progress': 0.6})) return;
    await Future<void>.delayed(latency);
    await receipts.writeExtraction(householdId, receiptId, sampleExtraction());
  }

  /// A realistic Canadian grocery receipt exercising every review path:
  /// confident items, low-confidence items, a missing quantity, an unknown
  /// line and a non-food purchase.
  static Map<String, dynamic> sampleExtraction() {
    final matcher = ProductMatcher(catalog.map((e) => e.product));
    Map<String, dynamic> line(String id, String raw, String name, FoodCategory cat, double conf,
        {Quantity? q, int? cents, String? pkg, StorageKind storage = StorageKind.fridge, bool food = true, List<String> issues = const []}) {
      final match = name.isEmpty ? null : matcher.best(name, minScore: 0.75);
      return ReceiptLineItem(
        id: id,
        rawText: raw,
        name: name,
        category: cat,
        confidence: conf,
        quantity: q,
        packageDescription: pkg,
        totalPrice: cents == null ? null : Money(cents),
        matchedProductId: match?.product.id,
        isFood: food,
        excluded: !food,
        storage: storage,
        issues: issues,
      ).toMap();
    }

    return {
      'status': ReceiptStatus.needsReview.name,
      'progress': 1.0,
      'isDemo': true,
      'aiModel': demoModel,
      'merchant': 'Maison Market (sample)',
      'purchaseDate': CalendarDate.fromDateTime(DateTime.now()).toIso(),
      'subtotal': const Money(5978).toMap(),
      'tax': const Money(45).toMap(),
      'total': const Money(6023).toMap(),
      'fingerprint': 'demo-maison-6023',
      'lines': [
        line('l1', 'LG EGGS 12CT', 'Eggs', FoodCategory.dairy, 0.96, q: const Quantity(12, Unit.piece), cents: 479, pkg: 'Dozen'),
        line('l2', 'MLK 2% 2L', 'Milk (2%)', FoodCategory.dairy, 0.93, q: const Quantity(2000, Unit.ml), cents: 549, pkg: '2 L carton'),
        line('l3', 'BBY SPINACH 142G', 'Baby spinach', FoodCategory.produce, 0.9, q: const Quantity(142, Unit.g), cents: 399),
        line('l4', 'ATL SALMON FIL 0.412kg @ 24.99/kg', 'Salmon fillet', FoodCategory.seafood, 0.82, q: const Quantity(412, Unit.g), cents: 1030),
        line('l5', 'AVOCADO HASS 2 @ 1.49', 'Avocados', FoodCategory.produce, 0.91, q: const Quantity(2, Unit.piece), cents: 298, storage: StorageKind.pantry),
        line('l6', 'SOURDOUGH LOAF', 'Sourdough bread', FoodCategory.bakery, 0.88, q: const Quantity(680, Unit.g), cents: 649, storage: StorageKind.pantry),
        line('l7', 'GRK YOG PLN 750G', 'Greek yogurt', FoodCategory.dairy, 0.71, q: const Quantity(750, Unit.g), cents: 699,
            issues: ['Low confidence reading the product name']),
        line('l8', 'LEMONS 3PK', 'Lemons', FoodCategory.produce, 0.86, q: const Quantity(3, Unit.piece), cents: 349),
        line('l9', 'ORG HNYCRSP', 'Honeycrisp apples', FoodCategory.produce, 0.55, cents: 599,
            issues: ['Quantity not printed — please enter how many']),
        line('l10', 'DISH SOAP 740ML H', 'Dish soap', FoodCategory.nonFood, 0.95, cents: 349, food: false, storage: StorageKind.custom),
        line('l11', 'XTRA FRM TOFU', 'Firm tofu', FoodCategory.pantry, 0.74, q: const Quantity(350, Unit.g), cents: 329),
        line('l12', 'MISC GROC 2.49', '', FoodCategory.other, 0.3, cents: 249, issues: ['Could not identify this item']),
      ],
      'issues': [
        const ReceiptIssue('sample', 'This is a built-in sample receipt for demo mode — not your photo.').toMap(),
      ],
    };
  }

  @override
  Future<ChefResult> recommend(ChefRequest request) async {
    await Future<void>.delayed(latency ~/ 2);
    final dietary = await dietaryOf();
    final lots = await inventory.activeLots(request.householdId);
    const guard = AllergenGuard();
    var pool = curatedRecipes.where((r) {
      if (request.mealType != null && !r.mealTypes.contains(request.mealType)) return false;
      if (request.maxMinutes != null && r.totalMinutes > request.maxMinutes!) return false;
      if (request.cuisines.isNotEmpty && !request.cuisines.any((c) => r.cuisine.toLowerCase().contains(c.toLowerCase()))) {
        return false;
      }
      return true;
    }).toList();
    final filtered = pool.where((r) => guard.checkRecipe(r, dietary, productAllergens: catalogAllergens).isBlocked).length;
    pool = pool.where((r) => !guard.checkRecipe(r, dietary, productAllergens: catalogAllergens).isBlocked).toList();
    if (request.nutritionFocus == 'more protein') {
      pool.sort((a, b) => b.nutritionPerServing[Nutrient.protein].compareTo(a.nutritionPerServing[Nutrient.protein]));
    }
    final today = CalendarDate.fromDateTime(DateTime.now());
    final ranked = request.useWhatIHave ? const RecipeAvailability().rank(pool, lots, today: today) : pool.map((r) => const RecipeAvailability().check(r, lots, today: today)).toList();
    return ChefResult(
      isDemo: true,
      provider: 'demo',
      filteredForSafety: filtered,
      suggestions: [
        for (final rep in ranked.take(request.count))
          ChefSuggestion(
            recipe: rep.recipe.scaledTo(request.servings),
            rationale: rep.canCookNow
                ? (rep.usesExpiringItems ? 'Uses things that need eating soon, and you have everything.' : 'You have everything you need.')
                : '${rep.label}. ${rep.recipe.totalMinutes} minutes.',
          ),
      ],
    );
  }

  @override
  Future<ChefMessage> chat({required String householdId, required List<ChefMessage> history}) async {
    final last = history.lastWhere((m) => m.fromUser, orElse: () => const ChefMessage(fromUser: true, text: '')).text.toLowerCase();
    MealType? meal;
    for (final m in MealType.values) {
      if (last.contains(m.name)) meal = m;
    }
    final quick = RegExp(r'quick|fast|minutes|easy|tired').hasMatch(last);
    final protein = last.contains('protein');
    final result = await recommend(ChefRequest(
      householdId: householdId,
      mealType: meal,
      maxMinutes: quick ? 20 : null,
      nutritionFocus: protein ? 'more protein' : null,
      count: 3,
    ));
    final recipes = result.suggestions.map((s) => s.recipe).toList();
    final text = recipes.isEmpty
        ? 'I couldn\'t find a recipe that fits everything you\'ve told me. Try loosening the time or cuisine.'
        : 'Here ${recipes.length == 1 ? 'is an idea' : 'are a few ideas'} from the Chefii kitchen, matched to what you have.'
            '${result.filteredForSafety > 0 ? ' I left out ${result.filteredForSafety} that didn\'t suit your dietary needs.' : ''}';
    return ChefMessage(fromUser: false, text: text, recipes: recipes, isDemo: true, at: DateTime.now().toUtc());
  }

  @override
  Future<ScanResult> scanStorage({required String householdId, required Uint8List image, required StorageKind location}) async {
    await Future<void>.delayed(latency);
    return const ScanResult(
      isDemo: true,
      message: 'Demo mode can\'t look at your photo. These sample suggestions show how confirmation works — '
          'nothing is added until you confirm each item and enter amounts.',
      suggestions: [
        ScanSuggestion(name: 'Milk (2%)', productId: 'milk', confidence: 0.9, category: FoodCategory.dairy, note: 'Carton visible; amount left unknown'),
        ScanSuggestion(name: 'Eggs', productId: 'egg', confidence: 0.85, category: FoodCategory.dairy, visibleCount: Quantity(6, Unit.piece)),
        ScanSuggestion(name: 'Red bell pepper', productId: 'bell_pepper', confidence: 0.7, category: FoodCategory.produce, visibleCount: Quantity(2, Unit.piece)),
        ScanSuggestion(name: 'Leafy greens', confidence: 0.45, category: FoodCategory.produce, note: 'Partly hidden — please confirm what this is'),
      ],
    );
  }

  @override
  Future<MealEstimate> estimateMeal({required String description, Uint8List? photo}) async {
    final q = description.toLowerCase();
    Recipe? best;
    var bestScore = 0.0;
    for (final r in curatedRecipes) {
      final words = ProductMatcher.tokens(r.title).toSet();
      final hit = words.intersection(ProductMatcher.tokens(q).toSet()).length / (words.isEmpty ? 1 : words.length);
      if (hit > bestScore) {
        bestScore = hit;
        best = r;
      }
    }
    if (best != null && bestScore >= 0.4) {
      return MealEstimate(
        title: best.title,
        nutrition: best.nutritionPerServing,
        isDemo: true,
        items: best.ingredients.map((i) => i.name).toList(),
        note: 'Matched to a Chefii recipe. Estimates only.',
      );
    }
    final matcher = ProductMatcher(catalog.map((e) => e.product));
    final m = matcher.best(description, minScore: 0.65);
    if (m != null) {
      final ref = nutrientReferences[m.product.id]!;
      final grams = m.product.bridge.gramsPerPiece ?? 100;
      return MealEstimate(
        title: m.product.name,
        nutrition: ref.per100g.scale(grams / 100),
        isDemo: true,
        items: [m.product.name],
        note: 'Estimated for ${grams.round()} g. Adjust the portion if needed.',
      );
    }
    return MealEstimate(
      title: description.trim(),
      nutrition: NutrientProfile.empty,
      isDemo: true,
      note: 'We couldn\'t estimate nutrition for this without AI. It\'s saved to your journal without numbers.',
    );
  }
}

class DemoImageUploader implements ImageUploader {
  @override
  Future<String> uploadReceiptPage({
    required String householdId,
    required String receiptId,
    required int page,
    required Uint8List bytes,
    required String contentType,
  }) async =>
      'demo://households/$householdId/receipts/$receiptId/page_$page';
}
