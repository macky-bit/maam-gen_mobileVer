import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/models/show.dart';

void main() {
  test('kids suitability requires a kids genre and rejects mature content', () {
    final family = Show.fromJson({
      'id': 1,
      'title': 'Family film',
      'genre_ids': [16, 10751],
      'adult': false,
    });
    final horror = Show.fromJson({
      'id': 2,
      'title': 'Animated horror',
      'genre_ids': [16, 27],
      'adult': false,
    });
    final adult = Show.fromJson({
      'id': 3,
      'title': 'Adult animation',
      'genre_ids': [16],
      'adult': true,
    });

    expect(family.isKidsAppropriate, isTrue);
    expect(horror.isKidsAppropriate, isFalse);
    expect(adult.isKidsAppropriate, isFalse);
  });

  test('local serialization preserves the show identity and restrictions', () {
    const show = Show(
      id: 42,
      title: 'Saved title',
      overview: 'Overview',
      posterPath: '/poster.jpg',
      backdropPath: '/backdrop.jpg',
      year: '2026',
      score: 87,
      mediaType: 'movie',
      contentId: 7,
      tmdbId: 42,
      categoryName: 'Movies',
      videoPath: 'content/7/video/title.mp4',
      runtimeMinutes: 91,
      ageRating: 'PG',
      catalogSource: 'tmdb',
      popularityRank: 3,
      genreIds: [16, 10751],
      genreNames: ['Animation', 'Family'],
      isAdult: false,
    );

    final restored = Show.fromJson(show.toJson());

    expect(restored, show);
    expect(restored.title, show.title);
    expect(restored.genreIds, show.genreIds);
    expect(restored.contentId, show.contentId);
    expect(restored.tmdbId, show.tmdbId);
    expect(restored.categoryName, show.categoryName);
    expect(restored.videoPath, show.videoPath);
    expect(restored.runtimeMinutes, show.runtimeMinutes);
    expect(restored.genreNames, show.genreNames);
    expect(restored.isKidsAppropriate, isTrue);
  });

  test('maps a manual StreamFlix title without inventing a TMDB reference', () {
    final show = Show.fromCatalogJson({
      'content_id': 91,
      'tmdb_id': null,
      'catalog_source': 'manual',
      'title': 'StreamFlix Original',
      'synopsis': 'Uploaded by the content team.',
      'release_year': 2026,
      'runtime': 88,
      'age_rating': 'PG',
      'thumbnail': 'manual/original.jpg',
      'video_file': 'content/91/video/original.mp4',
      'popularity_rank': 4,
      'category': {'category_name': 'Movies'},
      'genre': {'genre_name': 'Family'},
      'content_genre': [
        {
          'genre': {'genre_name': 'Animation'},
        },
      ],
    }, thumbnailUrl: 'https://cdn.example/manual/original.jpg');

    expect(show.id, 91);
    expect(show.contentId, 91);
    expect(show.tmdbReferenceId, isNull);
    expect(show.posterUrl, 'https://cdn.example/manual/original.jpg');
    expect(show.mediaType, 'movie');
    expect(show.categoryName, 'Movies');
    expect(show.videoPath, 'content/91/video/original.mp4');
    expect(show.genreNames, containsAll(['Family', 'Animation']));
    expect(show.isKidsAppropriate, isTrue);
  });
}
