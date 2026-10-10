import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/show.dart';

class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.contentId,
    required this.title,
    required this.thumbnail,
    required this.watchedAt,
    required this.lastPlaybackSeconds,
    required this.runtimeMinutes,
    this.show,
  });

  final int contentId;
  final String title;
  final String thumbnail;
  final DateTime? watchedAt;
  final int lastPlaybackSeconds;
  final int? runtimeMinutes;
  final Show? show;

  double get progress {
    final duration = (runtimeMinutes ?? 0) * 60;
    if (duration <= 0) return 0;
    return (lastPlaybackSeconds / duration).clamp(0, 1);
  }
}

class WatchHistoryService {
  const WatchHistoryService(this.supabase);

  final SupabaseClient supabase;

  Future<int?> resolveContentId(Show show) async {
    final rows = await supabase
        .from('content')
        .select('content_id, category(category_name)')
        .eq('tmdb_id', show.id)
        .limit(10);
    for (final value in rows) {
      final row = value;
      final category = _categoryName(row['category']);
      if (_categoryMatches(category, show.mediaType == 'tv')) {
        return (row['content_id'] as num).toInt();
      }
    }
    return null;
  }

  Future<void> recordProgress(int contentId, int seconds) async {
    await supabase.rpc(
      'record_my_watch_progress',
      params: {
        'selected_content_id': contentId,
        'selected_last_playback': seconds.clamp(0, 2147483647),
      },
    );
  }

  Future<List<WatchHistoryEntry>> load() async {
    final history =
        (await supabase.rpc('get_my_watch_history') as List<dynamic>)
            .cast<Map<String, dynamic>>();
    if (history.isEmpty) return const [];

    final ids = history
        .map((row) => (row['content_id'] as num).toInt())
        .toList(growable: false);
    final content = await supabase
        .from('content')
        .select(
          'content_id, tmdb_id, title, synopsis, release_year, thumbnail, '
          'category(category_name)',
        )
        .inFilter('content_id', ids);
    final catalog = <int, Map<String, dynamic>>{
      for (final value in content) (value['content_id'] as num).toInt(): value,
    };

    return history
        .map((row) {
          final contentId = (row['content_id'] as num).toInt();
          final details = catalog[contentId];
          final tmdbId = (details?['tmdb_id'] as num?)?.toInt();
          final thumbnail = (row['thumbnail'] ?? details?['thumbnail'] ?? '')
              .toString();
          final category = _categoryName(details?['category']);
          return WatchHistoryEntry(
            contentId: contentId,
            title: (row['title'] ?? details?['title'] ?? 'Untitled').toString(),
            thumbnail: thumbnail,
            watchedAt: DateTime.tryParse(row['watch_date']?.toString() ?? ''),
            lastPlaybackSeconds: (row['last_playback'] as num?)?.toInt() ?? 0,
            runtimeMinutes: (row['runtime'] as num?)?.toInt(),
            show: tmdbId == null
                ? null
                : Show(
                    id: tmdbId,
                    title: (details?['title'] ?? row['title'] ?? 'Untitled')
                        .toString(),
                    overview: (details?['synopsis'] ?? '').toString(),
                    posterPath: thumbnail,
                    backdropPath: thumbnail,
                    year: (details?['release_year'] ?? '').toString(),
                    score: 0,
                    mediaType: _categoryMatches(category, true)
                        ? 'tv'
                        : 'movie',
                  ),
          );
        })
        .toList(growable: false);
  }

  Future<void> delete(int contentId) => supabase.rpc(
    'delete_my_watch_history_entry',
    params: {'selected_content_id': contentId},
  );
}

String _categoryName(dynamic value) {
  final category = value is List ? value.firstOrNull : value;
  return category is Map ? (category['category_name'] ?? '').toString() : '';
}

bool _categoryMatches(String categoryName, bool isSeries) {
  final normalized = categoryName.trim().toLowerCase();
  return isSeries
      ? normalized == 'tv series' || normalized == 'tv shows'
      : normalized == 'movie' || normalized == 'movies';
}
