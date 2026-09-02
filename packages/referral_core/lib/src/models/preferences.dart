import '../enums.dart';

/// How the professional wants to be told a draft is waiting.
///
/// Content is fixed and non-clinical wherever these are honoured: the presence
/// of a draft is notifiable, its contents are not.
class NotificationPreferences {
  const NotificationPreferences({
    this.pushEnabled = true,
    this.emailEnabled = false,
    this.dailyDigestEnabled = false,
    this.dailyDigestHourLocal = 17,
  });

  final bool pushEnabled;
  final bool emailEnabled;

  /// The passive forcing function for drafts that are captured but never
  /// completed. Carries a count, never clinical detail.
  final bool dailyDigestEnabled;
  final int dailyDigestHourLocal;

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? dailyDigestEnabled,
    int? dailyDigestHourLocal,
  }) =>
      NotificationPreferences(
        pushEnabled: pushEnabled ?? this.pushEnabled,
        emailEnabled: emailEnabled ?? this.emailEnabled,
        dailyDigestEnabled: dailyDigestEnabled ?? this.dailyDigestEnabled,
        dailyDigestHourLocal: dailyDigestHourLocal ?? this.dailyDigestHourLocal,
      );

  Map<String, dynamic> toMap() => {
        'pushEnabled': pushEnabled,
        'emailEnabled': emailEnabled,
        'dailyDigestEnabled': dailyDigestEnabled,
        'dailyDigestHourLocal': dailyDigestHourLocal,
      };

  static NotificationPreferences fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NotificationPreferences();
    return NotificationPreferences(
      pushEnabled: map['pushEnabled'] as bool? ?? true,
      emailEnabled: map['emailEnabled'] as bool? ?? false,
      dailyDigestEnabled: map['dailyDigestEnabled'] as bool? ?? false,
      dailyDigestHourLocal: map['dailyDigestHourLocal'] as int? ?? 17,
    );
  }
}

/// Per-professional Quick Referral settings.
///
/// [professionalId] is the existing account's uid. This package never
/// authenticates; it is given an id and trusts the caller to have done so.
class ProfessionalReferralPreferences {
  const ProfessionalReferralPreferences({
    required this.professionalId,
    this.toothNotation = ToothNotation.fdi,
    this.timezone = 'UTC',
    this.notifications = const NotificationPreferences(),
    this.draftRetentionDays = 90,
    this.lastOperatory,
    this.lastOperatoryAt,
    this.operatoryStickyWindow = const Duration(minutes: 90),
  });

  final String professionalId;
  final ToothNotation toothNotation;

  /// IANA zone name, e.g. `America/Edmonton`. Stored for display; this package
  /// holds no timezone database and asks the caller for the offset when
  /// formatting.
  final String timezone;

  final NotificationPreferences notifications;

  /// Where production retention policy is configured. This is a default, not a
  /// legal position — see the package README.
  final int draftRetentionDays;

  /// The operatory last confirmed on a saved draft, used to pre-fill the chip.
  final String? lastOperatory;
  final DateTime? lastOperatoryAt;

  /// How long a remembered operatory stays offered. Past this, the chip shows
  /// empty: a blank operatory is safe, a stale one silently attributes a draft
  /// to the wrong room.
  final Duration operatoryStickyWindow;

  /// The operatory to pre-fill at [now], or null when the remembered value has
  /// gone stale.
  String? stickyOperatoryAt(DateTime now) {
    final at = lastOperatoryAt;
    final value = lastOperatory;
    if (at == null || value == null || value.isEmpty) return null;
    if (now.toUtc().difference(at.toUtc()) > operatoryStickyWindow) return null;
    return value;
  }

  ProfessionalReferralPreferences copyWith({
    ToothNotation? toothNotation,
    String? timezone,
    NotificationPreferences? notifications,
    int? draftRetentionDays,
    String? lastOperatory,
    DateTime? lastOperatoryAt,
    Duration? operatoryStickyWindow,
  }) =>
      ProfessionalReferralPreferences(
        professionalId: professionalId,
        toothNotation: toothNotation ?? this.toothNotation,
        timezone: timezone ?? this.timezone,
        notifications: notifications ?? this.notifications,
        draftRetentionDays: draftRetentionDays ?? this.draftRetentionDays,
        lastOperatory: lastOperatory ?? this.lastOperatory,
        lastOperatoryAt: lastOperatoryAt ?? this.lastOperatoryAt,
        operatoryStickyWindow:
            operatoryStickyWindow ?? this.operatoryStickyWindow,
      );

  Map<String, dynamic> toMap() => {
        'professionalId': professionalId,
        'toothNotation': toothNotation.wire,
        'timezone': timezone,
        'notifications': notifications.toMap(),
        'draftRetentionDays': draftRetentionDays,
        if (lastOperatory != null) 'lastOperatory': lastOperatory,
        if (lastOperatoryAt != null)
          'lastOperatoryAt': lastOperatoryAt!.toUtc().toIso8601String(),
        'operatoryStickyWindowMinutes': operatoryStickyWindow.inMinutes,
      };

  static ProfessionalReferralPreferences fromMap(Map<String, dynamic> map) {
    final stickyMinutes = map['operatoryStickyWindowMinutes'] as int? ?? 90;
    return ProfessionalReferralPreferences(
      professionalId: (map['professionalId'] as String?) ?? '',
      toothNotation: ToothNotation.fromWire(map['toothNotation'] as String?),
      timezone: (map['timezone'] as String?) ?? 'UTC',
      notifications: NotificationPreferences.fromMap(
        (map['notifications'] as Map?)?.cast<String, dynamic>(),
      ),
      draftRetentionDays: map['draftRetentionDays'] as int? ?? 90,
      lastOperatory: map['lastOperatory'] as String?,
      lastOperatoryAt: switch (map['lastOperatoryAt']) {
        final String s => DateTime.tryParse(s)?.toUtc(),
        _ => null,
      },
      operatoryStickyWindow: Duration(minutes: stickyMinutes),
    );
  }

  @override
  String toString() => 'ProfessionalReferralPreferences($professionalId, '
      '${toothNotation.wire})';
}
