import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../main.dart'; 
import '../../../core/database/app_database.dart' as db;

// 1. Streams all playlists
final playlistsProvider = StreamProvider<List<db.Playlist>>((ref) {
  final database = ref.watch(databaseProvider);
  return database.select(database.playlists).watch();
});

// 2. State to hold the currently clicked playlist ID
class SelectedPlaylistNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? id) {
    state = id;
  }
}

final selectedPlaylistIdProvider = NotifierProvider<SelectedPlaylistNotifier, int?>(SelectedPlaylistNotifier.new);

// 3. Streams the specific tracks for the selected playlist using an SQL JOIN
final playlistTracksProvider = StreamProvider.family<List<db.Track>, int>((ref, playlistId) {
  final database = ref.watch(databaseProvider);
  
  final query = database.select(database.tracks).join([
    innerJoin(
      database.playlistTracks, 
      database.playlistTracks.trackId.equalsExp(database.tracks.id)
    )
  ])..where(database.playlistTracks.playlistId.equals(playlistId));

  return query.watch().map((rows) {
    return rows.map((row) => row.readTable(database.tracks)).toList();
  });
});