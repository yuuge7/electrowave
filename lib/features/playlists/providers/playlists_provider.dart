import 'package:flutter_riverpod/flutter_riverpod.dart';
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

// 3. Streams the specific tracks for the selected playlist, in the manual
// order the user dragged them into.
final playlistTracksProvider =
    StreamProvider.family<List<db.Track>, int>((ref, playlistId) {
  return ref.watch(databaseProvider).watchPlaylistTracks(playlistId);
});

// 4. Membership ids for a playlist, so the track picker can grey out songs the
// playlist already holds without loading every joined track row.
final playlistTrackIdsProvider =
    StreamProvider.family<Set<int>, int>((ref, playlistId) {
  return ref.watch(databaseProvider).watchPlaylistTrackIds(playlistId);
});

/// Search + sort the track picker is currently showing.
///
/// A record so the family key compares structurally: two rebuilds with the
/// same text and sort reuse one stream instead of opening a new query.
typedef TrackPickerQuery = ({String search, db.LibrarySort sort});

// 5. The picker's own view of the library. Deliberately not [libraryProvider]:
// that one is driven by the library screen's search box, and typing in the
// picker must not scroll the screen behind it.
final trackPickerLibraryProvider = StreamProvider.autoDispose
    .family<List<db.Track>, TrackPickerQuery>((ref, query) {
  return ref
      .watch(databaseProvider)
      .watchLibrary(search: query.search, sort: query.sort);
});
