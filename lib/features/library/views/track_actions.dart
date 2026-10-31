import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../main.dart';
import '../../player/providers/player_provider.dart';
import '../../player/providers/queue_provider.dart';
import 'add_to_playlist_dialog.dart';
import 'bulk_tag_editor.dart';
import 'tag_editor_dialog.dart';

void showUndo(
  BuildContext context,
  String message,
  Future<void> Function() undo,
) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(label: 'Undo', onPressed: () => undo()),
    ),
  );
}

Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
  Offset position, {
  Future<void> Function()? removeFromPlaylist,
}) async {
  if (tracks.isEmpty || !context.mounted) return;
  final value = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: [
      for (final entry in <String, String>{
        'play': 'Play',
        'next': 'Play next',
        'queue': 'Add to queue',
        'playlist': 'Add to playlist...',
        'favorite': 'Favorite',
        'tags': 'Edit tags...',
        if (removeFromPlaylist != null)
          'playlistRemove': 'Remove from playlist',
        'remove': 'Remove from library',
      }.entries)
        PopupMenuItem(value: entry.key, child: Text(entry.value)),
    ],
  );
  if (!context.mounted) return;
  final database = ref.read(databaseProvider);
  switch (value) {
    case 'play':
      ref.read(playbackControllerProvider).playFromContext(tracks, 0);
    case 'next':
      for (final track in tracks.reversed) {
        ref.read(queueProvider.notifier).playNext(track);
      }
    case 'queue':
      for (final track in tracks) {
        ref.read(queueProvider.notifier).addToQueue(track);
      }
    case 'favorite':
      for (final track in tracks) {
        await database.setFavorite(track.id, true);
      }
    case 'playlist':
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => AddToPlaylistDialog(tracks: tracks),
        );
      }
    case 'tags':
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => tracks.length == 1
              ? TagEditorDialog(track: tracks.single)
              : BulkTagEditor(tracks: tracks),
        );
      }
    case 'playlistRemove':
      await removeFromPlaylist?.call();
    case 'remove':
      final ids = tracks.map((t) => t.id).toList();
      await database.softDeleteMany(ids);
      if (context.mounted) {
        showUndo(
          context,
          'Removed ${ids.length} tracks.',
          () => database.softDeleteMany(ids, deleted: false),
        );
      }
  }
}
