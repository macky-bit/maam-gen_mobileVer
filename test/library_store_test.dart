import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_flix/models/show.dart';
import 'package:stream_flix/services/library_store.dart';
import 'package:stream_flix/services/watch_history_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const show = Show(
    id: 7,
    title: 'A title',
    overview: '',
    posterPath: '/poster.jpg',
    backdropPath: '',
    year: '2026',
    score: 80,
    mediaType: 'movie',
  );

  test('saved titles are isolated by profile', () async {
    const first = LibraryStore(userId: 'user', profileId: 1);
    const second = LibraryStore(userId: 'user', profileId: 2);

    await first.saveMyList([show]);

    expect(await first.loadMyList(), [show]);
    expect(await second.loadMyList(), isEmpty);
  });

  test('server history exposes the real playback fraction', () {
    const entry = WatchHistoryEntry(
      contentId: 7,
      title: 'A title',
      thumbnail: '',
      watchedAt: null,
      lastPlaybackSeconds: 900,
      runtimeMinutes: 60,
    );
    expect(entry.progress, .25);
  });

  test('show artwork accepts server-provided absolute URLs', () {
    const absolute = 'https://image.tmdb.org/t/p/w500/poster.jpg';
    final restored = Show.fromJson({...show.toJson(), 'poster_path': absolute});
    expect(restored.posterUrl, absolute);
  });
}
