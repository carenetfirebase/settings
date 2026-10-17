import '../models/codec.dart';
import '../models/inventory.dart';
import '../units/units.dart';

/// Amount to take from one lot, expressed in that lot's unit.
class LotAllocation {
  const LotAllocation({required this.lot, required this.take, required this.isEstimate});

  final InventoryLot lot;
  final Quantity take;

  /// True if a density/per-piece bridge was used to convert units.
  final bool isEstimate;

  Quantity get remainingAfter => lot.quantity - take;
}

class ConsumptionPlan {
  const ConsumptionPlan({
    required this.requested,
    required this.allocations,
    required this.shortfall,
    required this.incompatibleLotIds,
  });

  final Quantity requested;
  final List<LotAllocation> allocations;

  /// Requested amount we could not find in recorded stock (requested unit).
  final Quantity shortfall;

  /// Lots skipped because their unit cannot be converted reliably.
  final List<String> incompatibleLotIds;

  bool get isFullySatisfied => shortfall.isZero;
  bool get usesEstimates => allocations.any((a) => a.isEstimate);
}

/// Pure planning logic: which lots to draw from, and how much.
///
/// Order of preference: an explicitly chosen lot, then the earliest confirmed
/// date, then the earliest estimated date, then oldest purchase. Lots in
/// [deprioritizedLocationIds] (typically the freezer) are used last. Stock is
/// never driven below zero — any excess becomes a reported shortfall.
class ConsumptionPlanner {
  const ConsumptionPlanner();

  ConsumptionPlan plan({
    required List<InventoryLot> lots,
    required Quantity requested,
    UnitBridge bridge = UnitBridge.none,
    String? preferLotId,
    Set<String> deprioritizedLocationIds = const {'freezer'},
  }) {
    if (requested.isNegative) {
      throw ArgumentError.value(requested, 'requested', 'must not be negative');
    }
    final candidates = lots.where((l) => !l.isDepleted).toList()
      ..sort((a, b) => _compare(a, b, preferLotId, deprioritizedLocationIds));

    final allocations = <LotAllocation>[];
    final incompatible = <String>[];
    var remaining = requested;

    for (final lot in candidates) {
      if (remaining.isZero) break;
      final inLotUnit = remaining.tryConvert(lot.quantity.unit, bridge);
      if (inLotUnit == null) {
        incompatible.add(lot.id);
        continue;
      }
      final take = inLotUnit.quantity.compareTo(lot.quantity) <= 0
          ? inLotUnit.quantity
          : lot.quantity;
      if (take.isZero) continue;
      final takenInRequested = take.tryConvert(requested.unit, bridge)!;
      allocations.add(LotAllocation(
        lot: lot,
        take: take,
        isEstimate: inLotUnit.isEstimate || takenInRequested.isEstimate,
      ));
      remaining = remaining - takenInRequested.quantity;
      // Absorb rounding residue from 3-decimal arithmetic.
      if (remaining.amount < 0.002) remaining = Quantity(0, requested.unit);
    }

    return ConsumptionPlan(
      requested: requested,
      allocations: allocations,
      shortfall: remaining,
      incompatibleLotIds: incompatible,
    );
  }

  static int _compare(InventoryLot a, InventoryLot b, String? prefer, Set<String> lastIds) {
    if (prefer != null) {
      if (a.id == prefer && b.id != prefer) return -1;
      if (b.id == prefer && a.id != prefer) return 1;
    }
    final aLast = lastIds.contains(a.locationId);
    final bLast = lastIds.contains(b.locationId);
    if (aLast != bLast) return aLast ? 1 : -1;
    final byConfirmed = _nullsLast(a.useByDate, b.useByDate);
    if (byConfirmed != 0) return byConfirmed;
    final byEstimate = _nullsLast(a.estimatedBestBefore, b.estimatedBestBefore);
    if (byEstimate != 0) return byEstimate;
    final byAge = a.acquiredAt.compareTo(b.acquiredAt);
    if (byAge != 0) return byAge;
    return a.id.compareTo(b.id);
  }

  static int _nullsLast(CalendarDate? a, CalendarDate? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }
}
