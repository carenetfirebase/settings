import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_smoke_test.dart' show pumpSignedIn, settle;

void main() {
  testWidgets('French kitchen shows catalogue names in French', (tester) async {
    final router = await pumpSignedIn(tester, locale: const Locale('fr', 'CA'));
    router.go('/kitchen');
    await settle(tester, 6);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await settle(tester, 4);
    expect(find.text('Avocats'), findsWidgets);
    router.go('/today');
    await settle(tester, 2);
  });
}
