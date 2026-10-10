import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/models/show.dart';

void main() {
  test('kids suitability requires a kids genre and rejects mature content', () {
    final family = Show.fromJson({
      'id': 1,
      'title': 'Family film',
      'genre_ids': [16, 10751],
      'adult': false,
    });
    final horror = Show.fromJson({
      'id': 2,
      'title': 'Animated horror',
      'genre_ids': [16, 27],
      'adult': false,
    });
    final adult = Show.fromJson({
      'id': 3,
      'title': 'Adult animation',
      'genre_ids': [16],
      'adult': true,
    });

    expect(family.isKidsAppropriate, isTrue);
    expect(horror.isKidsAppropriate, isFalse);
    expect(adult.isKidsAppropriate, isFalse);
  });

  test('local serialization preserves the show identity and restrictions', () {
    const show = Show(
      id: 42,
      title: 'Saved title',
      overview: 'Overview',
      posterPath: '/poster.jpg',
      backdropPath: '/backdrop.jpg',
      year: '2026',
      score: 87,
      mediaType: 'movie',
      genreIds: [16, 10751],
      isAdult: false,
    );

    final restored = Show.fromJson(show.toJson());

    expect(restored, show);
    expect(restored.title, show.title);
    expect(restored.genreIds, show.genreIds);
    expect(restored.isKidsAppropriate, isTrue);
  });
}
