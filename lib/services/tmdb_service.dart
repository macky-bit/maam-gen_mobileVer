import 'dart:convert';
import 'dart:io';

import '../models/show.dart';

class TmdbException implements Exception {
  const TmdbException(this.message);
  final String message;
  @override
  String toString() => message;
}

String? selectTrailerKey(List<dynamic> videos) {
  final youtube = videos
      .whereType<Map<String, dynamic>>()
      .where(
        (video) =>
            video['site'] == 'YouTube' &&
            video['key'] is String &&
            (video['key'] as String).isNotEmpty,
      )
      .toList(growable: false);
  for (final matches in [
    (Map<String, dynamic> video) =>
        video['type'] == 'Trailer' && video['official'] == true,
    (Map<String, dynamic> video) => video['type'] == 'Trailer',
    (Map<String, dynamic> video) => video['type'] == 'Teaser',
    (Map<String, dynamic> video) => true,
  ]) {
    final match = youtube.where(matches).firstOrNull;
    if (match != null) return match['key'] as String;
  }
  return null;
}

class TmdbService {
  TmdbService({HttpClient? client, this.kidsMode = false})
    : _client = client ?? HttpClient();

  static String _apiKey = const String.fromEnvironment('TMDB_API_KEY');
  static String _readToken = const String.fromEnvironment(
    'TMDB_READ_ACCESS_TOKEN',
  );
  static const _base = 'https://api.themoviedb.org/3';
  final HttpClient _client;
  final bool kidsMode;

  static void configureFromEnv(String source) {
    final values = <String, String>{};
    for (final sourceLine in const LineSplitter().convert(source)) {
      var line = sourceLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) line = line.substring(7).trimLeft();
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
    if (_apiKey.isEmpty) _apiKey = values['TMDB_API_KEY'] ?? '';
    if (_readToken.isEmpty) {
      _readToken = values['TMDB_READ_ACCESS_TOKEN'] ?? '';
    }
  }

  bool get isConfigured => _apiKey.isNotEmpty || _readToken.isNotEmpty;

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String> params = const {},
  ]) async {
    if (!isConfigured) {
      throw const TmdbException(
        'Add TMDB_API_KEY to .env or pass it with --dart-define to load the catalog.',
      );
    }
    final query = <String, String>{
      'language': 'en-US',
      'include_adult': 'false',
      ...params,
    };
    if (_apiKey.isNotEmpty) query['api_key'] = _apiKey;
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final request = await _client.getUrl(uri);
    if (_readToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $_readToken',
      );
    }
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmdbException('TMDB request failed (${response.statusCode}).');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<List<Show>> _list(
    String path, {
    String? type,
    Map<String, String> params = const {},
  }) async {
    final data = await _get(path, params);
    final shows = (data['results'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) => Show.fromJson(item, type: type))
        .where((show) => show.id != 0 && show.posterPath.isNotEmpty)
        .toList();
    return kidsMode
        ? shows.where((show) => show.isKidsAppropriate).toList()
        : shows;
  }

  Future<CatalogData> home() async {
    final results = await Future.wait([
      _list('/trending/all/week'),
      _list('/movie/now_playing', type: 'movie'),
      _list('/tv/popular', type: 'tv'),
      _list('/movie/top_rated', type: 'movie'),
      _list('/movie/popular', type: 'movie'),
      _list('/tv/top_rated', type: 'tv'),
    ]);
    final trending = results[0];
    final featured = trending.cast<Show?>().firstWhere(
      (show) => show?.backdropPath.isNotEmpty == true,
      orElse: () => trending.isEmpty ? null : trending.first,
    );
    return CatalogData(
      featured: featured,
      rows: [
        CatalogRow('Trending Now', trending),
        CatalogRow('New Movies', results[1]),
        CatalogRow('Popular TV Shows', results[2]),
        CatalogRow(
          'Top 10 Movies',
          results[3].take(10).toList(growable: false),
          ranked: true,
        ),
        CatalogRow('Recommended Movies', results[4]),
        CatalogRow('Recommended TV Shows', results[5]),
      ],
    );
  }

  Future<CatalogData> movies() =>
      _catalogFor('/movie/now_playing', 'movie', const [
        ('Now Playing', '/movie/now_playing'),
        ('Popular on StreamFlix', '/movie/popular'),
        ('Top Rated', '/movie/top_rated'),
        ('Upcoming', '/movie/upcoming'),
      ]);

  Future<CatalogData> television() =>
      _catalogFor('/tv/on_the_air', 'tv', const [
        ('On the Air', '/tv/on_the_air'),
        ('Popular Series', '/tv/popular'),
        ('Top Rated TV', '/tv/top_rated'),
        ('Airing Today', '/tv/airing_today'),
      ]);

  Future<CatalogData> newAndPopular() async {
    final results = await Future.wait([
      _list('/trending/all/day'),
      _list('/movie/upcoming', type: 'movie'),
      _list('/tv/on_the_air', type: 'tv'),
      _list('/movie/now_playing', type: 'movie'),
    ]);
    final trending = results[0];
    final featured = trending.cast<Show?>().firstWhere(
      (show) => show?.backdropPath.isNotEmpty == true,
      orElse: () => trending.isEmpty ? null : trending.first,
    );
    return CatalogData(
      featured: featured,
      rows: [
        CatalogRow('New & Popular', trending),
        CatalogRow('Coming Soon', results[1]),
        CatalogRow('New Episodes', results[2]),
        CatalogRow('In Theaters', results[3]),
      ],
    );
  }

  Future<List<CatalogRow>> upcomingRows({DateTime? from}) async {
    final today = DateTime(
      from?.year ?? DateTime.now().year,
      from?.month ?? DateTime.now().month,
      from?.day ?? DateTime.now().day,
    );
    final thisSunday = today.add(Duration(days: 7 - today.weekday));
    final nextMonday = thisSunday.add(const Duration(days: 1));
    final nextSunday = thisSunday.add(const Duration(days: 7));
    final laterStart = nextSunday.add(const Duration(days: 1));
    final windows = [
      _UpcomingWindow('Coming This Week', today, thisSunday),
      _UpcomingWindow('Coming Next Week', nextMonday, nextSunday),
      _UpcomingWindow(
        'Worth the Wait',
        laterStart,
        laterStart.add(const Duration(days: 180)),
      ),
    ];

    return Future.wait(windows.map(_upcomingRow));
  }

  Future<CatalogRow> _upcomingRow(_UpcomingWindow window) async {
    final groups = await Future.wait([
      _upcomingForType('movie', 'primary_release_date', window),
      _upcomingForType('tv', 'first_air_date', window),
    ]);
    final items = groups.expand((group) => group).toList()
      ..sort(
        (left, right) => window.title == 'Worth the Wait'
            ? right.popularity.compareTo(left.popularity)
            : left.date.compareTo(right.date),
      );
    final seen = <String>{};
    final shows = items
        .where((item) => seen.add('${item.show.mediaType}-${item.show.id}'))
        .map((item) => item.show)
        .take(8)
        .toList(growable: false);
    return CatalogRow(window.title, shows);
  }

  Future<List<_DatedShow>> _upcomingForType(
    String type,
    String dateField,
    _UpcomingWindow window,
  ) async {
    final data = await _get('/discover/$type', {
      '$dateField.gte': _dateString(window.start),
      '$dateField.lte': _dateString(window.end),
      'sort_by': 'popularity.desc',
      'include_adult': 'false',
    });
    return (data['results'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final date =
              (item[type == 'movie' ? 'release_date' : 'first_air_date'] ?? '')
                  .toString();
          final show = Show.fromJson(item, type: type);
          return _DatedShow(
            show,
            date,
            (item['popularity'] as num?)?.toDouble() ?? 0,
          );
        })
        .where(
          (item) =>
              item.date.compareTo(_dateString(window.start)) >= 0 &&
              item.date.compareTo(_dateString(window.end)) <= 0 &&
              item.show.posterPath.isNotEmpty &&
              (!kidsMode || item.show.isKidsAppropriate),
        )
        .toList(growable: false);
  }

  Future<CatalogData> _catalogFor(
    String featurePath,
    String type,
    List<(String, String)> definitions,
  ) async {
    final featuredItems = await _list(featurePath, type: type);
    final rows = await Future.wait(
      definitions.map(
        (row) async => CatalogRow(row.$1, await _list(row.$2, type: type)),
      ),
    );
    final featured = featuredItems.cast<Show?>().firstWhere(
      (show) => show?.backdropPath.isNotEmpty == true,
      orElse: () => featuredItems.isEmpty ? null : featuredItems.first,
    );
    return CatalogData(featured: featured, rows: rows);
  }

  Future<List<Show>> search(String query) =>
      _list(
        '/search/multi',
        params: {'query': query, 'include_adult': 'false'},
      ).then(
        (items) => items
            .where(
              (item) => item.mediaType == 'movie' || item.mediaType == 'tv',
            )
            .toList(),
      );

  Future<String?> trailerKey(Show show) async {
    try {
      final tmdbId = show.tmdbReferenceId;
      if (tmdbId == null) return null;
      final type = show.mediaType == 'tv' ? 'tv' : 'movie';
      final data = await _get('/$type/$tmdbId/videos');
      return selectTrailerKey(data['results'] as List<dynamic>? ?? const []);
    } catch (_) {
      return null;
    }
  }

  Future<List<Episode>> episodes(int tvId) async {
    final details = await _get('/tv/$tvId');
    final seasons = (details['seasons'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where(
          (season) =>
              (season['season_number'] as num?)?.toInt() != 0 &&
              ((season['episode_count'] as num?)?.toInt() ?? 0) > 0,
        )
        .toList();
    if (seasons.isEmpty) return const [];
    final seasonNumber = (seasons.first['season_number'] as num).toInt();
    final data = await _get('/tv/$tvId/season/$seasonNumber');
    return (data['episodes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (episode) => Episode(
            number: (episode['episode_number'] as num?)?.toInt() ?? 0,
            title: (episode['name'] ?? 'Episode').toString(),
            overview: (episode['overview'] ?? '').toString(),
            runtimeMinutes: (episode['runtime'] as num?)?.toInt() ?? 45,
            imageUrl: episode['still_path'] == null
                ? ''
                : 'https://image.tmdb.org/t/p/w780${episode['still_path']}',
          ),
        )
        .where((episode) => episode.number > 0)
        .toList();
  }
}

class _UpcomingWindow {
  const _UpcomingWindow(this.title, this.start, this.end);
  final String title;
  final DateTime start;
  final DateTime end;
}

class _DatedShow {
  const _DatedShow(this.show, this.date, this.popularity);
  final Show show;
  final String date;
  final double popularity;
}

String _dateString(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
