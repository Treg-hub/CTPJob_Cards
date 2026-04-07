// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.


import 'package:flutter_test/flutter_test.dart';

import 'package:ctp_job_cards/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // FIXED: CtpJobCardsApp now requires the isLoggedIn parameter
    await tester.pumpWidget(const CtpJobCardsApp(isLoggedIn: false));

    // Check that the app title appears (it exists in both LoginScreen and HomeScreen)
    expect(find.text('CTP Job Cards'), findsOneWidget);
  });
}