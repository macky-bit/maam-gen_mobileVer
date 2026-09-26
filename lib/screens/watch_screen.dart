import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/show.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../widgets/network_art.dart';

enum _WatchPanel {
  player,
  episodes,
  soundtrack,
  refresher,
  reactions,
  community,
}

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.show});

  final Show show;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  final _service = TmdbService();
  final _commentController = TextEditingController();
  final List<String> _comments = [];
  final Map<String, int> _reactions = {
    '\u{1F44D}': 25,
    '\u2764\uFE0F': 0,
    '\u{1F970}': 0,
    '\u{1F602}': 0,
    '\u{1F62E}': 0,
    '\u{1F622}': 0,
    '\u{1F621}': 0,
  };

  late Future<List<Episode>> _episodesFuture;
  List<Episode> _episodes = const [];
  Timer? _timer;
  _WatchPanel _panel = _WatchPanel.player;
  bool _playing = true;
  bool _muted = false;
  bool _captions = false;
  bool _showRefresherDetails = false;
  bool _controlsVisible = true;
  double _progress = .08;
  double _volume = .8;
  int _episodeIndex = 0;
  int _trackIndex = 0;
  String _quality = '1080p';
  String? _myReaction;

  bool get _isSeries => widget.show.mediaType == 'tv';
  Episode? get _episode => _episodes.isEmpty
      ? null
      : _episodes[_episodeIndex.clamp(0, _episodes.length - 1)];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _progress = (_progress + .0015).clamp(0, 1));
    });
    _episodesFuture = _isSeries
        ? _service.episodes(widget.show.id).then((items) {
            if (mounted) setState(() => _episodes = items);
            return items;
          })
        : Future.value(const []);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _commentController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _togglePlaying() {
    setState(() => _playing = !_playing);
    _timer?.cancel();
    if (_playing) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _progress = (_progress + .0015).clamp(0, 1));
      });
    }
  }

  void _nextEpisode() {
    if (!_isSeries || _episodes.isEmpty) return;
    setState(() {
      _episodeIndex = (_episodeIndex + 1).clamp(0, _episodes.length - 1);
      _progress = 0;
      _panel = _WatchPanel.player;
    });
  }

  void _togglePanel(_WatchPanel panel) {
    setState(() {
      _panel = _panel == panel ? _WatchPanel.player : panel;
    });
  }

  void _postComment() {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) return;
    setState(() {
      _comments.insert(0, comment);
      _commentController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final episode = _episode;
    final imageUrl = episode?.imageUrl.isNotEmpty == true
        ? episode!.imageUrl
        : widget.show.backdropUrl;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkArt(url: imageUrl, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99000000),
                    Color(0x08000000),
                    Color(0xD9000000),
                  ],
                  stops: [0, .5, 1],
                ),
              ),
            ),
            if (_panel != _WatchPanel.player)
              Center(
                child: Container(
                  width: MediaQuery.sizeOf(context).width * .62,
                  constraints: const BoxConstraints(maxHeight: 300),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xE6120E19),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: switch (_panel) {
                      _WatchPanel.player => _PlayerPanel(
                        key: const ValueKey('player'),
                        title: widget.show.title,
                        episode: episode,
                        playing: _playing,
                        onToggle: _togglePlaying,
                      ),
                      _WatchPanel.episodes => _EpisodesPanel(
                        key: const ValueKey('episodes'),
                        future: _episodesFuture,
                        episodes: _episodes,
                        selectedIndex: _episodeIndex,
                        onPrevious: _episodeIndex > 0
                            ? () => setState(() => _episodeIndex--)
                            : null,
                        onNext: _episodeIndex < _episodes.length - 1
                            ? () => setState(() => _episodeIndex++)
                            : null,
                        onPlay: () =>
                            setState(() => _panel = _WatchPanel.player),
                      ),
                      _WatchPanel.soundtrack => _SoundtrackPanel(
                        key: const ValueKey('soundtrack'),
                        title: widget.show.title,
                        trackIndex: _trackIndex,
                        onPrevious: () => setState(
                          () => _trackIndex = (_trackIndex - 1).clamp(0, 2),
                        ),
                        onNext: () => setState(
                          () => _trackIndex = (_trackIndex + 1).clamp(0, 2),
                        ),
                      ),
                      _WatchPanel.refresher => _RefresherPanel(
                        key: const ValueKey('refresher'),
                        isSeries: _isSeries,
                        revealed: _showRefresherDetails,
                        onToggle: () => setState(
                          () => _showRefresherDetails = !_showRefresherDetails,
                        ),
                      ),
                      _WatchPanel.reactions => _ReactionsPanel(
                        key: const ValueKey('reactions'),
                        reactions: _reactions,
                        myReaction: _myReaction,
                        onReact: (reaction) {
                          setState(() {
                            if (_myReaction != null) {
                              _reactions[_myReaction!] =
                                  (_reactions[_myReaction!]! - 1).clamp(0, 999);
                            }
                            if (_myReaction == reaction) {
                              _myReaction = null;
                            } else {
                              _myReaction = reaction;
                              _reactions[reaction] = _reactions[reaction]! + 1;
                            }
                          });
                        },
                      ),
                      _WatchPanel.community => _CommunityPanel(
                        key: const ValueKey('community'),
                        comments: _comments,
                        controller: _commentController,
                        onPost: _postComment,
                      ),
                    },
                  ),
                ),
              ),
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: SafeArea(
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: _TopBar(
                          title: widget.show.title,
                          year: widget.show.year,
                          isSeries: _isSeries,
                          episode: episode,
                          commentCount: _comments.length,
                          onBack: () => Navigator.pop(context),
                          onReaction: () => _togglePanel(_WatchPanel.reactions),
                          onMusic: () => _togglePanel(_WatchPanel.soundtrack),
                          onCommunity: () =>
                              _togglePanel(_WatchPanel.community),
                          onPanelSelected: _togglePanel,
                          isPlayingPanel: _panel == _WatchPanel.player,
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: _PlaybackControls(
                          playing: _playing,
                          progress: _progress,
                          volume: _muted ? 0 : _volume,
                          muted: _muted,
                          captions: _captions,
                          quality: _quality,
                          showNext: _isSeries,
                          onPlayPause: _togglePlaying,
                          onSeek: (value) => setState(() => _progress = value),
                          onReplay: () => setState(
                            () => _progress = (_progress - .03).clamp(0, 1),
                          ),
                          onForward: () => setState(
                            () => _progress = (_progress + .03).clamp(0, 1),
                          ),
                          onNext: _nextEpisode,
                          onMute: () => setState(() => _muted = !_muted),
                          onVolume: (value) => setState(() {
                            _volume = value;
                            _muted = false;
                          }),
                          onCaptions: () =>
                              setState(() => _captions = !_captions),
                          onQuality: (value) =>
                              setState(() => _quality = value),
                          onRefresher: () =>
                              _togglePanel(_WatchPanel.refresher),
                          onFullscreen: () =>
                              setState(() => _controlsVisible = false),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.year,
    required this.isSeries,
    required this.episode,
    required this.commentCount,
    required this.onBack,
    required this.onReaction,
    required this.onMusic,
    required this.onCommunity,
    required this.onPanelSelected,
    required this.isPlayingPanel,
  });
  final String title;
  final String year;
  final bool isSeries;
  final Episode? episode;
  final int commentCount;
  final VoidCallback onBack;
  final VoidCallback onReaction;
  final VoidCallback onMusic;
  final VoidCallback onCommunity;
  final ValueChanged<_WatchPanel> onPanelSelected;
  final bool isPlayingPanel;

  @override
  Widget build(BuildContext context) => Container(
    height: 76,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: const Color(0xB8000000),
    child: Row(
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                [
                  if (year.isNotEmpty) year,
                  if (episode != null) 'Episode ${episode!.number}',
                  isSeries ? 'Series' : 'Movie',
                  'HD',
                ].join('   '),
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onReaction,
          tooltip: 'Reactions',
          icon: const Icon(Icons.sentiment_satisfied_alt_rounded),
        ),
        IconButton(
          onPressed: onMusic,
          tooltip: 'Soundtrack',
          icon: const Icon(Icons.music_note_rounded),
        ),
        Badge(
          isLabelVisible: commentCount > 0,
          label: Text('$commentCount'),
          child: IconButton(
            onPressed: onCommunity,
            tooltip: 'Comments',
            icon: const Icon(Icons.chat_outlined),
          ),
        ),
        PopupMenuButton<_WatchPanel>(
          tooltip: 'More options',
          onSelected: onPanelSelected,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _WatchPanel.player,
              child: Text(isPlayingPanel ? 'Watching now' : 'Return to movie'),
            ),
            if (isSeries)
              const PopupMenuItem(
                value: _WatchPanel.episodes,
                child: Text('Episodes'),
              ),
            const PopupMenuItem(
              value: _WatchPanel.refresher,
              child: Text('Story recap'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    super.key,
    required this.title,
    required this.episode,
    required this.playing,
    required this.onToggle,
  });
  final String title;
  final Episode? episode;
  final bool playing;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Spacer(),
      IconButton.filled(
        onPressed: onToggle,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          minimumSize: const Size(70, 70),
        ),
        icon: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 42,
        ),
      ),
      const Spacer(),
      Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (episode != null)
              Text(
                'Episode ${episode!.number} • ${episode!.title}',
                style: const TextStyle(color: AppColors.muted),
              ),
          ],
        ),
      ),
    ],
  );
}

class _EpisodesPanel extends StatelessWidget {
  const _EpisodesPanel({
    super.key,
    required this.future,
    required this.episodes,
    required this.selectedIndex,
    required this.onPrevious,
    required this.onNext,
    required this.onPlay,
  });
  final Future<List<Episode>> future;
  final List<Episode> episodes;
  final int selectedIndex;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Episode>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        );
      }
      if (episodes.isEmpty) {
        return const Center(child: Text('Episode information is unavailable.'));
      }
      final episode = episodes[selectedIndex];
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'SEASON 1 • EPISODE ${episode.number}',
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            episode.title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '${episode.runtimeMinutes} min',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          Text(
            episode.overview.isEmpty
                ? 'Episode details are not available.'
                : episode.overview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.outlined(
                onPressed: onPrevious,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play episode'),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(
                onPressed: onNext,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _SoundtrackPanel extends StatelessWidget {
  const _SoundtrackPanel({
    super.key,
    required this.title,
    required this.trackIndex,
    required this.onPrevious,
    required this.onNext,
  });
  final String title;
  final int trackIndex;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  static const tracks = ['Main Theme', 'Featured Track', 'Closing Theme'];

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 94,
        height: 94,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.violet, AppColors.orange],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.album_rounded, size: 52),
      ),
      const SizedBox(height: 14),
      const Text(
        'SOUNDTRACK',
        style: TextStyle(
          color: AppColors.gold,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
        ),
      ),
      const SizedBox(height: 5),
      Text(tracks[trackIndex], style: Theme.of(context).textTheme.titleLarge),
      Text(title, style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.outlined(
            onPressed: onPrevious,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          const SizedBox(width: 18),
          const Icon(Icons.play_circle_fill_rounded, size: 52),
          const SizedBox(width: 18),
          IconButton.outlined(
            onPressed: onNext,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
    ],
  );
}

class _RefresherPanel extends StatelessWidget {
  const _RefresherPanel({
    super.key,
    required this.isSeries,
    required this.revealed,
    required this.onToggle,
  });
  final bool isSeries;
  final bool revealed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.refresh_rounded, size: 54, color: AppColors.violetLight),
      const SizedBox(height: 8),
      Text(
        '${isSeries ? 'Episode' : 'Movie'} Refresher',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 10),
      Text(
        revealed
            ? 'Key events, important characters, and story details are summarized here without requiring a scroll.'
            : 'Get a quick reminder before you continue watching. Details stay hidden until you choose to reveal them.',
        maxLines: 4,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: onToggle,
        icon: Icon(
          revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
        label: Text(revealed ? 'Hide details' : 'Reveal recap'),
      ),
    ],
  );
}

class _ReactionsPanel extends StatelessWidget {
  const _ReactionsPanel({
    super.key,
    required this.reactions,
    required this.myReaction,
    required this.onReact,
  });

  final Map<String, int> reactions;
  final String? myReaction;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: reactions.entries.map((entry) {
      final selected = myReaction == entry.key;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: selected ? AppColors.violet : Colors.white12,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => onReact(entry.key),
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: Center(
                    child: Text(
                      entry.key,
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${entry.value}',
              style: TextStyle(
                color: selected ? AppColors.violetLight : AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }).toList(),
  );
}

class _CommunityPanel extends StatelessWidget {
  const _CommunityPanel({
    super.key,
    required this.comments,
    required this.controller,
    required this.onPost,
  });
  final List<String> comments;
  final TextEditingController controller;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        'Comments',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 1,
              decoration: const InputDecoration(
                hintText: 'Write a comment…',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: onPost,
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (comments.isEmpty)
        const Text(
          'No comments yet. Be the first to share your thoughts.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        )
      else
        ...comments
            .take(2)
            .map(
              (comment) => ListTile(
                dense: true,
                leading: const CircleAvatar(radius: 14, child: Text('M')),
                title: const Text(
                  'You',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  comment,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
    ],
  );
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.playing,
    required this.progress,
    required this.volume,
    required this.muted,
    required this.captions,
    required this.quality,
    required this.showNext,
    required this.onPlayPause,
    required this.onSeek,
    required this.onReplay,
    required this.onForward,
    required this.onNext,
    required this.onMute,
    required this.onVolume,
    required this.onCaptions,
    required this.onQuality,
    required this.onRefresher,
    required this.onFullscreen,
  });
  final bool playing;
  final double progress;
  final double volume;
  final bool muted;
  final bool captions;
  final String quality;
  final bool showNext;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;
  final VoidCallback onReplay;
  final VoidCallback onForward;
  final VoidCallback onNext;
  final VoidCallback onMute;
  final ValueChanged<double> onVolume;
  final VoidCallback onCaptions;
  final ValueChanged<String> onQuality;
  final VoidCallback onRefresher;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xB8000000),
    padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Slider(
                value: progress,
                onChanged: onSeek,
                activeColor: const Color(0xFFFF1744),
                inactiveColor: Colors.white38,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${_timeLabel(progress)} / 2:18:24',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              onPressed: onPlayPause,
              tooltip: playing ? 'Pause' : 'Play',
              icon: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 34,
              ),
            ),
            IconButton(
              onPressed: onReplay,
              tooltip: 'Back 10 seconds',
              icon: const Icon(Icons.replay_10_rounded),
            ),
            IconButton(
              onPressed: onForward,
              tooltip: 'Forward 10 seconds',
              icon: const Icon(Icons.forward_10_rounded),
            ),
            IconButton(
              onPressed: onMute,
              tooltip: muted ? 'Unmute' : 'Mute',
              icon: Icon(
                muted || volume == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
              ),
            ),
            SizedBox(
              width: 150,
              child: Slider(
                value: volume,
                onChanged: onVolume,
                activeColor: Colors.white,
                inactiveColor: Colors.white30,
              ),
            ),
            if (showNext)
              IconButton(
                onPressed: onNext,
                tooltip: 'Next episode',
                icon: const Icon(Icons.skip_next_rounded),
              ),
            const Spacer(),
            IconButton(
              onPressed: onRefresher,
              tooltip: 'Story recap',
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              onPressed: onCaptions,
              tooltip: 'Captions',
              color: captions ? AppColors.gold : null,
              icon: const Icon(Icons.closed_caption_rounded),
            ),
            PopupMenuButton<String>(
              initialValue: quality,
              onSelected: onQuality,
              tooltip: 'Playback settings and resolution',
              itemBuilder: (_) => ['Auto', '720p', '1080p', '4K']
                  .map(
                    (value) => PopupMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              icon: const Icon(Icons.settings_outlined),
            ),
            IconButton(
              onPressed: onFullscreen,
              tooltip: 'Hide controls',
              icon: const Icon(Icons.fullscreen_rounded),
            ),
          ],
        ),
      ],
    ),
  );

  String _timeLabel(double value) {
    final totalSeconds = (value * (2 * 3600 + 18 * 60 + 24)).round();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return hours == 0
        ? '$minutes:${seconds.toString().padLeft(2, '0')}'
        : '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
