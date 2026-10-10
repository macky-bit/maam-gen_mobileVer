import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/screens/opening_video_screen.dart';
import 'package:stream_flix/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('opening video can always be skipped', (tester) async {
    var completed = false;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: OpeningVideoScreen(
          supabase: client,
          onComplete: () => completed = true,
        ),
      ),
    );
    expect(find.byTooltip('Mute'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(completed, isTrue);
  });
}
