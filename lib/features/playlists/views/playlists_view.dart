import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/playlists_provider.dart';
import '../../library/views/browse_views.dart';
import '../../library/views/tag_editor_dialog.dart';
import '../../player/providers/player_provider.dart';
import '../../player/providers/queue_provider.dart';
import '../../../main.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../core/database/app_database.dart' as db;

class PlaylistsView extends ConsumerWidget {
  const PlaylistsView({super.key});

  String _formatDurationMs(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showTrackMenu(
    BuildContext context,
    WidgetRef ref,
    db.Track track,
    int playlistId,
    Offset position,
  ) {
    final colors = context.colors;
    showMenu<String>(
      context: context,
      color: colors.surfaceAlt,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        _menuItem('play_next', Icons.playlist_play, 'Play next', colors),
        _menuItem('queue', Icons.queue_music, 'Add to queue', colors),
        _menuItem(
          'favorite',
          track.isFavorite ? Icons.favorite : Icons.favorite_border,
          track.isFavorite ? 'Remove from favorites' : 'Add to favorites',
          colors,
        ),
        _menuItem('tags', Icons.edit_note, 'Edit tags…', colors),
        _menuItem(
            'remove', Icons.playlist_remove, 'Remove from playlist', colors),
      ],
    ).then((value) {
      if (!context.mounted) return;
      switch (value) {
        case 'play_next':
          ref.read(queueProvider.notifier).playNext(track);
        case 'queue':
          ref.read(queueProvider.notifier).addToQueue(track);
        case 'favorite':
          ref.read(databaseProvider).setFavorite(track.id, !track.isFavorite);
        case 'tags':
          showDialog(
            context: context,
            builder: (context) => TagEditorDialog(track: track),
          );
        case 'remove':
          ref
              .read(databaseProvider)
              .removeTrackFromPlaylist(playlistId, track.id);
      }
    });
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    ElectrowaveColors colors,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: colors.textSecondary, size: 18),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: colors.textSecondary)),
        ],
      ),
    );
  }

  void _confirmDeletePlaylist(
      BuildContext context, WidgetRef ref, db.Playlist playlist) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title:
            Text('Delete Playlist', style: TextStyle(color: colors.textPrimary)),
        content: Text('Are you sure you want to delete "${playlist.name}"?',
            style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textFaint)),
          ),
          TextButton(
            onPressed: () async {
              final database = ref.read(databaseProvider);

              await (database.delete(database.playlistTracks)..where((t) => t.playlistId.equals(playlist.id))).go();
              await (database.delete(database.playlists)..where((t) => t.id.equals(playlist.id))).go();

              if (ref.read(selectedPlaylistIdProvider) == playlist.id) {
                ref.read(selectedPlaylistIdProvider.notifier).select(null);
              }

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      )
    );
  }

  void _renamePlaylist(
      BuildContext context, WidgetRef ref, db.Playlist playlist) {
    final colors = context.colors;
    final controller = TextEditingController(text: playlist.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:
            Text('Rename Playlist', style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            enabledBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: colors.border)),
            focusedBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: colors.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textFaint)),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await ref.read(databaseProvider).renamePlaylist(playlist.id, name);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: Text('Rename',
                style: TextStyle(
                    color: colors.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _playAll(WidgetRef ref, List<db.Track> tracks, {required bool shuffle}) {
    if (tracks.isEmpty) return;
    ref.read(shuffleProvider.notifier).set(shuffle);
    final index = shuffle ? Random().nextInt(tracks.length) : 0;
    ref.read(playbackControllerProvider).playFromContext(tracks, index);
  }

  /// Drag-to-reorder track list. A DataTable can't be reordered, so the
  /// playlist body is a list — the order *is* the point of a playlist.
  Widget _playlistTracks(
      BuildContext context, WidgetRef ref, int playlistId, List<db.Track> tracks) {
    final colors = context.colors;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${tracks.length} tracks',
                style: TextStyle(color: colors.textFaint, fontSize: 12),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                ),
                onPressed: () => _playAll(ref, tracks, shuffle: false),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  side: BorderSide(color: colors.border),
                ),
                onPressed: () => _playAll(ref, tracks, shuffle: true),
                icon: const Icon(Icons.shuffle),
                label: const Text('Shuffle'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            buildDefaultDragHandles: false,
            itemCount: tracks.length,
            // onReorderItem hands over the target index already adjusted for
            // the removed row, so the list can be rebuilt as-is.
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...tracks];
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex.clamp(0, reordered.length), moved);
              ref.read(databaseProvider).reorderPlaylist(
                    playlistId,
                    [for (final track in reordered) track.id],
                  );
            },
            itemBuilder: (context, index) {
              final track = tracks[index];
              return GestureDetector(
                key: ValueKey('playlist-track-${track.id}'),
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) => _showTrackMenu(
                    context, ref, track, playlistId, details.globalPosition),
                child: ListTile(
                  leading: ArtThumb(path: track.coverArtPath, size: 40),
                  title: Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textPrimary)),
                  subtitle: Text(track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textFaint, fontSize: 12)),
                  onTap: () => ref
                      .read(playbackControllerProvider)
                      .playFromContext(tracks, index),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_formatDurationMs(track.durationMs),
                          style: TextStyle(color: colors.textFaint, fontSize: 12)),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: track.isFavorite
                            ? 'Remove from favorites'
                            : 'Add to favorites',
                        icon: Icon(
                          track.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 18,
                        ),
                        color:
                            track.isFavorite ? colors.accent : colors.textFaint,
                        onPressed: () => ref
                            .read(databaseProvider)
                            .setFavorite(track.id, !track.isFavorite),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Icon(Icons.drag_handle,
                            color: colors.textFaint, size: 18),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final playlistsAsync = ref.watch(playlistsProvider);
    final selectedPlaylistId = ref.watch(selectedPlaylistIdProvider);

    return Scaffold(
      backgroundColor: colors.background,
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.accent,
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const CreatePlaylistDialog(),
          );
        },
        child: Icon(Icons.add, color: colors.onAccent),
      ),
      body: Row(
        children: [
          Container(
            width: 250,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: colors.border)),
            ),
            child: playlistsAsync.when(
              data: (playlists) {
                if (playlists.isEmpty) {
                  return Center(
                    child: Text('No playlists yet.',
                        style: TextStyle(color: colors.textFaint)),
                  );
                }
                return ListView.builder(
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    final isSelected = playlist.id == selectedPlaylistId;

                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: colors.surface,
                      leading: Icon(
                        Icons.queue_music,
                        color: isSelected ? colors.accent : colors.textFaint,
                      ),
                      title: Text(
                        playlist.name,
                        style: TextStyle(
                          color:
                              isSelected ? colors.accent : colors.textSecondary,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Playlist actions',
                        color: colors.surfaceAlt,
                        icon: Icon(Icons.more_vert,
                            color: colors.textFaint, size: 20),
                        onSelected: (value) {
                          if (value == 'rename') {
                            _renamePlaylist(context, ref, playlist);
                          } else if (value == 'delete') {
                            _confirmDeletePlaylist(context, ref, playlist);
                          }
                        },
                        itemBuilder: (context) => [
                          _menuItem('rename', Icons.drive_file_rename_outline,
                              'Rename', colors),
                          _menuItem(
                              'delete', Icons.delete_outline, 'Delete', colors),
                        ],
                      ),
                      onTap: () {
                        ref
                            .read(selectedPlaylistIdProvider.notifier)
                            .select(playlist.id);
                      },
                    );
                  },
                );
              },
              loading: () =>
                  Center(child: CircularProgressIndicator(color: colors.accent)),
              error: (err, stack) => Center(
                  child: Text('Error: $err',
                      style: const TextStyle(color: Colors.red))),
            ),
          ),

          Expanded(
            child: selectedPlaylistId == null
                ? Center(
                    child: Text('Select a playlist to view its tracks.',
                        style: TextStyle(color: colors.textFaint)),
                  )
                : Consumer(
                    builder: (context, ref, child) {
                      final tracksAsync =
                          ref.watch(playlistTracksProvider(selectedPlaylistId));

                      return tracksAsync.when(
                        data: (tracks) {
                          if (tracks.isEmpty) {
                            return Center(
                              child: Text('This playlist is empty.',
                                  style: TextStyle(color: colors.textFaint)),
                            );
                          }
                          return _playlistTracks(
                              context, ref, selectedPlaylistId, tracks);
                        },
                        loading: () => Center(
                            child:
                                CircularProgressIndicator(color: colors.accent)),
                        error: (err, stack) => Center(
                            child: Text('Error: $err',
                                style: const TextStyle(color: Colors.red))),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class CreatePlaylistDialog extends ConsumerStatefulWidget {
  const CreatePlaylistDialog({super.key});

  @override
  ConsumerState<CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends ConsumerState<CreatePlaylistDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Create New Playlist',
          style: TextStyle(color: colors.textPrimary)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(color: colors.textPrimary),
        decoration: InputDecoration(
          hintText: 'e.g., Late Night Coding',
          hintStyle: TextStyle(color: colors.textFaint),
          enabledBorder:
              UnderlineInputBorder(borderSide: BorderSide(color: colors.border)),
          focusedBorder:
              UnderlineInputBorder(borderSide: BorderSide(color: colors.accent)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: colors.textFaint)),
        ),
        TextButton(
          onPressed: () async {
            final name = _controller.text.trim();
            if (name.isNotEmpty) {
              final database = ref.read(databaseProvider);
              await database.into(database.playlists).insert(
                db.PlaylistsCompanion.insert(name: name)
              );
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: Text('Create',
              style:
                  TextStyle(color: colors.accent, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
