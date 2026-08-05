import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:electrowave/core/database/app_database.dart';

/// Builds a database exactly as schema version 6 left it: no favourites, no
/// play counts, no track numbering, and playlist membership with no position.
Database _openLegacyDatabase() {
  final raw = sqlite3.openInMemory();

  raw.execute('''
    CREATE TABLE tracks (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      file_path TEXT NOT NULL,
      title TEXT NOT NULL,
      artist TEXT NOT NULL,
      album TEXT NOT NULL,
      duration_ms INTEGER NOT NULL,
      cover_art_path TEXT NULL,
      genre TEXT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1))
    )
  ''');
  raw.execute('''
    CREATE TABLE playlists (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL
    )
  ''');
  raw.execute('''
    CREATE TABLE playlist_tracks (
      playlist_id INTEGER NOT NULL,
      track_id INTEGER NOT NULL,
      PRIMARY KEY (playlist_id, track_id)
    )
  ''');
  raw.execute('''
    CREATE TABLE playback_history (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      track_id INTEGER NOT NULL,
      played_at INTEGER NOT NULL
    )
  ''');

  for (var i = 1; i <= 3; i++) {
    raw.execute(
      'INSERT INTO tracks (id, file_path, title, artist, album, duration_ms) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [i, 'C:/music/track$i.mp3', 'Track $i', 'Artist', 'Album', 180000],
    );
  }

  // Track 1 played twice, track 2 once, track 3 never.
  const day = 86400;
  raw.execute('INSERT INTO playback_history (track_id, played_at) VALUES (1, ?)',
      [1700000000]);
  raw.execute('INSERT INTO playback_history (track_id, played_at) VALUES (1, ?)',
      [1700000000 + day]);
  raw.execute('INSERT INTO playback_history (track_id, played_at) VALUES (2, ?)',
      [1700000000 + 2 * day]);

  raw.execute("INSERT INTO playlists (id, name) VALUES (1, 'Old mix')");
  for (final trackId in [3, 1, 2]) {
    raw.execute(
      'INSERT INTO playlist_tracks (playlist_id, track_id) VALUES (1, ?)',
      [trackId],
    );
  }

  raw.execute('PRAGMA user_version = 6');
  return raw;
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.opened(_openLegacyDatabase()));
  });
  tearDown(() => db.close());

  test('upgrading from v6 keeps the library and backfills the new columns',
      () async {
    // The first query runs the migration.
    final tracks = await db.select(db.tracks).get();
    expect(tracks.length, 3);

    final byId = {for (final track in tracks) track.id: track};

    // Play counts and last-played rebuilt from the existing history rows.
    expect(byId[1]!.totalPlayCount, 2);
    expect(byId[2]!.totalPlayCount, 1);
    expect(byId[3]!.totalPlayCount, 0);
    expect(byId[1]!.lastPlayed, isNotNull);
    expect(byId[3]!.lastPlayed, isNull);

    // New columns exist with sane defaults.
    expect(byId[1]!.isFavorite, isFalse);
    expect(byId[1]!.trackNumber, isNull);
    expect(byId[1]!.dateAdded, isNull);

    // Most played is ordered by the rebuilt counts.
    final mostPlayed = await db.watchMostPlayed().first;
    expect(mostPlayed.map((t) => t.id), [1, 2]);
  });

  test('upgrading from v6 gives playlist rows their insertion order', () async {
    final tracks = await db.watchPlaylistTracks(1).first;

    // Inserted as 3, 1, 2 — positions must preserve that, not collapse to 0.
    expect(tracks.map((t) => t.id), [3, 1, 2]);

    final rows = await db.select(db.playlistTracks).get();
    expect(rows.map((row) => row.position).toList()..sort(), [0, 1, 2]);
  });

  test('the measured listening table is created by the upgrade', () async {
    final session = await db.startListeningSession(1);
    await db.saveListenedMs(session, 12345);

    expect(await db.watchTotalListenedMs().first, 12345);
  });
}
