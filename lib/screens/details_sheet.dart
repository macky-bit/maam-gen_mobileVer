import 'package:flutter/material.dart';

import '../models/show.dart';
import '../models/member_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/trailer_preview.dart';
import 'watch_screen.dart';

Future<void> showDetailsSheet(
  BuildContext context, {
  required Show show,
  required MemberProfile activeProfile,
  required String planName,
  required Duration initialPosition,
  required bool isSaved,
  required VoidCallback onToggleSaved,
  required VoidCallback onPlaybackEnded,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.inkSoft,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _DetailsSheet(
      show: show,
      activeProfile: activeProfile,
      planName: planName,
      initialPosition: initialPosition,
      isSaved: isSaved,
      onToggleSaved: onToggleSaved,
      onPlaybackEnded: onPlaybackEnded,
    ),
  );
}

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({
    required this.show,
    required this.activeProfile,
    required this.planName,
    required this.initialPosition,
    required this.isSaved,
    required this.onToggleSaved,
    required this.onPlaybackEnded,
  });
  final Show show;
  final MemberProfile activeProfile;
  final String planName;
  final Duration initialPosition;
  final bool isSaved;
  final VoidCallback onToggleSaved;
  final VoidCallback onPlaybackEnded;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  late bool _saved = widget.isSaved;

  @override
  Widget build(BuildContext context) {
    final show = widget.show;
    return DraggableScrollableSheet(
      initialChildSize: .88,
      minChildSize: .55,
      maxChildSize: .96,
      expand: false,
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TrailerPreview(show: show, showControls: true),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x33000000),
                            Color(0x22000000),
                            AppColors.inkSoft,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: IconButton.filledTonal(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 10,
                      child: Text(
                        show.title,
                        maxLines: 2,
                        style: Theme.of(
                          context,
                        ).textTheme.headlineLarge?.copyWith(fontSize: 31),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${show.score}% Match',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (show.year.isNotEmpty)
                        Text(
                          show.year,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      Text(
                        show.mediaType == 'tv' ? 'SERIES' : 'MOVIE',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const _QualityBadge(),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _openPlayer(context, show),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Open preview'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.outlined(
                        onPressed: () {
                          widget.onToggleSaved();
                          setState(() => _saved = !_saved);
                        },
                        style: IconButton.styleFrom(
                          minimumSize: const Size(52, 52),
                        ),
                        icon: Icon(
                          _saved ? Icons.check_rounded : Icons.add_rounded,
                        ),
                        tooltip: _saved
                            ? 'Remove from My List'
                            : 'Add to My List',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    show.overview.isEmpty
                        ? 'No description is available for this title yet.'
                        : show.overview,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: Color(0xFFE5E1E9),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'More details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _InfoLine(
                    label: 'Available in',
                    value: 'Interactive catalog preview',
                  ),
                  _InfoLine(
                    label: 'Content type',
                    value: show.mediaType == 'tv' ? 'Series' : 'Feature film',
                  ),
                  const _InfoLine(
                    label: 'Downloads',
                    value: 'Not available in this build',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPlayer(BuildContext context, Show show) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WatchScreen(
          show: show,
          activeProfile: widget.activeProfile,
          planName: widget.planName,
          initialPosition: widget.initialPosition,
        ),
      ),
    );
    widget.onPlaybackEnded();
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white54),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Text(
      'PREVIEW',
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, color: AppColors.muted),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    ),
  );
}
