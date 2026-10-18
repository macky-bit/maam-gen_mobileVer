import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';

class OpeningVideoScreen extends StatefulWidget {
  const OpeningVideoScreen({
    super.key,
    required this.supabase,
    required this.onComplete,
  });

  final SupabaseClient supabase;
  final VoidCallback onComplete;

  @override
  State<OpeningVideoScreen> createState() => _OpeningVideoScreenState();
}

class _OpeningVideoScreenState extends State<OpeningVideoScreen> {
  static const _bucket = 'streamflix-media';
  static const _path = 'opening/streamflix-opening.mp4';

  VideoPlayerController? _video;
  bool _loading = true;
  bool _muted = false;
  bool _finished = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideoChanged);
    unawaited(_video?.dispose());
    super.dispose();
  }

  Future<void> _load({bool muted = false}) async {
    final previous = _video;
    previous?.removeListener(_onVideoChanged);
    _video = null;
    await previous?.dispose();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _muted = muted;
    });

    final url = widget.supabase.storage.from(_bucket).getPublicUrl(_path);
    final video = VideoPlayerController.networkUrl(Uri.parse(url));
    _video = video;
    try {
      await video.initialize();
      if (!mounted || _video != video) {
        await video.dispose();
        return;
      }
      video.addListener(_onVideoChanged);
      await video.setVolume(_muted ? 0 : 1);
      await video.play();
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (_video == video) {
        _video = null;
        video.removeListener(_onVideoChanged);
        await video.dispose();
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'The opening video could not start.';
        });
      }
    }
  }

  void _onVideoChanged() {
    final value = _video?.value;
    if (!mounted || value == null) return;
    if (value.hasError && _error == null) {
      setState(() => _error = 'The opening video could not start.');
      return;
    }
    if (value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration) {
      _complete();
    }
  }

  Future<void> _toggleMute() async {
    final video = _video;
    if (video == null) return;
    setState(() => _muted = !_muted);
    await video.setVolume(_muted ? 0 : 1);
  }

  void _complete() {
    if (_finished) return;
    _finished = true;
    unawaited(_video?.pause());
    // VideoPlayerController notifies its inherited VideoPlayer widget when
    // playback reaches the end. Replacing this screen from inside that
    // notification deactivates the notifier while it still has dependants,
    // which trips Flutter's InheritedElement lifecycle assertions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onComplete();
    });
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return Scaffold(
      key: const ValueKey('opening-video'),
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (video?.value.isInitialized == true)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: video!.value.size.width,
                height: video.value.size.height,
                child: VideoPlayer(video),
              ),
            )
          else
            const Center(
              child: Text(
                'SF',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
            ),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 112),
                child: CircularProgressIndicator(),
              ),
            ),
          if (_error != null)
            Center(
              child: Container(
                margin: const EdgeInsets.all(28),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.inkSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed: () => unawaited(_load(muted: true)),
                          child: const Text('Retry video'),
                        ),
                        TextButton(
                          onPressed: _complete,
                          child: const Text('Continue'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton.filledTonal(
                      tooltip: _muted ? 'Turn sound on' : 'Mute',
                      onPressed: video?.value.isInitialized == true
                          ? _toggleMute
                          : null,
                      icon: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                      ),
                    ),
                    TextButton(onPressed: _complete, child: const Text('Skip')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
