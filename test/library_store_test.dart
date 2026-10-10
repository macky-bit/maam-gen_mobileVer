import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_flix/models/show.dart';
import 'package:stream_flix/services/library_store.dart';

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

  test('continue watching is capped at ten recent titles', () async {
    const store = LibraryStore(userId: 'user', profileId: 1);
    final shows = List.generate(
      12,
      (index) => Show(
        id: index + 1,
        title: 'Title $index',
        overview: '',
        posterPath: '/poster.jpg',
        backdropPath: '',
        year: '2026',
        score: 80,
        mediaType: 'movie',
      ),
    );

    await store.saveContinueWatching(shows);

    final restored = await store.loadContinueWatching();
    expect(restored, hasLength(10));
    expect(restored.first.id, 1);
    expect(restored.last.id, 10);
  });
}
