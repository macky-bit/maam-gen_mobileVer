import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/playback_quality.dart';
import '../models/member_profile.dart';
import '../models/show.dart';
import '../services/community_service.dart';
import '../services/tmdb_service.dart';
import '../services/watch_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/network_art.dart';

enum _WatchPanel { player, episodes, refresher, reactions, community }

class WatchScreen extends StatefulWidget {
  const WatchScreen({
    super.key,
    required this.show,
    required this.activeProfile,
    required this.planName,
    required this.initialPosition,
  });

  final Show show;
  final MemberProfile activeProfile;
  final String planName;
  final Duration initialPosition;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  final _service = TmdbService();
  late final WatchHistoryService _watchHistory;
  late final CommunityService _community;
  final _commentController = TextEditingController();
  List<CommunityComment> _comments = const [];
  Map<String, int> _reactions = emptyReactionCounts();

  late Future<List<Episode>> _episodesFuture;
  List<Episode> _episodes = const [];
  VideoPlayerController? _video;
  int _videoLoad = 0;
  _WatchPanel _panel = _WatchPanel.player;
  bool _muted = false;
  bool _captions = false;
  bool _showRefresherDetails = false;
  bool _controlsVisible = true;
  double _volume = .8;
  int _episodeIndex = 0;
  late int _quality;
  bool _videoLoading = true;
  String? _videoError;
  int? _contentId;
  int? _lastSyncedSecond;
  bool _syncingProgress = false;
  String? _myReaction;
  String? _communityUserId;
  String? _communityError;
  bool _communityLoading = true;
  bool _reactionPending = false;
  bool _commentPending = false;
  String? _commentActionPending;
  late Future<_SoundtrackEntry> _soundtrack;
  bool _soundtrackPrimed = false;

  bool get _isSeries => widget.show.mediaType == 'tv';
  Episode? get _episode => _episodes.isEmpty
      ? null
      : _episodes[_episodeIndex.clamp(0, _episodes.length - 1)];
  List<int> get _allowedQualities => playbackQualitiesForPlan(widget.planName);
  bool get _playing => _video?.value.isPlaying ?? false;
  double get _progress {
    final value = _video?.value;
    if (value == null ||
        !value.isInitialized ||
        value.duration.inMilliseconds == 0) {
      return 0;
    }
    return (value.position.inMilliseconds / value.duration.inMilliseconds)
        .clamp(0, 1);
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    final client = Supabase.instance.client;
    _watchHistory = WatchHistoryService(client);
    _community = CommunityService(client);
    _quality = preferredPlaybackQuality(widget.planName);
    unawaited(
      _loadVideo(_quality, position: widget.initialPosition, autoplay: true),
    );
    unawaited(_resolveContent());
    _episodesFuture = _isSeries
        ? _service.episodes(widget.show.id).then((items) {
            if (mounted) setState(() => _episodes = items);
            return items;
          })
        : Future.value(const []);
    _soundtrack = _loadSoundtrack();
  }

  Future<_SoundtrackEntry> _loadSoundtrack() async {
    try {
      final client = Supabase.instance.client;
      final content = await client
          .from('content')
          .select('content_id')
          .eq('tmdb_id', widget.show.id)
          .maybeSingle();
      if (content == null) throw StateError('Content not found');
      final row = await client
          .from('soundtrack')
          .select()
          .eq('content_id', content['content_id'])
          .limit(1)
          .maybeSingle();
      if (row == null) throw StateError('Soundtrack not found');
      String firstValue(List<String> keys) {
        for (final key in keys) {
          final value = row[key]?.toString().trim() ?? '';
          if (value.isNotEmpty) return value;
        }
        return '';
      }

      return _SoundtrackEntry(
        title: firstValue(['song_title', 'track_title', 'title', 'name']),
        url: firstValue(['external_url', 'youtube_url', 'spotify_url', 'url']),
      );
    } catch (_) {
      return _SoundtrackEntry(title: '${widget.show.title} Main Theme');
    }
  }

  Future<void> _handleSoundtrack() async {
    final track = await _soundtrack;
    if (!mounted) return;
    if (!_soundtrackPrimed) {
      setState(() => _soundtrackPrimed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('${track.title}\nTap the music icon again to open it.'),
        ),
      );
      return;
    }
    setState(() => _soundtrackPrimed = false);
    final uri = Uri.tryParse(track.url ?? '');
    if (uri == null ||
        !uri.hasScheme ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No soundtrack link is configured for this title.'),
          ),
        );
      }
    }
  }

  Future<void> _selectReaction(String reaction) async {
    final contentId = _contentId;
    final userId = _communityUserId;
    if (_reactionPending || contentId == null || userId == null) return;
    final previous = _myReaction;
    final previousCounts = _reactions;
    final next = previous == reaction ? null : reaction;
    final optimistic = optimisticReaction(previousCounts, previous, next);
    setState(() {
      _reactions = optimistic.counts;
      _myReaction = optimistic.myReaction;
      _reactionPending = true;
      _communityError = null;
    });
    try {
      await _community.saveReaction(
        contentId: contentId,
        userId: userId,
        previous: previous,
        next: next,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _reactions = previousCounts;
          _myReaction = previous;
          _communityError = _communityMessage(
            error,
            'Unable to save your reaction.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _reactionPending = false);
    }
  }

  @override
  void dispose() {
    final contentId = _contentId;
    final seconds = _video?.value.position.inSeconds ?? 0;
    if (contentId != null && seconds > 0 && seconds != _lastSyncedSecond) {
      unawaited(_watchHistory.recordProgress(contentId, seconds));
    }
    _videoLoad++;
    _video?.removeListener(_onVideoChanged);
    final video = _video;
    if (video != null) {
      unawaited(video.dispose());
    }
    _commentController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _loadVideo(
    int quality, {
    Duration position = Duration.zero,
    bool autoplay = false,
  }) async {
    final request = ++_videoLoad;
    if (mounted) {
      setState(() {
        _videoLoading = true;
        _videoError = null;
      });
    }
    final next = VideoPlayerController.asset(playbackAssetForQuality(quality));
    try {
      await next.initialize();
      if (!mounted || request != _videoLoad) {
        await next.dispose();
        return;
      }
      await next.setVolume(_muted ? 0 : _volume);
      if (position > Duration.zero) {
        await next.seekTo(
          position < next.value.duration ? position : Duration.zero,
        );
      }
      final previous = _video;
      previous?.removeListener(_onVideoChanged);
      _video = next..addListener(_onVideoChanged);
      _quality = quality;
      await previous?.dispose();
      if (autoplay) await next.play();
      if (mounted) setState(() => _videoLoading = false);
    } catch (_) {
      await next.dispose();
      if (mounted && request == _videoLoad) {
        setState(() {
          _videoLoading = false;
          _videoError = '${quality}p studio demo could not be loaded.';
        });
      }
    }
  }

  void _onVideoChanged() {
    final value = _video?.value;
    if (!mounted || value == null) return;
    final error = value.hasError ? value.errorDescription : null;
    if (value.isPlaying && value.position.inSeconds > 0) {
      unawaited(_syncProgress(value.position.inSeconds));
    }
    setState(() => _videoError = error);
  }

  Future<void> _resolveContent() async {
    try {
      final contentId = await _watchHistory.resolveContentId(widget.show);
      if (!mounted) return;
      setState(() => _contentId = contentId);
      if (contentId == null) {
        setState(() {
          _communityLoading = false;
          _communityError = 'Community is unavailable for this title.';
        });
        return;
      }
      await _loadCommunity(contentId);
    } catch (error) {
      if (mounted) {
        setState(() {
          _communityLoading = false;
          _communityError = _communityMessage(
            error,
            'Community could not be loaded.',
          );
        });
      }
    }
  }

  Future<void> _loadCommunity(int contentId) async {
    final snapshot = await _community.load(contentId);
    if (!mounted || _contentId != contentId) return;
    setState(() {
      _reactions = snapshot.counts;
      _myReaction = snapshot.myReaction;
      _comments = snapshot.comments;
      _communityUserId = snapshot.userId;
      _communityLoading = false;
      _communityError = null;
    });
  }

  Future<void> _syncProgress(int seconds) async {
    final contentId = _contentId;
    if (contentId == null ||
        _syncingProgress ||
        (_lastSyncedSecond != null &&
            (seconds - _lastSyncedSecond!).abs() < 15)) {
      return;
    }
    _syncingProgress = true;
    try {
      await _watchHistory.recordProgress(contentId, seconds);
      _lastSyncedSecond = seconds;
    } catch (_) {
      // Retry from a later player update instead of interrupting playback.
    } finally {
      _syncingProgress = false;
    }
  }

  Future<void> _togglePlaying() async {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    if (video.value.isPlaying) {
      await video.pause();
    } else {
      if (video.value.position >= video.value.duration) {
        await video.seekTo(Duration.zero);
      }
      await video.play();
    }
  }

  Future<void> _seek(double fraction) async {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    await video.seekTo(video.value.duration * fraction);
  }

  Future<void> _seekBy(int seconds) async {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    final target = video.value.position + Duration(seconds: seconds);
    await video.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > video.value.duration
          ? video.value.duration
          : target,
    );
  }

  Future<void> _changeQuality(int quality) async {
    if (!_allowedQualities.contains(quality) || quality == _quality) return;
    final value = _video?.value;
    await _loadVideo(
      quality,
      position: value?.position ?? Duration.zero,
      autoplay: value?.isPlaying ?? false,
    );
  }

  Future<void> _toggleMuted() async {
    setState(() => _muted = !_muted);
    await _video?.setVolume(_muted ? 0 : _volume);
  }

  Future<void> _setVolume(double value) async {
    setState(() {
      _volume = value;
      _muted = false;
    });
    await _video?.setVolume(value);
  }

  void _nextEpisode() {
    if (!_isSeries || _episodes.isEmpty) return;
    setState(() {
      _episodeIndex = (_episodeIndex + 1).clamp(0, _episodes.length - 1);
      _panel = _WatchPanel.player;
    });
    final video = _video;
    if (video != null) {
      unawaited(video.seekTo(Duration.zero));
      unawaited(video.play());
    }
  }

  void _togglePanel(_WatchPanel panel) {
    setState(() {
      _panel = _panel == panel ? _WatchPanel.player : panel;
    });
  }

  Future<void> _postComment() async {
    final contentId = _contentId;
    final userId = _communityUserId;
    if (_commentPending || contentId == null || userId == null) return;
    setState(() {
      _commentPending = true;
      _communityError = null;
    });
    try {
      final created = await _community.postComment(
        contentId: contentId,
        userId: userId,
        profile: widget.activeProfile,
        text: _commentController.text,
      );
      if (!mounted) return;
      setState(() {
        _comments = [created, ..._comments];
        _commentController.clear();
      });
      FocusScope.of(context).unfocus();
    } catch (error) {
      if (mounted) {
        setState(
          () => _communityError = _communityMessage(
            error,
            'Unable to post your comment.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _commentPending = false);
    }
  }

  Future<void> _editComment(CommunityComment comment) async {
    final controller = TextEditingController(text: comment.text);
    final updatedText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit comment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: commentMaxLength,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updatedText == null || _communityUserId == null) return;
    setState(() => _commentActionPending = comment.id);
    try {
      final text = await _community.updateComment(
        commentId: comment.id,
        userId: _communityUserId!,
        text: updatedText,
      );
      if (mounted) {
        setState(() {
          _comments = _comments
              .map((item) => item.id == comment.id ? item.copyWith(text: text) : item)
              .toList(growable: false);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _communityError = _communityMessage(
            error,
            'Unable to update your comment.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _commentActionPending = null);
    }
  }

  Future<void> _deleteComment(CommunityComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your comment?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || _communityUserId == null) return;
    setState(() => _commentActionPending = comment.id);
    try {
      await _community.deleteComment(
        commentId: comment.id,
        userId: _communityUserId!,
      );
      if (mounted) {
        setState(() {
          _comments = _comments
              .where((item) => item.id != comment.id)
              .toList(growable: false);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _communityError = _communityMessage(
            error,
            'Unable to delete your comment.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _commentActionPending = null);
    }
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
            if (_video?.value.isInitialized ?? false)
              Center(
                child: AspectRatio(
                  aspectRatio: _video!.value.aspectRatio,
                  child: VideoPlayer(_video!),
                ),
              ),
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
            if (_videoLoading)
              const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
            if (_videoError != null)
              Positioned(
                top: 84,
                left: 24,
                right: 24,
                child: Text(
                  _videoError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            if (_panel != _WatchPanel.player &&
                _panel != _WatchPanel.community &&
                _panel != _WatchPanel.reactions)
              Center(
                child: Container(
                  width: _panel == _WatchPanel.reactions
                      ? MediaQuery.sizeOf(context).width * .58
                      : MediaQuery.sizeOf(context).width * .62,
                  constraints: BoxConstraints(
                    maxWidth: _panel == _WatchPanel.reactions ? 560 : 720,
                    maxHeight: _panel == _WatchPanel.reactions ? 150 : 300,
                  ),
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
                      _WatchPanel.refresher => _RefresherPanel(
                        key: const ValueKey('refresher'),
                        isSeries: _isSeries,
                        revealed: _showRefresherDetails,
                        onToggle: () => setState(
                          () => _showRefresherDetails = !_showRefresherDetails,
                        ),
                      ),
                      _WatchPanel.reactions => const SizedBox.shrink(),
                      _WatchPanel.community => const SizedBox.shrink(),
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
                          quality: _quality,
                          commentCount: _comments.length,
                          onBack: () => Navigator.pop(context),
                          reaction: _myReaction,
                          onReaction: () => unawaited(
                            _selectReaction('\u{1F44D}'),
                          ),
                          onReactionLongPress: () =>
                              _togglePanel(_WatchPanel.reactions),
                          onMusic: _handleSoundtrack,
                          onCommunity: () =>
                              _togglePanel(_WatchPanel.community),
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
                          planName: widget.planName,
                          allowedQualities: _allowedQualities,
                          position: _video?.value.position ?? Duration.zero,
                          duration: _video?.value.duration ?? Duration.zero,
                          showNext: _isSeries,
                          onPlayPause: _togglePlaying,
                          onSeek: (value) => unawaited(_seek(value)),
                          onReplay: () => unawaited(_seekBy(-10)),
                          onForward: () => unawaited(_seekBy(10)),
                          onNext: _nextEpisode,
                          onMute: () => unawaited(_toggleMuted()),
                          onVolume: (value) => unawaited(_setVolume(value)),
                          onCaptions: () =>
                              setState(() => _captions = !_captions),
                          onQuality: (value) =>
                              unawaited(_changeQuality(value)),
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
            if (_panel == _WatchPanel.reactions)
              _ReactionDrawer(
                reactions: _reactions,
                myReaction: _myReaction,
                onReact: (reaction) => unawaited(
                  _selectReaction(reaction),
                ),
              ),
            if (_panel == _WatchPanel.community)
              _CommunityDrawer(
                comments: _comments,
                controller: _commentController,
                profile: widget.activeProfile,
                userId: _communityUserId,
                loading: _communityLoading,
                error: _communityError,
                posting: _commentPending,
                actionPending: _commentActionPending,
                onPost: () => unawaited(_postComment()),
                onEdit: (comment) => unawaited(_editComment(comment)),
                onDelete: (comment) => unawaited(_deleteComment(comment)),
                onClose: () => _togglePanel(_WatchPanel.community),
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
    required this.quality,
    required this.commentCount,
    required this.reaction,
    required this.onBack,
    required this.onReaction,
    required this.onReactionLongPress,
    required this.onMusic,
    required this.onCommunity,
  });
  final String title;
  final String year;
  final bool isSeries;
  final Episode? episode;
  final int quality;
  final int commentCount;
  final String? reaction;
  final VoidCallback onBack;
  final VoidCallback onReaction;
  final VoidCallback onReactionLongPress;
  final VoidCallback onMusic;
  final VoidCallback onCommunity;

  @override
  Widget build(BuildContext context) => Container(
    height: 76,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: Colors.black.withValues(alpha: .30),
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
                  'Studio demo clip',
                  '${quality}p',
                ].join('   '),
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
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
        Tooltip(
          message: 'Tap to like, hold for reactions',
          child: InkResponse(
            onTap: onReaction,
            onLongPress: onReactionLongPress,
            radius: 24,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: reaction == null
                  ? const Icon(Icons.thumb_up_outlined)
                  : Text(reaction!, style: const TextStyle(fontSize: 22)),
            ),
          ),
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

class _SoundtrackEntry {
  const _SoundtrackEntry({required this.title, this.url});
  final String title;
  final String? url;
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

class _ReactionDrawer extends StatelessWidget {
  const _ReactionDrawer({
    required this.reactions,
    required this.myReaction,
    required this.onReact,
  });

  final Map<String, int> reactions;
  final String? myReaction;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 72, right: 12),
        child: _ReactionsPanel(
          reactions: reactions,
          myReaction: myReaction,
          onReact: onReact,
        ),
      ),
    ),
  );
}

class _ReactionsPanel extends StatelessWidget {
  const _ReactionsPanel({
    required this.reactions,
    required this.myReaction,
    required this.onReact,
  });

  final Map<String, int> reactions;
  final String? myReaction;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) => Container(
    width: 62,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.inkSoft,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: AppColors.violet.withValues(alpha: .45)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: reactions.entries.map((entry) {
        final selected = myReaction == entry.key;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: selected
                    ? AppColors.violet.withValues(alpha: .38)
                    : Colors.white10,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => onReact(entry.key),
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Center(
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontSize: 23),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '${entry.value}',
                style: TextStyle(
                  color: selected ? AppColors.violetLight : AppColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ),
  );
}

class _CommunityDrawer extends StatelessWidget {
  const _CommunityDrawer({
    required this.comments,
    required this.controller,
    required this.profile,
    required this.userId,
    required this.loading,
    required this.error,
    required this.posting,
    required this.actionPending,
    required this.onPost,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });
  final List<CommunityComment> comments;
  final TextEditingController controller;
  final MemberProfile profile;
  final String? userId;
  final bool loading;
  final String? error;
  final bool posting;
  final String? actionPending;
  final VoidCallback onPost;
  final ValueChanged<CommunityComment> onEdit;
  final ValueChanged<CommunityComment> onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth < 720
          ? constraints.maxWidth * .68
          : (constraints.maxWidth * .44).clamp(380.0, 540.0);
      return SafeArea(
        minimum: const EdgeInsets.all(10),
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: SizedBox(
              width: width,
              height: double.infinity,
              child: _CommunityPanel(
                comments: comments,
                controller: controller,
                profile: profile,
                userId: userId,
                loading: loading,
                error: error,
                posting: posting,
                actionPending: actionPending,
                onPost: onPost,
                onEdit: onEdit,
                onDelete: onDelete,
                onClose: onClose,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CommunityPanel extends StatefulWidget {
  const _CommunityPanel({
    required this.comments,
    required this.controller,
    required this.profile,
    required this.userId,
    required this.loading,
    required this.error,
    required this.posting,
    required this.actionPending,
    required this.onPost,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });
  final List<CommunityComment> comments;
  final TextEditingController controller;
  final MemberProfile profile;
  final String? userId;
  final bool loading;
  final String? error;
  final bool posting;
  final String? actionPending;
  final VoidCallback onPost;
  final ValueChanged<CommunityComment> onEdit;
  final ValueChanged<CommunityComment> onDelete;
  final VoidCallback onClose;

  @override
  State<_CommunityPanel> createState() => _CommunityPanelState();
}

class _CommunityPanelState extends State<_CommunityPanel> {
  @override
  Widget build(BuildContext context) {
    final visible = widget.comments;
    return Material(
      color: AppColors.inkSoft.withValues(alpha: .97),
      elevation: 22,
      shadowColor: Colors.black87,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.violet.withValues(alpha: .5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 2),
            child: Row(
              children: [
                Text(
                  'Comments',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: 'Close comments',
                  icon: const Icon(Icons.close_rounded, size: 28),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: AppColors.violetLight.withValues(alpha: .18),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text(
                      'No comments in this view yet.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Colors.white10),
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final id = '${item.$1}-${item.$3}';
                      final liked = _liked.contains(id);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.violetDeep,
                            child: Text(item.$2),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.$1,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      item.$4,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (item.$6)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 7),
                                        child: Icon(
                                          Icons.visibility_off_outlined,
                                          color: AppColors.gold,
                                          size: 15,
                                        ),
                                      ),
                                    const Icon(
                                      Icons.more_horiz_rounded,
                                      color: AppColors.muted,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.$3,
                                  style: const TextStyle(height: 1.28),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => setState(
                                        () => liked
                                            ? _liked.remove(id)
                                            : _liked.add(id),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 18,
                                      color: liked
                                          ? AppColors.gold
                                          : AppColors.muted,
                                      icon: Icon(
                                        liked
                                            ? Icons.thumb_up_rounded
                                            : Icons.thumb_up_outlined,
                                      ),
                                    ),
                                    Text(
                                      '${item.$5 + (liked ? 1 : 0)}',
                                      style: TextStyle(
                                        color: liked
                                            ? AppColors.gold
                                            : AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 9, 12, 11),
            decoration: BoxDecoration(
              color: AppColors.ink,
              border: Border(
                top: BorderSide(color: AppColors.violet.withValues(alpha: .24)),
              ),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.violetDeep,
                  child: Text('M'),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => widget.onPost(),
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: widget.onPost,
                  tooltip: 'Post comment',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.ink,
                  ),
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.playing,
    required this.progress,
    required this.volume,
    required this.muted,
    required this.captions,
    required this.quality,
    required this.planName,
    required this.allowedQualities,
    required this.position,
    required this.duration,
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
  final int quality;
  final String planName;
  final List<int> allowedQualities;
  final Duration position;
  final Duration duration;
  final bool showNext;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;
  final VoidCallback onReplay;
  final VoidCallback onForward;
  final VoidCallback onNext;
  final VoidCallback onMute;
  final ValueChanged<double> onVolume;
  final VoidCallback onCaptions;
  final ValueChanged<int> onQuality;
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
              '${_timeLabel(position)} / ${_timeLabel(duration)}',
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
            PopupMenuButton<int>(
              initialValue: quality,
              onSelected: onQuality,
              tooltip: 'Playback settings and resolution',
              itemBuilder: (_) => playbackQualities
                  .map(
                    (value) => PopupMenuItem(
                      value: value,
                      enabled: allowedQualities.contains(value),
                      child: Text(
                        allowedQualities.contains(value)
                            ? '${value}p'
                            : '${value}p · ${requiredPlanForQuality(value)} plan',
                      ),
                    ),
                  )
                  .toList(),
              icon: Semantics(
                label: '$planName plan, ${quality}p studio demo',
                child: const Icon(Icons.settings_outlined),
              ),
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

  String _timeLabel(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return hours == 0
        ? '$minutes:${seconds.toString().padLeft(2, '0')}'
        : '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
