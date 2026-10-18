import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_profile.dart';
import '../models/show.dart';
import '../services/catalog_service.dart';
import '../services/content_notification_service.dart';
import '../services/tmdb_service.dart';
import '../services/library_store.dart';
import '../services/watch_history_service.dart';
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
    required this.planName,
    required this.onProfileChanged,
    required this.onProfileDeleted,
    required this.onManageProfiles,
    required this.onSubscriptionChanged,
    required this.onSignOut,
  });

  final SupabaseClient supabase;
  final MemberProfile activeProfile;
  final String planName;
  final ValueChanged<MemberProfile> onProfileChanged;
  final VoidCallback onProfileDeleted;
  final VoidCallback onManageProfiles;
  final Future<void> Function() onSubscriptionChanged;
  final VoidCallback onSignOut;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late CatalogService _catalogService;
  late ContentNotificationService _notificationService;
  late TmdbService _tmdbService;
  final Set<Show> _saved = {};
  final List<WatchHistoryEntry> _continueWatching = [];
  List<ContentNotification> _notifications = const [];
  RealtimeChannel? _notificationChannel;
  DateTime? _notificationsSeenAt;
  bool _notificationsLoading = true;
  String? _notificationsError;
  int _tab = 0;
  late List<Future<CatalogData>?> _catalogs;

  LibraryStore get _library => LibraryStore(
    userId: widget.supabase.auth.currentUser!.id,
    profileId: widget.activeProfile.id,
  );
  WatchHistoryService get _watchHistory => WatchHistoryService(widget.supabase);

  @override
  void initState() {
    super.initState();
    _configureServices();
    _loadCatalogs();
    unawaited(_loadLibrary());
    unawaited(_loadWatchHistory());
    unawaited(_startNotifications());
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeProfile.id != widget.activeProfile.id) {
      _configureServices();
      _loadCatalogs();
      setState(() {
        _tab = 0;
        _saved.clear();
        _continueWatching.clear();
      });
      unawaited(_loadLibrary());
      unawaited(_loadWatchHistory());
      unawaited(_loadNotificationsSeenAt());
      unawaited(_refreshNotifications());
    }
  }

  void _configureServices() {
    _catalogService = CatalogService(
      widget.supabase,
      kidsMode: widget.activeProfile.isKids,
    );
    _notificationService = ContentNotificationService(widget.supabase);
    _tmdbService = TmdbService(kidsMode: widget.activeProfile.isKids);
  }

  String get _notificationSeenKey =>
      'sf_content_notifications_seen_v1_${widget.supabase.auth.currentUser!.id}_${widget.activeProfile.id}';

  Future<void> _startNotifications() async {
    await _loadNotificationsSeenAt();
    await _refreshNotifications();
    if (!mounted) return;
    _notificationChannel = widget.supabase
        .channel('mobile-dashboard-content-notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'content',
          callback: (_) {
            unawaited(_refreshNotifications());
            _refreshLoadedCatalogs();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'content_genre',
          callback: (_) => _refreshLoadedCatalogs(),
        )
        .subscribe();
  }

  Future<void> _loadNotificationsSeenAt() async {
    final preferences = await SharedPreferences.getInstance();
    final milliseconds = preferences.getInt(_notificationSeenKey);
    if (!mounted) return;
    setState(() {
      _notificationsSeenAt = milliseconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(milliseconds);
    });
  }

  Future<void> _refreshNotifications() async {
    if (mounted) {
      setState(() {
        _notificationsLoading = true;
        _notificationsError = null;
      });
    }
    try {
      final notifications = await _notificationService.load();
      if (!mounted) return;
      setState(() {
        _notifications = notifications
            .where(
              (notification) =>
                  !widget.activeProfile.isKids ||
                  notification.show.isKidsAppropriate,
            )
            .toList(growable: false);
        _notificationsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notificationsLoading = false;
        _notificationsError = 'Content updates are temporarily unavailable.';
      });
    }
  }

  void _refreshLoadedCatalogs() {
    if (!mounted) return;
    setState(() {
      for (var index = 0; index < _catalogs.length; index++) {
        if (_catalogs[index] == null) continue;
        _catalogs[index] = switch (index) {
          0 => _loadCatalog(CatalogKind.home),
          1 => _loadCatalog(CatalogKind.movies),
          2 => _loadCatalog(CatalogKind.tvShows),
          _ => _loadCatalog(CatalogKind.newAndPopular),
        };
      }
    });
  }

  Future<void> _markNotificationsSeen() async {
    final newest = _notifications.firstOrNull?.changedAt;
    if (newest == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      _notificationSeenKey,
      newest.millisecondsSinceEpoch,
    );
    if (mounted) setState(() => _notificationsSeenAt = newest);
  }

  @override
  void dispose() {
    final channel = _notificationChannel;
    if (channel != null) unawaited(widget.supabase.removeChannel(channel));
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    final profileId = widget.activeProfile.id;
    final saved = await _library.loadMyList();
    if (!mounted || profileId != widget.activeProfile.id) return;
    setState(() {
      _saved
        ..clear()
        ..addAll(saved);
    });
  }

  Future<void> _loadWatchHistory() async {
    try {
      final entries = await _watchHistory.load();
      if (!mounted) return;
      setState(() {
        _continueWatching
          ..clear()
          ..addAll(entries.where((entry) => entry.show != null).take(10));
      });
    } catch (_) {
      // Keep the last known list when account history is temporarily unavailable.
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          supabase: widget.supabase,
          userId: widget.supabase.auth.currentUser!.id,
          activeProfile: widget.activeProfile,
          onActiveProfileUpdated: widget.onProfileChanged,
          onActiveProfileDeleted: widget.onProfileDeleted,
          onManageProfiles: () {
            Navigator.pop(context);
            widget.onManageProfiles();
          },
          onSubscriptionChanged: widget.onSubscriptionChanged,
          onWatchHistoryChanged: () => unawaited(_loadWatchHistory()),
          onSignOut: widget.onSignOut,
        ),
      ),
    );
  }

  void _loadCatalogs() {
    _catalogs = [_loadCatalog(CatalogKind.home), null, null, null];
  }

  Future<CatalogData> _loadCatalog(CatalogKind kind) async {
    final catalog = await _catalogService.load(kind);
    if (kind != CatalogKind.newAndPopular) return catalog;
    try {
      final upcoming = await _tmdbService.upcomingRows();
      return CatalogData(
        featured: catalog.featured,
        rows: [...catalog.rows, ...upcoming],
        genres: catalog.genres,
      );
    } catch (_) {
      return catalog;
    }
  }

  Future<CatalogData> _catalogFor(int index) {
    return _catalogs[index] ??= switch (index) {
      0 => _loadCatalog(CatalogKind.home),
      1 => _loadCatalog(CatalogKind.movies),
      2 => _loadCatalog(CatalogKind.tvShows),
      _ => _loadCatalog(CatalogKind.newAndPopular),
    };
  }

  Future<void> _refresh(int index) async {
    setState(() {
      _catalogs[index] = switch (index) {
        0 => _loadCatalog(CatalogKind.home),
        1 => _loadCatalog(CatalogKind.movies),
        2 => _loadCatalog(CatalogKind.tvShows),
        _ => _loadCatalog(CatalogKind.newAndPopular),
      };
    });
    try {
      await _catalogs[index]!;
    } catch (_) {
      // The catalog widget displays the error and keeps pull-to-refresh active.
    }
  }

  void _showDetails(Show show) {
    final history = _continueWatching
        .where((entry) => entry.show == show)
        .firstOrNull;
    showDetailsSheet(
      context,
      show: show,
      activeProfile: widget.activeProfile,
      planName: widget.planName,
      initialPosition: Duration(seconds: history?.lastPlaybackSeconds ?? 0),
      isSaved: _saved.contains(show),
      onToggleSaved: () => setState(() {
        if (!_saved.remove(show)) _saved.add(show);
        unawaited(_library.saveMyList(_saved));
      }),
      onPlaybackEnded: () => unawaited(_loadWatchHistory()),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          service: _catalogService,
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
    unawaited(_markNotificationsSeen());
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
              if (_notificationsLoading)
                const Center(child: CircularProgressIndicator())
              else if (_notificationsError case final message?)
                Text(message, style: const TextStyle(color: AppColors.muted))
              else if (_notifications.isEmpty)
                const Text(
                  'No new content updates.',
                  style: TextStyle(color: AppColors.muted),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      return _NotificationTile(
                        title: notification.show.title,
                        message: notification.show.overview.isEmpty
                            ? 'Now available on StreamFlix.'
                            : notification.show.overview,
                        time: _notificationDate(notification.changedAt),
                        onTap: () {
                          Navigator.pop(context);
                          _showDetails(notification.show);
                        },
                      );
                    },
                  ),
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
            icon: Badge(
              isLabelVisible: _notifications.any(
                (notification) =>
                    _notificationsSeenAt == null ||
                    notification.changedAt.isAfter(_notificationsSeenAt!),
              ),
              child: const Icon(Icons.notifications_none_rounded),
            ),
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
                continueWatching: const [],
                showHero: true,
              )
            else
              const SizedBox.shrink(),
            if (_catalogs[2] != null)
              CatalogScreen(
                catalog: _catalogs[2]!,
                onSelect: _showDetails,
                onRefresh: () => _refresh(2),
                continueWatching: const [],
                showHero: true,
              )
            else
              const SizedBox.shrink(),
            if (_catalogs[3] != null)
              CatalogScreen(
                catalog: _catalogs[3]!,
                onSelect: _showDetails,
                onRefresh: () => _refresh(3),
                continueWatching: const [],
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
    required this.title,
    required this.message,
    required this.time,
    required this.onTap,
  });

  final String title;
  final String message;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: AppColors.violet.withValues(alpha: .18),
      child: const Icon(
        Icons.movie_filter_outlined,
        color: AppColors.violetLight,
      ),
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

String _notificationDate(DateTime value) {
  final local = value.toLocal();
  return '${local.month}/${local.day}/${local.year}';
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
