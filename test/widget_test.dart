// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app_flutter/main.dart';
import 'package:chat_app_flutter/screens/login_screen.dart';

void main() {
  testWidgets('App starts with login screen when not logged in', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp(isLoggedIn: false));

    // Verify that the login screen is shown
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('App starts with home page when logged in', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp(isLoggedIn: true));

    // Verify that the home page is shown (searching for AppBar as a proxy for HomePage)
    expect(find.byType(AppBar), findsOneWidget);
  });
}
