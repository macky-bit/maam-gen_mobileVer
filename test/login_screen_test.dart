import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/screens/login_screen.dart';

void main() {
  testWidgets('email sign in validates and submits Supabase credentials', (
    tester,
  ) async {
    String? submittedEmail;
    String? submittedPassword;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onEmailSignIn: (email, password) async {
            submittedEmail = email;
            submittedPassword = password;
          },
          onRegister: (_, _, _) async => false,
          onGoogleSignIn: () async {},
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const ValueKey('email-sign-in')));
    await tester.tap(find.byKey(const ValueKey('email-sign-in')));
    await tester.pump();

    expect(submittedEmail, isNull);
    expect(find.text('Required.'), findsNWidgets(2));

    await tester.enterText(
      find.byKey(const ValueKey('email-input')),
      'member@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password-input')),
      'correct-password',
    );
    await tester.tap(find.byKey(const ValueKey('email-sign-in')));
    await tester.pump();

    expect(submittedEmail, 'member@example.com');
    expect(submittedPassword, 'correct-password');
  });
}
