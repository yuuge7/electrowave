import 'dart:math';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:electrowave/core/database/app_database.dart';
import 'package:electrowave/features/player/providers/player_provider.dart';
import 'package:electrowave/features/player/providers/queue_provider.dart';

class FailingMigration extends AppDatabase {
  FailingMigration(super.e) : super.forTesting();
  @override
  Future<void> customStatement(String statement, [List<dynamic>? args]) {
    if (statement.startsWith('CREATE UNIQUE INDEX')) {
      throw StateError('Simulated migration interruption');
    }
    return super.customStatement(statement, args);
  }
}

Track track(int id, {bool missing = false}) => Track(
  id: id,
  filePath: '/$id.flac',
  title: '$id',
  artist: 'Artist',
  album: 'Album',
  durationMs: 100000,
  isDeleted: false,
  isMissing: missing,
  rating: 0,
  totalPlayCount: 0,
  isFavorite: false,
);

Database legacy(int version, {bool duplicates = false}) {
  final raw = sqlite3.openInMemory();
  raw.execute(
    '''CREATE TABLE tracks(id INTEGER PRIMARY KEY AUTOINCREMENT,file_path TEXT NOT NULL,title TEXT NOT NULL,artist TEXT NOT NULL,album TEXT NOT NULL,duration_ms INTEGER NOT NULL
    ${version >= 2 ? ',cover_art_path TEXT' : ''}${version >= 3 ? ',genre TEXT' : ''}${version >= 6 ? ',is_deleted INTEGER NOT NULL DEFAULT 0' : ''}
    ${version >= 7 ? ',track_number INTEGER,disc_number INTEGER,year INTEGER,date_added INTEGER,total_play_count INTEGER NOT NULL DEFAULT 0,last_played INTEGER,is_favorite INTEGER NOT NULL DEFAULT 0' : ''})''',
  );
  raw.execute(
    "INSERT INTO tracks(file_path,title,artist,album,duration_ms) VALUES('/song','Song','Artist','Album',100000)",
  );
  if (duplicates) {
    raw.execute(
      "INSERT INTO tracks(file_path,title,artist,album,duration_ms) VALUES('/song','Copy','Artist','Album',100000)",
    );
  }
  if (version >= 4) {
    raw.execute(
      'CREATE TABLE playlists(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE playlist_tracks(playlist_id INTEGER NOT NULL,track_id INTEGER NOT NULL${version >= 7 ? ',position INTEGER NOT NULL DEFAULT 0' : ''},PRIMARY KEY(playlist_id,track_id))',
    );
    raw.execute("INSERT INTO playlists(id,name) VALUES(1,'Mix')");
    raw.execute(
      'INSERT INTO playlist_tracks(playlist_id,track_id) VALUES(1,1)',
    );
    if (duplicates) {
      raw.execute(
        'INSERT INTO playlist_tracks(playlist_id,track_id) VALUES(1,2)',
      );
    }
  }
  if (version >= 5) {
    raw.execute(
      'CREATE TABLE playback_history(id INTEGER PRIMARY KEY AUTOINCREMENT,track_id INTEGER NOT NULL,played_at INTEGER NOT NULL)',
    );
    raw.execute(
      'INSERT INTO playback_history(track_id,played_at) VALUES(1,1700000000)',
    );
    if (duplicates) {
      raw.execute(
        'INSERT INTO playback_history(track_id,played_at) VALUES(2,1700000010)',
      );
    }
  }
  if (version >= 7) {
    raw.execute(
      'CREATE TABLE listening_sessions(id INTEGER PRIMARY KEY AUTOINCREMENT,track_id INTEGER NOT NULL,started_at INTEGER NOT NULL DEFAULT 0,listened_ms INTEGER NOT NULL DEFAULT 0)',
    );
    raw.execute(
      'INSERT INTO listening_sessions(track_id,listened_ms) VALUES(1,10000)',
    );
    if (duplicates) {
      raw.execute(
        'INSERT INTO listening_sessions(track_id,listened_ms) VALUES(2,20000)',
      );
    }
  }
  raw.execute('PRAGMA user_version=$version');
  return raw;
}

void main() {
  test(
    'failed upgrades roll back schema and duplicate merging together',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'electrowave-migration-',
      );
      final path = '${dir.path}/library.sqlite';
      final source = legacy(7, duplicates: true);
      source.execute('VACUUM INTO ?', [path]);
      source.close();
      final broken = FailingMigration(NativeDatabase(File(path)));
      await expectLater(broken.watchLibrary().first, throwsStateError);
      await broken.close();
      final raw = sqlite3.open(path);
      expect(raw.select('PRAGMA user_version').single.values.first, 7);
      expect(raw.select('SELECT COUNT(*) AS n FROM tracks').single['n'], 2);
      expect(
        raw.select('PRAGMA table_info(tracks)').map((r) => r['name']),
        isNot(contains('album_artist')),
      );
      raw.close();
      final recovered = AppDatabase.forTesting(NativeDatabase(File(path)));
      expect((await recovered.watchLibrary().first).length, 1);
      expect(await recovered.watchTotalListenedMs().first, 30000);
      await recovered.close();
      await dir.delete(recursive: true);
    },
  );
  for (var version = 1; version <= 7; version++) {
    test(
      'upgrades schema $version to current without losing tracks or references',
      () async {
        final db = AppDatabase.forTesting(
          NativeDatabase.opened(legacy(version)),
        );
        addTearDown(db.close);
        expect((await db.watchLibrary().first).single.title, 'Song');
        expect((await db.trackById(1))!.isMissing, false);
        if (version >= 4) {
          expect((await db.watchPlaylistTracks(1).first).single.id, 1);
        }
        if (version >= 5) {
          expect((await db.select(db.playbackHistory).get()).length, 1);
        }
        if (version >= 7) expect(await db.watchTotalListenedMs().first, 10000);
        final indexes = await db
            .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
            .get();
        expect(
          indexes.map((r) => r.read<String>('name')),
          containsAll([
            'tracks_path_unique',
            'history_track_date',
            'sessions_track_date',
          ]),
        );
        await expectLater(
          db
              .into(db.tracks)
              .insert(
                TracksCompanion.insert(
                  filePath: '/song',
                  title: 'Duplicate',
                  artist: 'Artist',
                  album: 'Album',
                  durationMs: 1,
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
      },
    );
  }
  test(
    'deduplication migration merges history, measured time and playlist membership',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.opened(legacy(7, duplicates: true)),
      );
      addTearDown(db.close);
      expect((await db.watchLibrary().first).length, 1);
      expect((await db.watchPlaylistTracks(1).first).length, 1);
      expect(
        (await db.select(db.playbackHistory).get()).map((h) => h.trackId),
        [1, 1],
      );
      expect(await db.watchTotalListenedMs().first, 30000);
      expect((await db.trackById(1))!.totalPlayCount, 2);
    },
  );
  test(
    'queue prioritizes manual entries, skips missing files, and resumes context',
    () {
      final q = QueueState(
        context: [track(1), track(2, missing: true), track(3)],
        contextIndex: 0,
        manualQueue: [track(8, missing: true), track(9)],
      );
      final first = chooseNext(
        q,
        shuffle: false,
        repeat: PlaybackRepeatMode.off,
      )!;
      expect(first.track.id, 9);
      expect(first.queue.contextIndex, 0);
      expect(first.queue.manualQueue, isEmpty);
      expect(
        chooseNext(
          first.queue,
          shuffle: false,
          repeat: PlaybackRepeatMode.off,
        )!.track.id,
        3,
      );
    },
  );
  test(
    'repeat one applies to completion, manual next advances, repeat all wraps',
    () {
      final q = QueueState(context: [track(1), track(2)], contextIndex: 0);
      expect(
        chooseNext(
          q,
          shuffle: false,
          repeat: PlaybackRepeatMode.one,
          current: track(1),
        )!.track.id,
        1,
      );
      expect(
        chooseNext(
          q,
          shuffle: false,
          repeat: PlaybackRepeatMode.one,
          current: track(1),
          completed: false,
        )!.track.id,
        2,
      );
      expect(
        chooseNext(
          q.copyWith(contextIndex: 1),
          shuffle: false,
          repeat: PlaybackRepeatMode.off,
        ),
        null,
      );
      expect(
        chooseNext(
          q.copyWith(contextIndex: 1),
          shuffle: false,
          repeat: PlaybackRepeatMode.all,
        )!.track.id,
        1,
      );
      expect(
        chooseNext(
          q,
          shuffle: true,
          repeat: PlaybackRepeatMode.off,
          random: Random(1),
        )!.track.id,
        2,
      );
    },
  );
  test('queue reorder, clear and restore preserve exact order', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(queueProvider.notifier);
    notifier.setContext([track(1), track(2)], 0);
    notifier.addToQueue(track(3));
    notifier.playNext(track(4));
    final before = container.read(queueProvider);
    expect(before.manualQueue.map((t) => t.id), [4, 3]);
    notifier.reorderQueue(0, 1);
    expect(container.read(queueProvider).manualQueue.map((t) => t.id), [3, 4]);
    notifier.clearQueue();
    expect(container.read(queueProvider).manualQueue, isEmpty);
    notifier.replace(before);
    expect(container.read(queueProvider).manualQueue.map((t) => t.id), [4, 3]);
  });
}
