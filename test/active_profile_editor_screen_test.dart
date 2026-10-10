import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/models/member_profile.dart';
import 'package:stream_flix/screens/active_profile_editor_screen.dart';
import 'package:stream_flix/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('active profile editor exposes name avatar and PIN controls', (
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
    const profile = MemberProfile(
      id: 7,
      name: 'Mark',
      avatarPath: 'avatar-1.png',
      avatarUrl: '',
      isKids: false,
      displayOrder: 1,
    );
    const catalog = MemberProfileCatalog(
      context: MemberProfileContext(
        planName: 'Premium',
        maxProfiles: 4,
        allowsKids: true,
        activeProfileCount: 1,
        canAddProfile: true,
      ),
      profiles: [profile],
      avatars: [
        AvatarOption(path: 'avatar-1.png', signedUrl: ''),
        AvatarOption(path: 'avatar-2.png', signedUrl: ''),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ActiveProfileEditorScreen(
          supabase: client,
          profile: profile,
          onSaved: (_) {},
          loadCatalog: () async => catalog,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit active profile'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Profile name'), findsOneWidget);

    await expectLater(
      find.byType(ActiveProfileEditorScreen),
      matchesGoldenFile('goldens/active_profile_editor_320.png'),
    );

    await tester.scrollUntilVisible(
      find.text('Save profile'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.widgetWithText(TextField, 'New PIN (optional)'),
      findsOneWidget,
    );
    expect(find.text('Remove profile PIN'), findsOneWidget);
    expect(find.text('Save profile'), findsOneWidget);
  });
}
