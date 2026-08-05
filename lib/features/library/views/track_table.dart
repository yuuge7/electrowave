import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;

import '../../../core/database/app_database.dart' as db;
import '../../../main.dart';
import '../../../shared/theme/app_theme.dart';
import '../../player/providers/player_provider.dart';
import '../../player/providers/queue_provider.dart';
import 'add_to_playlist_dialog.dart';
import 'tag_editor_dialog.dart';

/// The library's track list, shared by the flat library, the album / artist /
/// folder detail views and the smart lists.
///
/// Clicking a row makes [tracks] the playback context, so next/previous stay
/// inside exactly the list on screen.
class TrackTable extends ConsumerWidget {
  const TrackTable({
    super.key,
    required this.tracks,
    this.emptyMessage = 'No tracks found.',
    this.showAlbum = true,
    this.onRemoveFromPlaylist,
  });

  final List<db.Track> tracks;
  final String emptyMessage;
  final bool showAlbum;

  /// When set, the row menu offers removing the track from the playlist being
  /// shown instead of only the library-wide actions.
  final void Function(db.Track track)? onRemoveFromPlaylist;

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
        _menuItem('playlist', Icons.playlist_add, 'Add to playlist…', colors),
        if (onRemoveFromPlaylist != null)
          _menuItem('remove_from_playlist', Icons.playlist_remove,
              'Remove from playlist', colors),
      ],
    ).then((value) {
      if (!context.mounted) return;
      switch (value) {
        case 'play_next':
          ref.read(queueProvider.notifier).playNext(track);
        case 'queue':
          ref.read(queueProvider.notifier).addToQueue(track);
        case 'favorite':
          ref
              .read(databaseProvider)
              .setFavorite(track.id, !track.isFavorite);
        case 'tags':
          showDialog(
            context: context,
            builder: (context) => TagEditorDialog(track: track),
          );
        case 'playlist':
          showDialog(
            context: context,
            builder: (context) => AddToPlaylistDialog(track: track),
          );
        case 'remove_from_playlist':
          onRemoveFromPlaylist?.call(track);
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

  DataCell _cell(
    BuildContext context,
    WidgetRef ref,
    db.Track track,
    String text,
  ) {
    return DataCell(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) =>
            _showTrackMenu(context, ref, track, details.globalPosition),
        child: Container(
          alignment: Alignment.centerLeft,
          child: Text(text, style: TextStyle(color: context.colors.textSecondary)),
        ),
      ),
    );
  }

  void _confirmDeleteTrack(
      BuildContext context, WidgetRef ref, db.Track track) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Delete Track', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Remove "${track.title}" from your library?\n\n'
          'The audio file is left untouched and the track can be restored '
          'from Settings → Removed tracks.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textFaint)),
          ),
          TextButton(
            onPressed: () async {
              final database = ref.read(databaseProvider);
              // SOFT DELETE: hide the track without destroying its stats.
              await (database.update(database.tracks)
                    ..where((t) => t.id.equals(track.id)))
                  .write(
                const db.TracksCompanion(isDeleted: drift.Value(true)),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    if (tracks.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: TextStyle(color: colors.textFaint)),
      );
    }

    final headerStyle = TextStyle(color: colors.textPrimary);

    return DataTable2(
      columnSpacing: 12,
      horizontalMargin: 16,
      columns: [
        DataColumn2(label: Text('Title', style: headerStyle), size: ColumnSize.L),
        DataColumn2(label: Text('Artist', style: headerStyle)),
        if (showAlbum) DataColumn2(label: Text('Album', style: headerStyle)),
        DataColumn2(
            label: Text('Duration', style: headerStyle), size: ColumnSize.S),
        const DataColumn2(label: Text(''), size: ColumnSize.S, fixedWidth: 96),
      ],
      rows: List<DataRow>.generate(tracks.length, (index) {
        final track = tracks[index];
        return DataRow(
          onSelectChanged: (selected) {
            if (selected ?? false) {
              ref
                  .read(playbackControllerProvider)
                  .playFromContext(tracks, index);
            }
          },
          cells: [
            _cell(context, ref, track, track.title),
            _cell(context, ref, track, track.artist),
            if (showAlbum) _cell(context, ref, track, track.album),
            _cell(context, ref, track, _formatDurationMs(track.durationMs)),
            DataCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: track.isFavorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  icon: Icon(
                    track.isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                  ),
                  color: track.isFavorite ? colors.accent : colors.textFaint,
                  onPressed: () => ref
                      .read(databaseProvider)
                      .setFavorite(track.id, !track.isFavorite),
                ),
                IconButton(
                  tooltip: 'Remove from library',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: colors.textFaint,
                  onPressed: () => _confirmDeleteTrack(context, ref, track),
                  hoverColor: Colors.redAccent.withValues(alpha: 0.1),
                ),
              ],
            )),
          ],
        );
      }),
    );
  }
}
