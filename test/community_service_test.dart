import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/services/community_service.dart';

void main() {
  group('normalizeComment', () {
    test('trims a valid comment', () {
      expect(normalizeComment('  Great episode!  '), 'Great episode!');
    });

    test('rejects empty and oversized comments', () {
      expect(() => normalizeComment('   '), throwsArgumentError);
      expect(
        () => normalizeComment('x' * (commentMaxLength + 1)),
        throwsArgumentError,
      );
    });
  });

  group('optimisticReaction', () {
    test('moves a reaction between emojis', () {
      final result = optimisticReaction(
        {...emptyReactionCounts(), reactionEmojis.first: 2},
        reactionEmojis.first,
        reactionEmojis[1],
      );

      expect(result.myReaction, reactionEmojis[1]);
      expect(result.counts[reactionEmojis.first], 1);
      expect(result.counts[reactionEmojis[1]], 1);
    });

    test('removes a toggled reaction without going below zero', () {
      final result = optimisticReaction(
        emptyReactionCounts(),
        reactionEmojis.first,
        null,
      );

      expect(result.myReaction, isNull);
      expect(result.counts[reactionEmojis.first], 0);
    });
  });
}
