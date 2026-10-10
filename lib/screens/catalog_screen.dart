import 'package:flutter/material.dart';

import '../models/show.dart';
import '../theme/app_theme.dart';
import '../widgets/network_art.dart';
import '../widgets/show_card.dart';

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({
    super.key,
    required this.catalog,
    required this.onSelect,
    required this.onRefresh,
    required this.continueWatching,
    this.showHero = false,
  });

  final Future<CatalogData> catalog;
  final ValueChanged<Show> onSelect;
  final Future<void> Function() onRefresh;
  final List<Show> continueWatching;
  final bool showHero;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CatalogData>(
      future: catalog,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _CatalogSkeleton();
        }
        if (snapshot.hasError) {
          return _CatalogError(
            message: snapshot.error.toString(),
            onRetry: onRefresh,
          );
        }
        final data = snapshot.data;
        if (data == null || data.rows.every((row) => row.items.isEmpty)) {
          return _CatalogError(
            message: 'Nothing to show right now. Pull to try again.',
            onRetry: onRefresh,
          );
        }
        return RefreshIndicator(
          onRefresh: onRefresh,
          color: AppColors.gold,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (showHero && data.featured != null)
                SliverToBoxAdapter(
                  child: _HeroBanner(show: data.featured!, onSelect: onSelect),
                ),
              if (continueWatching.isNotEmpty)
                SliverToBoxAdapter(
                  child: _ContinueWatchingRow(
                    items: continueWatching,
                    onSelect: onSelect,
                  ),
                ),
              SliverList.builder(
                itemCount: data.rows.length,
                itemBuilder: (context, index) {
                  final row = data.rows[index];
                  if (row.items.isEmpty) return const SizedBox.shrink();
                  return _CatalogRow(
                    row: row,
                    ranked: index == 0,
                    onSelect: onSelect,
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 26)),
            ],
          ),
        );
      },
    );
  }
}

class _ContinueWatchingRow extends StatelessWidget {
  const _ContinueWatchingRow({required this.items, required this.onSelect});

  final List<Show> items;
  final ValueChanged<Show> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'Continue Watching',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 13),
        SizedBox(
          height: 126,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final show = items[index];
              return InkWell(
                onTap: () => onSelect(show),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 210,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetworkArt(url: show.backdropUrl, fit: BoxFit.cover),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xD9000000)],
                          ),
                        ),
                      ),
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          size: 42,
                          color: Colors.white,
                        ),
                      ),
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: Text(
                          show.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: .08,
                          minHeight: 3,
                          color: AppColors.gold,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.show, required this.onSelect});
  final Show show;
  final ValueChanged<Show> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .48,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetworkArt(url: show.backdropUrl, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .42, .78, 1],
                colors: [
                  Color(0x44000000),
                  Color(0x11000000),
                  Color(0xB30D0817),
                  AppColors.ink,
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.violet,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Text(
                    'FEATURED',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  show.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.displayLarge?.copyWith(fontSize: 39, height: .95),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: [
                    Text(
                      '${show.score}% Match',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (show.year.isNotEmpty) Text(show.year),
                    Text(show.mediaType == 'tv' ? 'Series' : 'Movie'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  show.overview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .82),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => onSelect(show),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => onSelect(show),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          backgroundColor: Colors.black.withValues(alpha: .35),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: .35),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.info_outline_rounded),
                        label: const Text('More info'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.row,
    required this.onSelect,
    required this.ranked,
  });
  final CatalogRow row;
  final ValueChanged<Show> onSelect;
  final bool ranked;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  row.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
        const SizedBox(height: 13),
        SizedBox(
          height: 202,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: row.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 11),
            itemBuilder: (context, index) => ShowCard(
              show: row.items[index],
              rank: ranked && index < 10 ? index + 1 : null,
              onTap: () => onSelect(row.items[index]),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();
  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    children: [
      Container(
        height: MediaQuery.sizeOf(context).height * .48,
        color: AppColors.inkSoft,
      ),
      for (var row = 0; row < 2; row++)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 160, height: 20, color: Colors.white10),
              const SizedBox(height: 14),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, _) => Container(
                    width: 125,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.live_tv_outlined,
            color: AppColors.violetLight,
            size: 56,
          ),
          const SizedBox(height: 18),
          const Text(
            'Your catalog is waiting',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            message.replaceFirst('TmdbException: ', ''),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
