import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/watch_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/network_art.dart';

class WatchHistoryScreen extends StatefulWidget {
  const WatchHistoryScreen({
    super.key,
    required this.supabase,
    required this.onChanged,
  });

  final SupabaseClient supabase;
  final VoidCallback onChanged;

  @override
  State<WatchHistoryScreen> createState() => _WatchHistoryScreenState();
}

class _WatchHistoryScreenState extends State<WatchHistoryScreen> {
  late final WatchHistoryService _service;
  late Future<List<WatchHistoryEntry>> _history;
  int? _deletingId;

  @override
  void initState() {
    super.initState();
    _service = WatchHistoryService(widget.supabase);
    _history = _service.load();
  }

  void _reload() => setState(() => _history = _service.load());

  Future<void> _delete(WatchHistoryEntry entry) async {
    setState(() => _deletingId = entry.contentId);
    try {
      await _service.delete(entry.contentId);
      widget.onChanged();
      _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Watch-history item could not be removed.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Watch history')),
    body: FutureBuilder<List<WatchHistoryEntry>>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Watch history could not be loaded.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _reload,
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
        }
        final entries = snapshot.data ?? const [];
        if (entries.isEmpty) {
          return const Center(child: Text('No watch history.'));
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                leading: SizedBox(
                  width: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: NetworkArt(url: entry.thumbnail, fit: BoxFit.cover),
                  ),
                ),
                title: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_time(entry.lastPlaybackSeconds)} watched'
                  '${entry.runtimeMinutes == null ? '' : ' · ${entry.runtimeMinutes} min'}',
                  style: const TextStyle(color: AppColors.muted),
                ),
                trailing: IconButton(
                  onPressed: _deletingId == null ? () => _delete(entry) : null,
                  tooltip: 'Remove ${entry.title} from watch history',
                  icon: _deletingId == entry.contentId
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

String _time(int seconds) {
  final safe = seconds.clamp(0, 2147483647);
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final remaining = safe % 60;
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}'
      : '$minutes:${remaining.toString().padLeft(2, '0')}';
}
