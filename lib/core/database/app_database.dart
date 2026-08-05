import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// --- TABLE DEFINITIONS ---

class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get filePath => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  IntColumn get durationMs => integer()();
  TextColumn get coverArtPath => text().nullable()();
  TextColumn get genre => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  // Tag numbering, used to play albums in their real running order.
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();

  /// Nullable rather than defaulted: SQLite refuses a non-constant default on
  /// ALTER TABLE ADD COLUMN, so rows that predate this column stay null and
  /// simply sort last in "Recently added".
  DateTimeColumn get dateAdded => dateTime().nullable()();

  IntColumn get totalPlayCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayed => dateTime().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
}

class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}

class PlaylistTracks extends Table {
  IntColumn get playlistId => integer()();
  IntColumn get trackId => integer()();

  /// Manual running order inside the playlist.
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {playlistId, trackId};
}

// NEW: Tracks every single time a song is played so we can build historical stats
class PlaybackHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId => integer()();
  DateTimeColumn get playedAt => dateTime()(); // Logs the exact date and time
}

/// Measured listening time: one row per stretch of a track actually played.
///
/// Deliberately separate from [PlaybackHistory], which records *that* a play
/// happened — every stat built on it multiplies those rows by the track's full
/// duration, so a track skipped after ten seconds counts the same as one heard
/// to the end. This table counts the audio that really came out.
@DataClassName('ListeningSessionEntry')
class ListeningSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId => integer()();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get listenedMs => integer().withDefault(const Constant(0))();
}

// --- DATABASE CLASS ---

/// How the library list is ordered.
enum LibrarySort { title, artist, dateAdded, playCount }

/// Album grouping row, aggregated straight from the tracks table — there are
/// no album/artist tables, so identity is the name text.
class AlbumSummary {
  const AlbumSummary({
    required this.album,
    required this.artist,
    required this.trackCount,
    required this.totalMs,
    this.coverArtPath,
  });

  final String album;

  /// Single artist when the album has one, 'Various artists' otherwise.
  final String artist;
  final int trackCount;
  final int totalMs;
  final String? coverArtPath;
}

class ArtistSummary {
  const ArtistSummary({
    required this.artist,
    required this.trackCount,
    required this.albumCount,
    required this.totalMs,
    this.coverArtPath,
  });

  final String artist;
  final int trackCount;
  final int albumCount;
  final int totalMs;
  final String? coverArtPath;
}

/// One directory containing audio files, derived from track file paths.
class FolderSummary {
  const FolderSummary({
    required this.path,
    required this.name,
    required this.trackCount,
  });

  final String path;
  final String name;
  final int trackCount;
}

/// Measured listening time for one track, from [ListeningSessions].
class TrackListeningStat {
  const TrackListeningStat({required this.track, required this.listenedMs});

  final Track track;
  final int listenedMs;
}

@DriftDatabase(tables: [
  Tracks,
  Playlists,
  PlaylistTracks,
  PlaybackHistory,
  ListeningSessions,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(tracks, tracks.coverArtPath);
        }
        if (from < 3) {
          await m.addColumn(tracks, tracks.genre);
        }
        if (from < 4) {
          await m.createTable(playlists);
          await m.createTable(playlistTracks);
        }
        if (from < 5) {
          await m.createTable(playbackHistory);
        }
        if(from < 6) {
          await m.addColumn(tracks, tracks.isDeleted);
        }
        if (from < 7) {
          await m.addColumn(tracks, tracks.trackNumber);
          await m.addColumn(tracks, tracks.discNumber);
          await m.addColumn(tracks, tracks.year);
          await m.addColumn(tracks, tracks.dateAdded);
          await m.addColumn(tracks, tracks.totalPlayCount);
          await m.addColumn(tracks, tracks.lastPlayed);
          await m.addColumn(tracks, tracks.isFavorite);
          await m.addColumn(playlistTracks, playlistTracks.position);
          await m.createTable(listeningSessions);

          // Play counts existed only as history rows until now; rebuild them
          // so "Most played" and "Recently played" work from day one.
          await customStatement('''
            UPDATE tracks SET
              total_play_count =
                (SELECT COUNT(*) FROM playback_history h WHERE h.track_id = tracks.id),
              last_played =
                (SELECT MAX(h.played_at) FROM playback_history h WHERE h.track_id = tracks.id)
          ''');

          // Every existing playlist row landed on position 0; give them the
          // order they were inserted in.
          await customStatement('''
            UPDATE playlist_tracks SET position = (
              SELECT COUNT(*) FROM playlist_tracks older
              WHERE older.playlist_id = playlist_tracks.playlist_id
                AND older.rowid < playlist_tracks.rowid
            )
          ''');
        }
      },
    );
  }

  // -------------------------------------------------------------------------
  // Library
  // -------------------------------------------------------------------------

  /// Active library rows, filtered and ordered in SQL.
  Stream<List<Track>> watchLibrary({
    String search = '',
    LibrarySort sort = LibrarySort.title,
  }) {
    final query = select(tracks)..where((t) => t.isDeleted.equals(false));

    if (search.trim().isNotEmpty) {
      final needle = '%${search.trim()}%';
      query.where((t) =>
          t.title.like(needle) | t.artist.like(needle) | t.album.like(needle));
    }

    switch (sort) {
      case LibrarySort.title:
        query.orderBy(
            [(t) => OrderingTerm.asc(t.title.collate(Collate.noCase))]);
      case LibrarySort.artist:
        query.orderBy([
          (t) => OrderingTerm.asc(t.artist.collate(Collate.noCase)),
          (t) => OrderingTerm.asc(t.album.collate(Collate.noCase)),
          (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
        ]);
      case LibrarySort.dateAdded:
        query.orderBy([
          (t) => OrderingTerm.desc(t.dateAdded),
          (t) => OrderingTerm.desc(t.id),
        ]);
      case LibrarySort.playCount:
        query.orderBy([
          (t) => OrderingTerm.desc(t.totalPlayCount),
          (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
        ]);
    }

    return query.watch();
  }

  Future<Track?> trackById(int id) =>
      (select(tracks)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Live row for one track, so a screen holding a Track snapshot (the player
  /// bar, for instance) still reflects favourite and tag edits.
  Stream<Track?> watchTrackById(int id) =>
      (select(tracks)..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// Edit tags in the library. Only non-absent fields are written, so a caller
  /// can update one field without clobbering the rest.
  Future<void> updateTrackTags(
    int trackId, {
    Value<String> title = const Value.absent(),
    Value<String> artist = const Value.absent(),
    Value<String> album = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    Value<int?> trackNumber = const Value.absent(),
    Value<int?> discNumber = const Value.absent(),
    Value<int?> year = const Value.absent(),
  }) {
    return (update(tracks)..where((t) => t.id.equals(trackId))).write(
      TracksCompanion(
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        trackNumber: trackNumber,
        discNumber: discNumber,
        year: year,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Favorites and smart lists
  // -------------------------------------------------------------------------

  Future<void> setFavorite(int trackId, bool favorite) =>
      (update(tracks)..where((t) => t.id.equals(trackId)))
          .write(TracksCompanion(isFavorite: Value(favorite)));

  Stream<List<Track>> watchFavorites() {
    return (select(tracks)
          ..where((t) => t.isDeleted.equals(false) & t.isFavorite.equals(true))
          ..orderBy([
            (t) => OrderingTerm.asc(t.artist.collate(Collate.noCase)),
            (t) => OrderingTerm.asc(t.album.collate(Collate.noCase)),
            (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
          ]))
        .watch();
  }

  Stream<List<Track>> watchRecentlyAdded({int limit = 100}) {
    return (select(tracks)
          ..where((t) => t.isDeleted.equals(false) & t.dateAdded.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)])
          ..limit(limit))
        .watch();
  }

  Stream<List<Track>> watchRecentlyPlayed({int limit = 100}) {
    return (select(tracks)
          ..where((t) => t.isDeleted.equals(false) & t.lastPlayed.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.lastPlayed)])
          ..limit(limit))
        .watch();
  }

  Stream<List<Track>> watchMostPlayed({int limit = 100}) {
    return (select(tracks)
          ..where((t) =>
              t.isDeleted.equals(false) & t.totalPlayCount.isBiggerThanValue(0))
          ..orderBy([
            (t) => OrderingTerm.desc(t.totalPlayCount),
            (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
          ])
          ..limit(limit))
        .watch();
  }

  // -------------------------------------------------------------------------
  // Albums / artists / folders
  // -------------------------------------------------------------------------

  /// Albums are grouped by album name only. Grouping by (album, artist) would
  /// split compilations and albums with featured guests into one row per
  /// artist, so the artist shown is the single artist when the album has one
  /// and 'Various artists' otherwise.
  Stream<List<AlbumSummary>> watchAlbums({String search = ''}) {
    final count = tracks.id.count();
    final totalMs = tracks.durationMs.sum();
    final art = tracks.coverArtPath.max();
    final anyArtist = tracks.artist.min();
    final artistCount = tracks.artist.count(distinct: true);

    final query = selectOnly(tracks)
      ..addColumns([tracks.album, count, totalMs, art, anyArtist, artistCount])
      ..where(tracks.isDeleted.equals(false))
      ..groupBy([tracks.album])
      ..orderBy([OrderingTerm.asc(tracks.album.collate(Collate.noCase))]);

    if (search.trim().isNotEmpty) {
      final needle = '%${search.trim()}%';
      query.where(tracks.album.like(needle) | tracks.artist.like(needle));
    }

    return query.map((row) {
      final distinctArtists = row.read(artistCount) ?? 0;
      return AlbumSummary(
        album: row.read(tracks.album) ?? '',
        artist:
            distinctArtists > 1 ? 'Various artists' : (row.read(anyArtist) ?? ''),
        trackCount: row.read(count) ?? 0,
        totalMs: row.read(totalMs) ?? 0,
        coverArtPath: row.read(art),
      );
    }).watch();
  }

  Stream<List<ArtistSummary>> watchArtists({String search = ''}) {
    final count = tracks.id.count();
    final albumCount = tracks.album.count(distinct: true);
    final totalMs = tracks.durationMs.sum();
    final art = tracks.coverArtPath.max();

    final query = selectOnly(tracks)
      ..addColumns([tracks.artist, count, albumCount, totalMs, art])
      ..where(tracks.isDeleted.equals(false))
      ..groupBy([tracks.artist])
      ..orderBy([OrderingTerm.asc(tracks.artist.collate(Collate.noCase))]);

    if (search.trim().isNotEmpty) {
      query.where(tracks.artist.like('%${search.trim()}%'));
    }

    return query
        .map((row) => ArtistSummary(
              artist: row.read(tracks.artist) ?? '',
              trackCount: row.read(count) ?? 0,
              albumCount: row.read(albumCount) ?? 0,
              totalMs: row.read(totalMs) ?? 0,
              coverArtPath: row.read(art),
            ))
        .watch();
  }

  /// Album running order: disc, then track number, falling back to title for
  /// files whose tags carry no numbering.
  Stream<List<Track>> watchAlbumTracks(String album) {
    return (select(tracks)
          ..where((t) => t.isDeleted.equals(false) & t.album.equals(album))
          ..orderBy([
            (t) => OrderingTerm.asc(t.discNumber),
            (t) => OrderingTerm.asc(t.trackNumber),
            (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
          ]))
        .watch();
  }

  Stream<List<Track>> watchArtistTracks(String artist) {
    return (select(tracks)
          ..where((t) => t.isDeleted.equals(false) & t.artist.equals(artist))
          ..orderBy([
            (t) => OrderingTerm.asc(t.album.collate(Collate.noCase)),
            (t) => OrderingTerm.asc(t.discNumber),
            (t) => OrderingTerm.asc(t.trackNumber),
            (t) => OrderingTerm.asc(t.title.collate(Collate.noCase)),
          ]))
        .watch();
  }

  /// Grouped in Dart rather than SQL: SQLite has no dirname, and doing it here
  /// handles both path separators consistently.
  Stream<List<FolderSummary>> watchFolders() {
    final query = select(tracks)..where((t) => t.isDeleted.equals(false));
    return query.watch().map((rows) {
      final counts = <String, int>{};
      for (final row in rows) {
        final dir = p.dirname(row.filePath);
        counts[dir] = (counts[dir] ?? 0) + 1;
      }
      final folders = [
        for (final entry in counts.entries)
          FolderSummary(
            path: entry.key,
            name: p.basename(entry.key),
            trackCount: entry.value,
          ),
      ];
      folders
          .sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      return folders;
    });
  }

  Stream<List<Track>> watchFolderTracks(String folderPath) {
    final query = select(tracks)..where((t) => t.isDeleted.equals(false));
    return query.watch().map((rows) {
      final inFolder = [
        for (final row in rows)
          if (p.dirname(row.filePath) == folderPath) row,
      ];
      inFolder.sort((a, b) {
        final disc = (a.discNumber ?? 0).compareTo(b.discNumber ?? 0);
        if (disc != 0) return disc;
        final track = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
        if (track != 0) return track;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
      return inFolder;
    });
  }

  // -------------------------------------------------------------------------
  // Removed tracks (soft-deleted)
  // -------------------------------------------------------------------------

  Stream<List<Track>> watchDeletedTracks() {
    return (select(tracks)
          ..where((t) => t.isDeleted.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.title.collate(Collate.noCase))]))
        .watch();
  }

  Future<void> restoreTrack(int trackId) =>
      (update(tracks)..where((t) => t.id.equals(trackId)))
          .write(const TracksCompanion(isDeleted: Value(false)));

  /// Permanently drop a library row and everything referencing it. Does not
  /// touch the audio file on disk.
  Future<void> purgeTrack(int trackId) async {
    await transaction(() async {
      await (delete(playlistTracks)..where((pt) => pt.trackId.equals(trackId)))
          .go();
      await (delete(playbackHistory)..where((h) => h.trackId.equals(trackId)))
          .go();
      await (delete(listeningSessions)..where((s) => s.trackId.equals(trackId)))
          .go();
      await (delete(tracks)..where((t) => t.id.equals(trackId))).go();
    });
  }

  Future<int> emptyTrash() async {
    final removed =
        await (select(tracks)..where((t) => t.isDeleted.equals(true))).get();
    for (final track in removed) {
      await purgeTrack(track.id);
    }
    return removed.length;
  }

  // -------------------------------------------------------------------------
  // Play tracking
  // -------------------------------------------------------------------------

  /// Logs a play: a history row for the stats, plus the running count and
  /// last-played stamp the smart lists sort on.
  Future<void> recordPlay(int trackId) async {
    await transaction(() async {
      await into(playbackHistory).insert(
        PlaybackHistoryCompanion.insert(
          trackId: trackId,
          playedAt: DateTime.now(),
        ),
      );
      await (update(tracks)..where((t) => t.id.equals(trackId))).write(
        TracksCompanion.custom(
          totalPlayCount: tracks.totalPlayCount + const Constant(1),
          lastPlayed: Variable<DateTime>(DateTime.now()),
        ),
      );
    });
  }

  Future<void> clearPlayHistory() async {
    await transaction(() async {
      await delete(playbackHistory).go();
      await delete(listeningSessions).go();
      await update(tracks).write(const TracksCompanion(
        totalPlayCount: Value(0),
        lastPlayed: Value(null),
      ));
    });
  }

  /// Opens a row for the stretch of [trackId] about to be played and returns
  /// its id; the caller tops up [saveListenedMs] as audio actually comes out.
  Future<int> startListeningSession(int trackId) => into(listeningSessions)
      .insert(ListeningSessionsCompanion(trackId: Value(trackId)));

  /// Absolute value, not a delta — the caller owns the running total, so a
  /// dropped write costs precision rather than corrupting the count.
  Future<void> saveListenedMs(int sessionId, int listenedMs) =>
      (update(listeningSessions)..where((s) => s.id.equals(sessionId)))
          .write(ListeningSessionsCompanion(listenedMs: Value(listenedMs)));

  Expression<bool> _listenedInRange(DateTime? from, DateTime? to) {
    Expression<bool> expr = const Constant(true);
    if (from != null) {
      expr = expr & listeningSessions.startedAt.isBiggerOrEqualValue(from);
    }
    if (to != null) {
      expr = expr & listeningSessions.startedAt.isSmallerThanValue(to);
    }
    return expr;
  }

  /// Tracks by measured listening time. Unlike the play-count leaderboards
  /// this counts the audio that actually played, so a track left on repeat
  /// outranks one that was started and skipped many times.
  Stream<List<TrackListeningStat>> watchTracksByListeningTime({
    DateTime? from,
    DateTime? to,
    int limit = 10,
  }) {
    final listened = listeningSessions.listenedMs.sum();
    final query = select(tracks).join([
      innerJoin(
        listeningSessions,
        listeningSessions.trackId.equalsExp(tracks.id),
        useColumns: false,
      ),
    ])
      ..addColumns([listened])
      ..where(_listenedInRange(from, to))
      ..groupBy([tracks.id])
      ..orderBy([OrderingTerm.desc(listened)])
      ..limit(limit);
    return query
        .map((row) => TrackListeningStat(
              track: row.readTable(tracks),
              listenedMs: row.read(listened) ?? 0,
            ))
        .watch();
  }

  /// Measured counterpart to the play-count based total listening time.
  Stream<int> watchTotalListenedMs({DateTime? from, DateTime? to}) {
    final total = listeningSessions.listenedMs.sum();
    final query = selectOnly(listeningSessions)
      ..addColumns([total])
      ..where(_listenedInRange(from, to));
    return query.map((row) => row.read(total) ?? 0).watchSingle();
  }

  // -------------------------------------------------------------------------
  // Playlists
  // -------------------------------------------------------------------------

  Future<void> renamePlaylist(int id, String name) =>
      (update(playlists)..where((pl) => pl.id.equals(id)))
          .write(PlaylistsCompanion(name: Value(name)));

  /// Playlist contents in their manual order.
  Stream<List<Track>> watchPlaylistTracks(int playlistId) {
    final query = select(playlistTracks).join([
      innerJoin(tracks, tracks.id.equalsExp(playlistTracks.trackId)),
    ])
      ..where(playlistTracks.playlistId.equals(playlistId) &
          tracks.isDeleted.equals(false))
      ..orderBy([OrderingTerm.asc(playlistTracks.position)]);
    return query.map((row) => row.readTable(tracks)).watch();
  }

  /// Appends to the end of the playlist. Existing members are left alone.
  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    await transaction(() async {
      final maxPos = playlistTracks.position.max();
      final query = selectOnly(playlistTracks)
        ..addColumns([maxPos])
        ..where(playlistTracks.playlistId.equals(playlistId));
      final current = await query.map((row) => row.read(maxPos)).getSingle();
      await into(playlistTracks).insert(
        PlaylistTracksCompanion(
          playlistId: Value(playlistId),
          trackId: Value(trackId),
          position: Value((current ?? -1) + 1),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await (delete(playlistTracks)
          ..where((pt) =>
              pt.playlistId.equals(playlistId) & pt.trackId.equals(trackId)))
        .go();
    await _normalizePositions(playlistId);
  }

  /// Persist a full reorder: [orderedTrackIds] is the new order.
  Future<void> reorderPlaylist(int playlistId, List<int> orderedTrackIds) {
    return transaction(() async {
      for (var i = 0; i < orderedTrackIds.length; i++) {
        await (update(playlistTracks)
              ..where((pt) =>
                  pt.playlistId.equals(playlistId) &
                  pt.trackId.equals(orderedTrackIds[i])))
            .write(PlaylistTracksCompanion(position: Value(i)));
      }
    });
  }

  Future<void> _normalizePositions(int playlistId) async {
    final rows = await (select(playlistTracks)
          ..where((pt) => pt.playlistId.equals(playlistId))
          ..orderBy([(pt) => OrderingTerm.asc(pt.position)]))
        .get();
    await transaction(() async {
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].position != i) {
          await (update(playlistTracks)
                ..where((pt) =>
                    pt.playlistId.equals(playlistId) &
                    pt.trackId.equals(rows[i].trackId)))
              .write(PlaylistTracksCompanion(position: Value(i)));
        }
      }
    });
  }
}

// --- CONNECTION LOGIC ---

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final docsFolder = await getApplicationDocumentsDirectory();
    
    // 1. Define the new Electrowave directory
    final appFolder = Directory(p.join(docsFolder.path, 'Electrowave'));
    
    // 2. Create the directory if it doesn't exist yet
    if (!await appFolder.exists()) {
      await appFolder.create(recursive: true);
    }

    final newDbFile = File(p.join(appFolder.path, 'local_player_db.sqlite'));
    final oldDbFile = File(p.join(docsFolder.path, 'local_player_db.sqlite'));

    // 3. Auto-Migration: Move the old database to the new folder if it exists
    if (await oldDbFile.exists() && !await newDbFile.exists()) {
      await oldDbFile.rename(newDbFile.path);
    }

    return NativeDatabase.createInBackground(newDbFile);
  });
}