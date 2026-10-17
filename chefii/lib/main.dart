import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/config.dart';
import 'app/providers.dart';
import 'core/services/analytics.dart';
import 'core/services/notification_service.dart';
import 'data/ai/demo_ai_gateway.dart';
import 'data/ai/firebase_ai_gateway.dart';
import 'data/auth/auth_service.dart';
import 'data/auth/firebase_auth_service.dart';
import 'data/repositories/inventory_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/receipt_repository.dart';
import 'data/store/firestore_doc_store.dart';
import 'data/store/memory_doc_store.dart';
import 'domain/models/profile.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final overrides = config.isDemo ? await _demoOverrides(config) : await _firebaseOverrides(config);
  runApp(ProviderScope(overrides: overrides, child: const ChefiiApp()));
}

const _demoStoreKey = 'chefii_demo_store_v1';

Future<List<Override>> _demoOverrides(AppConfig config) async {
  final prefs = await SharedPreferences.getInstance();
  Timer? saveDebounce;
  final store = MemoryDocStore(onChanged: (s) {
    saveDebounce?.cancel();
    saveDebounce = Timer(const Duration(milliseconds: 400), () => prefs.setString(_demoStoreKey, s.exportJson()));
  });
  final saved = prefs.getString(_demoStoreKey);
  if (saved != null) {
    try {
      store.importJson(saved);
    } catch (_) {
      await prefs.remove(_demoStoreKey); // corrupt local demo data: start fresh
    }
  }
  final auth = DemoAuthService(prefs);
  final receipts = ReceiptRepository(store);
  final inventory = InventoryRepository(store);
  final profiles = ProfileRepository(store);
  final notifications = kIsWeb ? RecordingNotificationService() : LocalNotificationService();
  return [
    appConfigProvider.overrideWithValue(config),
    docStoreProvider.overrideWithValue(store),
    authServiceProvider.overrideWithValue(auth),
    imageUploaderProvider.overrideWithValue(DemoImageUploader()),
    notificationServiceProvider.overrideWithValue(notifications),
    aiGatewayProvider.overrideWithValue(DemoAiGateway(
      receipts: receipts,
      inventory: inventory,
      dietaryOf: () async {
        final uid = auth.currentUser?.uid;
        return uid == null ? const DietaryProfile() : profiles.dietary(uid);
      },
    )),
  ];
}

Future<List<Override>> _firebaseOverrides(AppConfig config) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check: Play Integrity / App Attest in release, reCAPTCHA v3 on the
  // website; debug provider locally.
  await FirebaseAppCheck.instance.activate(
    providerWeb: config.recaptchaSiteKey == null ? null : ReCaptchaV3Provider(config.recaptchaSiteKey!),
    providerAndroid: config.appCheckDebug ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
    providerApple: config.appCheckDebug ? const AppleDebugProvider() : const AppleAppAttestWithDeviceCheckFallbackProvider(),
  );

  if (config.useEmulators) {
    final host = config.emulatorHost;
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFunctions.instanceFor(region: 'northamerica-northeast1').useFunctionsEmulator(host, 5001);
    await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  }

  // Offline persistence keeps the kitchen usable without a connection.
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: 100 * 1024 * 1024);

  if (!kIsWeb) {
    // Crash reports carry stack traces and the error type only. Messages are
    // dropped: they can quote user content (a food name, a typed note).
    final crashlytics = FirebaseCrashlytics.instance;
    FlutterError.onError = (details) =>
        crashlytics.recordError(RedactedError(details.exception), details.stack, fatal: true);
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(RedactedError(error), stack, fatal: true);
      return true;
    };
  }

  final auth = FirebaseAuthService(FirebaseAuth.instance, googleServerClientId: config.googleServerClientId);
  final store = FirestoreDocStore(FirebaseFirestore.instance);
  final profiles = ProfileRepository(store);
  // Data residency: Canadian region for Functions (see docs/SECURITY_MODEL.md).
  final functions = FirebaseFunctions.instanceFor(region: 'northamerica-northeast1');
  final analytics = FirebaseAnalyticsSink(FirebaseAnalytics.instance);
  // Off until the user opts in; the sink turns it on when settings load with
  // consent (and the native flag keeps it off before this line runs).
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);

  return [
    appConfigProvider.overrideWithValue(config),
    docStoreProvider.overrideWithValue(store),
    authServiceProvider.overrideWithValue(auth),
    imageUploaderProvider.overrideWithValue(FirebaseImageUploader(FirebaseStorage.instance)),
    notificationServiceProvider.overrideWithValue(kIsWeb ? RecordingNotificationService() : LocalNotificationService()),
    analyticsProvider.overrideWithValue(analytics),
    aiGatewayProvider.overrideWithValue(FirebaseAiGateway(
      functions,
      dietaryOf: () async {
        final uid = auth.currentUser?.uid;
        return uid == null ? const DietaryProfile() : profiles.dietary(uid);
      },
    )),
  ];
}
