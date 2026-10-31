import 'package:electrowave/features/player/services/audio_file_info.dart';
import 'package:electrowave/core/local_log.dart';
import 'dart:io';
import 'support/audio_fixture.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:electrowave/core/app_paths.dart';
import 'package:electrowave/core/database/app_database.dart';
import 'package:electrowave/core/smart_rules.dart';
import 'package:electrowave/features/library/services/file_exchange.dart';
import 'package:electrowave/features/library/services/loudness_scanner.dart';
import 'package:electrowave/features/player/services/metadata_scanner.dart';
import 'package:electrowave/features/settings/services/backup_service.dart';

void main() {
  late Directory root;
  late AppDatabase db;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('electrowave-scan-test-');
    overrideAppDataDirectory(root);
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    await LocalLog.flush();
    overrideAppDataDirectory(null);
    await root.delete(recursive: true);
  });

  test(
    'scanner adds once, refreshes changes, flags missing, and preserves deliberate removals',
    () async {
      final music = await Directory(p.join(root.path, 'music')).create();
      final file = await writeWav(p.join(music.path, 'song.wav'));
      final events = <ScanProgress>[];
      final scanner = MetadataScanner(db, onProgress: events.add);
      await scanner.scanPaths([music.path]);
      await scanner.scanPaths([music.path]);
      var rows = await db.select(db.tracks).get();
      expect(rows.length, 1);
      expect(rows.single.fileSize, 16044);
      await db.softDeleteMany([rows.single.id]);
      await scanner.scanPaths([music.path]);
      expect((await db.trackById(rows.single.id))!.isDeleted, true);
      await scanner.scanPaths([music.path], reviveDeleted: true);
      expect((await db.trackById(rows.single.id))!.isDeleted, false);
      await file.delete();
      await scanner.scanPaths([music.path]);
      expect((await db.trackById(rows.single.id))!.isMissing, true);
      await writeWav(file.path);
      await scanner.scanPaths([music.path]);
      rows = await db.select(db.tracks).get();
      expect(rows.single.isMissing, false);
      expect(describeAudioFile(file.path), contains('16-bit'));
      expect(events.last.running, false);
      expect(events.last.processed, 1);
    },
  );

  test(
    'cancelled scans stop without treating undiscovered songs as deleted',
    () async {
      final music = await Directory(p.join(root.path, 'music')).create();
      for (var i = 0; i < 6; i++) {
        await writeWav(p.join(music.path, '$i.wav'));
      }
      late MetadataScanner scanner;
      ScanProgress? last;
      scanner = MetadataScanner(
        db,
        onProgress: (event) {
          last = event;
          if (event.processed == 2) scanner.cancel();
        },
      );
      await scanner.scanPaths([music.path]);
      expect((await db.select(db.tracks).get()).length, 2);
      expect(last!.cancelled, true);
    },
  );

  test(
    'M3U8 imports relative local paths, skips network URLs and round trips order',
    () async {
      final a = await writeWav(p.join(root.path, 'music', 'a.wav')),
          b = await writeWav(p.join(root.path, 'music', 'b.wav'));
      final file = File(p.join(root.path, 'Mix.m3u8'));
      await file.writeAsString(
        '\uFEFF#EXTM3U\n# comment\nmusic/b.wav\nhttps://example.test/stream\nmusic/a.wav\nmissing.wav\n',
      );
      final exchange = FileExchange(db);
      final result = await exchange.importPlaylist(file.path);
      expect(result.imported, 2);
      expect(result.skipped, 1);
      final tracks = await db.watchPlaylistTracks(result.playlistId).first;
      expect(tracks.map((t) => t.filePath), [b.path, a.path]);
      if (Platform.isWindows) {
        expect(FileExchange.parseM3u(a.path, file.path), [a.path]);
      }
      final output = p.join(root.path, 'Export.m3u8');
      await exchange.exportPlaylist(output, tracks);
      expect(FileExchange.parseM3u(await File(output).readAsString(), output), [
        b.path,
        a.path,
      ]);
    },
  );

  test(
    'CSV exports measured listening and escapes formulas and quotes',
    () async {
      final id = await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              filePath: '/a.flac',
              title: '=BAD,"value"',
              artist: 'Artist',
              album: 'Album',
              durationMs: 600000,
            ),
          );
      final session = await db.startListeningSession(id);
      await db.saveListenedMs(session, 10000);
      await db.recordPlay(id);
      final file = File(p.join(root.path, 'stats.csv'));
      await FileExchange(db).exportStats(file.path);
      final text = await file.readAsString();
      expect(text, contains('"10.0"'));
      expect(text, contains('"\'=BAD,""value"""'));
      expect(text, contains('Listening seconds'));
    },
  );

  test(
    'repair uses artist/album suffix and refuses ambiguous filenames',
    () async {
      final first = await writeWav(
        p.join(root.path, 'Artist A', 'Album', '01.wav'),
      );
      await writeWav(p.join(root.path, 'Artist B', 'Album', '01.wav'));
      final id = await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              filePath: 'Z:/old/Artist A/Album/01.wav',
              title: 'Intro',
              artist: 'Artist A',
              album: 'Album',
              durationMs: 0,
            ),
          );
      final ambiguous = await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              filePath: 'Z:/unknown/01.wav',
              title: 'Intro',
              artist: 'Unknown',
              album: 'Album',
              durationMs: 0,
            ),
          );
      expect(
        await BackupService(directory: root).relocateLibrary(root.path, db),
        1,
      );
      expect((await db.trackById(id))!.filePath, first.path);
      expect((await db.trackById(ambiguous))!.filePath, 'Z:/unknown/01.wav');
    },
  );

  test(
    'smart rules update with plays and ratings and duplicate matching uses duration tolerance',
    () async {
      final a = await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              filePath: '/a',
              title: 'Song',
              artist: 'Artist',
              album: 'Album',
              durationMs: 100000,
              genre: const Value('Rock'),
              dateAdded: Value(DateTime(2026)),
            ),
          );
      final b = await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              filePath: '/b',
              title: ' song ',
              artist: 'ARTIST',
              album: 'Album',
              durationMs: 101500,
            ),
          );
      final rules = SmartRules.decode(
        const SmartRules(
          genre: 'Rock',
          minimumPlays: 1,
          minimumRating: 4,
          addedSinceYear: 2026,
        ).encode(),
      );
      expect(await db.watchRules(rules).first, isEmpty);
      await db.recordPlay(a);
      await db.setRating(a, 4);
      expect((await db.watchRules(rules).first).map((t) => t.id), [a]);
      final duplicates = findDuplicates(await db.watchLibrary().first);
      expect(duplicates.single.map((t) => t.id).toSet(), {a, b});
      expect(
        LoudnessScanner.parseLoudness('I: -12.0 LUFS\nI: -23.5 LUFS'),
        5.5,
      );
      expect(LoudnessScanner.parseLoudness('I: -70.0 LUFS'), null);
      expect(
        kAudioExtensions,
        containsAll([
          '.opus',
          '.aac',
          '.aiff',
          '.wma',
          '.ape',
          '.wv',
          '.mka',
          '.dsf',
        ]),
      );
    },
  );
}
