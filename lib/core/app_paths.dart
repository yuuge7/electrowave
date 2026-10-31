import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const databaseFileName = 'electrowave.sqlite';
Directory? _dataDirectory;

void overrideAppDataDirectory(Directory? directory) =>
    _dataDirectory = directory;

Future<Directory> appDataDirectory() async {
  if (_dataDirectory case final directory?) {
    await directory.create(recursive: true);
    return directory;
  }
  final executableFolder = File(Platform.resolvedExecutable).parent;
  final portable = await File(
    p.join(executableFolder.path, 'portable'),
  ).exists();
  final Directory directory;
  if (portable) {
    directory = Directory(p.join(executableFolder.path, 'ElectrowaveData'));
  } else if (Platform.isWindows && Platform.environment['APPDATA'] != null) {
    directory = Directory(
      p.join(Platform.environment['APPDATA']!, 'Electrowave'),
    );
  } else if (Platform.isLinux) {
    final root =
        Platform.environment['XDG_DATA_HOME'] ??
        p.join(Platform.environment['HOME']!, '.local', 'share');
    directory = Directory(p.join(root, 'electrowave'));
  } else {
    directory = await getApplicationSupportDirectory();
  }
  await directory.create(recursive: true);
  if (!portable) {
    await migrateLegacyData(
      await getApplicationDocumentsDirectory(),
      directory,
    );
  }
  _dataDirectory = directory;
  return directory;
}

/// Copy first and retain the original for recovery. Mark complete only after
/// all files have landed, allowing an interrupted migration to resume safely.
Future<void> migrateLegacyData(Directory documents, Directory target) async {
  final marker = File(p.join(target.path, '.migrated'));
  if (await marker.exists()) return;
  final legacy = Directory(p.join(documents.path, 'Electrowave'));
  if (await legacy.exists()) {
    await for (final entry in legacy.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = p
          .basename(entry.path)
          .replaceFirst('local_player_db.sqlite', databaseFileName);
      final destination = File(p.join(target.path, name));
      if (!await destination.exists()) await entry.copy(destination.path);
    }
  }
  final oldDatabase = File(p.join(documents.path, 'local_player_db.sqlite'));
  final database = File(p.join(target.path, databaseFileName));
  if (!await database.exists() && await oldDatabase.exists()) {
    await oldDatabase.copy(database.path);
    for (final suffix in ['-wal', '-shm']) {
      final sidecar = File('${oldDatabase.path}$suffix');
      if (await sidecar.exists()) await sidecar.copy('${database.path}$suffix');
    }
  }
  final oldCovers = Directory(p.join(documents.path, '.local_player_covers'));
  if (await oldCovers.exists()) {
    final covers = Directory(p.join(target.path, 'covers'));
    await covers.create(recursive: true);
    await for (final entry in oldCovers.list(followLinks: false)) {
      if (entry is File) {
        final destination = File(p.join(covers.path, p.basename(entry.path)));
        if (!await destination.exists()) await entry.copy(destination.path);
      }
    }
  }
  await marker.writeAsString('1', flush: true);
}
