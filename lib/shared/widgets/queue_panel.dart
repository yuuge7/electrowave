import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/player/providers/player_provider.dart';
import '../../features/player/providers/queue_provider.dart';
import '../../core/database/app_database.dart' as db;
import '../theme/app_theme.dart';

/// Spotify-style queue side panel: now playing, the manual "Next in queue"
/// section, then the upcoming tracks from the current playback context.
class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  Widget _sectionHeader(
    String text,
    ElectrowaveColors colors, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: colors.textPrimary,
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
    db.Track track,
    ElectrowaveColors colors, {
    bool highlighted = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final placeholder =
        Icon(Icons.music_note, color: colors.textFaint, size: 18);

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: track.coverArtPath != null
            ? Image.file(
                File(track.coverArtPath!),
                fit: BoxFit.cover,
                cacheWidth: 96,
                errorBuilder: (context, error, stackTrace) => placeholder,
              )
            : placeholder,
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: highlighted ? colors.accent : colors.textSecondary,
          fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.textFaint, fontSize: 11),
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
    final colors = context.colors;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Queue',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Icons.close, color: colors.textFaint, size: 20),
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
                  _sectionHeader('Now playing', colors),
                  _trackTile(currentTrack, colors, highlighted: true),
                ],
                if (queue.manualQueue.isNotEmpty) ...[
                  _sectionHeader(
                    'Next in queue',
                    colors,
                    trailing: TextButton(
                      onPressed: () =>
                          ref.read(queueProvider.notifier).clearQueue(),
                      child: Text(
                        'Clear',
                        style:
                            TextStyle(color: colors.textFaint, fontSize: 12),
                      ),
                    ),
                  ),
                  // Drag to reorder what plays next.
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    // onReorderItem hands over the index already adjusted for
                    // the removed item, which is what reorderQueue expects.
                    onReorderItem: (oldIndex, newIndex) => ref
                        .read(queueProvider.notifier)
                        .reorderQueue(oldIndex, newIndex),
                    children: [
                      for (final entry in queue.manualQueue.asMap().entries)
                        ReorderableDragStartListener(
                          key: ValueKey('queue-${entry.key}-${entry.value.id}'),
                          index: entry.key,
                          child: _trackTile(
                            entry.value,
                            colors,
                            onTap: () =>
                                controller.playQueuedTrackNow(entry.value),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.drag_handle,
                                    color: colors.textFaint, size: 16),
                                IconButton(
                                  tooltip: 'Remove from queue',
                                  icon: Icon(Icons.close,
                                      color: colors.textFaint, size: 16),
                                  onPressed: () => ref
                                      .read(queueProvider.notifier)
                                      .removeFromQueue(entry.key),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (upcoming.isNotEmpty) ...[
                  _sectionHeader('Next up', colors),
                  ...upcoming.asMap().entries.map(
                        (entry) => _trackTile(
                          entry.value,
                          colors,
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
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Nothing queued.\nPlay a track or right-click one to add it to the queue.',
                      style: TextStyle(color: colors.textFaint, fontSize: 13),
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
