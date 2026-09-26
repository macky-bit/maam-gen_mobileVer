class Show {
  const Show({
    required this.id,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.year,
    required this.score,
    required this.mediaType,
    this.genreIds = const [],
  });

  final int id;
  final String title;
  final String overview;
  final String posterPath;
  final String backdropPath;
  final String year;
  final int score;
  final String mediaType;
  final List<int> genreIds;

  String get posterUrl =>
      posterPath.isEmpty ? '' : 'https://image.tmdb.org/t/p/w500$posterPath';
  String get backdropUrl => backdropPath.isEmpty
      ? posterUrl
      : 'https://image.tmdb.org/t/p/original$backdropPath';

  factory Show.fromJson(Map<String, dynamic> json, {String? type}) {
    final date = (json['release_date'] ?? json['first_air_date'] ?? '')
        .toString();
    final vote = (json['vote_average'] as num?)?.toDouble() ?? 0;
    return Show(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? json['name'] ?? 'Untitled').toString(),
      overview: (json['overview'] ?? '').toString(),
      posterPath: (json['poster_path'] ?? '').toString(),
      backdropPath: (json['backdrop_path'] ?? '').toString(),
      year: date.length >= 4 ? date.substring(0, 4) : '',
      score: (vote * 10).round(),
      mediaType:
          (type ??
                  json['media_type'] ??
                  (json['name'] != null ? 'tv' : 'movie'))
              .toString(),
      genreIds: (json['genre_ids'] as List<dynamic>? ?? const [])
          .whereType<num>()
          .map((id) => id.toInt())
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Show && other.id == id && other.mediaType == mediaType;

  @override
  int get hashCode => Object.hash(id, mediaType);
}

class CatalogData {
  const CatalogData({required this.featured, required this.rows});
  final Show? featured;
  final List<CatalogRow> rows;
}

class CatalogRow {
  const CatalogRow(this.title, this.items);
  final String title;
  final List<Show> items;
}

class Episode {
  const Episode({
    required this.number,
    required this.title,
    required this.overview,
    required this.runtimeMinutes,
    required this.imageUrl,
  });

  final int number;
  final String title;
  final String overview;
  final int runtimeMinutes;
  final String imageUrl;
}
