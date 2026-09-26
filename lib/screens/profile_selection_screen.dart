import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({
    super.key,
    required this.maxProfiles,
    required this.onContinue,
  });

  final int maxProfiles;
  final VoidCallback onContinue;

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  int _selected = 0;

  static const _profiles = [
    ('Mark', AppColors.gold, Icons.sentiment_satisfied_alt_rounded),
    ('Profile 2', AppColors.violet, Icons.face_6_rounded),
    ('Kids', Color(0xFF1CA7A0), Icons.child_care_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles.take(widget.maxProfiles.clamp(1, 3)).toList();
    final canAdd = profiles.length < widget.maxProfiles.clamp(1, 4);
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.85),
            radius: 1.1,
            colors: [Color(0xFF32165B), AppColors.ink],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
            child: Column(
              children: [
                const BrandLogo(compact: true),
                const Spacer(flex: 2),
                Text(
                  "Who's watching?",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 9),
                const Text(
                  'Choose a profile to personalize your experience.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 36),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 18,
                  runSpacing: 24,
                  children: [
                    for (var index = 0; index < profiles.length; index++)
                      _ProfileCard(
                        label: profiles[index].$1,
                        color: profiles[index].$2,
                        icon: profiles[index].$3,
                        selected: index == _selected,
                        onTap: () => setState(() => _selected = index),
                      ),
                    if (canAdd)
                      const _ProfileCard(
                        label: 'Add Profile',
                        color: AppColors.card,
                        icon: Icons.add_rounded,
                        selected: false,
                      ),
                  ],
                ),
                const Spacer(flex: 3),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: widget.onContinue,
                    child: Text('Continue as ${profiles[_selected].$1}'),
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: AppColors.muted,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Profiles are private and secure.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.label,
    required this.color,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      width: 92,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(21),
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: 3,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.violet.withValues(alpha: .55),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: 43,
              color: color == AppColors.card ? AppColors.muted : AppColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.muted,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}
