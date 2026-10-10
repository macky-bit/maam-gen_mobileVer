import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_profile.dart';
import '../models/show.dart';
import '../services/tmdb_service.dart';
import '../services/library_store.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/show_card.dart';
import 'catalog_screen.dart';
import 'details_sheet.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.supabase,
    required this.activeProfile,
    required this.onProfileChanged,
    required this.onManageProfiles,
    required this.onSignOut,
  });

  final SupabaseClient supabase;
  final MemberProfile activeProfile;
  final ValueChanged<MemberProfile> onProfileChanged;
  final VoidCallback onManageProfiles;
  final VoidCallback onSignOut;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late TmdbService _service;
  final Set<Show> _saved = {};
  final List<Show> _continueWatching = [];
  int _tab = 0;
  late List<Future<CatalogData>?> _catalogs;

  LibraryStore get _library => LibraryStore(
    userId: widget.supabase.auth.currentUser!.id,
    profileId: widget.activeProfile.id,
  );

  @override
  void initState() {
    super.initState();
    _service = TmdbService(kidsMode: widget.activeProfile.isKids);
    _loadCatalogs();
    unawaited(_loadLibrary());
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeProfile.id != widget.activeProfile.id) {
      _service = TmdbService(kidsMode: widget.activeProfile.isKids);
      _loadCatalogs();
      setState(() {
        _tab = 0;
        _saved.clear();
        _continueWatching.clear();
      });
      unawaited(_loadLibrary());
    }
  }

  Future<void> _loadLibrary() async {
    final profileId = widget.activeProfile.id;
    final results = await Future.wait([
      _library.loadMyList(),
      _library.loadContinueWatching(),
    ]);
    if (!mounted || profileId != widget.activeProfile.id) return;
    setState(() {
      _saved
        ..clear()
        ..addAll(results[0]);
      _continueWatching
        ..clear()
        ..addAll(results[1]);
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          supabase: widget.supabase,
          userId: widget.supabase.auth.currentUser!.id,
          activeProfile: widget.activeProfile,
          onActiveProfileUpdated: widget.onProfileChanged,
          onManageProfiles: () {
            Navigator.pop(context);
            widget.onManageProfiles();
          },
          onClearWatchHistory: () {
            setState(_continueWatching.clear);
            unawaited(_library.clearContinueWatching());
          },
          onSignOut: widget.onSignOut,
        ),
      ),
    );
  }

  void _loadCatalogs() {
    _catalogs = [_service.home(), null, null, null];
  }

  Future<CatalogData> _catalogFor(int index) {
    return _catalogs[index] ??= switch (index) {
      0 => _service.home(),
      1 => _service.movies(),
      2 => _service.television(),
      _ => _service.newAndPopular(),
    };
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
      await _catalogs[index]!;
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
        unawaited(_library.saveMyList(_saved));
      }),
      onPlayStarted: (started) => setState(() {
        _continueWatching.remove(started);
        _continueWatching.insert(0, started);
        if (_continueWatching.length > 10) _continueWatching.removeLast();
        unawaited(_library.saveContinueWatching(_continueWatching));
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
        backgroundColor: AppColors.inkSoft.withValues(alpha: .98),
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
            child: IconButton(
              onPressed: _openSettings,
              tooltip: 'Profile and settings',
              icon: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.card,
                backgroundImage: widget.activeProfile.avatarUrl.isEmpty
                    ? null
                    : NetworkImage(widget.activeProfile.avatarUrl),
                child: widget.activeProfile.avatarUrl.isEmpty
                    ? Text(
                        widget.activeProfile.name.characters.first
                            .toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.75, -1),
            radius: 1.35,
            colors: [Color(0xFF32165B), AppColors.ink],
          ),
        ),
        child: IndexedStack(
          index: _tab,
          children: [
            CatalogScreen(
              catalog: _catalogFor(0),
              onSelect: _showDetails,
              onRefresh: () => _refresh(0),
              continueWatching: _continueWatching,
              showHero: true,
            ),
            if (_catalogs[1] != null)
              CatalogScreen(
                catalog: _catalogs[1]!,
                onSelect: _showDetails,
                onRefresh: () => _refresh(1),
                continueWatching: _continueWatching,
              )
            else
              const SizedBox.shrink(),
            if (_catalogs[2] != null)
              CatalogScreen(
                catalog: _catalogs[2]!,
                onSelect: _showDetails,
                onRefresh: () => _refresh(2),
                continueWatching: _continueWatching,
              )
            else
              const SizedBox.shrink(),
            if (_catalogs[3] != null)
              CatalogScreen(
                catalog: _catalogs[3]!,
                onSelect: _showDetails,
                onRefresh: () => _refresh(3),
                continueWatching: _continueWatching,
              )
            else
              const SizedBox.shrink(),
            _MyList(
              items: _saved.toList(),
              onSelect: _showDetails,
              onBrowse: () => setState(() => _tab = 0),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.inkSoft,
        selectedIndex: _tab,
        height: 70,
        onDestinationSelected: (value) => setState(() {
          _tab = value;
          if (value < 4) _catalogFor(value);
        }),
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
