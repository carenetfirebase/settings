import 'package:chefii/app/app.dart';
import 'package:chefii/app/actions.dart';
import 'package:chefii/app/providers.dart';
import 'package:chefii/app/router.dart';
import 'package:chefii/core/services/notification_service.dart';
import 'package:chefii/core/services/voice.dart';
import 'package:chefii/data/ai/demo_ai_gateway.dart';
import 'package:chefii/data/auth/auth_service.dart';
import 'package:chefii/data/repositories/inventory_repository.dart';
import 'package:chefii/data/repositories/receipt_repository.dart';
import 'package:chefii/data/store/memory_doc_store.dart';
import 'package:chefii/domain/models/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(ProviderContainer, MemoryDocStore)> pumpApp(WidgetTester tester, {double textScale = 1, Brightness brightness = Brightness.light, Locale locale = const Locale('en', 'CA')}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = MemoryDocStore();
  final auth = DemoAuthService(prefs);
  final container = ProviderContainer(overrides: [
    docStoreProvider.overrideWithValue(store),
    authServiceProvider.overrideWithValue(auth),
    imageUploaderProvider.overrideWithValue(DemoImageUploader()),
    notificationServiceProvider.overrideWithValue(RecordingNotificationService()),
    voiceInputProvider.overrideWithValue(UnavailableVoiceInput()),
    speakerProvider.overrideWithValue(SilentSpeaker()),
    aiGatewayProvider.overrideWithValue(DemoAiGateway(
      receipts: ReceiptRepository(store),
      inventory: InventoryRepository(store),
      dietaryOf: () async => const DietaryProfile(),
      latency: Duration.zero,
    )),
  ]);
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const ChefiiApp()));
  await tester.pump(const Duration(milliseconds: 100));
  return (container, store);
}

Future<void> tapOn(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
}

Future<void> settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

const allRoutes = [
  '/today', '/today/briefing', '/today/notifications',
  '/kitchen', '/kitchen/location/fridge', '/kitchen/add', '/kitchen/scan', '/kitchen/freshness',
  '/kitchen/reconcile', '/kitchen/shopping', '/kitchen/spending', '/kitchen/receipts',
  '/discover', '/discover?filter=expiring', '/journal', '/journal/add', '/journal/history', '/journal/reminders', '/journal/patterns',
  '/you', '/you/dietary', '/you/culinary', '/you/wellness', '/you/nutrition', '/you/nutrition/intelligence',
  '/you/nutrition/hair-skin-nails', '/you/nutrition/evidence', '/you/nutrition/nutrient/fibre', '/you/smile', '/you/smile/history',
  '/you/diabetes', '/you/glucose', '/you/glucose/timeline', '/you/circle', '/you/household', '/you/privacy', '/you/connected',
  '/you/membership', '/you/accessibility', '/you/security', '/you/help', '/you/legal', '/you/data',
  '/receipt/capture', '/receipt/preview', '/chef', '/chef/preferences', '/chef/results', '/recipe/red-lentil-dal',
  '/cook/timers', '/morning/setup', '/morning/alarm', '/morning/evening', '/morning/wake', '/morning/checklist', '/morning/late',
  '/plan', '/plan/assign', '/plan/leftovers', '/pro',
];

/// Signs a demo user in and onboards through the repositories (the UI flow
/// is covered by the first test), with an example kitchen.
Future<GoRouter> pumpSignedIn(WidgetTester tester, {double textScale = 1, Brightness brightness = Brightness.light, Locale locale = const Locale('en', 'CA')}) async {
  final (container, _) = await pumpApp(tester, textScale: textScale, brightness: brightness, locale: locale);
  await settle(tester);
  final auth = container.read(authServiceProvider) as DemoAuthService;
  final user = await auth.signInDemo('Alexandra');
  await settle(tester);
  await container.read(profileRepoProvider).ensureProfile(uid: user.uid, displayName: 'Alexandra');
  await container.read(householdRepoProvider).createHousehold(
      uid: user.uid, ownerName: 'Alexandra', name: 'Home', type: HouseholdType.family, portions: 4);
  await container.read(profileRepoProvider).updateProfileFields(user.uid, {'onboardingComplete': true});
  await settle(tester, 10);
  await container.read(actionsProvider).seedExampleKitchen();
  await settle(tester, 10);
  return container.read(routerProvider);
}

void main() {
  test('session redirect rules', () {
    String? go(String loc, {bool signedIn = true, bool onboarded = true}) =>
        sessionRedirect(location: loc, authLoading: false, signedIn: signedIn, profileLoading: false, onboarded: onboarded);
    expect(go('/today', signedIn: false), '/welcome');
    expect(go('/welcome', signedIn: false), isNull);
    expect(go('/onboarding/account', signedIn: false), isNull);
    expect(go('/today', onboarded: false), '/onboarding/household');
    expect(go('/onboarding/dietary', onboarded: false), isNull);
    expect(go('/welcome'), '/today');
    expect(go('/kitchen/item/x'), isNull);
  });

  testWidgets('demo user can onboard and every screen renders', (tester) async {
    final (container, store) = await pumpApp(tester);
    await settle(tester);
    expect(find.text('Get started'), findsOneWidget);

    await tapOn(tester, find.text('Get started'));
    await settle(tester);
    expect(find.text('Meet your chef'), findsOneWidget);
    await tapOn(tester, find.text('Continue'));
    await settle(tester);

    // Account: demo sign-in requires accepting terms first.
    await tapOn(tester, find.text('Continue with a demo account'));
    await settle(tester);
    expect(find.textContaining('accept the Terms'), findsOneWidget);
    await tapOn(tester, find.byType(CheckboxListTile));
    await tapOn(tester, find.text('Continue with a demo account'));
    await settle(tester, 15);
    expect(find.text('Your household'), findsOneWidget);

    await tapOn(tester, find.text('Continue'));
    await settle(tester, 15);
    expect(find.text('Dietary safety'), findsOneWidget);
    await tapOn(tester, find.text('Yes'));
    await settle(tester);
    await tapOn(tester, find.text('Peanuts'));
    await settle(tester);
    await tapOn(tester, find.text('Continue'));
    await settle(tester, 15);
    expect(find.text('What you love to eat'), findsOneWidget);
    await tapOn(tester, find.text('Continue'));
    await settle(tester, 15);
    expect(find.text('Wellness, your way'), findsOneWidget);
    await tapOn(tester, find.text('Continue'));
    await settle(tester, 15);
    expect(find.text('Build your kitchen'), findsOneWidget);
    await tapOn(tester, find.text('Start with example ingredients'));
    await settle(tester, 20);

    // Landed on Today with a seeded kitchen.
    expect(find.textContaining('Alex'), findsWidgets);
    final uid = container.read(uidProvider)!;
    final dietary = await container.read(profileRepoProvider).dietary(uid);
    expect(dietary.allergies, ['peanut']);
    final hid = container.read(householdIdProvider)!;
    expect((await container.read(inventoryRepoProvider).activeLots(hid)).length, greaterThan(20));

    // Render every route; any build exception fails the test.
    final router = container.read(routerProvider);
    final lot = (await container.read(inventoryRepoProvider).activeLots(hid)).first;
    final routes = [...allRoutes, '/kitchen/item/${lot.id}'];
    for (final r in routes) {
      router.go(r);
      await settle(tester, 4);
      expect(tester.takeException(), isNull, reason: 'route $r threw');
      expect(find.byType(ErrorWidget), findsNothing, reason: 'route $r rendered an error');
    }
    // Peanut allergy is respected in recipes shown.
    router.go('/recipe/apple-peanut-butter');
    await settle(tester, 4);
    expect(find.text('Not safe for your household'), findsOneWidget);

    expect(store.documentCount, greaterThan(30));
    // Stop periodic timers before teardown.
    router.go('/today');
    await settle(tester, 2);
    expect(router, isA<GoRouter>());
  });

  testWidgets('key screens survive 160% text size without overflow', (tester) async {
    final router = await pumpSignedIn(tester, textScale: 1.6);
    for (final r in [
      '/today', '/kitchen', '/kitchen/freshness', '/kitchen/reconcile', '/kitchen/add', '/discover', '/journal',
      '/you', '/recipe/red-lentil-dal', '/plan', '/chef', '/receipt/capture', '/morning/setup', '/you/privacy',
    ]) {
      router.go(r);
      await settle(tester, 4);
      expect(tester.takeException(), isNull, reason: 'route $r overflowed or threw at 160% text');
    }
    router.go('/today');
    await settle(tester, 2);
  });

  const a11yRoutes = [
    '/today', '/kitchen', '/kitchen/freshness', '/kitchen/reconcile', '/kitchen/add', '/kitchen/shopping', '/discover',
    '/journal', '/journal/add', '/you', '/you/dietary', '/you/privacy', '/you/accessibility', '/recipe/red-lentil-dal',
    '/plan', '/chef', '/receipt/capture', '/morning/setup', '/you/nutrition', '/you/glucose',
  ];

  for (final brightness in Brightness.values) {
    testWidgets('accessibility guidelines hold in ${brightness.name} mode', (tester) async {
      final semantics = tester.ensureSemantics();
      final router = await pumpSignedIn(tester, brightness: brightness);
      for (final r in a11yRoutes) {
        router.go(r);
        await settle(tester, 4);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: '$r: Android 48dp tap targets');
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline), reason: '$r: iOS 44pt tap targets');
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: '$r: every tap target has a label');
        await expectLater(tester, meetsGuideline(textContrastGuideline), reason: '$r: WCAG text contrast');
      }
      router.go('/today');
      await settle(tester, 2);
      semantics.dispose();
    });
  }

  testWidgets('key screens survive 200% text size without overflow', (tester) async {
    final router = await pumpSignedIn(tester, textScale: 2.0);
    for (final r in a11yRoutes) {
      router.go(r);
      await settle(tester, 4);
      final e = tester.takeException();
      if (e != null) {
        for (final ro in tester.allRenderObjects.whereType<RenderFlex>()) {
          if (ro.toStringShort().contains('OVERFLOWING')) debugPrint('OVERFLOW_DETAIL ${ro.debugCreator}');
        }
      }
      expect(e, isNull, reason: 'route $r overflowed or threw at 200% text');
    }
    router.go('/today');
    await settle(tester, 2);
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('every route renders in Canadian French at ${(scale * 100).round()}% text', (tester) async {
      final router = await pumpSignedIn(tester, textScale: scale, locale: const Locale('fr', 'CA'));
      router.go('/today');
      await settle(tester, 4);
      expect(find.textContaining(RegExp('Bonjour|Bon après-midi|Bonsoir')), findsWidgets);
      for (final r in allRoutes) {
        router.go(r);
        await settle(tester, 4);
        final e = tester.takeException();
        if (e != null) {
          for (final ro in tester.allRenderObjects.whereType<RenderFlex>()) {
            if (ro.toStringShort().contains('OVERFLOWING')) debugPrint('OVERFLOW_DETAIL ${ro.debugCreator}');
          }
        }
        expect(e, isNull, reason: 'route $r overflowed or threw in French at ${scale}x');
      }
      router.go('/today');
      await settle(tester, 2);
    });
  }

  testWidgets('guided cooking steps forward with reduce motion on', (tester) async {
    final router = await pumpSignedIn(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    router.push('/recipe/red-lentil-dal');
    await settle(tester, 10);
    await tapOn(tester, find.text('Start cooking'));
    await settle(tester, 10);
    await tapOn(tester, find.textContaining(RegExp(r'^Begin (cooking|anyway)$')));
    await settle(tester, 10);
    expect(find.textContaining('STEP 1'), findsOneWidget);
    await tapOn(tester, find.text('Next step'));
    await settle(tester, 4);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('STEP 2'), findsOneWidget);
  });
}
