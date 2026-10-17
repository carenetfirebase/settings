import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while guided cooking is open, so messy hands don't
/// have to unlock the phone. Failures (tests, unsupported platforms) are
/// ignored: the screen simply sleeps as usual.
abstract final class ScreenAwake {
  static Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  static Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}
