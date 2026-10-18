import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/show.dart';

class ContentNotification {
  const ContentNotification({
    required this.id,
    required this.changedAt,
    required this.show,
  });

  final int id;
  final DateTime changedAt;
  final Show show;
}

class ContentNotificationService {
  const ContentNotificationService(this.client);

  final SupabaseClient client;

  Future<List<ContentNotification>> load() async {
    final rows = await client
        .from('content')
        .select(
          'content_id, tmdb_id, catalog_source, title, synopsis, '
          'release_year, runtime, age_rating, thumbnail, popularity_rank, '
          'admin_updated_at, category(category_name), '
          'genre!content_genre_id_fkey(genre_name), '
          'content_genre(genre(genre_name))',
        )
        .eq('availability_status', 'available')
        .not('admin_updated_at', 'is', null)
        .order('admin_updated_at', ascending: false)
        .limit(20);

    return rows
        .cast<Map<String, dynamic>>()
        .map((row) {
          final thumbnail = (row['thumbnail'] ?? '').toString();
          final thumbnailUrl =
              thumbnail.isNotEmpty &&
                  !thumbnail.startsWith('http://') &&
                  !thumbnail.startsWith('https://')
              ? client.storage
                    .from('content-thumbnails')
                    .getPublicUrl(thumbnail)
              : thumbnail;
          return ContentNotification(
            id: (row['content_id'] as num).toInt(),
            changedAt: DateTime.parse(row['admin_updated_at'].toString()),
            show: Show.fromCatalogJson(row, thumbnailUrl: thumbnailUrl),
          );
        })
        .toList(growable: false);
  }
}
