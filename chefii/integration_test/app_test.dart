import 'package:chefii/main.dart' as app;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs the real app (demo backend, real platform plugins) on a simulator or
/// emulator: onboarding, Today, guided cooking, kitchen, and switching to
/// French. CI runs it on an iPhone simulator and an Android emulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Real devices are slower and smaller than the test window: wait for the
  /// target to appear, scrolling down if it is below the fold (lazy lists
  /// don't build off-screen items).
  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 120 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 150));
      final scrollables = find.byType(Scrollable);
      // Try below the fold first, then back above it (earlier steps may have
      // scrolled the target off the top).
      if (i % 10 == 9 && scrollables.evaluate().isNotEmpty) {
        await tester.drag(scrollables.last, Offset(0, i < 50 ? -300 : 300), warnIfMissed: false);
      }
    }
    if (f.evaluate().isEmpty) {
      final onScreen = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(40).join(' | ');
      fail('Never found $f. On screen: $onScreen');
    }
  }

  Future<void> tap(WidgetTester tester, Finder f, {int frames = 10}) async {
    await waitFor(tester, f);
    await tester.ensureVisible(f.first);
    await tester.pump();
    await tester.tap(f.first);
    await settle(tester, frames);
  }

  testWidgets('a new user can onboard, cook and switch to French', (tester) async {
    app.main();
    await settle(tester, 30);

    // Onboarding with a peanut allergy and the example kitchen.
    await tap(tester, find.text('Get started'));
    await tap(tester, find.text('Continue'));
    // The terms checkbox appears after the first attempt (as in the widget test).
    await tap(tester, find.text('Continue with a demo account'));
    // Tap the box itself: the tile's centre can land on its "Read them" link.
    await tap(tester, find.descendant(of: find.byType(CheckboxListTile), matching: find.byType(Checkbox)));
    await tap(tester, find.text('Continue with a demo account'), frames: 20);
    await tap(tester, find.text('Continue'), frames: 15);
    await tap(tester, find.text('Yes'));
    await tap(tester, find.text('Peanuts'));
    await tap(tester, find.text('Continue'), frames: 15);
    await tap(tester, find.text('Continue'), frames: 15);
    await tap(tester, find.text('Continue'), frames: 15);
    await tap(tester, find.text('Start with example ingredients'), frames: 30);
    await waitFor(tester, find.textContaining('Alex')); // Today greets the user

    // Guided cooking from Today's suggestion (keeps the screen awake).
    // Today → recipe page → prep checklist → step-by-step.
    await tap(tester, find.text('Start cooking'), frames: 20);
    await tap(tester, find.text('Start cooking'), frames: 20);
    await tap(tester, find.textContaining(RegExp(r'^Begin (cooking|anyway)$')), frames: 20);
    await waitFor(tester, find.textContaining('STEP 1'));
    await tap(tester, find.text('Next step'));
    await waitFor(tester, find.textContaining('STEP 2'));

    // Back to the kitchen tab.
    // Back (system back) until the tab bar shows again.
    final kitchenTab = find.descendant(of: find.byType(NavigationBar), matching: find.text('Kitchen'));
    for (var i = 0; i < 6 && kitchenTab.evaluate().isEmpty; i++) {
      await tester.binding.handlePopRoute();
      await settle(tester, 10);
    }
    await tap(tester, kitchenTab, frames: 15);
    await waitFor(tester, find.text('My kitchen'));

    // Switch the whole app to Canadian French.
    await tap(tester, find.descendant(of: find.byType(NavigationBar), matching: find.text('You')), frames: 15);
    await tap(tester, find.text('Accessibility & language'), frames: 15);
    await tap(tester, find.text('Français (Canada)'), frames: 20);
    await waitFor(tester, find.textContaining(RegExp("^Aujourd['’]hui\$"))); // navigation is now in French
  });
}
