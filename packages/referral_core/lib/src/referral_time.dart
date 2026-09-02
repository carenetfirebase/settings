/// Timestamp rendering.
///
/// Instants are stored in UTC and rendered against the professional's zone at
/// display time. This package carries no timezone database, so the caller
/// supplies the offset in effect for the instant being rendered — which keeps
/// the dependency out of the core and keeps daylight-saving correctness with
/// the layer that has a real zone implementation.
abstract final class ReferralTime {
  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// `10:42 AM`
  static String formatTime(DateTime utc, Duration offset) {
    final local = utc.toUtc().add(offset);
    final hour24 = local.hour;
    final suffix = hour24 < 12 ? 'AM' : 'PM';
    final hour12 = switch (hour24 % 12) { 0 => 12, final h => h };
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $suffix';
  }

  /// `September 2, 2026`
  static String formatDate(DateTime utc, Duration offset) {
    final local = utc.toUtc().add(offset);
    return '${_months[local.month - 1]} ${local.day}, ${local.year}';
  }

  /// `10:42 AM · September 2, 2026`
  static String formatStamp(DateTime utc, Duration offset) =>
      '${formatTime(utc, offset)} · ${formatDate(utc, offset)}';

  /// Local calendar day, used to group the inbox without exposing an instant.
  static DateTime localDay(DateTime utc, Duration offset) {
    final local = utc.toUtc().add(offset);
    return DateTime.utc(local.year, local.month, local.day);
  }
}
