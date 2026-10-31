import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:drift/drift.dart';
import '../../../core/app_paths.dart';
import '../../../core/local_log.dart';
import '../../../core/database/app_database.dart' as db;
import '../../../main.dart';
import '../../player/services/metadata_scanner.dart';
import 'settings_persistence.dart';

final backupServiceProvider = Provider(
  (ref) => BackupService(database: ref.read(databaseProvider)),
);

class BackupService {
  BackupService({this.database, this.directory});
  final db.AppDatabase? database;
  final Directory? directory;
  String? lastError;
  Future<void>? _automaticPending;
  Future<Directory> get _directory async =>
      directory ?? await appDataDirectory();

  static void validateDatabase(String path) {
    final raw = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
    try {
      if (raw.select('PRAGMA quick_check').single.values.first != 'ok') {
        throw const FormatException('This backup database is damaged.');
      }
      final version =
          raw.select('PRAGMA user_version').single.values.first as int;
      if (version < 1 || version > 8) {
        throw const FormatException('Unsupported Electrowave backup version.');
      }
      final expected = <String, Set<String>>{
        'tracks': {
          'id',
          'file_path',
          'title',
          'artist',
          'album',
          'duration_ms',
        },
        if (version >= 4)
          'playlists': {
            'id',
            'name',
            if (version >= 8) ...{'folder', 'rules_json'},
          },
        if (version >= 4)
          'playlist_tracks': {
            'playlist_id',
            'track_id',
            if (version >= 7) 'position',
          },
        if (version >= 5) 'playback_history': {'id', 'track_id', 'played_at'},
        if (version >= 7)
          'listening_sessions': {'id', 'track_id', 'started_at', 'listened_ms'},
      };
      for (final entry in expected.entries) {
        final columns = raw
            .select('PRAGMA table_info(${entry.key})')
            .map((r) => r['name'] as String)
            .toSet();
        if (!columns.containsAll(entry.value)) {
          throw const FormatException('This is not an Electrowave library.');
        }
      }
      final columns = raw
          .select('PRAGMA table_info(tracks)')
          .map((r) => r['name'] as String)
          .toSet();
      final additions = <int, Set<String>>{
        2: {'cover_art_path'},
        3: {'genre'},
        6: {'is_deleted'},
        7: {
          'track_number',
          'disc_number',
          'year',
          'date_added',
          'total_play_count',
          'last_played',
          'is_favorite',
        },
        8: {
          'album_artist',
          'file_size',
          'modified_ms',
          'is_missing',
          'rating',
          'replay_gain_db',
        },
      };
      for (final e in additions.entries) {
        if (version >= e.key && !columns.containsAll(e.value)) {
          throw const FormatException('The backup schema is incomplete.');
        }
      }
      if (raw
          .select(
            "SELECT name FROM sqlite_master WHERE type IN ('trigger','view')",
          )
          .isNotEmpty) {
        throw const FormatException('Unexpected executable schema in backup.');
      }
    } finally {
      raw.close();
    }
  }

  Future<bool> exportDatabase() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save complete backup',
      fileName:
          'electrowave-backup-${DateTime.now().toIso8601String().substring(0, 10)}.ewbackup',
      type: FileType.custom,
      allowedExtensions: ['ewbackup'],
    );
    if (path == null) return false;
    try {
      await exportTo(path);
      return true;
    } catch (e, st) {
      lastError = '$e';
      LocalLog.write(e, st);
      return false;
    }
  }

  Future<void> exportTo(String destination, {String? version}) async {
    final dir = await _directory;
    for (final name in [
      databaseFileName,
      'settings.json',
      'session.json',
      'window.json',
    ]) {
      if (p.equals(
        p.normalize(p.absolute(destination)),
        p.join(dir.path, name),
      )) {
        throw const FormatException(
          'Choose a separate backup file, not an app data file.',
        );
      }
    }
    final work = await Directory.systemTemp.createTemp('electrowave-export-');
    try {
      final snapshot = File(p.join(work.path, databaseFileName));
      if (database != null) {
        await database!.customStatement('VACUUM INTO ?', [snapshot.path]);
      } else {
        final raw = sql.sqlite3.open(p.join(dir.path, databaseFileName));
        try {
          raw.execute('VACUUM INTO ?', [snapshot.path]);
        } finally {
          raw.close();
        }
      }
      validateDatabase(snapshot.path);
      final raw = sql.sqlite3.open(snapshot.path);
      final archive = Archive();
      var count = 0;
      try {
        count =
            raw.select('SELECT COUNT(*) AS n FROM tracks').single['n'] as int;
        final schema =
            raw.select('PRAGMA user_version').single.values.first as int;
        if (schema >= 2) {
          final rows = raw.select(
            'SELECT id, cover_art_path FROM tracks WHERE cover_art_path IS NOT NULL',
          );
          for (final row in rows) {
            final original = File(row['cover_art_path'] as String);
            // Older libraries may still reference the legacy covers directory.
            final migrated = File(
              p.join(dir.path, 'covers', p.basename(original.path)),
            );
            final file = await original.exists() ? original : migrated;
            if (!await file.exists()) continue;
            final name = 'covers/track_${row['id']}${p.extension(file.path)}';
            final bytes = await file.readAsBytes();
            archive.addFile(ArchiveFile(name, bytes.length, bytes));
            raw.execute('UPDATE tracks SET cover_art_path = ? WHERE id = ?', [
              name,
              row['id'],
            ]);
          }
        }
        final manifest = utf8.encode(
          jsonEncode({
            'format': 'electrowave',
            'version': 1,
            'appVersion': version ?? (await PackageInfo.fromPlatform()).version,
            'schemaVersion': schema,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'trackCount': count,
          }),
        );
        archive.addFile(
          ArchiveFile('manifest.json', manifest.length, manifest),
        );
      } finally {
        raw.close();
      }
      for (final name in [databaseFileName, 'settings.json', 'session.json']) {
        final file = name == databaseFileName
            ? snapshot
            : File(p.join(dir.path, name));
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
        }
      }
      final bytes = await Isolate.run(() => ZipEncoder().encode(archive));
      final temp = File('$destination.tmp');
      await temp.parent.create(recursive: true);
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(destination);
    } finally {
      await work.delete(recursive: true);
    }
  }

  Future<bool> stageImport(String source) async {
    final dir = await _directory;
    final validation = await Directory(
      p.join(dir.path, 'import-validation'),
    ).create(recursive: true);
    final work = await validation.createTemp('stage-');
    try {
      final input = File(source);
      if (await input.length() > 512 * 1024 * 1024) {
        throw const FormatException('Backup exceeds 512 MB.');
      }
      if (['.sqlite', '.db'].contains(p.extension(source).toLowerCase())) {
        validateDatabase(source);
        // Snapshot legacy WAL databases too, rather than copying a live file.
        final raw = sql.sqlite3.open(source, mode: sql.OpenMode.readOnly);
        try {
          raw.execute('VACUUM INTO ?', [p.join(work.path, databaseFileName)]);
        } finally {
          raw.close();
        }
      } else {
        final bytes = await input.readAsBytes();
        final archive = await Isolate.run(
          () => ZipDecoder().decodeBytes(bytes, verify: true),
        );
        var size = 0;
        final seen = <String>{};
        for (final entry in archive) {
          final name = entry.name.replaceAll('\\', '/');
          size += entry.size;
          if (size > 512 * 1024 * 1024 ||
              entry.isSymbolicLink ||
              !seen.add(name) ||
              name.startsWith('/') ||
              name.split('/').contains('..') ||
              name.contains(':') ||
              !(name == 'manifest.json' ||
                  name == databaseFileName ||
                  name == 'settings.json' ||
                  name == 'session.json' ||
                  (name.startsWith('covers/') &&
                      name.split('/').length == 2))) {
            throw const FormatException(
              'Unsafe or unexpected backup contents.',
            );
          }
          if (!entry.isFile) continue;
          final output = File(p.join(work.path, name));
          await output.parent.create(recursive: true);
          await output.writeAsBytes(entry.content as List<int>, flush: true);
        }
        final manifest =
            jsonDecode(
                  await File(p.join(work.path, 'manifest.json')).readAsString(),
                )
                as Map<String, dynamic>;
        if (manifest['format'] != 'electrowave' || manifest['version'] != 1) {
          throw const FormatException('Unknown backup format.');
        }
        final raw = sql.sqlite3.open(
          p.join(work.path, databaseFileName),
          mode: sql.OpenMode.readOnly,
        );
        try {
          if (manifest['schemaVersion'] !=
                  raw.select('PRAGMA user_version').single.values.first ||
              manifest['trackCount'] !=
                  raw.select('SELECT COUNT(*) AS n FROM tracks').single['n']) {
            throw const FormatException(
              'Backup manifest does not match its database.',
            );
          }
        } finally {
          raw.close();
        }
        final settings = File(p.join(work.path, 'settings.json'));
        if (await settings.exists()) {
          AppSettings.fromJson(
            jsonDecode(await settings.readAsString()) as Map<String, dynamic>,
          );
        }
      }
      validateDatabase(p.join(work.path, databaseFileName));
      final pending = Directory(p.join(dir.path, 'pending_import'));
      final old = Directory('${pending.path}.old');
      if (await old.exists()) await old.delete(recursive: true);
      if (await pending.exists()) await pending.rename(old.path);
      await work.rename(pending.path);
      if (await old.exists()) await old.delete(recursive: true);
      return true;
    } catch (e, st) {
      lastError = '$e';
      LocalLog.write(e, st);
      return false;
    } finally {
      if (await work.exists()) await work.delete(recursive: true);
    }
  }

  /// Only called before any database connection is opened. A complete recovery
  /// bundle and rollback copies are retained until the replacement commits.
  Future<bool> applyPendingImport() async {
    final dir = await _directory;
    await _recoverRollback(dir);
    final pending = Directory(p.join(dir.path, 'pending_import'));
    final legacy = File(p.join(dir.path, 'pending_import.sqlite'));
    if (!await pending.exists() && await legacy.exists()) {
      if (!await stageImport(legacy.path)) return false;
      await legacy.delete();
    }
    if (!await pending.exists()) return false;
    validateDatabase(p.join(pending.path, databaseFileName));
    final current = File(p.join(dir.path, databaseFileName));
    if (await current.exists()) {
      await exportTo(
        p.join(
          dir.path,
          'before_import_${DateTime.now().toUtc().millisecondsSinceEpoch}.ewbackup',
        ),
      );
    }
    final rollback = Directory(p.join(dir.path, 'import-rollback'));
    await rollback.create(recursive: true);
    final names = [
      databaseFileName,
      '$databaseFileName-wal',
      '$databaseFileName-shm',
      'session.json',
      if (await File(p.join(pending.path, 'settings.json')).exists())
        'settings.json',
      if (await Directory(p.join(pending.path, 'covers')).exists()) 'covers',
    ];
    // A durable journal makes a killed process recoverable on the next launch.
    final present = <String>[];
    for (final name in names) {
      final path = p.join(dir.path, name);
      if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        present.add(name);
      }
    }
    await File(p.join(rollback.path, 'journal.json')).writeAsString(
      jsonEncode({'names': names, 'present': present, 'committed': false}),
      flush: true,
    );
    try {
      for (final name in present) {
        final path = p.join(dir.path, name);
        if (await FileSystemEntity.isDirectory(path)) {
          await Directory(path).rename(p.join(rollback.path, name));
        } else {
          await File(path).rename(p.join(rollback.path, name));
        }
      }
      for (final name in [databaseFileName, 'settings.json', 'covers']) {
        final path = p.join(pending.path, name);
        if (await FileSystemEntity.isDirectory(path)) {
          await _copyDirectory(
            Directory(path),
            Directory(p.join(dir.path, name)),
          );
        } else if (await File(path).exists()) {
          await File(path).copy(p.join(dir.path, name));
        }
      }
      final raw = sql.sqlite3.open(current.path);
      try {
        final version =
            raw.select('PRAGMA user_version').single.values.first as int;
        if (version >= 2) {
          for (final row in raw.select(
            'SELECT id,cover_art_path FROM tracks WHERE cover_art_path IS NOT NULL',
          )) {
            final path = row['cover_art_path'] as String;
            if (path.startsWith('covers/') && !path.contains('..')) {
              raw.execute('UPDATE tracks SET cover_art_path=? WHERE id=?', [
                p.join(dir.path, path),
                row['id'],
              ]);
            }
          }
        }
      } finally {
        raw.close();
      }
      await File(
        p.join(dir.path, 'import_success.flag'),
      ).writeAsString('1', flush: true);
      await File(p.join(rollback.path, 'journal.json')).writeAsString(
        jsonEncode({'names': names, 'present': present, 'committed': true}),
        flush: true,
      );
    } catch (_) {
      await _recoverRollback(dir);
      rethrow;
    }
    await pending.delete(recursive: true);
    await rollback.delete(recursive: true);
    return true;
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entry in source.list(followLinks: false)) {
      final destination = p.join(target.path, p.basename(entry.path));
      if (entry is File) {
        await entry.copy(destination);
      } else if (entry is Directory) {
        await _copyDirectory(entry, Directory(destination));
      }
    }
  }

  static Future<void> _recoverRollback(Directory dir) async {
    final rollback = Directory(p.join(dir.path, 'import-rollback'));
    final journal = File(p.join(rollback.path, 'journal.json'));
    if (!await journal.exists()) return;
    final data =
        jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
    if (data['committed'] != true) {
      final present = (data['present'] as List).cast<String>();
      for (final name in (data['names'] as List).cast<String>()) {
        final old = p.join(rollback.path, name),
            target = p.join(dir.path, name);
        final saved =
            await FileSystemEntity.type(old) != FileSystemEntityType.notFound;
        // If a rename had not happened yet, its original is still in place.
        if (present.contains(name) && !saved) continue;
        if (await FileSystemEntity.isDirectory(target)) {
          await Directory(target).delete(recursive: true);
        } else if (await File(target).exists()) {
          await File(target).delete();
        }
        if (saved) {
          if (await FileSystemEntity.isDirectory(old)) {
            await Directory(old).rename(target);
          } else {
            await File(old).rename(target);
          }
        }
      }
      final flag = File(p.join(dir.path, 'import_success.flag'));
      if (await flag.exists()) await flag.delete();
    } else {
      final pending = Directory(p.join(dir.path, 'pending_import'));
      if (await pending.exists()) await pending.delete(recursive: true);
    }
    await rollback.delete(recursive: true);
  }

  Future<void> automaticBackup(AppSettings settings, {String? version}) {
    if (_automaticPending != null) return _automaticPending!;
    final work = _automaticBackup(settings, version: version);
    _automaticPending = work;
    return work.whenComplete(() => _automaticPending = null);
  }

  Future<void> _automaticBackup(AppSettings settings, {String? version}) async {
    final folder = settings.backupFolder;
    if (folder == null) return;
    final dir = await Directory(folder).create(recursive: true);
    final backups = await dir
        .list()
        .where(
          (e) =>
              e is File &&
              p.basename(e.path).startsWith('electrowave-auto-') &&
              e.path.endsWith('.ewbackup'),
        )
        .cast<File>()
        .toList();
    backups.sort((a, b) => b.path.compareTo(a.path));
    if (backups.isEmpty ||
        DateTime.now().difference(await backups.first.lastModified()).inDays >=
            7) {
      final name =
          'electrowave-auto-${DateTime.now().toUtc().millisecondsSinceEpoch}.ewbackup';
      await exportTo(p.join(dir.path, name), version: version);
      backups.insert(0, File(p.join(dir.path, name)));
    }
    for (final file in backups.skip(5)) {
      await file.delete();
    }
  }

  Future<int> relocateLibrary(
    String newRootPath,
    db.AppDatabase database,
  ) async {
    final candidates = <String, List<File>>{};
    await for (final entry in Directory(
      newRootPath,
    ).list(recursive: true, followLinks: false)) {
      if (entry is File &&
          kAudioExtensions.contains(p.extension(entry.path).toLowerCase())) {
        final key = entry.path.split(RegExp(r'[/\\]')).last.toLowerCase();
        candidates.putIfAbsent(key, () => []).add(entry);
      }
    }
    var updated = 0;
    for (final track in await database.select(database.tracks).get()) {
      if (await File(track.filePath).exists()) continue;
      var matches =
          candidates[track.filePath
              .split(RegExp(r'[/\\]'))
              .last
              .toLowerCase()] ??
          <File>[];
      if (matches.isEmpty) continue;
      final suffix = track.filePath
          .replaceAll('\\', '/')
          .split('/')
          .reversed
          .take(3)
          .toList()
          .reversed
          .join('/')
          .toLowerCase();
      final bySuffix = matches
          .where(
            (f) => f.path.replaceAll('\\', '/').toLowerCase().endsWith(suffix),
          )
          .toList();
      if (bySuffix.isNotEmpty) matches = bySuffix;
      if (matches.length > 1 && track.fileSize != null) {
        final sized = <File>[];
        for (final f in matches) {
          if (await f.length() == track.fileSize) sized.add(f);
        }
        matches = sized;
      }
      if (matches.length > 1 && track.durationMs > 0) {
        final timed = <File>[];
        for (final file in matches) {
          final path = file.path;
          final tags = await Isolate.run(
            () => parseTags(path, withImage: false),
          );
          if ((tags.durationMs - track.durationMs).abs() <= 1500) {
            timed.add(file);
          }
        }
        matches = timed;
      }
      if (matches.length != 1) {
        continue; // Ambiguity must never silently relink.
      }
      final path = matches.single.path;
      if (await (database.select(
            database.tracks,
          )..where((t) => t.filePath.equals(path))).getSingleOrNull() !=
          null) {
        continue;
      }
      await (database.update(
        database.tracks,
      )..where((t) => t.id.equals(track.id))).write(
        db.TracksCompanion(
          filePath: Value(path),
          isMissing: const Value(false),
        ),
      );
      updated++;
    }
    return updated;
  }
}
