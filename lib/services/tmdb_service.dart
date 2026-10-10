import 'dart:convert';
import 'dart:io';

import '../models/show.dart';

class TmdbException implements Exception {
  const TmdbException(this.message);
  final String message;
  @override
  String toString() => message;
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
      _list('/movie/popular', type: 'movie'),
      _list('/tv/popular', type: 'tv'),
      _list('/movie/top_rated', type: 'movie'),
      _list('/movie/upcoming', type: 'movie'),
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
        CatalogRow('Popular Movies', results[1]),
        CatalogRow('Binge-worthy TV', results[2]),
        CatalogRow('Critically Acclaimed', results[3]),
        CatalogRow('Coming Soon', results[4]),
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
