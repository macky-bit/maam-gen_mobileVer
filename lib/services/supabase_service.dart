import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static const oauthRedirectUri = 'com.streamflix.app://login-callback/';

  static Future<SupabaseClient> initialize(String environment) async {
    final values = _parseEnvironment(environment);
    const definedUrl = String.fromEnvironment('SUPABASE_URL');
    const definedKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    final url = definedUrl.isNotEmpty ? definedUrl : values['SUPABASE_URL'];
    final key = definedKey.isNotEmpty
        ? definedKey
        : values['SUPABASE_ANON_KEY'];

    if (url == null || url.isEmpty || key == null || key.isEmpty) {
      throw StateError(
        'Missing SUPABASE_URL or SUPABASE_ANON_KEY. Add them to '
        '.env or pass them with --dart-define.',
      );
    }

    await Supabase.initialize(
      url: url,
      // The current SDK uses publishableKey as its public-client key input;
      // it accepts the legacy anon JWT here without changing its privileges.
      publishableKey: key,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    return Supabase.instance.client;
  }

  static Future<void> signInWithGoogle(SupabaseClient client) async {
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : oauthRedirectUri,
      authScreenLaunchMode: LaunchMode.externalApplication,
      queryParams: const {'prompt': 'select_account'},
    );
    if (!launched) {
      throw const AuthException('Could not open Google sign-in.');
    }
  }

  static Map<String, String> _parseEnvironment(String source) {
    final values = <String, String>{};
    for (final rawLine in source.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      final name = line.substring(0, separator).trim();
      var value = line.substring(separator + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      values[name] = value;
    }
    return values;
  }
}
