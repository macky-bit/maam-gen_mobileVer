import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/screens/google_onboarding_screen.dart';

void main() {
  testWidgets('Google onboarding shows fixed email and validates fields', (
    tester,
  ) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: GoogleOnboardingScreen(
          email: 'google.member@example.com',
          onSubmit: (_, _) async => submitted = true,
          onSignOut: () async {},
        ),
      ),
    );

    expect(find.text('Complete your account'), findsOneWidget);
    expect(find.text('google.member@example.com'), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, -700), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('complete-google-account')));
    await tester.pump();

    expect(find.text('Birthdate is required.'), findsOneWidget);
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(submitted, isFalse);
  });
}
