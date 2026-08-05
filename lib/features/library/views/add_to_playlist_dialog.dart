import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../main.dart';
import '../../../shared/theme/app_theme.dart';
import '../../playlists/providers/playlists_provider.dart';

class AddToPlaylistDialog extends ConsumerStatefulWidget {
  final db.Track track;
  const AddToPlaylistDialog({super.key, required this.track});

  @override
  ConsumerState<AddToPlaylistDialog> createState() =>
      _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends ConsumerState<AddToPlaylistDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final database = ref.read(databaseProvider);
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Add "${widget.track.title}" to...',
        style: TextStyle(color: colors.textPrimary, fontSize: 18),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'New Playlist Name',
                      hintStyle: TextStyle(color: colors.textFaint),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colors.border)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colors.accent)),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add_circle, color: colors.accent),
                  onPressed: () async {
                    if (_controller.text.trim().isNotEmpty) {
                      final newPlaylistId = await database
                          .into(database.playlists)
                          .insert(db.PlaylistsCompanion.insert(
                              name: _controller.text.trim()));
                      await database.addTrackToPlaylist(
                          newPlaylistId, widget.track.id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                )
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: colors.border),

            playlistsAsync.when(
              data: (playlists) {
                if (playlists.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('No custom playlists yet.',
                        style: TextStyle(color: colors.textFaint)),
                  );
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(playlist.name,
                            style: TextStyle(color: colors.textSecondary)),
                        trailing:
                            Icon(Icons.add, color: colors.textFaint, size: 20),
                        onTap: () async {
                          await database.addTrackToPlaylist(
                              playlist.id, widget.track.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                      );
                    },
                  ),
                );
              },
              loading: () => CircularProgressIndicator(color: colors.accent),
              error: (e, st) => const Text('Failed to load playlists.',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: colors.textFaint)),
        ),
      ],
    );
  }
}
