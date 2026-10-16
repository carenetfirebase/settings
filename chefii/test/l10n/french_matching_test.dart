import 'package:chefii/domain/catalog/catalog.dart';
import 'package:chefii/domain/catalog/product_matcher.dart';
import 'package:chefii/domain/inventory/inventory_command_parser.dart';
import 'package:chefii/domain/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// French receipt lines and spoken names map to the right catalogue product.
void main() {
  final matcher = ProductMatcher(catalog.map((e) => e.product));
  const cases = {
    'OEUFS GROS CAL 12': 'egg',
    'œufs': 'egg',
    'LAIT 2% 4L': 'milk',
    'lait de coco': 'coconut_milk',
    'pommes': 'apple',
    'pommes de terre': 'potato',
    'PATATES': 'potato',
    "beurre d'arachide": 'peanut_butter',
    'BEURRE SALE': 'butter',
    'bleuets': 'blueberries',
    'BOEUF HACHE MAIGRE': 'ground_beef',
    'sirop d’érable': 'maple_syrup',
    'poireaux': null, // not in the catalogue: no false match
    // English still works.
    'LG EGGS 12CT': 'egg',
    '2% milk': 'milk',
  };
  cases.forEach((text, id) {
    test(text, () {
      final m = matcher.best(text, minScore: 0.6);
      expect(m?.product.id, id, reason: 'score ${m?.score}');
    });
  });

  group('French kitchen commands', () {
    final parser = InventoryCommandParser(matcher);
    final cases = <String, (InventoryCommandAction, String, Quantity?)>{
      "J'ai utilisé deux œufs": (InventoryCommandAction.consume, 'egg', const Quantity(2, Unit.piece)),
      'j’ai mangé une banane': (InventoryCommandAction.consume, 'banana', const Quantity(1, Unit.piece)),
      '250 ml de lait utilisé': (InventoryCommandAction.consume, 'milk', null), // no verb first: not parsed below
      "J'ai acheté 2 kg de farine": (InventoryCommandAction.add, 'flour', const Quantity(2, Unit.kg)),
      "On n'a plus de lait": (InventoryCommandAction.markEmpty, 'milk', null),
      "J'ai jeté les épinards": (InventoryCommandAction.discard, 'spinach', null),
      'Il reste 4 pommes': (InventoryCommandAction.setCount, 'apple', const Quantity(4, Unit.piece)),
      "j'ai utilisé 250 ml de lait": (InventoryCommandAction.consume, 'milk', const Quantity(250, Unit.ml)),
    };
    cases.forEach((text, expected) {
      test(text, () {
        final c = parser.parse(text);
        if (text.startsWith('250')) {
          expect(c, isNull);
          return;
        }
        expect(c, isNotNull);
        expect(c!.action, expected.$1);
        expect(c.product?.id, expected.$2);
        expect(c.quantity, expected.$3);
      });
    });

    test('English still parses first', () {
      final c = parser.parse('I used two eggs')!;
      expect(c.action, InventoryCommandAction.consume);
      expect(c.quantity, const Quantity(2, Unit.piece));
    });
  });
}
