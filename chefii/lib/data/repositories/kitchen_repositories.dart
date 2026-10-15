import '../../domain/catalog/catalog.dart';
import '../../domain/models/codec.dart';
import '../../domain/models/inventory.dart';
import '../../domain/models/meals.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/models/planning.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/curated_recipes.dart';
import '../../domain/recipes/recipe_availability.dart';
import '../../domain/units/units.dart';
import '../paths.dart';
import '../store/doc_store.dart';
import 'inventory_repository.dart';

class RecipeRepository {
  RecipeRepository(this._store, {DateTime Function()? clock}) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DocStore _store;
  final DateTime Function() _clock;

  Stream<List<Recipe>> watchSaved(String householdId) => _store
      .watchQuery(HouseholdPaths(householdId).recipes, const QuerySpec(orderBy: 'createdAt', descending: true))
      .map((ds) => ds.map((d) => Recipe.fromMap(d.id, d.data)).toList());

  Future<Recipe?> find(String householdId, String id) async {
    final curated = curatedById[id];
    if (curated != null) return curated;
    final d = await _store.get(HouseholdPaths(householdId).recipe(id));
    return d == null ? null : Recipe.fromMap(d.id, d.data);
  }

  Future<void> save(String householdId, Recipe r) {
    final map = r.toMap();
    map['createdAt'] ??= _clock();
    return _store.set(HouseholdPaths(householdId).recipe(r.id), map);
  }

  Future<void> delete(String householdId, String id) => _store.delete(HouseholdPaths(householdId).recipe(id));
}

/// Cooking sessions: planned ingredients -> one confirmation -> one atomic
/// inventory deduction -> journal + leftovers.
class CookingRepository {
  CookingRepository(this._store, this._inventory, {DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  final DocStore _store;
  final InventoryRepository _inventory;
  final DateTime Function() _clock;

  static String cookOperationId(String sessionId) => 'cook_$sessionId';
  static String leftoverOperationId(String sessionId) => 'leftover_$sessionId';

  Stream<CookingSession?> watch(String householdId, String id) => _store
      .watch(HouseholdPaths(householdId).cookingSession(id))
      .map((d) => d == null ? null : CookingSession.fromMap(d.id, d.data));

  Future<CookingSession?> get(String householdId, String id) async {
    final d = await _store.get(HouseholdPaths(householdId).cookingSession(id));
    return d == null ? null : CookingSession.fromMap(d.id, d.data);
  }

  Stream<List<CookingSession>> watchRecent(String householdId, {int limit = 20}) => _store
      .watchQuery(HouseholdPaths(householdId).cookingSessions, QuerySpec(orderBy: 'startedAt', descending: true, limit: limit))
      .map((ds) => ds.map((d) => CookingSession.fromMap(d.id, d.data)).toList());

  Future<CookingSession> start({
    required String householdId,
    required String uid,
    required Recipe recipe,
    required int servings,
    String? mealPlanEntryId,
  }) async {
    final scaled = recipe.scaledTo(servings);
    final session = CookingSession(
      id: _store.newId(),
      householdId: householdId,
      uid: uid,
      recipe: scaled,
      servings: servings,
      status: CookingStatus.preparing,
      startedAt: _clock(),
      mealPlanEntryId: mealPlanEntryId,
      consumptions: [
        for (final i in scaled.ingredients)
          if (i.productId != null && i.quantity != null)
            IngredientConsumption(ingredientName: i.name, productId: i.productId, planned: i.quantity),
      ],
    );
    await _store.set(HouseholdPaths(householdId).cookingSession(session.id), session.toMap());
    return session;
  }

  Future<void> update(CookingSession s) => _store.set(HouseholdPaths(s.householdId).cookingSession(s.id), s.toMap());

  /// The single inventory confirmation for a meal. Idempotent per session.
  Future<OperationResult> confirmIngredients(CookingSession s, List<IngredientConsumption> confirmed) async {
    final requests = <ConsumeRequest>[];
    for (final c in confirmed) {
      final q = c.effectiveQuantity;
      final pid = c.effectiveProductId;
      if (q == null || pid == null || q.isZero) continue;
      requests.add(ConsumeRequest(
        productId: pid,
        productName: c.substitutedWithName ?? c.ingredientName,
        quantity: q,
        bridge: catalogById[pid]?.product.bridge ?? UnitBridge.none,
      ));
    }
    final opId = cookOperationId(s.id);
    final OperationResult result;
    if (requests.isEmpty) {
      result = OperationResult(
        InventoryOperation(
          id: opId,
          householdId: s.householdId,
          kind: OperationKind.cook,
          adjustmentIds: const [],
          lotIdsCreated: const [],
          createdAt: _clock(),
          createdBy: s.uid,
          summary: 'Cooked ${s.recipe.title} (no tracked ingredients)',
        ),
        alreadyApplied: false,
      );
    } else {
      result = await _inventory.consume(
        householdId: s.householdId,
        operationId: opId,
        actorUid: s.uid,
        requests: requests,
        kind: OperationKind.cook,
        reason: 'Cooked ${s.recipe.title}',
        summary: 'Cooked ${s.recipe.title}',
      );
    }
    await update(s.copyWith(consumptions: confirmed, status: CookingStatus.confirming, inventoryOperationId: opId));
    return result;
  }

  /// Records the meal in the cook's private journal, optional leftovers in
  /// shared inventory, and marks any plan entry as cooked.
  Future<void> complete(
    CookingSession s, {
    required double portionsEaten,
    required int leftoverPortions,
    int? rating,
    required MealType mealType,
  }) async {
    final now = _clock();
    final perServing = s.recipe.nutritionPerServing;
    final journalId = 'cook_${s.id}';
    await _store.set(
      UserPaths(s.uid).journalEntry(journalId),
      MealConsumption(
        id: journalId,
        uid: s.uid,
        title: s.recipe.title,
        mealType: mealType,
        eatenAt: now,
        portions: portionsEaten,
        source: MealEntrySource.cooked,
        createdAt: now,
        recipeId: s.recipe.id,
        cookingSessionId: s.id,
        nutrition: perServing.scale(portionsEaten),
      ).toMap(),
    );
    if (leftoverPortions > 0) {
      await _inventory.addLots(
        householdId: s.householdId,
        operationId: leftoverOperationId(s.id),
        actorUid: s.uid,
        kind: OperationKind.leftover,
        summary: 'Saved $leftoverPortions portion${leftoverPortions == 1 ? '' : 's'} of ${s.recipe.title}',
        inputs: [
          NewLotInput(
            product: FoodProduct(
              id: 'leftover_${s.recipe.id}',
              name: s.recipe.title,
              category: FoodCategory.prepared,
              defaultUnit: Unit.piece,
              defaultStorage: StorageKind.fridge,
              nutrientRefId: null,
            ),
            quantity: Quantity(leftoverPortions.toDouble(), Unit.piece),
            locationId: 'fridge',
            source: LotSource.leftover,
            provenance: const Provenance(source: ProvenanceSource.user),
            packageDescription: 'Portions',
            // Common guidance: eat refrigerated leftovers within 3–4 days.
            estimatedBestBefore: CalendarDate.fromDateTime(now.toLocal()).addDays(3),
            preparedFromRecipeId: s.recipe.id,
          ),
        ],
      );
    }
    if (s.mealPlanEntryId != null) {
      await _store.set(HouseholdPaths(s.householdId).mealPlanEntry(s.mealPlanEntryId!), {'cooked': true}, merge: true);
    }
    await update(s.copyWith(
      status: CookingStatus.completed,
      completedAt: now,
      rating: rating,
      portionsEaten: portionsEaten,
      leftoverPortions: leftoverPortions,
    ));
  }
}

class PlanningRepository {
  PlanningRepository(this._store, {DateTime Function()? clock}) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DocStore _store;
  final DateTime Function() _clock;

  Stream<List<MealPlanEntry>> watchRange(String householdId, CalendarDate from, CalendarDate toExclusive) => _store
      .watchQuery(
        HouseholdPaths(householdId).mealPlan,
        QuerySpec(where: [Where('date', WhereOp.gte, from.toIso()), Where('date', WhereOp.lt, toExclusive.toIso())], orderBy: 'date'),
      )
      .map((ds) => ds.map((d) => MealPlanEntry.fromMap(d.id, d.data)).toList());

  Future<List<MealPlanEntry>> range(String householdId, CalendarDate from, CalendarDate toExclusive) async {
    final ds = await _store.query(
      HouseholdPaths(householdId).mealPlan,
      QuerySpec(where: [Where('date', WhereOp.gte, from.toIso()), Where('date', WhereOp.lt, toExclusive.toIso())], orderBy: 'date'),
    );
    return ds.map((d) => MealPlanEntry.fromMap(d.id, d.data)).toList();
  }

  Future<MealPlanEntry> assign({
    required String householdId,
    required String uid,
    required CalendarDate date,
    required MealType mealType,
    required Recipe recipe,
    required int portions,
    String? fromLeftoverLotId,
  }) async {
    final e = MealPlanEntry(
      id: _store.newId(),
      householdId: householdId,
      date: date,
      mealType: mealType,
      recipeId: recipe.id,
      recipeTitle: recipe.title,
      portions: portions,
      createdBy: uid,
      recipeSnapshot: recipe.origin == RecipeOrigin.curated ? null : recipe,
      fromLeftoverLotId: fromLeftoverLotId,
    );
    await _store.set(HouseholdPaths(householdId).mealPlanEntry(e.id), e.toMap());
    return e;
  }

  Future<void> updateEntry(MealPlanEntry e) => _store.set(HouseholdPaths(e.householdId).mealPlanEntry(e.id), e.toMap());

  Future<void> removeEntry(String householdId, String id) => _store.delete(HouseholdPaths(householdId).mealPlanEntry(id));

  // ---- Shopping ----

  Stream<List<ShoppingItem>> watchShopping(String householdId) => _store
      .watchQuery(HouseholdPaths(householdId).shoppingItems, const QuerySpec(orderBy: 'createdAt'))
      .map((ds) => ds.map((d) => ShoppingItem.fromMap(d.id, d.data)).toList());

  Future<ShoppingItem?> shoppingItem(String householdId, String id) async {
    final d = await _store.get(HouseholdPaths(householdId).shoppingItem(id));
    return d == null ? null : ShoppingItem.fromMap(d.id, d.data);
  }

  Future<void> addShoppingItem({
    required String householdId,
    required String name,
    FoodCategory category = FoodCategory.other,
    String? productId,
    Quantity? quantity,
    ShoppingReason reason = ShoppingReason.manual,
    List<String> forRecipes = const [],
  }) {
    final id = productId == null ? _store.newId() : 'p_$productId';
    return _store.transaction((tx) async {
      final path = HouseholdPaths(householdId).shoppingItem(id);
      final existing = await tx.get(path);
      if (existing != null) {
        final e = ShoppingItem.fromMap(existing.id, existing.data);
        Quantity? merged = e.quantity;
        if (quantity != null) {
          final conv = e.quantity == null ? null : quantity.tryConvert(e.quantity!.unit, catalogById[productId]?.product.bridge ?? UnitBridge.none);
          merged = e.quantity == null ? quantity : (conv == null ? e.quantity : e.quantity! + conv.quantity);
        }
        tx.set(path, e.copyWith(quantity: merged, checked: false).toMap()
          ..['forRecipeTitles'] = {...e.forRecipeTitles, ...forRecipes}.toList());
        return;
      }
      tx.set(
        path,
        ShoppingItem(
          id: id,
          householdId: householdId,
          name: name,
          category: category,
          reason: reason,
          createdAt: _clock(),
          productId: productId,
          quantity: quantity,
          forRecipeTitles: forRecipes,
        ).toMap(),
      );
    });
  }

  Future<void> updateShoppingItem(ShoppingItem i) =>
      _store.set(HouseholdPaths(i.householdId).shoppingItem(i.id), i.toMap());

  Future<void> removeShoppingItem(String householdId, String id) =>
      _store.delete(HouseholdPaths(householdId).shoppingItem(id));

  Future<void> clearChecked(String householdId, Iterable<ShoppingItem> items) => _store.transaction((tx) async {
        for (final i in items.where((i) => i.checked)) {
          tx.delete(HouseholdPaths(householdId).shoppingItem(i.id));
        }
      });

  /// Adds whatever planned meals need that isn't in stock. Re-running is
  /// safe: items are keyed by product, so nothing duplicates — but quantities
  /// do accumulate, so callers should only run it on explicit request.
  Future<int> addMissingForPlan({
    required String householdId,
    required List<MealPlanEntry> entries,
    required List<InventoryLot> lots,
    required Recipe? Function(MealPlanEntry) recipeOf,
  }) async {
    final needs = <String, (RecipeIngredient, Quantity, Set<String>)>{};
    // Aggregate all planned requirements first, then compare to stock once.
    for (final e in entries.where((e) => !e.cooked)) {
      final r = recipeOf(e);
      if (r == null) continue;
      for (final i in r.scaledTo(e.portions).ingredients) {
        if (i.productId == null || i.quantity == null || i.optional) continue;
        final prev = needs[i.productId!];
        if (prev == null) {
          needs[i.productId!] = (i, i.quantity!, {r.title});
        } else {
          final conv = i.quantity!.tryConvert(prev.$2.unit, catalogById[i.productId]?.product.bridge ?? UnitBridge.none);
          needs[i.productId!] = (prev.$1, conv == null ? prev.$2 : prev.$2 + conv.quantity, {...prev.$3, r.title});
        }
      }
    }
    final stock = RecipeAvailability.stockByProduct(lots);
    var added = 0;
    for (final entry in needs.entries) {
      final (ing, need, titles) = entry.value;
      final have = stock[entry.key];
      Quantity? shortfall = need;
      if (have != null) {
        final conv = have.tryConvert(need.unit, catalogById[entry.key]?.product.bridge ?? UnitBridge.none);
        if (conv == null) {
          shortfall = null; // can't compare; assume covered
        } else {
          final diff = need - conv.quantity;
          shortfall = diff.isNegative || diff.isZero ? null : diff;
        }
      }
      if (shortfall == null) continue;
      final product = catalogById[entry.key]?.product;
      await addShoppingItem(
        householdId: householdId,
        name: product?.name ?? ing.name,
        category: product?.category ?? FoodCategory.other,
        productId: entry.key,
        quantity: shortfall,
        reason: ShoppingReason.missingForPlan,
        forRecipes: titles.toList(),
      );
      added++;
    }
    return added;
  }

  /// Products at or below their low-stock threshold.
  static List<FoodProduct> lowStock(List<InventoryLot> lots, Iterable<FoodProduct> products) {
    final stock = RecipeAvailability.stockByProduct(lots);
    final out = <FoodProduct>[];
    for (final p in products) {
      final t = p.lowStockThreshold;
      if (t == null) continue;
      final have = stock[p.id];
      if (have == null) continue; // never bought: not "low"
      final conv = have.tryConvert(t.unit, p.bridge);
      if (conv != null && conv.quantity.compareTo(t) <= 0) out.add(p);
    }
    return out;
  }
}

class JournalRepository {
  JournalRepository(this._store, {DateTime Function()? clock}) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DocStore _store;
  final DateTime Function() _clock;

  Stream<List<MealConsumption>> watchRange(String uid, DateTime fromUtc, DateTime toUtc) => _store
      .watchQuery(
        UserPaths(uid).journal,
        QuerySpec(where: [Where('eatenAt', WhereOp.gte, fromUtc), Where('eatenAt', WhereOp.lt, toUtc)], orderBy: 'eatenAt', descending: true),
      )
      .map((ds) => ds.map((d) => MealConsumption.fromMap(d.id, d.data)).toList());

  Future<List<MealConsumption>> range(String uid, DateTime fromUtc, DateTime toUtc) async {
    final ds = await _store.query(
      UserPaths(uid).journal,
      QuerySpec(where: [Where('eatenAt', WhereOp.gte, fromUtc), Where('eatenAt', WhereOp.lt, toUtc)], orderBy: 'eatenAt'),
    );
    return ds.map((d) => MealConsumption.fromMap(d.id, d.data)).toList();
  }

  Future<MealConsumption> add({
    required String uid,
    required String title,
    required MealType mealType,
    required DateTime eatenAt,
    required double portions,
    required MealEntrySource source,
    NutrientProfile nutrition = NutrientProfile.empty,
    String? recipeId,
    String? notes,
  }) async {
    final m = MealConsumption(
      id: _store.newId(),
      uid: uid,
      title: title,
      mealType: mealType,
      eatenAt: eatenAt.toUtc(),
      portions: portions,
      source: source,
      createdAt: _clock(),
      recipeId: recipeId,
      nutrition: nutrition,
      notes: notes,
    );
    await _store.set(UserPaths(uid).journalEntry(m.id), m.toMap());
    return m;
  }

  Future<void> update(MealConsumption m) => _store.set(UserPaths(m.uid).journalEntry(m.id), m.toMap());

  Future<void> delete(String uid, String id) => _store.delete(UserPaths(uid).journalEntry(id));
}
