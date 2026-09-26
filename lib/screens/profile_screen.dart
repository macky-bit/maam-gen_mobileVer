import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.onSignOut});
  final VoidCallback onSignOut;

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
          child: const Row(
            children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: AppColors.gold,
                child: Text(
                  'M',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Profile',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Premium member',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit_outlined),
            ],
          ),
        ),
        const SizedBox(height: 26),
        const _SectionLabel('ACCOUNT'),
        _SettingsTile(
          icon: Icons.person_outline_rounded,
          title: 'Account details',
          subtitle: 'Email, password and profile',
        ),
        _SettingsTile(
          icon: Icons.workspace_premium_outlined,
          title: 'Subscription',
          subtitle: 'Premium • Renews monthly',
          trailing: 'Manage',
        ),
        _SettingsTile(
          icon: Icons.devices_rounded,
          title: 'Devices',
          subtitle: 'Manage signed-in devices',
        ),
        const SizedBox(height: 22),
        const _SectionLabel('PREFERENCES'),
        _SettingsTile(
          icon: Icons.notifications_none_rounded,
          title: 'Notifications',
          subtitle: 'New releases and recommendations',
        ),
        _SettingsTile(
          icon: Icons.download_outlined,
          title: 'Downloads',
          subtitle: 'Wi-Fi only • Standard quality',
        ),
        _SettingsTile(
          icon: Icons.language_rounded,
          title: 'Language',
          subtitle: 'English',
        ),
        _SettingsTile(
          icon: Icons.child_care_outlined,
          title: 'Parental controls',
          subtitle: 'Viewing restrictions and PIN',
        ),
        const SizedBox(height: 22),
        const _SectionLabel('SUPPORT'),
        _SettingsTile(
          icon: Icons.help_outline_rounded,
          title: 'Help center',
          subtitle: 'FAQs and contact options',
        ),
        _SettingsTile(
          icon: Icons.info_outline_rounded,
          title: 'About StreamFlix',
          subtitle: 'Version 1.0.0',
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
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;

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
    onTap: () {},
  );
}
