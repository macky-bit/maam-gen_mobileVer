import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NetworkArt extends StatelessWidget {
  const NetworkArt({super.key, required this.url, required this.fit});
  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _Placeholder();
    return Image.network(
      url,
      fit: fit,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: sync || frame != null ? 1 : 0,
        child: child,
      ),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _Placeholder(),
      errorBuilder: (_, _, _) => const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.card,
    child: Center(
      child: Icon(
        Icons.movie_creation_outlined,
        color: AppColors.muted,
        size: 32,
      ),
    ),
  );
}
