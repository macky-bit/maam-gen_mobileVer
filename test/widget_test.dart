import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/app.dart';

void main() {
  testWidgets('shows the StreamFlix sign-in experience', (tester) async {
    await tester.pumpWidget(const StreamFlixApp());

    expect(find.text('STREAMFLIX'), findsOneWidget);
    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Explore as guest'), findsNothing);
    expect(find.text('Register'), findsOneWidget);

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(find.text('First Name'), findsOneWidget);
    expect(find.text('Last Name'), findsOneWidget);
    expect(find.text('Date of Birth'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
  });
}
