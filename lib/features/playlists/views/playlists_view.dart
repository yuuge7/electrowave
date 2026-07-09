import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/playlists_provider.dart';
import '../../player/providers/player_provider.dart';
import '../../player/providers/queue_provider.dart';
import '../../../main.dart';
import '../../../core/database/app_database.dart' as db;

class PlaylistsView extends ConsumerWidget {
  const PlaylistsView({super.key});

  String _formatDurationMs(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  DataCell _queueMenuCell(BuildContext context, WidgetRef ref, db.Track track, String text) {
    return DataCell(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) {
          showMenu<String>(
            context: context,
            color: const Color(0xFF282828),
            position: RelativeRect.fromLTRB(
              details.globalPosition.dx,
              details.globalPosition.dy,
              details.globalPosition.dx,
              details.globalPosition.dy,
            ),
            items: const [
              PopupMenuItem(
                value: 'queue',
                child: Row(
                  children: [
                    Icon(Icons.queue_music, color: Colors.white70, size: 18),
                    SizedBox(width: 10),
                    Text('Add to queue', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ).then((value) {
            if (value == 'queue') {
              ref.read(queueProvider.notifier).addToQueue(track);
            }
          });
        },
        child: Container(
          alignment: Alignment.centerLeft,
          child: Text(text, style: const TextStyle(color: Colors.white70)),
        ),
      ),
    );
  }

  void _confirmDeletePlaylist(BuildContext context, WidgetRef ref, db.Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text('Delete Playlist', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${playlist.name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final selectedPlaylistId = ref.watch(selectedPlaylistIdProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent,
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const CreatePlaylistDialog(),
          );
        },
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: Row(
        children: [
          Container(
            width: 250,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Colors.white10)),
            ),
            child: playlistsAsync.when(
              data: (playlists) {
                if (playlists.isEmpty) {
                  return const Center(
                    child: Text('No playlists yet.', style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    final isSelected = playlist.id == selectedPlaylistId;
                    
                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: Colors.white10,
                      leading: Icon(
                        Icons.queue_music, 
                        color: isSelected ? Colors.greenAccent : Colors.grey
                      ),
                      title: Text(
                        playlist.name, 
                        style: TextStyle(
                          color: isSelected ? Colors.greenAccent : Colors.white70,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        )
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                        onPressed: () => _confirmDeletePlaylist(context, ref, playlist),
                      ),
                      onTap: () {
                        ref.read(selectedPlaylistIdProvider.notifier).select(playlist.id);
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
              error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
            ),
          ),

          Expanded(
            child: selectedPlaylistId == null
                ? const Center(
                    child: Text('Select a playlist to view its tracks.', style: TextStyle(color: Colors.grey))
                  )
                : Consumer(
                    builder: (context, ref, child) {
                      final tracksAsync = ref.watch(playlistTracksProvider(selectedPlaylistId));

                      return tracksAsync.when(
                        data: (tracks) {
                          if (tracks.isEmpty) {
                            return const Center(
                              child: Text('This playlist is empty.', style: TextStyle(color: Colors.grey)),
                            );
                          }

                          return DataTable2(
                            columnSpacing: 12,
                            horizontalMargin: 16,
                            columns: const [
                              DataColumn2(label: Text('Title', style: TextStyle(color: Colors.white)), size: ColumnSize.L),
                              DataColumn2(label: Text('Artist', style: TextStyle(color: Colors.white))),
                              DataColumn2(label: Text('Duration', style: TextStyle(color: Colors.white)), size: ColumnSize.S),
                            ],
                            rows: List<DataRow>.generate(tracks.length, (index) {
                              final track = tracks[index];
                              return DataRow(
                                onSelectChanged: (selected) {
                                  if (selected ?? false) {
                                    // The playlist becomes the playback
                                    // context: next/previous stay inside it.
                                    ref.read(playbackControllerProvider)
                                        .playFromContext(tracks, index);
                                  }
                                },
                                cells: [
                                  _queueMenuCell(context, ref, track, track.title),
                                  _queueMenuCell(context, ref, track, track.artist),
                                  _queueMenuCell(context, ref, track, _formatDurationMs(track.durationMs)),
                                ],
                              );
                            }),
                          );
                        },
                        loading: () => const Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
                        error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
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
    return AlertDialog(
      backgroundColor: const Color(0xFF181818),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Create New Playlist', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _controller,
        autofocus: true, 
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'e.g., Late Night Coding',
          hintStyle: TextStyle(color: Colors.grey),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
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
          child: const Text('Create', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}