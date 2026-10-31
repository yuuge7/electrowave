import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../../core/database/app_database.dart';
import '../../player/services/metadata_scanner.dart';

class PlaylistImportResult {
  const PlaylistImportResult(this.playlistId, this.imported, this.skipped);
  final int playlistId, imported, skipped;
}

class FileExchange {
  FileExchange(this.db);
  final AppDatabase db;

  static List<String> parseM3u(String contents, String playlistPath) {
    final paths = <String>[];
    for (final line in const LineSplitter().convert(
      contents.replaceFirst('\uFEFF', ''),
    )) {
      final value = line.trim();
      if (value.isEmpty || value.startsWith('#')) continue;
      if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
        paths.add(p.normalize(value));
        continue;
      }
      final uri = Uri.tryParse(value);
      if (uri?.hasScheme ?? false) {
        if (uri!.scheme != 'file') continue; // Local files only.
        paths.add(uri.toFilePath(windows: Platform.isWindows));
      } else {
        paths.add(
          p.normalize(
            p.isAbsolute(value)
                ? value
                : p.join(
                    p.dirname(playlistPath),
                    value.replaceAll('\\', p.separator),
                  ),
          ),
        );
      }
    }
    return paths;
  }

  Future<PlaylistImportResult> importPlaylist(String path) async {
    final file = File(path);
    final contents = await file
        .readAsString(encoding: utf8)
        .catchError((_) => file.readAsString(encoding: latin1));
    final paths = parseM3u(contents, path);
    await MetadataScanner(db).scanPaths(paths, reviveDeleted: true);
    final ids = <int>[];
    var skipped = 0;
    for (final path in paths) {
      final track =
          await (db.select(
                db.tracks,
              )..where((t) => t.filePath.equals(p.normalize(p.absolute(path)))))
              .getSingleOrNull();
      if (track == null || !await File(path).exists()) {
        skipped++;
      } else {
        ids.add(track.id);
      }
    }
    final id = await db.createPlaylist(p.basenameWithoutExtension(path));
    final count = await db.addTracksToPlaylist(id, ids);
    return PlaylistImportResult(id, count, skipped);
  }

  Future<void> exportPlaylist(String path, List<Track> tracks) async {
    final lines = <String>['#EXTM3U'];
    for (final track in tracks) {
      final relative = p.relative(track.filePath, from: p.dirname(path));
      final title = '${track.artist} - ${track.title}'.replaceAll(
        RegExp(r'[\r\n]'),
        ' ',
      );
      lines.add('#EXTINF:${track.durationMs ~/ 1000},$title');
      lines.add(relative.replaceAll('\\', '/'));
    }
    await File(
      path,
    ).writeAsString('${lines.join('\n')}\n', encoding: utf8, flush: true);
  }

  static String csvCell(Object? value) {
    var text = '${value ?? ''}';
    // Spreadsheet applications interpret formula prefixes even inside quotes.
    if (RegExp(r'^\s*[=+@\-\t\r]').hasMatch(text)) text = "'$text";
    return '"${text.replaceAll('"', '""')}"';
  }

  Future<void> exportStats(String path) async {
    final stats = await db.watchSongStats().first;
    stats.sort((a, b) => b.plays.compareTo(a.plays));
    final rows = <List<Object?>>[
      [
        'Rank',
        'Title',
        'Artist',
        'Album',
        'Plays',
        'Listening seconds',
        'Starts',
        'Skips',
        'Rating',
        'Last played',
        'File',
      ],
      for (var i = 0; i < stats.length; i++)
        [
          i + 1,
          stats[i].track.title,
          stats[i].track.artist,
          stats[i].track.album,
          stats[i].plays,
          stats[i].listenedMs / 1000,
          stats[i].starts,
          stats[i].skips,
          stats[i].track.rating,
          stats[i].lastPlayed?.toIso8601String(),
          stats[i].track.filePath,
        ],
    ];
    await File(path).writeAsString(
      '\uFEFF${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n',
      flush: true,
    );
  }
}

List<List<Track>> findDuplicates(List<Track> tracks) {
  final groups = <String, List<Track>>{};
  String clean(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  for (final track in tracks.where((t) => !t.isDeleted)) {
    final key = '${clean(track.title)}\u0000${clean(track.artist)}';
    groups.putIfAbsent(key, () => []).add(track);
  }
  final result = <List<Track>>[];
  for (final group in groups.values) {
    group.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    var cluster = <Track>[];
    for (final track in group) {
      if (cluster.isNotEmpty &&
          (track.durationMs - cluster.first.durationMs).abs() > 2000) {
        if (cluster.length > 1) result.add(cluster);
        cluster = [];
      }
      cluster.add(track);
    }
    if (cluster.length > 1) result.add(cluster);
  }
  return result;
}
