import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Privacy-safe analytics.
///
/// Events describe *product usage* only. Parameters are filtered against an
/// allow-list so health data, food names, allergies, free text, glucose
/// values and identifiers can never be sent, even by mistake. Nothing is
/// sent unless the user opted in (AppSettings.analyticsConsent).
abstract final class AnalyticsEvents {
  static const onboardingStep = 'onboarding_step';
  static const onboardingComplete = 'onboarding_complete';
  static const receiptCaptured = 'receipt_captured';
  static const receiptImported = 'receipt_imported';
  static const receiptFailed = 'receipt_failed';
  static const inventoryAdjusted = 'inventory_adjusted';
  static const inventoryUndo = 'inventory_undo';
  static const voiceCommand = 'voice_command';
  static const recipeViewed = 'recipe_viewed';
  static const cookingStarted = 'cooking_started';
  static const cookingCompleted = 'cooking_completed';
  static const chefMessage = 'chef_message';
  static const mealPlanned = 'meal_planned';
  static const shoppingGenerated = 'shopping_generated';
  static const mealLogged = 'meal_logged';
  static const routineEnabled = 'routine_enabled';
  static const shareGranted = 'share_granted';
  static const shareRevoked = 'share_revoked';
  static const screenView = 'screen_view';
}

const _allowedParams = {
  'step', 'source', 'kind', 'count', 'duration_bucket', 'result', 'screen', 'method', 'meal_type', 'has_demo',
  'item_count_bucket', 'error_code',
};

Map<String, Object> sanitizeAnalyticsParams(Map<String, Object?> params) {
  final out = <String, Object>{};
  params.forEach((k, v) {
    if (!_allowedParams.contains(k) || v == null) return;
    if (v is num || v is bool) {
      out[k] = v is bool ? (v ? 1 : 0) : v;
    } else if (v is String && v.length <= 40 && RegExp(r'^[a-z0-9_]+$').hasMatch(v)) {
      out[k] = v; // enum-like tokens only
    }
  });
  return out;
}

String countBucket(int n) => n == 0 ? '0' : n <= 5 ? '1_5' : n <= 15 ? '6_15' : n <= 40 ? '16_40' : '40_plus';

abstract class Analytics {
  bool enabled = false;
  void log(String event, [Map<String, Object?> params = const {}]);
}

class DebugAnalytics extends Analytics {
  final events = <(String, Map<String, Object>)>[];

  @override
  void log(String event, [Map<String, Object?> params = const {}]) {
    final clean = sanitizeAnalyticsParams(params);
    events.add((event, clean));
    if (kDebugMode && enabled) debugPrint('[analytics] $event $clean');
  }
}

class FirebaseAnalyticsSink extends Analytics {
  FirebaseAnalyticsSink(this._fa);
  final FirebaseAnalytics _fa;

  @override
  void log(String event, [Map<String, Object?> params = const {}]) {
    if (!enabled) return;
    _fa.logEvent(name: event, parameters: sanitizeAnalyticsParams(params));
  }
}
