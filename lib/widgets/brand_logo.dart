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
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            colors: [AppColors.gold, AppColors.orange, AppColors.violet],
          ).createShader(rect),
          child: Icon(
            Icons.local_fire_department_rounded,
            color: Colors.white,
            size: compact ? 27 : 39,
          ),
        ),
        const SizedBox(width: 5),
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
