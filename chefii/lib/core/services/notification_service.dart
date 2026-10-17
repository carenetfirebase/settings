import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../l10n/l10n.dart';

/// Notification id ranges, so groups can be cancelled together.
abstract final class NotificationIds {
  static const mealBase = 1000; // + meal index
  static const morningAlarmBase = 2000; // + ISO weekday
  static const eveningPreviewBase = 2100; // + ISO weekday
  static const timerBase = 3000; // + timer index
  static const generic = 9000;
  static const snoozeBase = 9100; // + original id % 100
}

/// Action id for "Snooze 10 min" on reminders and the morning alarm.
const snoozeActionId = 'snooze';
const snoozeDuration = Duration(minutes: 10);
const _snoozeCategory = 'chefii_snoozable';

/// The app's language for notification text, set by the app from the
/// language setting; null follows the device. Background isolates (snooze
/// without opening the app) don't share it and use the device language.
Locale? notificationLocale;

/// Strings for notifications, which are built without a BuildContext.
AppLocalizations notificationStrings() {
  final device = PlatformDispatcher.instance.locale;
  return lookupAppLocalizations(
      notificationLocale ?? (device.languageCode == 'fr' ? const Locale('fr', 'CA') : const Locale('en', 'CA')));
}

/// What a snoozed notification says, from the original's deep link.
({String title, String body}) snoozedContent(String? payload, [AppLocalizations? strings]) {
  final l = strings ?? notificationStrings();
  return switch (payload) {
    '/morning/wake' => (title: l.commonGoodMorning, body: l.coreSnoozeWakeBody),
    '/morning/evening' => (title: l.coreSnoozeEveningTitle, body: l.coreSnoozeEveningBody),
    _ => (title: l.coreSnoozeReminderTitle, body: l.coreSnoozeReminderBody),
  };
}

Future<void> _scheduleSnooze(FlutterLocalNotificationsPlugin plugin, NotificationResponse r) async {
  final content = snoozedContent(r.payload);
  final alarm = r.payload == '/morning/wake';
  await plugin.zonedSchedule(
    id: NotificationIds.snoozeBase + ((r.id ?? 0) % 100),
    scheduledDate: tz.TZDateTime.now(tz.local).add(snoozeDuration),
    notificationDetails: LocalNotificationService.detailsFor(alarm ? LocalNotificationService.alarmChannel : LocalNotificationService.remindersChannel, timeSensitive: alarm),
    androidScheduleMode: alarm ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.inexactAllowWhileIdle,
    title: content.title,
    body: content.body,
    payload: r.payload,
  );
}

/// Runs in a background isolate when "Snooze" is tapped without opening the app.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse r) async {
  if (r.actionId != snoozeActionId) return;
  tzdata.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('America/Toronto'));
  }
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(settings: LocalNotificationService.initSettings);
  await _scheduleSnooze(plugin, r);
}

class ScheduledTime {
  const ScheduledTime(this.hour, this.minute);
  final int hour;
  final int minute;

  static ScheduledTime parse(String hhmm) {
    final p = hhmm.split(':').map(int.parse).toList();
    return ScheduledTime(p[0], p[1]);
  }

  int get minutesOfDay => hour * 60 + minute;
}

/// True if [t] falls in the quiet window [start, end) (hours, may wrap midnight).
bool isInQuietHours(ScheduledTime t, int startHour, int endHour) {
  if (startHour == endHour) return false;
  final m = t.minutesOfDay, s = startHour * 60, e = endHour * 60;
  return s < e ? (m >= s && m < e) : (m >= s || m < e);
}

abstract class NotificationService {
  Future<void> init({void Function(String? payload)? onTap});
  Future<bool> requestPermission({bool exactAlarms = false});

  /// Repeats weekly on each ISO weekday given (1 = Monday).
  Future<void> scheduleWeekly({
    required int baseId,
    required List<int> weekdays,
    required ScheduledTime time,
    required String title,
    required String body,
    String? payload,
    bool alarm = false,
  });

  Future<void> scheduleDaily({required int id, required ScheduledTime time, required String title, required String body, String? payload});

  Future<void> scheduleIn({required int id, required Duration after, required String title, required String body, String? payload});

  Future<void> showNow({required int id, required String title, required String body, String? payload});

  Future<void> cancel(int id);
  Future<void> cancelRange(int baseId, int count);
}

/// Records calls; used on web, in tests and when notifications are unavailable.
class RecordingNotificationService implements NotificationService {
  final scheduled = <int, String>{};

  @override
  Future<void> init({void Function(String? payload)? onTap}) async {}

  @override
  Future<bool> requestPermission({bool exactAlarms = false}) async => true;

  @override
  Future<void> scheduleWeekly({
    required int baseId,
    required List<int> weekdays,
    required ScheduledTime time,
    required String title,
    required String body,
    String? payload,
    bool alarm = false,
  }) async {
    for (final d in weekdays) {
      scheduled[baseId + d] = title;
    }
  }

  @override
  Future<void> scheduleDaily({required int id, required ScheduledTime time, required String title, required String body, String? payload}) async =>
      scheduled[id] = title;

  @override
  Future<void> scheduleIn({required int id, required Duration after, required String title, required String body, String? payload}) async =>
      scheduled[id] = title;

  @override
  Future<void> showNow({required int id, required String title, required String body, String? payload}) async {}

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<void> cancelRange(int baseId, int count) async {
    for (var i = 0; i < count; i++) {
      scheduled.remove(baseId + i);
    }
  }
}

/// Local notifications on iOS/Android.
///
/// Morning alarms use Android's `alarmClock` schedule mode (shown in the
/// system clock UI, exempt from Doze) with a full-screen intent, and iOS
/// time-sensitive notifications. Neither replaces the system alarm app; iOS
/// AlarmKit integration is a planned native bridge (docs/FEATURE_STATUS.md).
class LocalNotificationService implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // Channel names and actions are in the app's language (notificationStrings).
  static AndroidNotificationAction get _snooze =>
      AndroidNotificationAction(snoozeActionId, notificationStrings().coreSnoozeAction, cancelNotification: true);

  static AndroidNotificationDetails get remindersChannel => AndroidNotificationDetails(
        'chefii_reminders',
        notificationStrings().coreChannelReminders,
        channelDescription: notificationStrings().coreChannelRemindersDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        actions: [_snooze],
      );
  static AndroidNotificationDetails get alarmChannel => AndroidNotificationDetails(
        'chefii_morning_alarm',
        notificationStrings().coreChannelAlarm,
        channelDescription: notificationStrings().coreChannelAlarmDescription,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        actions: [_snooze],
      );
  static AndroidNotificationDetails get _timers => AndroidNotificationDetails(
        'chefii_timers',
        notificationStrings().coreChannelTimers,
        channelDescription: notificationStrings().coreChannelTimersDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
      );

  static NotificationDetails detailsFor(AndroidNotificationDetails android, {bool timeSensitive = false}) => NotificationDetails(
        android: android,
        iOS: DarwinNotificationDetails(
          interruptionLevel: timeSensitive ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
          categoryIdentifier: android.actions?.isNotEmpty == true ? _snoozeCategory : null,
        ),
      );

  NotificationDetails _details(AndroidNotificationDetails android, {bool timeSensitive = false}) =>
      detailsFor(android, timeSensitive: timeSensitive);

  static InitializationSettings get initSettings => InitializationSettings(
    android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(_snoozeCategory, actions: [DarwinNotificationAction.plain(snoozeActionId, notificationStrings().coreSnoozeAction)]),
      ],
    ),
  );

  @override
  Future<void> init({void Function(String? payload)? onTap}) async {
    if (_ready || kIsWeb) return;
    tzdata.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('America/Toronto'));
    }
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (r) {
        if (r.actionId == snoozeActionId) {
          _scheduleSnooze(_plugin, r);
        } else {
          onTap?.call(r.payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission({bool exactAlarms = false}) async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final ok = await android.requestNotificationsPermission() ?? false;
      if (exactAlarms) await android.requestExactAlarmsPermission();
      return ok;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true, badge: true) ?? false;
    return false;
  }

  tz.TZDateTime _next(ScheduledTime t, {int? weekday}) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
    if (weekday != null) {
      while (d.weekday != weekday || !d.isAfter(now)) {
        d = d.add(const Duration(days: 1));
      }
    } else if (!d.isAfter(now)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  @override
  Future<void> scheduleWeekly({
    required int baseId,
    required List<int> weekdays,
    required ScheduledTime time,
    required String title,
    required String body,
    String? payload,
    bool alarm = false,
  }) async {
    await cancelRange(baseId, 8);
    for (final wd in weekdays) {
      await _plugin.zonedSchedule(
        id: baseId + wd,
        scheduledDate: _next(time, weekday: wd),
        notificationDetails: _details(alarm ? alarmChannel : remindersChannel, timeSensitive: alarm),
        androidScheduleMode: alarm ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  @override
  Future<void> scheduleDaily({required int id, required ScheduledTime time, required String title, required String body, String? payload}) =>
      _plugin.zonedSchedule(
        id: id,
        scheduledDate: _next(time),
        notificationDetails: _details(remindersChannel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.time,
      );

  @override
  Future<void> scheduleIn({required int id, required Duration after, required String title, required String body, String? payload}) =>
      _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.now(tz.local).add(after),
        notificationDetails: _details(_timers, timeSensitive: true),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: title,
        body: body,
        payload: payload,
      );

  @override
  Future<void> showNow({required int id, required String title, required String body, String? payload}) =>
      _plugin.show(id: id, title: title, body: body, notificationDetails: _details(remindersChannel), payload: payload);

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelRange(int baseId, int count) async {
    for (var i = 0; i < count; i++) {
      await _plugin.cancel(id: baseId + i);
    }
  }
}
