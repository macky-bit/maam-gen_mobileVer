import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/show.dart';

enum CatalogKind { home, movies, tvShows, newAndPopular }

class CatalogService {
  const CatalogService(this.client, {this.kidsMode = false});

  final SupabaseClient client;
  final bool kidsMode;

  Future<CatalogData> load(CatalogKind kind) async {
    final rows = await client
        .from('content')
        .select(
          'content_id, tmdb_id, catalog_source, title, synopsis, '
          'release_year, runtime, age_rating, thumbnail, popularity_rank, '
          'video_file, '
          'category(category_name), genre!content_genre_id_fkey(genre_name), '
          'content_genre(genre(genre_name))',
        )
        .order('popularity_rank', ascending: true, nullsFirst: false)
        .range(0, 999);

    final shows = rows.cast<Map<String, dynamic>>().map((row) {
      final thumbnail = (row['thumbnail'] ?? '').toString();
      final thumbnailUrl =
          thumbnail.isNotEmpty &&
              !thumbnail.startsWith('http://') &&
              !thumbnail.startsWith('https://')
          ? client.storage.from('content-thumbnails').getPublicUrl(thumbnail)
          : thumbnail;
      return Show.fromCatalogJson(row, thumbnailUrl: thumbnailUrl);
    });

    return buildStreamFlixCatalog(kind, shows, kidsMode: kidsMode);
  }

  Future<List<Show>> search(String query) async {
    final catalog = await load(CatalogKind.home);
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final all = catalog.rows
        .where((row) => row.title == 'All Content')
        .expand((row) => row.items);
    return all
        .where((show) {
          return matchesCatalogSearch(show, needle);
        })
        .toList(growable: false);
  }
}

bool matchesCatalogSearch(Show show, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return false;
  final contentType = show.mediaType == 'tv' ? 'tv series show' : 'movie film';
  return [
    show.title,
    show.categoryName,
    contentType,
    ...show.genreNames,
  ].join(' ').toLowerCase().contains(needle);
}

CatalogData buildStreamFlixCatalog(
  CatalogKind kind,
  Iterable<Show> source, {
  bool kidsMode = false,
}) {
  final all = source
      .where((show) => !kidsMode || show.isKidsAppropriate)
      .toList(growable: false);
  final movies = all.where((show) => show.mediaType == 'movie').toList()
    ..sort(_byPopularity);
  final tv = all.where((show) => show.mediaType == 'tv').toList()
    ..sort(_byPopularity);
  final trending = _interleave(movies, tv);
  final newestMovies = [...movies]..sort(_byNewest);
  final newestTv = [...tv]..sort(_byNewest);

  final rows = switch (kind) {
    CatalogKind.movies => [
      CatalogRow('Popular Movies', movies.take(12).toList()),
      CatalogRow('New Movies', newestMovies.take(12).toList()),
      CatalogRow('Top 10 Movies', movies.take(10).toList(), ranked: true),
      CatalogRow('Recommended Movies', _recommendations(movies)),
    ],
    CatalogKind.tvShows => [
      CatalogRow('Popular TV Shows', tv.take(12).toList()),
      CatalogRow('New TV Shows', newestTv.take(12).toList()),
      CatalogRow('Top 10 TV Shows', tv.take(10).toList(), ranked: true),
      CatalogRow('Recommended TV Shows', _recommendations(tv)),
    ],
    CatalogKind.newAndPopular => [
      CatalogRow(
        'New on StreamFlix',
        ([...all]
              ..sort((a, b) => (b.contentId ?? 0).compareTo(a.contentId ?? 0)))
            .take(12)
            .toList(),
      ),
      CatalogRow('Top 10 Movies', movies.take(10).toList(), ranked: true),
      CatalogRow('Top 10 TV Series', tv.take(10).toList(), ranked: true),
    ],
    CatalogKind.home => [
      CatalogRow('Trending Now', trending),
      CatalogRow('New Movies', newestMovies.take(12).toList()),
      CatalogRow('Popular TV Shows', tv.take(12).toList()),
      CatalogRow('Top 10 Movies', movies.take(10).toList(), ranked: true),
      CatalogRow('Recommended Movies', _recommendations(movies)),
      CatalogRow('Recommended TV Shows', _recommendations(tv)),
      CatalogRow(
        'All Content',
        [...all]
          ..sort((a, b) => (a.contentId ?? 0).compareTo(b.contentId ?? 0)),
      ),
    ],
  };
  final genreCounts = <String, int>{};
  for (final show in all) {
    for (final genre in show.genreNames) {
      genreCounts[genre] = (genreCounts[genre] ?? 0) + 1;
    }
  }
  final genres = genreCounts.entries.toList()
    ..sort(
      (a, b) => b.value.compareTo(a.value) != 0
          ? b.value.compareTo(a.value)
          : a.key.compareTo(b.key),
    );
  final featured = switch (kind) {
    CatalogKind.movies => movies.firstOrNull,
    CatalogKind.tvShows => tv.firstOrNull,
    _ => trending.firstOrNull,
  };

  return CatalogData(
    featured: featured,
    rows: rows,
    genres: genres.take(15).map((entry) => entry.key).toList(),
  );
}

int _byPopularity(Show left, Show right) =>
    (left.popularityRank ?? 1 << 62).compareTo(right.popularityRank ?? 1 << 62);

int _byNewest(Show left, Show right) {
  final leftManual = left.catalogSource == 'manual';
  final rightManual = right.catalogSource == 'manual';
  if (leftManual != rightManual) return leftManual ? -1 : 1;
  if (leftManual) {
    return (right.contentId ?? 0).compareTo(left.contentId ?? 0);
  }
  final year = int.tryParse(
    right.year,
  )?.compareTo(int.tryParse(left.year) ?? 0);
  return year != null && year != 0 ? year : _byPopularity(left, right);
}

List<Show> _interleave(List<Show> left, List<Show> right) {
  final mixed = <Show>[];
  for (var index = 0; mixed.length < 12; index++) {
    if (index < left.length) mixed.add(left[index]);
    if (mixed.length < 12 && index < right.length) mixed.add(right[index]);
    if (index >= left.length && index >= right.length) break;
  }
  return mixed;
}

List<Show> _recommendations(List<Show> items) {
  final recommended = items.skip(10).take(12).toList();
  return recommended.length >= 6 ? recommended : items.take(12).toList();
}
