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
    this.contentId,
    this.tmdbId,
    this.categoryName = '',
    this.videoPath = '',
    this.runtimeMinutes,
    this.ageRating = '',
    this.catalogSource = '',
    this.popularityRank,
    this.isAdult = false,
    this.genreIds = const [],
    this.genreNames = const [],
  });

  final int id;
  final String title;
  final String overview;
  final String posterPath;
  final String backdropPath;
  final String year;
  final int score;
  final String mediaType;
  final int? contentId;
  final int? tmdbId;
  final String categoryName;
  final String videoPath;
  final int? runtimeMinutes;
  final String ageRating;
  final String catalogSource;
  final int? popularityRank;
  final bool isAdult;
  final List<int> genreIds;
  final List<String> genreNames;

  int? get tmdbReferenceId => tmdbId ?? (contentId == null ? id : null);

  String get posterUrl => posterPath.isEmpty
      ? ''
      : posterPath.startsWith('http')
      ? posterPath
      : 'https://image.tmdb.org/t/p/w500$posterPath';
  String get backdropUrl => backdropPath.isEmpty
      ? posterUrl
      : backdropPath.startsWith('http')
      ? backdropPath
      : 'https://image.tmdb.org/t/p/w1280$backdropPath';

  bool get isKidsAppropriate {
    const kidsGenres = {16, 10751, 10762};
    const matureGenres = {27, 80, 10752};
    const kidsGenreNames = {'animation', 'family', 'kids', 'children'};
    const matureGenreNames = {'crime', 'horror', 'war'};
    final normalizedNames = genreNames
        .map((name) => name.trim().toLowerCase())
        .toSet();
    return !isAdult &&
        (genreIds.any(kidsGenres.contains) ||
            normalizedNames.any(kidsGenreNames.contains)) &&
        !genreIds.any(matureGenres.contains) &&
        !normalizedNames.any(matureGenreNames.contains);
  }

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
      contentId: (json['content_id'] as num?)?.toInt(),
      tmdbId: json.containsKey('tmdb_id')
          ? (json['tmdb_id'] as num?)?.toInt()
          : (json['id'] as num?)?.toInt(),
      categoryName: (json['category_name'] ?? '').toString(),
      videoPath: (json['video_file'] ?? '').toString(),
      runtimeMinutes: (json['runtime'] as num?)?.toInt(),
      ageRating: (json['age_rating'] ?? '').toString(),
      catalogSource: (json['catalog_source'] ?? '').toString(),
      popularityRank: (json['popularity_rank'] as num?)?.toInt(),
      isAdult: json['adult'] as bool? ?? false,
      genreIds: (json['genre_ids'] as List<dynamic>? ?? const [])
          .whereType<num>()
          .map((id) => id.toInt())
          .toList(),
      genreNames: (json['genre_names'] as List<dynamic>? ?? const [])
          .map((name) => name.toString())
          .where((name) => name.isNotEmpty)
          .toList(),
    );
  }

  factory Show.fromCatalogJson(
    Map<String, dynamic> json, {
    String? thumbnailUrl,
  }) {
    final contentId = (json['content_id'] as num).toInt();
    final tmdbId = (json['tmdb_id'] as num?)?.toInt();
    final category = _relationName(json['category'], 'category_name');
    final legacyGenre = _relationName(json['genre'], 'genre_name');
    final genreNames = <String>{
      if (legacyGenre.isNotEmpty) legacyGenre,
      for (final item in json['content_genre'] as List<dynamic>? ?? const [])
        if (item is Map) _relationName(item['genre'], 'genre_name'),
    }..remove('');
    final thumbnail = thumbnailUrl ?? (json['thumbnail'] ?? '').toString();

    return Show(
      id: tmdbId ?? contentId,
      contentId: contentId,
      tmdbId: tmdbId,
      categoryName: category,
      videoPath: (json['video_file'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled').toString(),
      overview: (json['synopsis'] ?? '').toString(),
      posterPath: thumbnail,
      backdropPath: thumbnail,
      year: (json['release_year'] ?? '').toString(),
      score: 0,
      mediaType: category.toLowerCase().contains('tv') ? 'tv' : 'movie',
      runtimeMinutes: (json['runtime'] as num?)?.toInt(),
      ageRating: (json['age_rating'] ?? '').toString(),
      catalogSource: (json['catalog_source'] ?? '').toString(),
      popularityRank: (json['popularity_rank'] as num?)?.toInt(),
      genreNames: genreNames.toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'overview': overview,
    'poster_path': posterPath,
    'backdrop_path': backdropPath,
    'release_date': year,
    'vote_average': score / 10,
    'media_type': mediaType,
    'content_id': contentId,
    'tmdb_id': tmdbId,
    'category_name': categoryName,
    'video_file': videoPath,
    'runtime': runtimeMinutes,
    'age_rating': ageRating,
    'catalog_source': catalogSource,
    'popularity_rank': popularityRank,
    'genre_ids': genreIds,
    'genre_names': genreNames,
    'adult': isAdult,
  };

  @override
  bool operator ==(Object other) =>
      other is Show && other.id == id && other.mediaType == mediaType;

  @override
  int get hashCode => Object.hash(id, mediaType);
}

class CatalogData {
  const CatalogData({
    required this.featured,
    required this.rows,
    this.genres = const [],
  });
  final Show? featured;
  final List<CatalogRow> rows;
  final List<String> genres;
}

class CatalogRow {
  const CatalogRow(this.title, this.items, {this.ranked = false});
  final String title;
  final List<Show> items;
  final bool ranked;
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

String _relationName(dynamic value, String key) {
  final relation = value is List ? value.firstOrNull : value;
  return relation is Map ? (relation[key] ?? '').toString() : '';
}
