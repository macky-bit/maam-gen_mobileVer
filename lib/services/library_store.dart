import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/show.dart';

class LibraryStore {
  const LibraryStore({required this.userId, required this.profileId});

  final String userId;
  final int profileId;

  String get _myListKey => 'sf_mylist_v1_${userId}_$profileId';
  String get _continueKey => 'sf_continue_v1_${userId}_$profileId';

  Future<List<Show>> loadMyList() => _load(_myListKey);

  Future<List<Show>> loadContinueWatching() => _load(_continueKey);

  Future<void> saveMyList(Iterable<Show> shows) => _save(_myListKey, shows);

  Future<void> saveContinueWatching(Iterable<Show> shows) =>
      _save(_continueKey, shows.take(10));

  Future<void> clearContinueWatching() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_continueKey);
  }

  Future<List<Show>> _load(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final source = preferences.getString(key);
    if (source == null) return const [];
    try {
      final rows = jsonDecode(source) as List<dynamic>;
      return rows
          .whereType<Map<String, dynamic>>()
          .map(Show.fromJson)
          .where((show) => show.id != 0)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(String key, Iterable<Show> shows) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      key,
      jsonEncode(shows.map((show) => show.toJson()).toList()),
    );
  }
}
