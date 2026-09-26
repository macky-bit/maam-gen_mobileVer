import 'package:flutter/material.dart';

import '../models/show.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/show_card.dart';
import 'catalog_screen.dart';
import 'details_sheet.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.onSignOut});
  final VoidCallback onSignOut;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _service = TmdbService();
  final Set<Show> _saved = {};
  final List<Show> _continueWatching = [];
  int _tab = 0;
  late List<Future<CatalogData>> _catalogs;

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
  }

  void _loadCatalogs() {
    _catalogs = [
      _service.home(),
      _service.movies(),
      _service.television(),
      _service.newAndPopular(),
    ];
  }

  Future<void> _refresh(int index) async {
    setState(() {
      _catalogs[index] = switch (index) {
        0 => _service.home(),
        1 => _service.movies(),
        2 => _service.television(),
        _ => _service.newAndPopular(),
      };
    });
    try {
      await _catalogs[index];
    } catch (_) {
      // The catalog widget displays the error and keeps pull-to-refresh active.
    }
  }

  void _showDetails(Show show) {
    showDetailsSheet(
      context,
      show: show,
      isSaved: _saved.contains(show),
      onToggleSaved: () => setState(() {
        if (!_saved.remove(show)) _saved.add(show);
      }),
      onPlayStarted: (started) => setState(() {
        _continueWatching.remove(started);
        _continueWatching.insert(0, started);
      }),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          service: _service,
          onSelect: (show) {
            Navigator.pop(context);
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _showDetails(show),
            );
          },
        ),
      ),
    );
  }

  void _showNotifications() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.inkSoft,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifications',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              const _NotificationTile(
                icon: Icons.local_fire_department_rounded,
                title: 'New & trending this week',
                message: 'Fresh movies and series are waiting for you.',
                time: 'Now',
              ),
              const _NotificationTile(
                icon: Icons.movie_filter_outlined,
                title: 'Because you watch dramas',
                message: 'Explore the latest critically acclaimed stories.',
                time: '2h',
              ),
              const _NotificationTile(
                icon: Icons.download_done_rounded,
                title: 'Ready to watch offline',
                message: 'Your downloaded titles are ready.',
                time: '1d',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: AppColors.ink.withValues(alpha: .98),
        elevation: 0,
        title: const BrandLogo(compact: true),
        actions: [
          IconButton(
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search',
          ),
          IconButton(
            onPressed: _showNotifications,
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'Notifications',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(onSignOut: widget.onSignOut),
                ),
              ),
              child: const CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.gold,
                child: Text(
                  'M',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          CatalogScreen(
            catalog: _catalogs[0],
            onSelect: _showDetails,
            onRefresh: () => _refresh(0),
            continueWatching: _continueWatching,
            showHero: true,
          ),
          CatalogScreen(
            catalog: _catalogs[1],
            onSelect: _showDetails,
            onRefresh: () => _refresh(1),
            continueWatching: _continueWatching,
          ),
          CatalogScreen(
            catalog: _catalogs[2],
            onSelect: _showDetails,
            onRefresh: () => _refresh(2),
            continueWatching: _continueWatching,
          ),
          CatalogScreen(
            catalog: _catalogs[3],
            onSelect: _showDetails,
            onRefresh: () => _refresh(3),
            continueWatching: _continueWatching,
          ),
          _MyList(
            items: _saved.toList(),
            onSelect: _showDetails,
            onBrowse: () => setState(() => _tab = 0),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 70,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie_rounded),
            label: 'Movies',
          ),
          NavigationDestination(
            icon: Icon(Icons.live_tv_outlined),
            selectedIcon: Icon(Icons.live_tv_rounded),
            label: 'TV',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_fire_department_outlined),
            selectedIcon: Icon(Icons.local_fire_department_rounded),
            label: 'New',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border_rounded),
            selectedIcon: Icon(Icons.bookmark_rounded),
            label: 'My List',
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.icon,
    required this.title,
    required this.message,
    required this.time,
  });

  final IconData icon;
  final String title;
  final String message;
  final String time;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: AppColors.violet.withValues(alpha: .18),
      child: Icon(icon, color: AppColors.violetLight),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(
      message,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: AppColors.muted, fontSize: 12),
    ),
    trailing: Text(
      time,
      style: const TextStyle(color: AppColors.muted, fontSize: 11),
    ),
  );
}

class _MyList extends StatelessWidget {
  const _MyList({
    required this.items,
    required this.onSelect,
    required this.onBrowse,
  });
  final List<Show> items;
  final ValueChanged<Show> onSelect;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.violet.withValues(alpha: .15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bookmark_add_outlined,
                  size: 40,
                  color: AppColors.violetLight,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Build your watchlist',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 9),
              const Text(
                'Tap + on any title to save it here for later.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: onBrowse,
                child: const Text('Browse titles'),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) =>
          ShowGridTile(show: items[index], onTap: () => onSelect(items[index])),
    );
  }
}
