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

  Future<void> tap(WidgetTester tester, Finder f, {int frames = 10}) async {
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
    await tap(tester, find.byType(CheckboxListTile));
    await tap(tester, find.text('Continue with a demo account'), frames: 20);
    await tap(tester, find.text('Continue'), frames: 15);
    await tap(tester, find.text('Yes'));
    await tap(tester, find.text('Peanuts'));
    await tap(tester, find.text('Continue'), frames: 15);
    await tap(tester, find.text('Continue'), frames: 15);
    await tap(tester, find.text('Continue'), frames: 15);
    await tap(tester, find.text('Start with example ingredients'), frames: 30);
    expect(find.textContaining('Alex'), findsWidgets, reason: 'Today greets the user');

    // Guided cooking from Today's suggestion (keeps the screen awake).
    await tap(tester, find.text('Start cooking'), frames: 20);
    final begin = find.text('Begin cooking');
    await tap(tester, begin.evaluate().isNotEmpty ? begin : find.text('Begin anyway'), frames: 20);
    expect(find.textContaining('STEP 1'), findsOneWidget);
    await tap(tester, find.text('Next step'));
    expect(find.textContaining('STEP 2'), findsOneWidget);

    // Back to the kitchen tab.
    await tester.pageBack();
    await settle(tester, 10);
    await tester.pageBack();
    await settle(tester, 10);
    await tap(tester, find.text('Kitchen'), frames: 15);
    expect(find.text('My kitchen'), findsOneWidget);

    // Switch the whole app to Canadian French.
    await tap(tester, find.text('You'), frames: 15);
    await tap(tester, find.text('Accessibility & language'), frames: 15);
    await tap(tester, find.text('Français (Canada)'), frames: 20);
    expect(find.text('Aujourd’hui').evaluate().isNotEmpty || find.text("Aujourd'hui").evaluate().isNotEmpty, isTrue,
        reason: 'navigation is now in French');
  });
}
