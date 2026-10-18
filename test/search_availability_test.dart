import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/models/show.dart';
import 'package:stream_flix/services/catalog_service.dart';

void main() {
  const show = Show(
    id: 110,
    contentId: 110,
    tmdbId: null,
    title: 'Manual Space Story',
    overview: 'An administrator-uploaded title.',
    posterPath: '',
    backdropPath: '',
    year: '2026',
    score: 0,
    mediaType: 'tv',
    categoryName: 'StreamFlix Originals',
    genreNames: ['Science Fiction', 'Drama'],
  );

  test('catalog search matches stored title, genre, category, and type', () {
    expect(matchesCatalogSearch(show, 'space'), isTrue);
    expect(matchesCatalogSearch(show, 'science fiction'), isTrue);
    expect(matchesCatalogSearch(show, 'originals'), isTrue);
    expect(matchesCatalogSearch(show, 'series'), isTrue);
    expect(matchesCatalogSearch(show, 'comedy'), isFalse);
  });
}
