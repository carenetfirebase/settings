import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/models/nutrition.dart';
import '../l10n/l10n.dart';

/// Locale tag for intl formatters ('en_CA', 'fr_CA').
String localeTag(BuildContext context) => Localizations.localeOf(context).toString();

String formatNutrient(Nutrient n, double v) {
  final rounded = switch (n) {
    Nutrient.energyKcal || Nutrient.sodium || Nutrient.calcium || Nutrient.potassium => v.round().toString(),
    _ => v >= 10 ? v.round().toString() : v.toStringAsFixed(1),
  };
  return n == Nutrient.energyKcal ? rounded : '$rounded ${n.unit}';
}

/// [formatNutrient] for the current language: decimal comma and a
/// non-breaking space before the unit in French.
String formatNutrientFor(BuildContext context, Nutrient n, double v) {
  final s = formatNutrient(n, v);
  return localeTag(context).startsWith('fr') ? s.replaceAll('.', ',').replaceAll(' ', '\u00a0') : s;
}

String formatTime(BuildContext context, DateTime t) {
  final local = t.toLocal();
  final tag = localeTag(context);
  // French Canada uses the 24-hour clock ("7 h 30").
  if (MediaQuery.alwaysUse24HourFormatOf(context) || tag.startsWith('fr')) {
    return tag.startsWith('fr') ? DateFormat("H 'h' mm", tag).format(local) : DateFormat.Hm(tag).format(local);
  }
  return DateFormat.jm(tag).format(local).replaceAll(' AM', ' am').replaceAll(' PM', ' pm');
}

String formatDay(BuildContext context, DateTime t, {DateTime? now}) {
  final l = context.l10n;
  final tag = localeTag(context);
  final local = t.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final d = DateTime(local.year, local.month, local.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return l.commonToday;
  if (diff == -1) return l.commonYesterday;
  if (diff == 1) return l.commonTomorrow;
  if (diff.abs() < 7) return DateFormat.EEEE(tag).format(local);
  return DateFormat.MMMd(tag).format(local);
}

String greetingFor(BuildContext context, DateTime now) {
  final l = context.l10n;
  final h = now.hour;
  if (h < 5) return l.commonGoodEvening;
  if (h < 12) return l.commonGoodMorning;
  if (h < 17) return l.commonGoodAfternoon;
  return l.commonGoodEvening;
}

String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}
