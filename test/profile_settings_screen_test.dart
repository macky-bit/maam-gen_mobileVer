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

  Widget subject() => MaterialApp(
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
    expect(find.text('Watch history'), findsOneWidget);
    expect(find.byTooltip('Edit active profile'), findsOneWidget);
    expect(find.text('Devices'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
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
