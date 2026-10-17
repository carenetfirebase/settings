import 'package:chefii/domain/catalog/catalog.dart';
import 'package:chefii/domain/catalog/product_matcher.dart';
import 'package:chefii/domain/inventory/inventory_command_parser.dart';
import 'package:chefii/domain/models/codec.dart';
import 'package:chefii/domain/models/inventory.dart';
import 'package:chefii/domain/models/nutrition.dart';
import 'package:chefii/domain/models/profile.dart';
import 'package:chefii/domain/models/recipe.dart';
import 'package:chefii/domain/recipes/curated_recipes.dart';
import 'package:chefii/domain/recipes/recipe_availability.dart';
import 'package:chefii/domain/safety/allergen_guard.dart';
import 'package:chefii/domain/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final matcher = ProductMatcher(catalog.map((e) => e.product));

  group('ProductMatcher', () {
    test('matches names, plurals and receipt abbreviations', () {
      expect(matcher.best('eggs')!.product.id, 'egg');
      expect(matcher.best('BNLS SKNLS CHKN BRST')!.product.id, 'chicken_breast');
      expect(matcher.best('MLK 2%')!.product.id, 'milk');
      expect(matcher.best('apples')!.product.id, 'apple');
    });

    test('returns null for unrelated text', () {
      expect(matcher.best('dish soap'), isNull);
    });
  });

  group('InventoryCommandParser', () {
    final parser = InventoryCommandParser(matcher);

    test('"I used two eggs"', () {
      final c = parser.parse('I used two eggs')!;
      expect(c.action, InventoryCommandAction.consume);
      expect(c.product!.id, 'egg');
      expect(c.quantity, const Quantity(2, Unit.piece));
      expect(c.isActionable, isTrue);
    });

    test('numeric amounts with units', () {
      final c = parser.parse('used 250 ml of milk')!;
      expect(c.product!.id, 'milk');
      expect(c.quantity, const Quantity(250, Unit.ml));
      final add = parser.parse('Add 1 kg flour')!;
      expect(add.action, InventoryCommandAction.add);
      expect(add.quantity, const Quantity(1, Unit.kg));
      expect(add.product!.id, 'flour');
    });

    test('marking empty and discarding', () {
      final empty = parser.parse("We're out of milk")!;
      expect(empty.action, InventoryCommandAction.markEmpty);
      expect(empty.product!.id, 'milk');
      expect(empty.isActionable, isTrue);
      final toss = parser.parse('threw out the spinach')!;
      expect(toss.action, InventoryCommandAction.discard);
      expect(toss.product!.id, 'spinach');
    });

    test('set count', () {
      final c = parser.parse('there are 4 apples left')!;
      expect(c.action, InventoryCommandAction.setCount);
      expect(c.quantity, const Quantity(4, Unit.piece));
      expect(c.product!.id, 'apple');
    });

    test('never invents a quantity for uncountable products', () {
      final c = parser.parse('used 2 milk')!;
      expect(c.product!.id, 'milk');
      expect(c.quantity, isNull, reason: '2 of what? Ask instead of guessing.');
      expect(c.isActionable, isFalse);
    });

    test('unknown phrasing returns null', () {
      expect(parser.parse('what should I cook tonight'), isNull);
    });
  });

  group('AllergenGuard', () {
    const guard = AllergenGuard();

    test('detects allergens and respects exclusions', () {
      expect(guard.detect('unsalted butter'), contains('milk'));
      expect(guard.detect('coconut milk'), isNot(contains('milk')));
      expect(guard.detect('peanut butter'), contains('peanut'));
      expect(guard.detect('peanut butter'), isNot(contains('milk')));
      expect(guard.detect('eggplant'), isNot(contains('egg')));
      expect(guard.detect('soy sauce'), containsAll(['soy', 'wheat', 'gluten']));
      expect(guard.detect('tamari'), isNot(contains('wheat')));
      expect(guard.detect('toasted almonds'), contains('tree_nut'));
      expect(guard.detect('Swiss chard'), isNot(contains('fish')));
    });

    test('blocks allergy conflicts, warns on dislikes', () {
      final r = curatedById['tomato-basil-spaghetti']!;
      final report = guard.checkRecipe(
        r,
        const DietaryProfile(allergyStatus: DisclosureStatus.provided, allergies: ['milk'], dislikes: ['basil']),
      );
      expect(report.isBlocked, isTrue);
      expect(report.blocking.first.ingredient, 'Parmigiano Reggiano');
      expect(report.conflicts.any((c) => c.severity == ConflictSeverity.dislike), isTrue);
    });

    test('allergens named only in steps, tips or preparation still block', () {
      final r = curatedById['tomato-basil-spaghetti']!;
      const peanut = DietaryProfile(allergyStatus: DisclosureStatus.provided, allergies: ['peanut']);
      expect(guard.checkRecipe(r, peanut).isBlocked, isFalse);
      Recipe withStep(RecipeStep s) => Recipe.fromMap(r.id, {...r.toMap(), 'steps': [...r.steps.map((x) => x.toMap()), s.toMap()]});
      expect(guard.checkRecipe(withStep(const RecipeStep(text: 'Garnish with crushed peanuts.')), peanut).isBlocked, isTrue);
      expect(guard.checkRecipe(withStep(const RecipeStep(text: 'Serve.', tip: 'Lovely fried in peanut oil.')), peanut).isBlocked, isTrue);
    });

    test('product allergen tags catch what names miss', () {
      final report = guard.checkIngredients(
        [('chocolate', ['milk'])],
        const DietaryProfile(allergyStatus: DisclosureStatus.provided, allergies: ['milk']),
      );
      expect(report.isBlocked, isTrue);
    });

    test('unknown allergy status is surfaced, never assumed safe', () {
      final report = guard.checkIngredients([('rice', const [])], const DietaryProfile());
      expect(report.notices.single, contains("haven't told us"));
      expect(report.isBlocked, isFalse);
    });

    test('vegetarian restriction catches meat and fish', () {
      final report = guard.checkRecipe(
        curatedById['lemon-herb-salmon']!,
        const DietaryProfile(restrictions: ['vegetarian'], allergyStatus: DisclosureStatus.noneKnown),
      );
      expect(report.isBlocked, isTrue);
    });
  });

  group('Curated recipes', () {
    test('all have computed nutrition and safe derived tags', () {
      expect(curatedRecipes.length, greaterThanOrEqualTo(20));
      for (final r in curatedRecipes) {
        expect(r.steps, isNotEmpty, reason: r.id);
        expect(r.nutritionPerServing[Nutrient.energyKcal], greaterThan(0), reason: r.id);
        expect(r.nutritionPerServing.completeness, greaterThan(0.8), reason: r.id);
        for (final i in r.ingredients.where((i) => i.productId != null)) {
          expect(catalogById.containsKey(i.productId), isTrue, reason: '${r.id}: ${i.productId}');
        }
      }
      expect(curatedById['red-lentil-dal']!.tags, contains('vegan'));
      expect(curatedById['beef-bean-chili']!.tags, isNot(contains('vegetarian')));
      expect(curatedById['chocolate-almond-plate']!.tags, isNot(contains('vegan')),
          reason: 'dark chocolate is tagged as possibly containing milk');
    });

    test('scrambled eggs nutrition is in a sensible range', () {
      final n = curatedById['soft-scrambled-eggs']!.nutritionPerServing;
      expect(n[Nutrient.energyKcal], inInclusiveRange(450, 600));
      expect(n[Nutrient.protein], inInclusiveRange(25, 40));
    });

    test('scaling servings scales ingredients', () {
      final r = curatedById['red-lentil-dal']!.scaledTo(2);
      expect(r.ingredients.first.quantity!.amount, 100);
    });
  });

  group('RecipeAvailability', () {
    InventoryLot lot(String pid, double qty, Unit unit) => InventoryLot(
          id: pid,
          householdId: 'h',
          productId: pid,
          productName: pid,
          category: FoodCategory.other,
          quantity: Quantity(qty, unit),
          initialQuantity: Quantity(qty, unit),
          locationId: 'fridge',
          acquiredAt: DateTime.utc(2026),
          source: LotSource.manual,
          provenance: const Provenance(source: ProvenanceSource.user),
          updatedAt: DateTime.utc(2026),
        );

    test('reports missing and partial ingredients', () {
      final r = curatedById['soft-scrambled-eggs']!;
      final report = const RecipeAvailability().check(r, [
        lot('egg', 2, Unit.piece),
        lot('butter', 250, Unit.g),
        lot('milk', 1, Unit.l),
        lot('salt', 500, Unit.g),
      ]);
      final byPid = {for (final c in report.checks) c.ingredient.productId: c};
      expect(byPid['egg']!.availability, IngredientAvailability.partial);
      expect(byPid['egg']!.shortBy!.amount, 1);
      expect(byPid['milk']!.availability, IngredientAvailability.available);
      expect(byPid['bread']!.availability, IngredientAvailability.missing);
      expect(report.canCookNow, isFalse);
      expect(report.label, '2 ingredients to buy');
    });

    test('ranks cookable recipes first', () {
      final ranked = const RecipeAvailability().rank(
        [curatedById['beef-bean-chili']!, curatedById['apple-peanut-butter']!],
        [lot('apple', 3, Unit.piece), lot('peanut_butter', 500, Unit.g)],
      );
      expect(ranked.first.recipe.id, 'apple-peanut-butter');
      expect(ranked.first.canCookNow, isTrue);
    });
  });

  test('CalendarDate arithmetic', () {
    const d = CalendarDate(2026, 2, 27);
    expect(d.addDays(3).toIso(), '2026-03-02');
    expect(d.daysUntil(const CalendarDate(2026, 3, 1)), 2);
  });

  test('Money formats minor units', () {
    expect(const Money(1234).format(), r'$12.34');
    expect(const Money(-5).format(), r'-$0.05');
  });

  test('Recipe round-trips through maps', () {
    final r = curatedById['red-lentil-dal']!;
    final back = Recipe.fromMap(r.id, r.toMap());
    expect(back.ingredients.length, r.ingredients.length);
    expect(back.nutritionPerServing[Nutrient.protein], closeTo(r.nutritionPerServing[Nutrient.protein], 0.01));
  });
}
