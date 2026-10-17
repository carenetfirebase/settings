/// Explicit units and conversion rules.
///
/// Rule: quantities are only converted inside a dimension (mass, volume,
/// count) unless a product supplies a reliable bridge (density, or the mass
/// of one piece). Bridged conversions are flagged as estimates so callers can
/// downgrade inventory confidence accordingly. Nothing here ever silently
/// mixes pieces, grams, millilitres or servings.
library;

enum Dimension { mass, volume, count }

enum Unit {
  mg('mg', Dimension.mass, 0.001),
  g('g', Dimension.mass, 1),
  kg('kg', Dimension.mass, 1000),
  oz('oz', Dimension.mass, 28.349523125),
  lb('lb', Dimension.mass, 453.59237),
  ml('ml', Dimension.volume, 1),
  l('L', Dimension.volume, 1000),
  // Canadian/US customary kitchen measures (metric cup used in Canada = 250 ml).
  tsp('tsp', Dimension.volume, 5),
  tbsp('tbsp', Dimension.volume, 15),
  cup('cup', Dimension.volume, 250),
  piece('pc', Dimension.count, 1),
  dozen('dozen', Dimension.count, 12);

  const Unit(this.symbol, this.dimension, this.toBase);

  final String symbol;
  final Dimension dimension;

  /// Factor converting one of this unit into the dimension's base unit
  /// (g, ml or piece).
  final double toBase;

  static Unit? tryParse(String raw) {
    final s = raw.trim().toLowerCase();
    for (final u in Unit.values) {
      if (u.name == s || u.symbol.toLowerCase() == s) return u;
    }
    const aliases = <String, Unit>{
      'gram': Unit.g,
      'grams': Unit.g,
      'gr': Unit.g,
      'kilogram': Unit.kg,
      'kilograms': Unit.kg,
      'kgs': Unit.kg,
      'milligram': Unit.mg,
      'milligrams': Unit.mg,
      'ounce': Unit.oz,
      'ounces': Unit.oz,
      'pound': Unit.lb,
      'pounds': Unit.lb,
      'lbs': Unit.lb,
      'millilitre': Unit.ml,
      'millilitres': Unit.ml,
      'milliliter': Unit.ml,
      'milliliters': Unit.ml,
      'litre': Unit.l,
      'litres': Unit.l,
      'liter': Unit.l,
      'liters': Unit.l,
      'teaspoon': Unit.tsp,
      'teaspoons': Unit.tsp,
      'tablespoon': Unit.tbsp,
      'tablespoons': Unit.tbsp,
      'cups': Unit.cup,
      'pc': Unit.piece,
      'pcs': Unit.piece,
      'pieces': Unit.piece,
      'each': Unit.piece,
      'ea': Unit.piece,
      'unit': Unit.piece,
      'units': Unit.piece,
      'x': Unit.piece,
      // Canadian French.
      'gramme': Unit.g,
      'grammes': Unit.g,
      'kilo': Unit.kg,
      'kilos': Unit.kg,
      'kilogramme': Unit.kg,
      'kilogrammes': Unit.kg,
      'once': Unit.oz,
      'onces': Unit.oz,
      'livre': Unit.lb,
      'livres': Unit.lb,
      'tasse': Unit.cup,
      'tasses': Unit.cup,
      'unite': Unit.piece,
      'unites': Unit.piece,
      'unité': Unit.piece,
      'unités': Unit.piece,
      'douzaine': Unit.dozen,
      'douzaines': Unit.dozen,
    };
    return aliases[s];
  }
}

/// Product-specific bridges between dimensions. Supplied only when known.
class UnitBridge {
  const UnitBridge({this.gramsPerMl, this.gramsPerPiece, this.isEstimate = true});

  /// Density, e.g. milk ≈ 1.03 g/ml.
  final double? gramsPerMl;

  /// Typical mass of one piece, e.g. a large egg ≈ 50 g.
  final double? gramsPerPiece;

  /// Bridges are typical values, so conversions through them are estimates.
  final bool isEstimate;

  static const none = UnitBridge();

  Map<String, dynamic> toMap() => {
        if (gramsPerMl != null) 'gramsPerMl': gramsPerMl,
        if (gramsPerPiece != null) 'gramsPerPiece': gramsPerPiece,
        'isEstimate': isEstimate,
      };

  static UnitBridge fromMap(Map<String, dynamic>? m) {
    if (m == null) return none;
    return UnitBridge(
      gramsPerMl: (m['gramsPerMl'] as num?)?.toDouble(),
      gramsPerPiece: (m['gramsPerPiece'] as num?)?.toDouble(),
      isEstimate: m['isEstimate'] as bool? ?? true,
    );
  }
}

class ConversionResult {
  const ConversionResult(this.quantity, {required this.isEstimate});
  final Quantity quantity;
  final bool isEstimate;
}

class UnitConversionException implements Exception {
  UnitConversionException(this.from, this.to);
  final Unit from;
  final Unit to;
  @override
  String toString() =>
      'Cannot convert ${from.symbol} to ${to.symbol} without a known product bridge';
}

/// An immutable amount with an explicit unit.
class Quantity implements Comparable<Quantity> {
  const Quantity(this.amount, this.unit);

  final double amount;
  final Unit unit;

  static const double epsilon = 1e-6;

  bool get isZero => amount.abs() < epsilon;
  bool get isNegative => amount < -epsilon;

  double get inBase => amount * unit.toBase;

  Quantity operator +(Quantity other) =>
      Quantity(_round(amount + other.to(unit).amount), unit);
  Quantity operator -(Quantity other) =>
      Quantity(_round(amount - other.to(unit).amount), unit);
  Quantity operator *(num factor) => Quantity(_round(amount * factor), unit);
  Quantity operator -() => Quantity(-amount, unit);

  /// Converts within the same dimension. Throws across dimensions.
  Quantity to(Unit target) {
    if (target == unit) return this;
    if (target.dimension != unit.dimension) {
      throw UnitConversionException(unit, target);
    }
    return Quantity(_round(inBase / target.toBase), target);
  }

  bool canConvertTo(Unit target, [UnitBridge bridge = UnitBridge.none]) =>
      tryConvert(target, bridge) != null;

  /// Converts, crossing dimensions only through an explicit [bridge].
  ConversionResult? tryConvert(Unit target, [UnitBridge bridge = UnitBridge.none]) {
    if (target.dimension == unit.dimension) {
      return ConversionResult(to(target), isEstimate: false);
    }
    final grams = _toGrams(bridge);
    if (grams == null) return null;
    final double? targetBase = switch (target.dimension) {
      Dimension.mass => grams,
      Dimension.volume =>
        bridge.gramsPerMl == null ? null : grams / bridge.gramsPerMl!,
      Dimension.count =>
        bridge.gramsPerPiece == null ? null : grams / bridge.gramsPerPiece!,
    };
    if (targetBase == null) return null;
    return ConversionResult(
      Quantity(_round(targetBase / target.toBase), target),
      isEstimate: bridge.isEstimate,
    );
  }

  double? _toGrams(UnitBridge bridge) => switch (unit.dimension) {
        Dimension.mass => inBase,
        Dimension.volume =>
          bridge.gramsPerMl == null ? null : inBase * bridge.gramsPerMl!,
        Dimension.count =>
          bridge.gramsPerPiece == null ? null : inBase * bridge.gramsPerPiece!,
      };

  @override
  int compareTo(Quantity other) => inBase.compareTo(other.to(unit).inBase);

  @override
  bool operator ==(Object other) =>
      other is Quantity &&
      other.unit.dimension == unit.dimension &&
      (other.inBase - inBase).abs() < epsilon;

  @override
  int get hashCode => Object.hash(unit.dimension, (inBase * 1000).round());

  /// Human-friendly formatting: "2 pc", "1.5 kg", "250 ml". UI code uses
  /// `context.formatQty(q)` (lib/l10n/labels.dart) for translated units.
  String format({String Function(Unit unit)? unitLabel, String decimalSeparator = '.'}) {
    final a = amount;
    // Counted items read like a cook writes them: "½ onion", "1½ cloves".
    if (unit.dimension == Dimension.count) {
      final whole = a.floor();
      final frac = a - whole;
      const glyphs = [(0.25, '¼'), (0.5, '½'), (0.75, '¾')];
      for (final (value, glyph) in glyphs) {
        if ((frac - value).abs() < 0.01) {
          return '${whole == 0 ? '' : whole}$glyph ${unitLabel?.call(unit) ?? unit.symbol}';
        }
      }
    }
    final text = (a - a.roundToDouble()).abs() < 0.005
        ? a.round().toString()
        : a.toStringAsFixed(a.abs() < 10 ? 2 : 1).replaceFirst(RegExp(r'\.?0+$'), '');
    return '${text.replaceAll('.', decimalSeparator)} ${unitLabel?.call(unit) ?? unit.symbol}';
  }

  @override
  String toString() => format();

  Map<String, dynamic> toMap() => {'amount': amount, 'unit': unit.name};

  static Quantity fromMap(Map<String, dynamic> m) => Quantity(
        (m['amount'] as num).toDouble(),
        Unit.values.byName(m['unit'] as String),
      );

  static double _round(double v) => (v * 1000).roundToDouble() / 1000;
}
