import 'package:supabase_flutter/supabase_flutter.dart';

class RefresherContent {
  const RefresherContent({
    required this.summary,
    required this.events,
    required this.characters,
    required this.keyDetails,
    required this.sourceTitle,
    required this.sourceUrl,
    required this.scope,
    required this.cached,
  });

  final String summary;
  final List<String> events;
  final List<String> characters;
  final List<String> keyDetails;
  final String sourceTitle;
  final Uri sourceUrl;
  final String scope;
  final bool cached;

  factory RefresherContent.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) {
      final value = json[key];
      if (value is! List || value.any((item) => item is! String)) {
        throw const FormatException(
          'Wikipedia returned an invalid refresher response.',
        );
      }
      return value
          .cast<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    final summary = json['summary']?.toString().trim() ?? '';
    final sourceTitle = json['sourceTitle']?.toString().trim() ?? '';
    final sourceUrl = Uri.tryParse(json['sourceUrl']?.toString() ?? '');
    final scope = json['scope']?.toString() ?? '';
    if (summary.isEmpty ||
        sourceTitle.isEmpty ||
        sourceUrl == null ||
        sourceUrl.scheme != 'https' ||
        sourceUrl.host.toLowerCase() != 'en.wikipedia.org' ||
        (scope != 'movie' && scope != 'series') ||
        json['sourceName'] != 'Wikipedia' ||
        json['cached'] is! bool) {
      throw const FormatException(
        'Wikipedia returned an invalid refresher response.',
      );
    }
    return RefresherContent(
      summary: summary,
      events: strings('events'),
      characters: strings('characters'),
      keyDetails: strings('keyDetails'),
      sourceTitle: sourceTitle,
      sourceUrl: sourceUrl,
      scope: scope,
      cached: json['cached'] == true,
    );
  }
}

class RefresherBundle {
  const RefresherBundle({required this.content, required this.videoUrl});

  final RefresherContent content;
  final Uri videoUrl;
}

class RefresherService {
  const RefresherService(this.client);

  final SupabaseClient client;

  Future<RefresherBundle> load(int contentId) async {
    if (contentId <= 0) throw ArgumentError.value(contentId, 'contentId');
    final results = await Future.wait<dynamic>([
      client.functions.invoke(
        'wikipedia-refresher',
        headers: const {'Origin': 'https://mobile.streamflix.app'},
        body: {'contentId': contentId},
      ),
      client.storage
          .from('refresher_video_url')
          .createSignedUrl('refresher_all.mp4', 30 * 60),
    ]);
    final response = results[0] as FunctionResponse;
    if (response.data is! Map) {
      throw const FormatException(
        'Wikipedia returned an invalid refresher response.',
      );
    }
    final videoUrl = Uri.tryParse(results[1] as String);
    if (videoUrl == null || videoUrl.scheme != 'https') {
      throw StateError('The refresher video does not have a playable URL.');
    }
    return RefresherBundle(
      content: RefresherContent.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      ),
      videoUrl: videoUrl,
    );
  }
}
