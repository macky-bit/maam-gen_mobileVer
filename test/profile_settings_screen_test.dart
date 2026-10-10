import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/models/member_profile.dart';
import 'package:stream_flix/screens/profile_screen.dart';
import 'package:stream_flix/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final client = SupabaseClient('https://example.supabase.co', 'test-anon-key');
  const profile = MemberProfile(
    id: 7,
    name: 'Mark',
    avatarPath: '',
    avatarUrl: '',
    isKids: false,
    displayOrder: 0,
  );

  Widget subject({Future<void> Function()? signOutOtherDevices}) => MaterialApp(
    theme: buildTheme(),
    home: ProfileScreen(
      supabase: client,
      userId: '00000000-0000-0000-0000-000000000001',
      activeProfile: profile,
      onActiveProfileUpdated: (_) {},
      onActiveProfileDeleted: () {},
      onManageProfiles: () {},
      onSubscriptionChanged: () async {},
      onWatchHistoryChanged: () {},
      onSignOut: () {},
      signOutOtherDevices: signOutOtherDevices,
    ),
  );

  testWidgets('settings expose implemented sections without device alerts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();

    expect(find.text('Account details'), findsOneWidget);
    expect(find.text('Profiles'), findsOneWidget);
    expect(find.text('Playback & privacy'), findsOneWidget);
    expect(find.text('Sign out other devices'), findsOneWidget);
    expect(find.byTooltip('Edit active profile'), findsOneWidget);
    expect(find.text('Devices'), findsNothing);
    expect(find.text('Notifications'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Watch history'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Watch history'), findsOneWidget);
  });

  testWidgets('signs out other devices but keeps this session active', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      subject(
        signOutOtherDevices: () async {
          calls++;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out other devices'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out other devices?'), findsOneWidget);
    expect(
      find.textContaining('This device will remain signed in.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Sign out others'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(
      find.text('Other devices signed out. This device remains active.'),
      findsOneWidget,
    );
  });

  testWidgets('settings hub matches its mobile visual baseline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1236, 2745);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(subject());
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ProfileScreen),
      matchesGoldenFile('goldens/profile_settings.png'),
    );
  });
}
