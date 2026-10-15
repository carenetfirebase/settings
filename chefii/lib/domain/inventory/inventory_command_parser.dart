import '../catalog/product_matcher.dart';
import '../models/inventory.dart';
import '../units/units.dart';

enum InventoryCommandAction {
  consume('Use'),
  add('Add'),
  discard('Discard'),
  markEmpty('Mark empty'),
  setCount('Set count');

  const InventoryCommandAction(this.label);
  final String label;
}

/// A parsed, *unapplied* instruction. The UI always shows it for confirmation.
class InventoryCommand {
  const InventoryCommand({
    required this.action,
    required this.productQuery,
    this.product,
    this.quantity,
    this.confidence = 1,
  });

  final InventoryCommandAction action;
  final String productQuery;
  final FoodProduct? product;
  final Quantity? quantity;
  final double confidence;

  bool get isActionable => product != null && (quantity != null || action == InventoryCommandAction.markEmpty);

  String describe() {
    final what = product?.name ?? '"$productQuery"';
    return switch (action) {
      InventoryCommandAction.markEmpty => 'Mark $what as used up',
      InventoryCommandAction.setCount => 'Set $what to ${quantity?.format() ?? '?'}',
      _ => '${action.label} ${quantity?.format() ?? ''} $what'.replaceAll(RegExp(r'\s+'), ' '),
    };
  }
}

/// Deterministic parser for everyday kitchen phrases. Works offline and with
/// AI disabled; the AI path (functions: parseInventoryCommand) is only used
/// when this returns null.
///
/// Examples: "I used two eggs", "add 1 kg flour", "threw out the spinach",
/// "we're out of milk", "there are 4 apples left", "used 250 ml of milk".
class InventoryCommandParser {
  InventoryCommandParser(this.matcher);

  final ProductMatcher matcher;

  static const _numbers = {
    'a': 1.0, 'an': 1.0, 'one': 1.0, 'two': 2.0, 'three': 3.0, 'four': 4.0, 'five': 5.0, 'six': 6.0,
    'seven': 7.0, 'eight': 8.0, 'nine': 9.0, 'ten': 10.0, 'eleven': 11.0, 'twelve': 12.0, 'half': 0.5,
    'half a': 0.5, 'a half': 0.5, 'a couple of': 2.0, 'a couple': 2.0, 'couple of': 2.0, 'a dozen': 12.0,
    'dozen': 12.0, 'a few': 3.0, 'quarter': 0.25, 'a quarter': 0.25,
  };

  static final _consume = RegExp(r'^(?:i |we )?(?:just )?(?:used|ate|had|cooked with|took|drank|consumed|use)\s+(.+)$');
  static final _add = RegExp(r'^(?:i |we )?(?:just )?(?:added|add|bought|got|picked up|purchased|put away)\s+(.+)$');
  static final _discard = RegExp(r'^(?:i |we )?(?:just )?(?:threw out|threw away|tossed|discarded|binned|composted|throw out|toss|discard)\s+(.+)$');
  static final _empty = RegExp(r"^(?:i |we )?(?:'re |are |am |'m )?(?:just )?(?:finished|used up|used all(?: of)?|ran out of|run out of|out of|no more|all out of|finished off)\s+(.+)$");
  static final _setCount = RegExp(r'^(?:there (?:are|is)|we have|i have|we\x27ve got|i\x27ve got|only)\s+(.+?)(?:\s+left)?$');

  InventoryCommand? parse(String input) {
    var s = input.trim().toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r'[.!?]+$'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) return null;
    // "we're out of milk" -> normalise contractions used by _empty.
    s = s.replaceFirstMapped(RegExp(r"^(we|i)(['’]re|['’]m| are| am) "), (m) => '${m[1]} ');

    RegExpMatch? m;
    if ((m = _empty.firstMatch(s)) != null) {
      return _build(InventoryCommandAction.markEmpty, m!.group(1)!);
    }
    if ((m = _discard.firstMatch(s)) != null) {
      return _build(InventoryCommandAction.discard, m!.group(1)!);
    }
    if ((m = _consume.firstMatch(s)) != null) {
      return _build(InventoryCommandAction.consume, m!.group(1)!);
    }
    if ((m = _add.firstMatch(s)) != null) {
      return _build(InventoryCommandAction.add, m!.group(1)!);
    }
    if ((m = _setCount.firstMatch(s)) != null) {
      return _build(InventoryCommandAction.setCount, m!.group(1)!);
    }
    return null;
  }

  InventoryCommand? _build(InventoryCommandAction action, String rest) {
    var text = rest.trim().replaceFirst(RegExp(r'^(?:the|my|our|all the|all of the|all|of the)\s+'), '');
    Quantity? qty;
    var parsedQty = false;

    // Numeric amount: "250 ml of milk", "1.5kg flour", "2 eggs"
    final numeric = RegExp(r'^(\d+(?:[.,]\d+)?|\d+/\d+)\s*([a-z]+)?\s*(?:of\s+)?(.*)$').firstMatch(text);
    double? amount;
    String? unitWord;
    if (numeric != null) {
      amount = _parseNumber(numeric.group(1)!);
      unitWord = numeric.group(2);
      text = numeric.group(3)!;
      parsedQty = true;
    } else {
      final words = _numbers.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
      for (final w in words) {
        if (text == w || text.startsWith('$w ')) {
          amount = _numbers[w];
          text = text.substring(w.length).trim();
          final uw = RegExp(r'^([a-z]+)\s+(?:of\s+)?(.*)$').firstMatch(text);
          if (uw != null && Unit.tryParse(uw.group(1)!) != null) {
            unitWord = uw.group(1);
            text = uw.group(2)!;
          }
          parsedQty = true;
          break;
        }
      }
    }

    Unit? unit;
    if (unitWord != null) {
      unit = Unit.tryParse(unitWord);
      if (unit == null) {
        // Not a unit: it was the first word of the product ("2 eggs").
        text = '$unitWord $text'.trim();
      }
    }
    text = text.replaceFirst(RegExp(r'^(?:of\s+)?(?:the\s+)?'), '').trim();
    if (text.isEmpty) return null;

    final match = matcher.best(text, minScore: 0.45);
    final product = match?.product;
    if (parsedQty && amount != null) {
      unit ??= product?.defaultUnit == Unit.piece || product == null ? Unit.piece : product.defaultUnit;
      // "2 milk" with a volume product and no unit is ambiguous: keep pieces
      // only if the product is counted; otherwise leave quantity unset.
      final explicitUnit = unitWord != null && Unit.tryParse(unitWord) != null;
      if (!explicitUnit && product != null && product.defaultUnit.dimension != Dimension.count) {
        qty = null;
      } else {
        qty = Quantity(amount, unit);
      }
    }
    // A missing quantity is returned as-is; the UI asks for the amount.
    return InventoryCommand(
      action: action,
      productQuery: text,
      product: product,
      quantity: qty,
      confidence: match?.score ?? 0,
    );
  }

  static double? _parseNumber(String s) {
    if (s.contains('/')) {
      final p = s.split('/');
      final d = double.tryParse(p[1]);
      return d == null || d == 0 ? null : (double.tryParse(p[0]) ?? 0) / d;
    }
    return double.tryParse(s.replaceAll(',', '.'));
  }
}
