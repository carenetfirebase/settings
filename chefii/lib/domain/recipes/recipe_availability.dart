import '../catalog/catalog.dart';
import '../models/codec.dart';
import '../models/inventory.dart';
import '../models/recipe.dart';
import '../units/units.dart';

enum IngredientAvailability { available, partial, missing, untracked }

class IngredientCheck {
  const IngredientCheck(this.ingredient, this.availability, {this.onHand, this.shortBy, this.expiringSoon = false});

  final RecipeIngredient ingredient;
  final IngredientAvailability availability;
  final Quantity? onHand;
  final Quantity? shortBy;

  /// Uses something that's close to its date — good to cook first.
  final bool expiringSoon;
}

class AvailabilityReport {
  const AvailabilityReport(this.recipe, this.checks);

  final Recipe recipe;
  final List<IngredientCheck> checks;

  Iterable<IngredientCheck> get _required =>
      checks.where((c) => !c.ingredient.optional && c.availability != IngredientAvailability.untracked);

  Iterable<IngredientCheck> get missing =>
      _required.where((c) => c.availability == IngredientAvailability.missing || c.availability == IngredientAvailability.partial);

  /// Fraction of required, trackable ingredients fully on hand.
  double get score {
    final req = _required.toList();
    if (req.isEmpty) return 1;
    return req.where((c) => c.availability == IngredientAvailability.available).length / req.length;
  }

  bool get canCookNow => missing.isEmpty;
  bool get usesExpiringItems => checks.any((c) => c.expiringSoon);

  String get label {
    final n = missing.length;
    if (n == 0) return 'Everything on hand';
    return n == 1 ? '1 ingredient to buy' : '$n ingredients to buy';
  }
}

/// Compares a recipe against current stock (aggregated across lots).
class RecipeAvailability {
  const RecipeAvailability();

  /// Total on-hand per product in that product's default unit.
  static Map<String, Quantity> stockByProduct(Iterable<InventoryLot> lots) {
    final out = <String, Quantity>{};
    for (final l in lots) {
      if (l.isDepleted) continue;
      final existing = out[l.productId];
      if (existing == null) {
        out[l.productId] = l.quantity;
      } else {
        final bridge = catalogById[l.productId]?.product.bridge ?? UnitBridge.none;
        final conv = l.quantity.tryConvert(existing.unit, bridge);
        if (conv != null) out[l.productId] = existing + conv.quantity;
      }
    }
    return out;
  }

  AvailabilityReport check(Recipe recipe, Iterable<InventoryLot> lots, {CalendarDate? today}) {
    final lotList = lots.toList();
    final stock = stockByProduct(lotList);
    final checks = <IngredientCheck>[];
    for (final ing in recipe.ingredients) {
      final pid = ing.productId;
      if (pid == null || ing.quantity == null) {
        checks.add(IngredientCheck(ing, pid != null && stock.containsKey(pid) ? IngredientAvailability.available : IngredientAvailability.untracked));
        continue;
      }
      final have = stock[pid];
      final expiring = today != null &&
          lotList.any((l) => l.productId == pid && !l.isDepleted && (l.daysLeft(today) ?? 99) <= 2);
      if (have == null) {
        checks.add(IngredientCheck(ing, IngredientAvailability.missing, shortBy: ing.quantity));
        continue;
      }
      final bridge = ing.bridge.gramsPerMl != null || ing.bridge.gramsPerPiece != null
          ? ing.bridge
          : (catalogById[pid]?.product.bridge ?? UnitBridge.none);
      final need = ing.quantity!.tryConvert(have.unit, bridge);
      if (need == null) {
        // Can't compare units reliably; having some counts as available.
        checks.add(IngredientCheck(ing, IngredientAvailability.available, onHand: have, expiringSoon: expiring));
        continue;
      }
      if (have.compareTo(need.quantity) >= 0) {
        checks.add(IngredientCheck(ing, IngredientAvailability.available, onHand: have, expiringSoon: expiring));
      } else {
        checks.add(IngredientCheck(ing, IngredientAvailability.partial,
            onHand: have, shortBy: need.quantity - have, expiringSoon: expiring));
      }
    }
    return AvailabilityReport(recipe, checks);
  }

  /// Ranks recipes: cookable first, then those rescuing expiring food.
  List<AvailabilityReport> rank(Iterable<Recipe> recipes, Iterable<InventoryLot> lots, {CalendarDate? today}) {
    final reports = recipes.map((r) => check(r, lots, today: today)).toList()
      ..sort((a, b) {
        final s = b.score.compareTo(a.score);
        if (s != 0) return s;
        if (a.usesExpiringItems != b.usesExpiringItems) return a.usesExpiringItems ? -1 : 1;
        return a.recipe.totalMinutes.compareTo(b.recipe.totalMinutes);
      });
    return reports;
  }
}
