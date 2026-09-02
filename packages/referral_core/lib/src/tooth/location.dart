import '../enums.dart';
import 'tooth.dart';

/// The shapes a referral location can take.
enum LocationKind {
  tooth('tooth'),
  quadrant('quadrant'),
  region('region'),
  generalized('generalized'),
  fullMouth('full_mouth');

  const LocationKind(this.wire);

  final String wire;

  static LocationKind? fromWire(String? value) {
    for (final k in LocationKind.values) {
      if (k.wire == value) return k;
    }
    return null;
  }
}

/// One place a referral concerns.
///
/// A draft holds a list of these, so "18 and 28" is two tooth locations and
/// "generalized" is one.
class ReferralLocation {
  const ReferralLocation._({
    required this.kind,
    this.toothCode,
    this.notation,
    this.canonicalFdi,
    this.quadrant,
    this.region,
  });

  /// A single tooth, recorded as the professional said it plus the notation
  /// they work in. [canonicalFdi] is an internal key for comparison only.
  factory ReferralLocation.tooth({
    required String code,
    required ToothNotation notation,
    String? canonicalFdi,
  }) =>
      ReferralLocation._(
        kind: LocationKind.tooth,
        toothCode: code.trim().toUpperCase(),
        notation: notation,
        canonicalFdi: canonicalFdi,
      );

  factory ReferralLocation.quadrant(Quadrant quadrant) =>
      ReferralLocation._(kind: LocationKind.quadrant, quadrant: quadrant);

  factory ReferralLocation.region(OralRegion region) =>
      ReferralLocation._(kind: LocationKind.region, region: region);

  const ReferralLocation.generalized() : this._(kind: LocationKind.generalized);

  const ReferralLocation.fullMouth() : this._(kind: LocationKind.fullMouth);

  final LocationKind kind;
  final String? toothCode;
  final ToothNotation? notation;
  final String? canonicalFdi;
  final Quadrant? quadrant;
  final OralRegion? region;

  /// How this location reads on the confirmation card and in the inbox.
  ///
  /// A tooth is always shown with its notation named, because "36" alone means
  /// different teeth in different systems.
  String display() => switch (kind) {
        LocationKind.tooth => '$toothCode · ${notation!.displayName}',
        LocationKind.quadrant => quadrant!.displayName,
        LocationKind.region => region!.displayName,
        LocationKind.generalized => 'Generalized',
        LocationKind.fullMouth => 'Full mouth',
      };

  /// The same location expressed in [target], for a professional reading a
  /// draft in a different notation. Returns null when it cannot be rendered.
  String? renderIn(ToothNotation target) {
    if (kind != LocationKind.tooth) return null;
    if (canonicalFdi == null) return null;
    return ToothCodec.render(canonicalFdi!, target);
  }

  Map<String, dynamic> toMap() => {
        'kind': kind.wire,
        if (toothCode != null) 'toothCode': toothCode,
        if (notation != null) 'notation': notation!.wire,
        if (canonicalFdi != null) 'canonicalFdi': canonicalFdi,
        if (quadrant != null) 'quadrant': quadrant!.wire,
        if (region != null) 'region': region!.wire,
      };

  static ReferralLocation? fromMap(Map<String, dynamic> map) {
    final kind = LocationKind.fromWire(map['kind'] as String?);
    if (kind == null) return null;
    return switch (kind) {
      LocationKind.tooth => ReferralLocation.tooth(
          code: (map['toothCode'] as String?) ?? '',
          notation: ToothNotation.fromWire(map['notation'] as String?),
          canonicalFdi: map['canonicalFdi'] as String?,
        ),
      LocationKind.quadrant => ReferralLocation.quadrant(
          Quadrant.fromWire(map['quadrant'] as String?) ?? Quadrant.upperRight,
        ),
      LocationKind.region => ReferralLocation.region(
          OralRegion.fromWire(map['region'] as String?) ?? OralRegion.anterior,
        ),
      LocationKind.generalized => const ReferralLocation.generalized(),
      LocationKind.fullMouth => const ReferralLocation.fullMouth(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ReferralLocation &&
      other.kind == kind &&
      other.toothCode == toothCode &&
      other.notation == notation &&
      other.quadrant == quadrant &&
      other.region == region;

  @override
  int get hashCode => Object.hash(kind, toothCode, notation, quadrant, region);

  @override
  String toString() => 'ReferralLocation(${display()})';
}
