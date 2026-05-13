// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ctp_job_cards/main.dart';
import 'package:ctp_job_cards/screens/login_screen.dart'; // ← Add this import

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CtpJobCardsApp(
          initialScreen: LoginScreen(), // ← Fixed: Pass required parameter
        ),
      ),
    );

    // Check that the app title appears
    expect(find.text('CTP Job Cards'), findsOneWidget);
  });
}