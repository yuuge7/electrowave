import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift; // Added for soft delete Value()

import '../providers/library_provider.dart';
import '../../player/services/metadata_scanner.dart';
import '../../player/providers/player_provider.dart';
import '../../player/providers/queue_provider.dart';
import '../../playlists/providers/playlists_provider.dart';
import '../../../main.dart';
import '../../../core/database/app_database.dart' as db;

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void updateQuery(String query) {
    state = query;
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

class LibraryView extends ConsumerWidget {
  const LibraryView({super.key});

  String _formatDurationMs(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showTrackMenu(BuildContext context, WidgetRef ref, db.Track track, Offset position) {
    showMenu<String>(
      context: context,
      color: const Color(0xFF282828),
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
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
        PopupMenuItem(
          value: 'playlist',
          child: Row(
            children: [
              Icon(Icons.playlist_add, color: Colors.white70, size: 18),
              SizedBox(width: 10),
              Text('Add to playlist…', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'queue') {
        ref.read(queueProvider.notifier).addToQueue(track);
      } else if (value == 'playlist' && context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AddToPlaylistDialog(track: track),
        );
      }
    });
  }

  DataCell _buildRightClickableCell(BuildContext context, WidgetRef ref, db.Track track, String text) {
    return DataCell(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) {
          _showTrackMenu(context, ref, track, details.globalPosition);
        },
        child: Container(
          alignment: Alignment.centerLeft,
          child: Text(text, style: const TextStyle(color: Colors.white70)),
        ),
      ),
    );
  }

  void _confirmDeleteTrack(BuildContext context, WidgetRef ref, db.Track track) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text('Delete Track', style: TextStyle(color: Colors.white)),
        content: Text('Remove "${track.title}" from your library?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final database = ref.read(databaseProvider);
              
              // 1. Remove the track from any playlists it belongs to
              await (database.delete(database.playlistTracks)..where((t) => t.trackId.equals(track.id))).go();
              
              // 2. SOFT DELETE: Hide the track without destroying its stats
              await (database.update(database.tracks)..where((t) => t.id.equals(track.id))).write(
                const db.TracksCompanion(
                  isDeleted: drift.Value(true),
                ),
              );
              
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
    final libraryAsync = ref.watch(libraryProvider);
    final database = ref.read(databaseProvider);
    final searchQuery = ref.watch(searchQueryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      
      // UPDATED FAB: Now pops a bottom sheet to choose between Folder or Files
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent,
        onPressed: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF181818),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.create_new_folder, color: Colors.greenAccent),
                    title: const Text('Scan Entire Folder', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Finds all music in a directory', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    onTap: () async {
                      Navigator.pop(context);
                      await MetadataScanner(database).scanDirectory();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.queue_music, color: Colors.greenAccent),
                    title: const Text('Add Specific Files', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Select individual tracks to add', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    onTap: () async {
                      Navigator.pop(context);
                      await MetadataScanner(database).scanSpecificFiles();
                    },
                  ),
                ],
              ),
            ),
          );
        },
        child: const Icon(Icons.add, color: Colors.black),
      ),
      
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 8.0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search songs, artists, or albums...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF181818),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.greenAccent, width: 1),
                ),
              ),
              onChanged: (value) {
                ref.read(searchQueryProvider.notifier).updateQuery(value);
              },
            ),
          ),
          
          Expanded(
            child: libraryAsync.when(
              data: (tracks) {
                final filteredTracks = tracks.where((track) {
                  final query = searchQuery.toLowerCase();
                  return track.title.toLowerCase().contains(query) ||
                         track.artist.toLowerCase().contains(query) ||
                         track.album.toLowerCase().contains(query);
                }).toList();

                if (filteredTracks.isEmpty) {
                  return const Center(
                    child: Text('No tracks found.', style: TextStyle(color: Colors.grey)),
                  );
                }

                return DataTable2(
                  columnSpacing: 12,
                  horizontalMargin: 16,
                  columns: const [
                    DataColumn2(label: Text('Title', style: TextStyle(color: Colors.white)), size: ColumnSize.L),
                    DataColumn2(label: Text('Artist', style: TextStyle(color: Colors.white))),
                    DataColumn2(label: Text('Album', style: TextStyle(color: Colors.white))),
                    DataColumn2(label: Text('Duration', style: TextStyle(color: Colors.white)), size: ColumnSize.S),
                    DataColumn2(label: Text(''), size: ColumnSize.S, fixedWidth: 50),
                  ],
                  rows: List<DataRow>.generate(filteredTracks.length, (index) {
                    final track = filteredTracks[index];
                    return DataRow(
                      onSelectChanged: (selected) {
                        if (selected ?? false) {
                          // The filtered list becomes the playback context,
                          // so next/previous stay inside what's on screen.
                          ref.read(playbackControllerProvider)
                              .playFromContext(filteredTracks, index);
                        }
                      },
                      cells: [
                        _buildRightClickableCell(context, ref, track, track.title),
                        _buildRightClickableCell(context, ref, track, track.artist),
                        _buildRightClickableCell(context, ref, track, track.album),
                        _buildRightClickableCell(context, ref, track, _formatDurationMs(track.durationMs)),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                            onPressed: () => _confirmDeleteTrack(context, ref, track),
                            hoverColor: Colors.redAccent.withValues(alpha: 0.1),
                          )
                        ),
                      ],
                    );
                  }),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
              error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
            ),
          ),
        ],
      ),
    );
  }
}

class AddToPlaylistDialog extends ConsumerStatefulWidget {
  final db.Track track;
  const AddToPlaylistDialog({super.key, required this.track});

  @override
  ConsumerState<AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
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

    return AlertDialog(
      backgroundColor: const Color(0xFF181818),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Add "${widget.track.title}" to...', 
        style: const TextStyle(color: Colors.white, fontSize: 18),
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
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'New Playlist Name',
                      hintStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.greenAccent),
                  onPressed: () async {
                    if (_controller.text.trim().isNotEmpty) {
                      final newPlaylistId = await database.into(database.playlists).insert(
                        db.PlaylistsCompanion.insert(name: _controller.text.trim())
                      );
                      await database.into(database.playlistTracks).insert(
                        db.PlaylistTracksCompanion.insert(playlistId: newPlaylistId, trackId: widget.track.id)
                      );
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                )
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            
            playlistsAsync.when(
              data: (playlists) {
                if (playlists.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No custom playlists yet.', style: TextStyle(color: Colors.grey)),
                  );
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final p = playlists[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.name, style: const TextStyle(color: Colors.white70)),
                        trailing: const Icon(Icons.add, color: Colors.grey, size: 20),
                        onTap: () async {
                          try {
                            await database.into(database.playlistTracks).insert(
                              db.PlaylistTracksCompanion.insert(playlistId: p.id, trackId: widget.track.id)
                            );
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                      );
                    },
                  ),
                );
              },
              loading: () => const CircularProgressIndicator(color: Colors.greenAccent),
              error: (e, st) => const Text('Failed to load playlists.', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}