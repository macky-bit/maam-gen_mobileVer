import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/services/tmdb_service.dart';

void main() {
  test('selects official YouTube trailers before trailers and teasers', () {
    final key = selectTrailerKey([
      {'site': 'YouTube', 'type': 'Teaser', 'key': 'teaser'},
      {'site': 'Vimeo', 'type': 'Trailer', 'official': true, 'key': 'vimeo'},
      {'site': 'YouTube', 'type': 'Trailer', 'key': 'trailer'},
      {
        'site': 'YouTube',
        'type': 'Trailer',
        'official': true,
        'key': 'official',
      },
    ]);

    expect(key, 'official');
    expect(selectTrailerKey(const []), isNull);
  });
}
