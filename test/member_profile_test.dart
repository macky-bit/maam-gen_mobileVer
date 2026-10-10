import 'package:flutter_test/flutter_test.dart';
import 'package:stream_flix/models/member_profile.dart';

void main() {
  test('maps the server profile context', () {
    final context = MemberProfileContext.fromJson({
      'plan_name': 'Premium',
      'max_profiles': 4,
      'allows_kids': true,
      'active_profile_count': 2,
      'can_add_profile': true,
    });

    expect(context.planName, 'Premium');
    expect(context.maxProfiles, 4);
    expect(context.allowsKids, isTrue);
    expect(context.activeProfileCount, 2);
    expect(context.canAddProfile, isTrue);
  });

  test('maps a member profile without exposing PIN data', () {
    final profile = MemberProfile.fromJson({
      'member_profile_id': 7,
      'profile_name': 'Kids',
      'avatar_image': 'avatar.png',
      'is_kids': true,
      'display_order': 2,
    }, avatarUrl: 'https://signed.example/avatar.png');

    expect(profile.id, 7);
    expect(profile.name, 'Kids');
    expect(profile.avatarPath, 'avatar.png');
    expect(profile.isKids, isTrue);
    expect(profile.displayOrder, 2);
  });
}
