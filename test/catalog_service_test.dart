import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/models/show.dart';
import 'package:stream_flix/services/catalog_service.dart';

void main() {
  test('builds the same viewer rows and rankings as the web catalog', () {
    final shows = [
      for (var index = 1; index <= 22; index++)
        _show(index, 'Movie $index', 'movie', rank: index),
      for (var index = 1; index <= 22; index++)
        _show(100 + index, 'TV $index', 'tv', rank: index),
    ];

    final home = buildStreamFlixCatalog(CatalogKind.home, shows);
    final tv = buildStreamFlixCatalog(CatalogKind.tvShows, shows);

    expect(home.rows.map((row) => row.title), [
      'Trending Now',
      'New Movies',
      'Popular TV Shows',
      'Top 10 Movies',
      'Recommended Movies',
      'Recommended TV Shows',
      'All Content',
    ]);
    expect(home.rows[3].ranked, isTrue);
    expect(home.rows[4].items.first.title, 'Movie 11');
    expect(tv.rows[2].title, 'Top 10 TV Shows');
    expect(tv.rows[2].ranked, isTrue);
    expect(home.rows.last.items, hasLength(44));
  });

  test('keeps manual content and applies database genres to Kids profiles', () {
    final manual = _show(
      91,
      'Manual Family Title',
      'movie',
      contentId: 91,
      tmdbId: null,
      source: 'manual',
      genres: const ['Family'],
    );
    final horror = _show(
      92,
      'Animated Horror',
      'movie',
      genres: const ['Animation', 'Horror'],
    );

    final catalog = buildStreamFlixCatalog(CatalogKind.movies, [
      manual,
      horror,
    ], kidsMode: true);

    expect(catalog.rows.first.items, [manual]);
    expect(catalog.genres, ['Family']);
    expect(manual.tmdbReferenceId, isNull);
  });

  test('keeps titles without thumbnails for the shared fallback card', () {
    final title = _show(7, 'No artwork yet', 'movie', poster: '');

    final catalog = buildStreamFlixCatalog(CatalogKind.home, [title]);

    expect(catalog.rows.last.items, [title]);
  });
}

Show _show(
  int id,
  String title,
  String mediaType, {
  int? rank,
  int? contentId,
  int? tmdbId,
  String source = 'tmdb',
  String? poster,
  List<String> genres = const ['Drama'],
}) => Show(
  id: id,
  contentId: contentId ?? id,
  tmdbId: contentId == null ? (tmdbId ?? id) : tmdbId,
  title: title,
  overview: '',
  posterPath: poster ?? 'https://cdn.example/$id.jpg',
  backdropPath: 'https://cdn.example/$id.jpg',
  year: '${2026 - id % 5}',
  score: 0,
  mediaType: mediaType,
  catalogSource: source,
  popularityRank: rank,
  genreNames: genres,
);
