import '../enums.dart';

/// A specialist or clinic the professional refers to.
///
/// Professional and clinic details only. Nothing here describes a patient.
class ReferralDestination {
  const ReferralDestination({
    required this.id,
    required this.professionalId,
    required this.specialty,
    required this.providerName,
    this.clinicName,
    this.isDefault = false,
    this.isActive = true,
  });

  final String id;
  final String professionalId;
  final Specialty specialty;
  final String providerName;
  final String? clinicName;
  final bool isDefault;
  final bool isActive;

  /// What the confirmation card and handoff text show.
  String get display {
    final clinic = clinicName;
    if (clinic == null || clinic.isEmpty) return providerName;
    if (providerName.isEmpty) return clinic;
    return '$providerName · $clinic';
  }

  ReferralDestination copyWith({
    Specialty? specialty,
    String? providerName,
    String? clinicName,
    bool? isDefault,
    bool? isActive,
  }) =>
      ReferralDestination(
        id: id,
        professionalId: professionalId,
        specialty: specialty ?? this.specialty,
        providerName: providerName ?? this.providerName,
        clinicName: clinicName ?? this.clinicName,
        isDefault: isDefault ?? this.isDefault,
        isActive: isActive ?? this.isActive,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'professionalId': professionalId,
        'specialty': specialty.wire,
        'providerName': providerName,
        if (clinicName != null) 'clinicName': clinicName,
        'isDefault': isDefault,
        'isActive': isActive,
      };

  static ReferralDestination fromMap(Map<String, dynamic> map) =>
      ReferralDestination(
        id: (map['id'] as String?) ?? '',
        professionalId: (map['professionalId'] as String?) ?? '',
        specialty:
            Specialty.fromWire(map['specialty'] as String?) ?? Specialty.other,
        providerName: (map['providerName'] as String?) ?? '',
        clinicName: map['clinicName'] as String?,
        isDefault: map['isDefault'] as bool? ?? false,
        isActive: map['isActive'] as bool? ?? true,
      );

  @override
  String toString() => 'ReferralDestination($id, ${specialty.wire})';
}

/// Resolves "my usual endodontist" against the professional's configured
/// destinations.
abstract final class DestinationResolver {
  static ReferralDestination? defaultFor(
    Iterable<ReferralDestination> destinations,
    Specialty specialty,
  ) {
    ReferralDestination? firstActive;
    for (final d in destinations) {
      if (d.specialty != specialty || !d.isActive) continue;
      firstActive ??= d;
      if (d.isDefault) return d;
    }
    return firstActive;
  }
}
