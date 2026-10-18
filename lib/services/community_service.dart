import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_profile.dart';

const reactionEmojis = [
  '\u{1F44D}',
  '\u{1F602}',
  '\u2764\uFE0F',
  '\u{1F62E}',
  '\u{1F621}',
  '\u{1F622}',
];

const commentMaxLength = 1000;

Map<String, int> emptyReactionCounts() => {
  for (final emoji in reactionEmojis) emoji: 0,
};

String normalizeComment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) throw ArgumentError('Write a comment before posting.');
  if (trimmed.length > commentMaxLength) {
    throw ArgumentError(
      'Comments are limited to $commentMaxLength characters.',
    );
  }
  return trimmed;
}

({Map<String, int> counts, String? myReaction}) optimisticReaction(
  Map<String, int> counts,
  String? current,
  String? next,
) {
  final updated = Map<String, int>.of(counts);
  if (current != null) {
    updated[current] = (updated[current]! - 1).clamp(0, 1 << 31);
  }
  if (next != null) updated[next] = updated[next]! + 1;
  return (counts: updated, myReaction: next);
}

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.text,
    required this.commentedAt,
    required this.userId,
    required this.memberProfileId,
  });

  final String id;
  final String text;
  final DateTime? commentedAt;
  final String userId;
  final int? memberProfileId;

  CommunityComment copyWith({String? text}) => CommunityComment(
    id: id,
    text: text ?? this.text,
    commentedAt: commentedAt,
    userId: userId,
    memberProfileId: memberProfileId,
  );
}

class CommunitySnapshot {
  const CommunitySnapshot({
    required this.counts,
    required this.myReaction,
    required this.comments,
    required this.userId,
  });

  final Map<String, int> counts;
  final String? myReaction;
  final List<CommunityComment> comments;
  final String? userId;
}

class CommunityService {
  const CommunityService(this.supabase);

  final SupabaseClient supabase;

  Future<CommunitySnapshot> load(int contentId) async {
    final userFuture = _currentAppUserId();
    final reactionFuture = supabase
        .from('reaction')
        .select('emoji, user_id')
        .eq('content_id', contentId)
        .eq('status', 'Active');
    final commentFuture = supabase.rpc(
      'get_content_comments_with_authors',
      params: {'selected_content_id': contentId},
    );

    final userId = await userFuture;
    final reactionRows = await reactionFuture;
    final counts = emptyReactionCounts();
    String? myReaction;
    for (final row in reactionRows) {
      final emoji = row['emoji']?.toString();
      if (emoji == null || !counts.containsKey(emoji)) continue;
      counts[emoji] = counts[emoji]! + 1;
      if (row['user_id']?.toString() == userId) myReaction = emoji;
    }

    final commentRows = (await commentFuture as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final comments = commentRows
        .map((row) {
          return CommunityComment(
            id: row['comment_id'].toString(),
            text: row['comment_text'].toString(),
            commentedAt: DateTime.tryParse(
              row['commented_at']?.toString() ?? '',
            ),
            userId: row['user_id']?.toString() ?? '',
            memberProfileId: (row['member_profile_id'] as num?)?.toInt(),
          );
        })
        .toList(growable: false);

    return CommunitySnapshot(
      counts: counts,
      myReaction: myReaction,
      comments: comments,
      userId: userId,
    );
  }

  Future<void> saveReaction({
    required int contentId,
    required String userId,
    required String? previous,
    required String? next,
  }) async {
    if (previous != null) {
      await supabase
          .from('reaction')
          .delete()
          .eq('content_id', contentId)
          .eq('user_id', userId);
    }
    if (next == null) return;
    try {
      await supabase.from('reaction').insert({
        'content_id': contentId,
        'user_id': userId,
        'emoji': next,
      });
    } catch (_) {
      if (previous != null) {
        await supabase.from('reaction').insert({
          'content_id': contentId,
          'user_id': userId,
          'emoji': previous,
        });
      }
      rethrow;
    }
  }

  Future<CommunityComment> postComment({
    required int contentId,
    required String userId,
    required MemberProfile profile,
    required String text,
  }) async {
    final normalized = normalizeComment(text);
    final row = await supabase
        .from('content_comment')
        .insert({
          'content_id': contentId,
          'user_id': userId,
          'member_profile_id': profile.id,
          'comment_text': normalized,
        })
        .select('comment_id, comment_text, commented_at, user_id')
        .single();
    return CommunityComment(
      id: row['comment_id'].toString(),
      text: row['comment_text'].toString(),
      commentedAt: DateTime.tryParse(row['commented_at']?.toString() ?? ''),
      userId: row['user_id'].toString(),
      memberProfileId: profile.id,
    );
  }

  Future<String> updateComment({
    required String commentId,
    required String userId,
    required String text,
  }) async {
    final normalized = normalizeComment(text);
    final row = await supabase
        .from('content_comment')
        .update({'comment_text': normalized})
        .eq('comment_id', commentId)
        .eq('user_id', userId)
        .select('comment_text')
        .single();
    return row['comment_text'].toString();
  }

  Future<void> deleteComment({
    required String commentId,
    required String userId,
  }) async {
    await supabase
        .from('content_comment')
        .delete()
        .eq('comment_id', commentId)
        .eq('user_id', userId);
  }

  Future<String?> _currentAppUserId() async {
    final authId = supabase.auth.currentUser?.id;
    if (authId == null) return null;
    final row = await supabase
        .from('user')
        .select('user_id')
        .eq('auth_user_id', authId)
        .maybeSingle();
    return row?['user_id']?.toString();
  }
}
