import '../models/inventory.dart';

class ProductMatch {
  const ProductMatch(this.product, this.score);
  final FoodProduct product;

  /// 0..1 similarity.
  final double score;
}

/// Matches free text (receipt lines, voice commands, AI ingredient names) to
/// catalogue products. Deterministic and explainable: exact name/alias, then
/// token overlap with simple plural folding.
class ProductMatcher {
  ProductMatcher(Iterable<FoodProduct> products) : _products = products.toList();

  final List<FoodProduct> _products;

  static const _stop = {
    'the', 'a', 'an', 'of', 'some', 'fresh', 'organic', 'large', 'small', 'medium', 'lg', 'sm', 'pk', 'pack',
    'bag', 'box', 'can', 'jar', 'bottle', 'my', 'our', 'and', 'with', 'g', 'kg', 'ml', 'l', 'lb', 'oz', 'each',
    // French (Québec receipts and voice).
    'le', 'la', 'les', 'de', 'du', 'des', 'd', 'un', 'une', 'au', 'aux', 'et', 'avec', 'mon', 'ma', 'mes', 'nos',
    'frais', 'fraiche', 'bio', 'biologique', 'gros', 'grosse', 'petit', 'petite', 'sac', 'boite', 'pot', 'bouteille',
    'paquet', 'conserve', 'chaque', 'unite',
  };

  static const _fold = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i',
    'ô': 'o', 'ö': 'o', 'û': 'u', 'ù': 'u', 'ü': 'u', 'ÿ': 'y', 'ñ': 'n', 'æ': 'ae', 'œ': 'oe',
  };

  /// Lower-case and fold accents so "Œufs" matches "oeufs".
  static String fold(String s) => s.toLowerCase().split('').map((c) => _fold[c] ?? c).join();

  static List<String> tokens(String s) => fold(s)
      .replaceAll(RegExp(r"['’]"), ' ')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !_stop.contains(t) && !RegExp(r'^\d+$').hasMatch(t))
      .map(_singular)
      .toList();

  static String _singular(String t) {
    if (t.length > 4 && (t.endsWith('eaux') || t.endsWith('oux'))) return t.substring(0, t.length - 1);
    if (t.length > 4 && t.endsWith('ies')) return '${t.substring(0, t.length - 3)}y';
    if (t.length > 4 && t.endsWith('oes')) return t.substring(0, t.length - 2);
    if (t.length > 3 && t.endsWith('s') && !t.endsWith('ss')) return t.substring(0, t.length - 1);
    return t;
  }

  List<ProductMatch> search(String query, {int limit = 5, double minScore = 0.34}) {
    final q = fold(query.trim());
    if (q.isEmpty) return const [];
    final qt = tokens(q).toSet();
    final results = <ProductMatch>[];
    for (final p in _products) {
      var best = 0.0;
      final names = [p.name, p.id.replaceAll('_', ' '), ...p.aliases];
      for (final n in names) {
        final nl = fold(n);
        if (nl == q) {
          best = 1;
          break;
        }
        final nt = tokens(nl).toSet();
        if (nt.isEmpty || qt.isEmpty) continue;
        final inter = nt.intersection(qt).length;
        if (inter == 0) continue;
        // Weighted: how much of the product name the query covers matters most.
        final coverage = inter / nt.length;
        final precision = inter / qt.length;
        final s = 0.7 * coverage + 0.3 * precision;
        if (s > best) best = s;
      }
      if (best >= minScore) results.add(ProductMatch(p, best));
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList();
  }

  ProductMatch? best(String query, {double minScore = 0.5}) {
    final r = search(query, limit: 1, minScore: minScore);
    return r.isEmpty ? null : r.first;
  }
}
