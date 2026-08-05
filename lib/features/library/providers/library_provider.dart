import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../main.dart'; // Import to access databaseProvider

/// How the library is grouped on screen.
enum LibraryBrowseMode { tracks, albums, artists, folders }

/// Generated lists that aren't playlists: they come from listening data.
enum SmartList { favorites, recentlyAdded, recentlyPlayed, mostPlayed }

String smartListLabel(SmartList list) => switch (list) {
      SmartList.favorites => 'Favorites',
      SmartList.recentlyAdded => 'Recently added',
      SmartList.recentlyPlayed => 'Recently played',
      SmartList.mostPlayed => 'Most played',
    };

String librarySortLabel(LibrarySort sort) => switch (sort) {
      LibrarySort.title => 'Title',
      LibrarySort.artist => 'Artist',
      LibrarySort.dateAdded => 'Date added',
      LibrarySort.playCount => 'Play count',
    };

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void updateQuery(String query) {
    state = query;
  }
}

final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

class LibrarySortNotifier extends Notifier<LibrarySort> {
  @override
  LibrarySort build() => LibrarySort.title;

  void set(LibrarySort sort) => state = sort;
}

final librarySortProvider =
    NotifierProvider<LibrarySortNotifier, LibrarySort>(LibrarySortNotifier.new);

class LibraryBrowseModeNotifier extends Notifier<LibraryBrowseMode> {
  @override
  LibraryBrowseMode build() => LibraryBrowseMode.tracks;

  void set(LibraryBrowseMode mode) => state = mode;
}

final libraryBrowseModeProvider =
    NotifierProvider<LibraryBrowseModeNotifier, LibraryBrowseMode>(
        LibraryBrowseModeNotifier.new);

/// The album / artist / folder the user drilled into, or null at the top
/// level. Cleared whenever the browse mode changes.
class BrowseDetail {
  const BrowseDetail({required this.mode, required this.key});

  final LibraryBrowseMode mode;

  /// Album name, artist name or folder path, depending on [mode].
  final String key;
}

class BrowseDetailNotifier extends Notifier<BrowseDetail?> {
  @override
  BrowseDetail? build() => null;

  void open(LibraryBrowseMode mode, String key) =>
      state = BrowseDetail(mode: mode, key: key);

  void close() => state = null;
}

final browseDetailProvider =
    NotifierProvider<BrowseDetailNotifier, BrowseDetail?>(
        BrowseDetailNotifier.new);

/// Selected smart list, or null when browsing the library normally.
class SmartListNotifier extends Notifier<SmartList?> {
  @override
  SmartList? build() => null;

  void select(SmartList? list) => state = list;
}

final selectedSmartListProvider =
    NotifierProvider<SmartListNotifier, SmartList?>(SmartListNotifier.new);

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

/// Provides a reactive stream of all active tracks, filtered by the search box
/// and ordered by the chosen sort.
final libraryProvider = StreamProvider<List<Track>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchLibrary(
    search: ref.watch(searchQueryProvider),
    sort: ref.watch(librarySortProvider),
  );
});

final albumsProvider = StreamProvider<List<AlbumSummary>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAlbums(search: ref.watch(searchQueryProvider));
});

final artistsProvider = StreamProvider<List<ArtistSummary>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchArtists(search: ref.watch(searchQueryProvider));
});

final foldersProvider = StreamProvider<List<FolderSummary>>((ref) {
  return ref.watch(databaseProvider).watchFolders();
});

final albumTracksProvider =
    StreamProvider.family<List<Track>, String>((ref, album) {
  return ref.watch(databaseProvider).watchAlbumTracks(album);
});

final artistTracksProvider =
    StreamProvider.family<List<Track>, String>((ref, artist) {
  return ref.watch(databaseProvider).watchArtistTracks(artist);
});

final folderTracksProvider =
    StreamProvider.family<List<Track>, String>((ref, folderPath) {
  return ref.watch(databaseProvider).watchFolderTracks(folderPath);
});

final smartListTracksProvider =
    StreamProvider.family<List<Track>, SmartList>((ref, list) {
  final db = ref.watch(databaseProvider);
  return switch (list) {
    SmartList.favorites => db.watchFavorites(),
    SmartList.recentlyAdded => db.watchRecentlyAdded(),
    SmartList.recentlyPlayed => db.watchRecentlyPlayed(),
    SmartList.mostPlayed => db.watchMostPlayed(),
  };
});

/// Live row for the track in the player bar, so the favourite heart and tag
/// edits show up without restarting playback.
final liveTrackProvider = StreamProvider.family<Track?, int>((ref, id) {
  return ref.watch(databaseProvider).watchTrackById(id);
});

/// Soft-deleted tracks, shown in Settings → Removed tracks.
final deletedTracksProvider = StreamProvider<List<Track>>((ref) {
  return ref.watch(databaseProvider).watchDeletedTracks();
});
