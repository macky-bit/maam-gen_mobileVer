class MemberProfile {
  const MemberProfile({
    required this.id,
    required this.name,
    required this.avatarPath,
    required this.avatarUrl,
    required this.isKids,
    this.hasPin = false,
    this.isEntitled = true,
    required this.displayOrder,
  });

  final int id;
  final String name;
  final String avatarPath;
  final String avatarUrl;
  final bool isKids;
  final bool hasPin;
  final bool isEntitled;
  final int displayOrder;

  factory MemberProfile.fromJson(
    Map<String, dynamic> json, {
    required String avatarUrl,
  }) {
    return MemberProfile(
      id: (json['member_profile_id'] as num).toInt(),
      name: json['profile_name'] as String,
      avatarPath: json['avatar_image'] as String? ?? '',
      avatarUrl: avatarUrl,
      isKids: json['is_kids'] as bool? ?? false,
      hasPin: json['has_pin'] as bool? ?? false,
      isEntitled: json['is_entitled'] as bool? ?? true,
      displayOrder: (json['display_order'] as num).toInt(),
    );
  }
}

class MemberProfileContext {
  const MemberProfileContext({
    required this.planName,
    required this.maxProfiles,
    required this.allowsKids,
    required this.activeProfileCount,
    required this.canAddProfile,
  });

  final String planName;
  final int maxProfiles;
  final bool allowsKids;
  final int activeProfileCount;
  final bool canAddProfile;

  factory MemberProfileContext.fromJson(Map<String, dynamic> json) {
    return MemberProfileContext(
      planName: json['plan_name'] as String,
      maxProfiles: (json['max_profiles'] as num).toInt(),
      allowsKids: json['allows_kids'] as bool? ?? false,
      activeProfileCount: (json['active_profile_count'] as num).toInt(),
      canAddProfile: json['can_add_profile'] as bool? ?? false,
    );
  }
}

class AvatarOption {
  const AvatarOption({required this.path, required this.signedUrl});

  final String path;
  final String signedUrl;
}

class MemberProfileCatalog {
  const MemberProfileCatalog({
    required this.context,
    required this.profiles,
    required this.avatars,
  });

  final MemberProfileContext context;
  final List<MemberProfile> profiles;
  final List<AvatarOption> avatars;
}
