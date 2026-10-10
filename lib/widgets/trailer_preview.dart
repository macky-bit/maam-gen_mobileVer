import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/show.dart';
import '../services/tmdb_service.dart';
import 'network_art.dart';

class TrailerPreview extends StatefulWidget {
  const TrailerPreview({
    super.key,
    required this.show,
    this.showControls = false,
  });

  final Show show;
  final bool showControls;

  @override
  State<TrailerPreview> createState() => _TrailerPreviewState();
}

class _TrailerPreviewState extends State<TrailerPreview> {
  YoutubePlayerController? _controller;
  StreamSubscription<YoutubePlayerValue>? _subscription;
  var _request = 0;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant TrailerPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.show != widget.show) unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    final previous = _controller;
    _controller = null;
    await _subscription?.cancel();
    _subscription = null;
    if (previous != null) await previous.close();
    if (mounted) setState(() => _failed = false);

    final key = await TmdbService().trailerKey(widget.show);
    if (!mounted || request != _request || key == null) return;
    final controller = YoutubePlayerController.fromVideoId(
      videoId: key,
      autoPlay: true,
      params: YoutubePlayerParams(
        mute: true,
        showControls: widget.showControls,
        showFullscreenButton: widget.showControls,
        showVideoAnnotations: false,
        loop: true,
        strictRelatedVideos: true,
      ),
    );
    _subscription = controller.stream.listen((value) {
      if (value.hasError && mounted && identical(_controller, controller)) {
        setState(() => _failed = true);
      }
    });
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _request++;
    unawaited(_subscription?.cancel());
    final controller = _controller;
    if (controller != null) unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        NetworkArt(url: widget.show.backdropUrl, fit: BoxFit.cover),
        if (controller != null && !_failed)
          Center(
            child: IgnorePointer(
              ignoring: !widget.showControls,
              child: YoutubePlayer(
                controller: controller,
                aspectRatio: 16 / 9,
                backgroundColor: Colors.black,
                autoFullScreen: widget.showControls,
              ),
            ),
          ),
      ],
    );
  }
}
