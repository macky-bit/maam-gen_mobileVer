import 'package:shared_preferences/shared_preferences.dart';

class SettingsPreferences {
  SettingsPreferences(String userId) : _prefix = 'streamflix.$userId.';

  final String _prefix;

  Future<bool> getBool(String key, bool fallback) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool('$_prefix$key') ?? fallback;
  }

  Future<String> getString(String key, String fallback) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString('$_prefix$key') ?? fallback;
  }

  Future<void> setBool(String key, bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('$_prefix$key', value);
  }

  Future<void> setString(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('$_prefix$key', value);
  }
}
