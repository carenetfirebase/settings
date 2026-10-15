import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/models/nutrition.dart';

String formatNutrient(Nutrient n, double v) {
  final rounded = switch (n) {
    Nutrient.energyKcal || Nutrient.sodium || Nutrient.calcium || Nutrient.potassium => v.round().toString(),
    _ => v >= 10 ? v.round().toString() : v.toStringAsFixed(1),
  };
  return n == Nutrient.energyKcal ? rounded : '$rounded ${n.unit}';
}

String formatTime(BuildContext context, DateTime t) {
  final local = t.toLocal();
  return MediaQuery.alwaysUse24HourFormatOf(context)
      ? DateFormat.Hm().format(local)
      : DateFormat.jm().format(local).replaceAll(' AM', ' am').replaceAll(' PM', ' pm');
}

String formatDay(DateTime t, {DateTime? now}) {
  final local = t.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final d = DateTime(local.year, local.month, local.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  if (diff == 1) return 'Tomorrow';
  if (diff.abs() < 7) return DateFormat.EEEE().format(local);
  return DateFormat.MMMd().format(local);
}

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 5) return 'Good evening';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
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
