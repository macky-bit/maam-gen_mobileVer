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
    this.unavailable = false,
  });

  final Show show;
  final VoidCallback onTap;
  final int? rank;
  final double width;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: rank == null ? width : width + 30,
      child: InkWell(
        onTap: unavailable ? null : onTap,
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
                    if (unavailable) const ColoredBox(color: Color(0x990D0817)),
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
                          if (show.score > 0)
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
                    if (unavailable)
                      const Positioned(
                        left: 8,
                        top: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xE6241638),
                            borderRadius: BorderRadius.all(Radius.circular(6)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            child: Text(
                              'UNAVAILABLE',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .5,
                              ),
                            ),
                          ),
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
  const ShowGridTile({
    super.key,
    required this.show,
    required this.onTap,
    this.unavailable = false,
  });
  final Show show;
  final VoidCallback onTap;
  final bool unavailable;

  @override
  Widget build(BuildContext context) => ShowCard(
    show: show,
    onTap: onTap,
    width: double.infinity,
    unavailable: unavailable,
  );
}
