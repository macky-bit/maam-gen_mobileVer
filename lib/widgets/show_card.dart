import 'package:flutter/material.dart';

import '../models/show.dart';
import '../theme/app_theme.dart';
import 'network_art.dart';

class ShowCard extends StatelessWidget {
  const ShowCard({
    super.key,
    required this.show,
    required this.onTap,
    this.rank,
    this.width = 132,
  });

  final Show show;
  final VoidCallback onTap;
  final int? rank;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: rank == null ? width : width + 30,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            if (rank != null)
              Positioned(
                left: 0,
                bottom: -8,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 82,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: AppColors.inkSoft,
                    shadows: const [
                      Shadow(color: AppColors.violetLight, blurRadius: 2),
                    ],
                  ),
                ),
              ),
            Container(
              width: width,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: .08)),
              ),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkArt(url: show.posterUrl, fit: BoxFit.cover),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Color(0xC9000000),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 9,
                      right: 9,
                      bottom: 9,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            show.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${show.score}% Match',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShowGridTile extends StatelessWidget {
  const ShowGridTile({super.key, required this.show, required this.onTap});
  final Show show;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      ShowCard(show: show, onTap: onTap, width: double.infinity);
}
