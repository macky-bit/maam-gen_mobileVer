import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/services/refresher_service.dart';

void main() {
  test('maps only verified Wikipedia refresher responses', () {
    final refresher = RefresherContent.fromJson({
      'summary': 'A verified summary.',
      'events': ['First event'],
      'characters': ['Main character'],
      'keyDetails': ['Remember this'],
      'sourceName': 'Wikipedia',
      'sourceTitle': 'Example film',
      'sourceUrl': 'https://en.wikipedia.org/wiki/Example_film',
      'scope': 'movie',
      'cached': true,
    });

    expect(refresher.events, ['First event']);
    expect(refresher.characters, ['Main character']);
    expect(refresher.sourceUrl.host, 'en.wikipedia.org');
    expect(refresher.cached, isTrue);

    expect(
      () => RefresherContent.fromJson({
        'summary': 'Untrusted summary.',
        'sourceTitle': 'Example',
        'sourceUrl': 'https://example.com/not-wikipedia',
        'scope': 'movie',
      }),
      throwsFormatException,
    );
  });
}
