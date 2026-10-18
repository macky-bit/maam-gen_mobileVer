import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/streamflix_logo.png',
          width: compact ? 34 : 52,
          height: compact ? 34 : 52,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 4),
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            colors: [AppColors.gold, AppColors.orange, AppColors.violetLight],
          ).createShader(rect),
          child: Text(
            'STREAMFLIX',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 18 : 29,
              fontWeight: FontWeight.w900,
              letterSpacing: compact ? -.5 : -1,
            ),
          ),
        ),
      ],
    );
  }
}
