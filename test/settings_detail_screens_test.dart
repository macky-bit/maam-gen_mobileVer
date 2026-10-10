import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/screens/settings_detail_screens.dart';
import 'package:stream_flix/services/account_service.dart';
import 'package:stream_flix/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Widget app(Widget child) => MaterialApp(theme: buildTheme(), home: child);

  testWidgets('help center filters its articles and exposes support', (
    tester,
  ) async {
    await tester.pumpWidget(app(const HelpCenterScreen()));

    expect(find.text('How to manage profiles'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Google password');
    await tester.pump();

    expect(find.text('Why a Google password is not shown'), findsOneWidget);
    expect(find.text('How to manage profiles'), findsNothing);
  });

  testWidgets('about screen identifies the real content providers', (
    tester,
  ) async {
    await tester.pumpWidget(app(const AboutStreamFlixScreen()));

    expect(find.text('About StreamFlix'), findsOneWidget);
    expect(find.text('TMDB'), findsOneWidget);
    expect(find.text('Supabase'), findsOneWidget);
  });

  testWidgets('account details recompose into editable fields at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 2100);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final details = AccountSettings.fromJson({
      'first_name': 'Mark',
      'last_name': 'Lee',
      'email': 'mark@example.com',
      'date_of_birth': '2000-05-14',
      'plan_name': 'Premium',
      'monthly_price': 499,
      'max_user': 4,
      'payment_date': '2026-09-30T08:00:00+00:00',
      'payment_amount': 499,
      'end_date': '2026-10-30T08:00:00+00:00',
      'payment_method': 'prototype',
      'billing_history': [
        {
          'payment_id': 2,
          'amount': 499,
          'payment_method': 'Stripe',
          'reference_number': 'pi_second',
          'status': 'Paid',
          'paid_at': '2026-09-30T08:00:00+00:00',
          'created_at': '2026-09-30T08:00:00+00:00',
        },
        {
          'payment_id': 1,
          'amount': 499,
          'payment_method': 'Stripe',
          'reference_number': 'pi_first',
          'status': 'Paid',
          'paid_at': '2026-08-30T08:00:00+00:00',
          'created_at': '2026-08-30T08:00:00+00:00',
        },
      ],
    });
    var updateCount = 0;

    await tester.pumpWidget(
      app(
        AccountDetailsScreen(
          supabase: client,
          loadDetails: () async => details,
          updateProfile:
              ({
                required firstName,
                required lastName,
                required birthDate,
              }) async {
                updateCount++;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PERSONAL INFORMATION'), findsOneWidget);
    expect(find.text('MEMBERSHIP RECORD'), findsOneWidget);
    expect(find.text('BILLING HISTORY'), findsOneWidget);
    expect(find.text('08/30/2026'), findsOneWidget);
    expect(find.text('SIGN-IN & SECURITY'), findsNothing);
    expect(find.text('DATABASE RECORD'), findsNothing);
    expect(find.text('Username'), findsNothing);
    expect(find.text('Reference'), findsNothing);
    expect(find.text('Edit'), findsNWidgets(2));
    expect(find.text('Change'), findsNWidgets(2));

    await expectLater(
      find.byType(AccountDetailsScreen),
      matchesGoldenFile('goldens/account_details_320.png'),
    );

    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(updateCount, 1);
    expect(tester.takeException(), isNull);
  });
}
