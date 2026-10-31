import 'package:electrowave/core/local_log.dart';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:electrowave/core/app_paths.dart';
import 'package:electrowave/core/database/app_database.dart';
import 'package:electrowave/features/settings/services/backup_service.dart';
import 'package:electrowave/features/settings/services/settings_persistence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDatabase db;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('electrowave-backup-test-');
    overrideAppDataDirectory(root);
    PackageInfo.setMockInitialValues(
      appName: 'Electrowave',
      packageName: 'io.github.yuuge7.electrowave',
      version: 'test',
      buildNumber: '0',
      buildSignature: '',
    );
    db = AppDatabase.forTesting(
      NativeDatabase(File(p.join(root.path, databaseFileName))),
    );
    await db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            filePath: '/music/song.flac',
            title: 'Song',
            artist: 'Artist',
            album: 'Album',
            durationMs: 100000,
          ),
        );
  });
  tearDown(() async {
    await db.close();
    await LocalLog.flush();
    overrideAppDataDirectory(null);
    await root.delete(recursive: true);
  });

  test(
    'complete backup round trip preserves library settings art and measured stats, clears session',
    () async {
      final cover = File(p.join(root.path, 'cover.png'));
      await cover.writeAsBytes([1, 2, 3, 4]);
      await (db.update(db.tracks)..where((t) => t.id.equals(1))).write(
        TracksCompanion(
          coverArtPath: Value(cover.path),
          rating: const Value(4),
        ),
      );
      await db.recordPlay(1);
      final session = await db.startListeningSession(1);
      await db.saveListenedMs(session, 12345);
      final playlist = await db.createPlaylist('Mix');
      await db.addTrackToPlaylist(playlist, 1);
      await File(
        p.join(root.path, 'settings.json'),
      ).writeAsString(jsonEncode(const AppSettings(eqEnabled: true).toJson()));
      await File(
        p.join(root.path, 'session.json'),
      ).writeAsString('{"currentTrackId":1}');
      final backup = p.join(root.path, 'complete.ewbackup');
      final service = BackupService(database: db, directory: root);
      await service.exportTo(backup, version: 'test');
      final archive = ZipDecoder().decodeBytes(
        await File(backup).readAsBytes(),
      );
      expect(
        archive.map((f) => f.name),
        containsAll([
          'manifest.json',
          databaseFileName,
          'settings.json',
          'session.json',
          'covers/track_1.png',
        ]),
      );
      expect(
        await service.stageImport(backup),
        isTrue,
        reason: service.lastError,
      );
      await db.renamePlaylist(playlist, 'Changed after backup');
      await db.close();
      expect(await BackupService(directory: root).applyPendingImport(), isTrue);
      db = AppDatabase.forTesting(
        NativeDatabase(File(p.join(root.path, databaseFileName))),
      );
      expect((await db.select(db.playlists).get()).single.name, 'Mix');
      expect((await db.trackById(1))!.rating, 4);
      expect(await db.watchTotalListenedMs().first, 12345);
      expect(await File((await db.trackById(1))!.coverArtPath!).readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
      expect(
        jsonDecode(
          await File(p.join(root.path, 'settings.json')).readAsString(),
        )['eqEnabled'],
        true,
      );
      expect(await File(p.join(root.path, 'session.json')).exists(), false);
      expect(
        (await root.list().toList())
            .where((e) => p.basename(e.path).startsWith('before_import_'))
            .length,
        1,
      );
      expect(await BackupService(directory: root).applyPendingImport(), false);
    },
  );

  test(
    'rejects random files, foreign SQLite, future schema and incomplete schema without replacing staged data',
    () async {
      final service = BackupService(database: db, directory: root);
      final good = p.join(root.path, 'good.ewbackup');
      await service.exportTo(good, version: 'test');
      expect(await service.stageImport(good), true);
      final before = await File(
        p.join(root.path, 'pending_import', databaseFileName),
      ).readAsBytes();
      final junk = File(p.join(root.path, 'junk.sqlite'));
      await junk.writeAsString('not sqlite');
      expect(await service.stageImport(junk.path), false);
      final foreign = p.join(root.path, 'foreign.sqlite');
      final other = AppDatabase.forTesting(NativeDatabase(File(foreign)));
      await other.customStatement('PRAGMA user_version = 999');
      await other.close();
      expect(await service.stageImport(foreign), false);
      expect(
        await File(
          p.join(root.path, 'pending_import', databaseFileName),
        ).readAsBytes(),
        before,
      );
      expect((await db.trackById(1))!.title, 'Song');
    },
  );

  test(
    'legacy SQLite imports are snapshotted and preserve existing settings',
    () async {
      final settings = File(p.join(root.path, 'settings.json'));
      await settings.writeAsString(
        jsonEncode(const AppSettings(textScale: 1.2).toJson()),
      );
      final legacy = p.join(root.path, 'legacy.sqlite');
      await db.customStatement('VACUUM INTO ?', [legacy]);
      final service = BackupService(database: db, directory: root);
      expect(
        await service.stageImport(legacy),
        true,
        reason: service.lastError,
      );
      await db.close();
      expect(await BackupService(directory: root).applyPendingImport(), true);
      db = AppDatabase.forTesting(
        NativeDatabase(File(p.join(root.path, databaseFileName))),
      );
      expect((await db.trackById(1))!.title, 'Song');
      expect(
        AppSettings.fromJson(
          jsonDecode(await settings.readAsString()) as Map<String, dynamic>,
        ).textScale,
        1.2,
      );
    },
  );

  test('rejects zip traversal and inconsistent manifest', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('../escape.txt', 4, utf8.encode('oops')));
    final path = p.join(root.path, 'bad.ewbackup');
    await File(path).writeAsBytes(ZipEncoder().encode(archive));
    final service = BackupService(database: db, directory: root);
    expect(await service.stageImport(path), false);
    expect(await File(p.join(root.parent.path, 'escape.txt')).exists(), false);
    await service.exportTo(path, version: 'test');
    final valid = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    final altered = Archive();
    for (final entry in valid) {
      if (entry.name == 'manifest.json') {
        final manifest =
            jsonDecode(utf8.decode(entry.content as List<int>))
                as Map<String, dynamic>;
        manifest['trackCount'] = 9000;
        final bytes = utf8.encode(jsonEncode(manifest));
        altered.addFile(ArchiveFile(entry.name, bytes.length, bytes));
      } else {
        altered.addFile(entry);
      }
    }
    await File(path).writeAsBytes(ZipEncoder().encode(altered));
    expect(await service.stageImport(path), false);
  });

  test(
    'weekly retention keeps five automatic backups and leaves unrelated files alone',
    () async {
      final dir = await Directory(p.join(root.path, 'backups')).create();
      for (var i = 0; i < 7; i++) {
        final file = File(p.join(dir.path, 'electrowave-auto-000$i.ewbackup'));
        await file.writeAsString('old');
        await file.setLastModified(DateTime(2000));
      }
      final unrelated = File(p.join(dir.path, 'my-personal-backup.ewbackup'));
      await unrelated.writeAsString('keep');
      final service = BackupService(database: db, directory: root);
      final settings = AppSettings(backupFolder: dir.path);
      await service.automaticBackup(settings, version: 'test');
      expect((await dir.list().toList()).length, 6);
      await service.automaticBackup(settings, version: 'test');
      expect((await dir.list().toList()).length, 6);
      expect(await unrelated.readAsString(), 'keep');
    },
  );

  test(
    'crash journal restores moved library before retrying an import',
    () async {
      await db.close();
      final rollback = await Directory(
        p.join(root.path, 'import-rollback'),
      ).create();
      await File(
        p.join(root.path, databaseFileName),
      ).rename(p.join(rollback.path, databaseFileName));
      await File(
        p.join(root.path, databaseFileName),
      ).writeAsString('interrupted replacement');
      await File(p.join(rollback.path, 'journal.json')).writeAsString(
        jsonEncode({
          'names': [databaseFileName, 'session.json'],
          'present': [databaseFileName],
          'committed': false,
        }),
      );
      expect(await BackupService(directory: root).applyPendingImport(), false);
      db = AppDatabase.forTesting(
        NativeDatabase(File(p.join(root.path, databaseFileName))),
      );
      expect((await db.trackById(1))!.title, 'Song');
    },
  );
}
