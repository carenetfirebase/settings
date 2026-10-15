import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/services/notification_service.dart';

class CookingTimer {
  const CookingTimer({required this.id, required this.label, required this.total, required this.remainingAtStart, this.startedAt});

  final int id;
  final String label;
  final Duration total;

  /// Remaining when last (re)started or paused.
  final Duration remainingAtStart;

  /// Null when paused.
  final DateTime? startedAt;

  bool get running => startedAt != null;

  Duration remaining(DateTime now) {
    if (startedAt == null) return remainingAtStart;
    final left = remainingAtStart - now.difference(startedAt!);
    return left.isNegative ? Duration.zero : left;
  }

  bool finished(DateTime now) => remaining(now) == Duration.zero;

  CookingTimer copyWith({Duration? remainingAtStart, DateTime? startedAt, bool clearStart = false}) => CookingTimer(
        id: id,
        label: label,
        total: total,
        remainingAtStart: remainingAtStart ?? this.remainingAtStart,
        startedAt: clearStart ? null : (startedAt ?? this.startedAt),
      );
}

/// Multiple named timers that survive navigation. Each running timer has a
/// scheduled local notification, so it still alerts if the app is closed.
class CookingTimers extends Notifier<List<CookingTimer>> {
  int _next = 0;
  DateTime Function() now = DateTime.now;

  @override
  List<CookingTimer> build() => const [];

  NotificationService get _n => ref.read(notificationServiceProvider);

  int start(String label, Duration d) {
    final id = _next++ % 100;
    final t = CookingTimer(id: id, label: label, total: d, remainingAtStart: d, startedAt: now());
    state = [...state.where((x) => x.id != id), t];
    _n.scheduleIn(id: NotificationIds.timerBase + id, after: d, title: '$label is done', body: 'Your Chefii timer has finished.', payload: '/cook/timers');
    return id;
  }

  void pause(int id) {
    state = [
      for (final t in state)
        if (t.id == id && t.running) t.copyWith(remainingAtStart: t.remaining(now()), clearStart: true) else t,
    ];
    _n.cancel(NotificationIds.timerBase + id);
  }

  void resume(int id) {
    state = [
      for (final t in state)
        if (t.id == id && !t.running) t.copyWith(startedAt: now()) else t,
    ];
    final t = state.firstWhere((t) => t.id == id);
    _n.scheduleIn(id: NotificationIds.timerBase + id, after: t.remainingAtStart, title: '${t.label} is done', body: 'Your Chefii timer has finished.');
  }

  void addTime(int id, Duration extra) {
    final t = state.firstWhere((t) => t.id == id);
    final left = t.remaining(now()) + extra;
    state = [for (final x in state) x.id == id ? x.copyWith(remainingAtStart: left, startedAt: x.running ? now() : null, clearStart: !x.running) : x];
    if (t.running) {
      _n.scheduleIn(id: NotificationIds.timerBase + id, after: left, title: '${t.label} is done', body: 'Your Chefii timer has finished.');
    }
  }

  void cancel(int id) {
    state = state.where((t) => t.id != id).toList();
    _n.cancel(NotificationIds.timerBase + id);
  }

  void clearFinished() => state = state.where((t) => !t.finished(now())).toList();
}

final cookingTimersProvider = NotifierProvider<CookingTimers, List<CookingTimer>>(CookingTimers.new);
