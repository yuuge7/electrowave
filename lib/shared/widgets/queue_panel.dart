import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/player/providers/player_provider.dart';
import '../../features/player/providers/queue_provider.dart';
import '../../core/database/app_database.dart' as db;

/// Spotify-style queue side panel: now playing, the manual "Next in queue"
/// section, then the upcoming tracks from the current playback context.
class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  Widget _sectionHeader(String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _trackTile(
    db.Track track, {
    bool highlighted = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: track.coverArtPath != null
            ? Image.file(
                File(track.coverArtPath!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.music_note, color: Colors.grey, size: 18),
              )
            : const Icon(Icons.music_note, color: Colors.grey, size: 18),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: highlighted ? Colors.greenAccent : Colors.white70,
          fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.grey, fontSize: 11),
      ),
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);
    final currentTrack = ref.watch(currentTrackProvider);
    final controller = ref.read(playbackControllerProvider);
    final upcoming = queue.upcomingFromContext;

    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
        border: Border(left: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Queue',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  onPressed: () =>
                      ref.read(queuePanelVisibleProvider.notifier).close(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (currentTrack != null) ...[
                  _sectionHeader('Now playing'),
                  _trackTile(currentTrack, highlighted: true),
                ],
                if (queue.manualQueue.isNotEmpty) ...[
                  _sectionHeader(
                    'Next in queue',
                    trailing: TextButton(
                      onPressed: () =>
                          ref.read(queueProvider.notifier).clearQueue(),
                      child: const Text(
                        'Clear',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ),
                  ...queue.manualQueue.asMap().entries.map(
                        (entry) => _trackTile(
                          entry.value,
                          onTap: () =>
                              controller.playQueuedTrackNow(entry.value),
                          trailing: IconButton(
                            tooltip: 'Remove from queue',
                            icon: const Icon(Icons.close,
                                color: Colors.grey, size: 16),
                            onPressed: () => ref
                                .read(queueProvider.notifier)
                                .removeFromQueue(entry.key),
                          ),
                        ),
                      ),
                ],
                if (upcoming.isNotEmpty) ...[
                  _sectionHeader('Next up'),
                  ...upcoming.asMap().entries.map(
                        (entry) => _trackTile(
                          entry.value,
                          onTap: () => controller.playFromContext(
                            queue.context,
                            queue.contextIndex + 1 + entry.key,
                          ),
                        ),
                      ),
                ],
                if (currentTrack == null &&
                    queue.manualQueue.isEmpty &&
                    upcoming.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nothing queued.\nPlay a track or right-click one to add it to the queue.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
