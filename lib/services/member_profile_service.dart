import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_profile.dart';

class MemberProfileService {
  const MemberProfileService(this.client);

  final SupabaseClient client;

  Future<MemberProfileCatalog> loadCatalog() async {
    final contextRows =
        await client.rpc('get_my_member_profile_context') as List;
    if (contextRows.isEmpty) {
      throw StateError('An active subscription is required.');
    }
    final context = MemberProfileContext.fromJson(
      contextRows.first as Map<String, dynamic>,
    );

    final profileRows = await client.rpc('get_my_member_profiles') as List;

    final avatarFiles = await client.storage.from('avatar').list();
    final avatarPaths = avatarFiles
        .map((file) => file.name)
        .where((name) => name.toLowerCase().endsWith('.png'))
        .toList(growable: false);
    final signedUrls = <String, String>{};
    await Future.wait(
      avatarPaths.map((path) async {
        signedUrls[path] = await client.storage
            .from('avatar')
            .createSignedUrl(path, 3600);
      }),
    );

    final profiles = profileRows
        .map((row) {
          final path = row['avatar_image'] as String? ?? '';
          return MemberProfile.fromJson(row, avatarUrl: signedUrls[path] ?? '');
        })
        .toList(growable: false);
    final avatars = avatarPaths
        .map(
          (path) => AvatarOption(path: path, signedUrl: signedUrls[path] ?? ''),
        )
        .toList(growable: false);

    return MemberProfileCatalog(
      context: context,
      profiles: profiles,
      avatars: avatars,
    );
  }

  Future<void> createProfile({
    required String name,
    required String avatarPath,
    required bool isKids,
    String? pin,
  }) async {
    await client.rpc(
      'create_my_member_profile',
      params: {
        'selected_profile_name': name,
        'selected_avatar_path': avatarPath,
        'selected_is_kids': isKids,
        'selected_pin': pin?.trim().isEmpty == true ? null : pin?.trim(),
      },
    );
  }

  Future<void> updateProfile({
    required int profileId,
    required String name,
    required String avatarPath,
    String? newPin,
    bool removePin = false,
  }) async {
    await client.rpc(
      'update_my_member_profile',
      params: {
        'selected_profile_id': profileId,
        'selected_profile_name': name.trim(),
        'selected_avatar_path': avatarPath,
        'selected_pin': newPin?.trim().isEmpty == true ? null : newPin?.trim(),
        'remove_pin': removePin,
      },
    );
  }
}
