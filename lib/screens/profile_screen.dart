import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import 'active_profile_editor_screen.dart';
import 'settings_detail_screens.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.supabase,
    required this.userId,
    required this.activeProfile,
    required this.onActiveProfileUpdated,
    required this.onManageProfiles,
    required this.onClearWatchHistory,
    required this.onSignOut,
  });

  final SupabaseClient supabase;
  final String userId;
  final MemberProfile activeProfile;
  final ValueChanged<MemberProfile> onActiveProfileUpdated;
  final VoidCallback onManageProfiles;
  final VoidCallback onClearWatchHistory;
  final VoidCallback onSignOut;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late MemberProfile activeProfile;
  SupabaseClient get supabase => widget.supabase;
  String get userId => widget.userId;
  VoidCallback get onManageProfiles => widget.onManageProfiles;
  VoidCallback get onClearWatchHistory => widget.onClearWatchHistory;
  VoidCallback get onSignOut => widget.onSignOut;

  @override
  void initState() {
    super.initState();
    activeProfile = widget.activeProfile;
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeProfile.id != widget.activeProfile.id ||
        oldWidget.activeProfile.name != widget.activeProfile.name ||
        oldWidget.activeProfile.avatarPath != widget.activeProfile.avatarPath) {
      activeProfile = widget.activeProfile;
    }
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _editActiveProfile() {
    _open(
      context,
      ActiveProfileEditorScreen(
        supabase: supabase,
        profile: activeProfile,
        onSaved: (updated) {
          setState(() => activeProfile = updated);
          widget.onActiveProfileUpdated(updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const BrandLogo(compact: true), centerTitle: false),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.violetDeep, AppColors.card],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: AppColors.card,
                backgroundImage: activeProfile.avatarUrl.isEmpty
                    ? null
                    : NetworkImage(activeProfile.avatarUrl),
                child: activeProfile.avatarUrl.isEmpty
                    ? Text(
                        activeProfile.name.characters.first.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeProfile.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      activeProfile.isKids ? 'Kids profile' : 'Active profile',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _editActiveProfile,
                tooltip: 'Edit active profile',
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        const _SectionLabel('ACCOUNT'),
        _SettingsTile(
          icon: Icons.person_outline_rounded,
          title: 'Account details',
          subtitle: 'Email, password and profile',
          onTap: () => _open(context, AccountDetailsScreen(supabase: supabase)),
        ),
        _SettingsTile(
          icon: Icons.switch_account_outlined,
          title: 'Profiles',
          subtitle: 'Switch, add or manage viewing profiles',
          onTap: onManageProfiles,
        ),
        _SettingsTile(
          icon: Icons.workspace_premium_outlined,
          title: 'Subscription',
          subtitle: 'Membership and billing details',
          trailing: 'Manage',
          onTap: () =>
              _open(context, SubscriptionDetailsScreen(supabase: supabase)),
        ),
        const SizedBox(height: 22),
        const _SectionLabel('PREFERENCES'),
        _SettingsTile(
          icon: Icons.play_circle_outline_rounded,
          title: 'Playback & privacy',
          subtitle: 'Autoplay, quality, history and subtitles',
          onTap: () => _open(
            context,
            PlaybackPrivacyScreen(
              userId: userId,
              onClearWatchHistory: onClearWatchHistory,
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.download_outlined,
          title: 'Downloads',
          subtitle: 'Wi-Fi only • Standard quality',
          onTap: () => _open(context, DownloadSettingsScreen(userId: userId)),
        ),
        _SettingsTile(
          icon: Icons.language_rounded,
          title: 'Language',
          subtitle: 'English',
          onTap: () => _open(context, LanguageSettingsScreen(userId: userId)),
        ),
        _SettingsTile(
          icon: Icons.child_care_outlined,
          title: 'Parental controls',
          subtitle: 'Viewing restrictions and PIN',
          onTap: () => _open(
            context,
            ParentalControlsScreen(supabase: supabase, profile: activeProfile),
          ),
        ),
        const SizedBox(height: 22),
        const _SectionLabel('SUPPORT'),
        _SettingsTile(
          icon: Icons.help_outline_rounded,
          title: 'Help center',
          subtitle: 'FAQs and contact options',
          onTap: () => _open(context, HelpCenterScreen(supabase: supabase)),
        ),
        _SettingsTile(
          icon: Icons.info_outline_rounded,
          title: 'About StreamFlix',
          subtitle: 'Version 1.0.0',
          onTap: () => _open(context, const AboutStreamFlixScreen()),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            onSignOut();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFF7777),
            side: const BorderSide(color: Color(0x55FF7777)),
            minimumSize: const Size(0, 52),
          ),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.violetLight,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.violet.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.violetLight),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(
      subtitle,
      style: const TextStyle(color: AppColors.muted, fontSize: 12),
    ),
    trailing: trailing == null
        ? const Icon(Icons.chevron_right_rounded, color: AppColors.muted)
        : Text(
            trailing!,
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
    onTap: onTap ?? () {},
  );
}
