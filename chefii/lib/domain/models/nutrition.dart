import 'codec.dart';

/// Nutrients we estimate. Values are per the context they're attached to
/// (per 100 g in references, per serving in recipes, per day in snapshots).
enum Nutrient {
  energyKcal('Calories', 'kcal'),
  protein('Protein', 'g'),
  carbohydrate('Carbohydrates', 'g'),
  fat('Fat', 'g'),
  saturatedFat('Saturated fat', 'g'),
  fibre('Fibre', 'g'),
  sugars('Total sugars', 'g'),
  sodium('Sodium', 'mg'),
  calcium('Calcium', 'mg'),
  iron('Iron', 'mg'),
  potassium('Potassium', 'mg'),
  vitaminC('Vitamin C', 'mg');

  const Nutrient(this.label, this.unit);
  final String label;
  final String unit;

  static const core = [energyKcal, protein, carbohydrate, fat, fibre, sodium];
}

/// A set of nutrient values plus how complete the underlying data was.
class NutrientProfile {
  const NutrientProfile(this.values, {this.completeness = 1, this.isEstimate = true});

  final Map<Nutrient, double> values;

  /// Fraction (0..1) of ingredient mass that had reference data.
  final double completeness;

  /// Nutrition shown in Chefii is always an estimate unless a professional
  /// or a label provided it.
  final bool isEstimate;

  static const empty = NutrientProfile({}, completeness: 0);

  double operator [](Nutrient n) => values[n] ?? 0;

  bool has(Nutrient n) => values.containsKey(n);

  NutrientProfile operator +(NutrientProfile o) {
    final out = Map<Nutrient, double>.from(values);
    o.values.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    return NutrientProfile(out, completeness: (completeness + o.completeness) / 2, isEstimate: isEstimate || o.isEstimate);
  }

  NutrientProfile scale(double factor) => NutrientProfile(
        values.map((k, v) => MapEntry(k, v * factor)),
        completeness: completeness,
        isEstimate: isEstimate,
      );

  Map<String, dynamic> toMap() => {
        'values': values.map((k, v) => MapEntry(k.name, double.parse(v.toStringAsFixed(2)))),
        'completeness': completeness,
        'isEstimate': isEstimate,
      };

  static NutrientProfile fromMap(Object? raw) {
    final m = readMap(raw);
    final vals = <Nutrient, double>{};
    readMap(m['values']).forEach((k, v) {
      final n = Nutrient.values.where((e) => e.name == k).firstOrNull;
      if (n != null && v is num) vals[n] = v.toDouble();
    });
    return NutrientProfile(
      vals,
      completeness: (m['completeness'] as num?)?.toDouble() ?? 1,
      isEstimate: m['isEstimate'] as bool? ?? true,
    );
  }
}

/// Reference composition per 100 g of an ingredient.
class NutrientReference {
  const NutrientReference({required this.id, required this.name, required this.per100g, required this.source});

  final String id;
  final String name;
  final NutrientProfile per100g;

  /// e.g. "USDA FoodData Central (SR Legacy), rounded".
  final String source;
}

/// Dietary reference value for an adult, used for context, never as a target
/// imposed on the user.
class DailyReference {
  const DailyReference(this.nutrient, this.amount, this.kind, this.source);

  final Nutrient nutrient;
  final double amount;

  /// 'Daily Value' (label reference), 'AI', 'RDA', 'CDRR' (upper reduction target).
  final String kind;
  final String source;
}

/// Health Canada label Daily Values for adults/children ≥4 (2016 amendments
/// to the Food and Drug Regulations). Used only as a common yardstick.
const dailyReferences = <Nutrient, DailyReference>{
  Nutrient.fibre: DailyReference(Nutrient.fibre, 28, 'Daily Value', 'Health Canada, Table of Daily Values'),
  Nutrient.sodium: DailyReference(Nutrient.sodium, 2300, 'Daily Value', 'Health Canada, Table of Daily Values'),
  Nutrient.fat: DailyReference(Nutrient.fat, 75, 'Daily Value', 'Health Canada, Table of Daily Values'),
  Nutrient.saturatedFat: DailyReference(Nutrient.saturatedFat, 20, 'Daily Value', 'Health Canada, Table of Daily Values'),
  Nutrient.sugars: DailyReference(Nutrient.sugars, 100, 'Daily Value', 'Health Canada, Table of Daily Values'),
  Nutrient.calcium: DailyReference(Nutrient.calcium, 1300, 'Daily Value', 'Health Canada, Table of Daily Values'),
  Nutrient.iron: DailyReference(Nutrient.iron, 18, 'Daily Value', 'Health Canada, Table of Daily Values'),
  Nutrient.potassium: DailyReference(Nutrient.potassium, 3400, 'Daily Value', 'Health Canada, Table of Daily Values'),
  Nutrient.vitaminC: DailyReference(Nutrient.vitaminC, 90, 'Daily Value', 'Health Canada, Table of Daily Values'),
};
