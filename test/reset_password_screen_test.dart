import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/screens/reset_password_screen.dart';

void main() {
  testWidgets('validates and submits a matching new password', (tester) async {
    String? submittedPassword;
    await tester.pumpWidget(
      MaterialApp(
        home: ResetPasswordScreen(
          onSubmit: (password) async => submittedPassword = password,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('reset-password')),
      'short',
    );
    await tester.tap(find.byKey(const ValueKey('update-password')));
    await tester.pump();
    expect(
      find.text('Password must be at least 8 characters.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('reset-password')),
      'new-password',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reset-password-confirmation')),
      'different-password',
    );
    await tester.tap(find.byKey(const ValueKey('update-password')));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('reset-password-confirmation')),
      'new-password',
    );
    await tester.tap(find.byKey(const ValueKey('update-password')));
    await tester.pump();
    expect(submittedPassword, 'new-password');
  });
}
