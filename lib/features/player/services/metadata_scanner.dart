import '../../library/services/extra_tags.dart';
import 'dart:io';
import 'dart:isolate';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'package:image/image.dart' as img;
import '../../../core/app_paths.dart';
import '../../../core/local_log.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart';
import 'package:electrowave/core/database/app_database.dart';

/// Audio containers the scanner picks up.
const Set<String> kAudioExtensions = {
  '.mp3',
  '.flac',
  '.m4a',
  '.ogg',
  '.wav',
  '.opus',
  '.aac',
  '.aiff',
  '.aif',
  '.wma',
  '.ape',
  '.wv',
  '.mka',
  '.dsf',
};

/// Cover images to look for next to the audio file when a track carries no
/// embedded art — the common layout for CD rips and Bandcamp downloads.
const List<String> kFolderArtNames = [
  'cover',
  'folder',
  'front',
  'album',
  'albumart',
  'artwork',
  'thumb',
];

const List<String> kFolderArtExtensions = ['.jpg', '.jpeg', '.png', '.webp'];

/// Plain tag data extracted in a worker isolate: tag parsing is synchronous
/// and would jank the UI on a large scan otherwise.
class ParsedTags {
  const ParsedTags({
    this.rating,
    this.albumArtist,
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.durationMs = 0,
    this.artBytes,
    this.artMime,
    this.trackNumber,
    this.discNumber,
    this.year,
  });

  final int? rating;
  final String? albumArtist;
  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int durationMs;
  final Uint8List? artBytes;
  final String? artMime;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
}

/// Top-level so it can run inside [Isolate.run].
ParsedTags parseTags(String filePath, {bool withImage = true}) {
  try {
    final meta = readMetadata(File(filePath), getImage: withImage);
    final raw = readAllMetadata(File(filePath), getImage: false);
    final extras =
        {'.m4a', '.mp4'}.contains(p.extension(filePath).toLowerCase())
        ? readMp4Identity(File(filePath))
        : <String, String>{};
    final String? albumArtist = switch (raw) {
      Mp3Metadata m => m.bandOrOrchestra,
      VorbisMetadata m =>
        m.unknowns['ALBUMARTIST'] ??
            m.unknowns['ALBUM ARTIST'] ??
            (m.unknowns['COMPILATION'] == '1' ? 'Various artists' : null),
      ApeMetadata m => m.albumArtist,
      Mp4Metadata _ =>
        extras['aART'] ?? (extras['cpil'] == '1' ? 'Various artists' : null),
      _ => null,
    };
    final popm = raw is Mp3Metadata ? readId3Rating(File(filePath)) : null;
    final picture = meta.pictures.isNotEmpty ? meta.pictures.first : null;
    return ParsedTags(
      rating: switch (raw) {
        Mp3Metadata _ when popm != null => switch (popm) {
          0 => 0,
          1 => 1,
          final n when n < 96 => 2,
          final n when n < 160 => 3,
          final n when n < 224 => 4,
          _ => 5,
        },
        Mp3Metadata m =>
          int.tryParse(m.customMetadata['RATING'] ?? '') == null
              ? null
              : ((int.parse(m.customMetadata['RATING']!)) / 20).round().clamp(
                  0,
                  5,
                ),
        VorbisMetadata m =>
          int.tryParse(m.unknowns['RATING'] ?? '') == null
              ? null
              : ((int.parse(m.unknowns['RATING']!)) / 20).round().clamp(0, 5),
        _ => null,
      },
      albumArtist: albumArtist,
      title: meta.title,
      artist: extras['\u00a9ART'] ?? meta.artist,
      album: meta.album,
      genre: meta.genres.isNotEmpty ? meta.genres.first : null,
      durationMs: meta.duration?.inMilliseconds ?? 0,
      artBytes: picture?.bytes,
      artMime: picture?.mimetype,
      trackNumber: meta.trackNumber,
      discNumber: meta.discNumber,
      year: meta.year?.year,
    );
  } catch (_) {
    return const ParsedTags(); // Unreadable tags: fall back to the filename.
  }
}

class ScanProgress {
  const ScanProgress({
    this.processed = 0,
    this.total = 0,
    this.running = false,
    this.errors = 0,
    this.cancelled = false,
  });
  final int processed, total, errors;
  final bool running, cancelled;
}

class MetadataScanner {
  MetadataScanner(this.db, {this.onProgress});
  final AppDatabase db;
  final void Function(ScanProgress)? onProgress;
  bool _cancelled = false;
  bool _running = false;
  void cancel() => _cancelled = true;

  Future<void> scanDirectory() async {
    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory != null) await scanPaths([directory], reviveDeleted: true);
  }

  Future<void> scanSpecificFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: kAudioExtensions.map((e) => e.substring(1)).toList(),
    );
    if (result != null) {
      await scanPaths(
        result.paths.whereType<String>().toList(),
        reviveDeleted: true,
      );
    }
  }

  Future<void> scanPaths(
    List<String> paths, {
    bool reviveDeleted = false,
  }) async {
    if (_running) return;
    _running = true;
    _cancelled = false;
    var done = 0, errors = 0;
    final files = <String>{};
    onProgress?.call(const ScanProgress(running: true));
    try {
      for (final path in paths) {
        if (_cancelled) break;
        if (await FileSystemEntity.isDirectory(path)) {
          try {
            await for (final entity in Directory(
              path,
            ).list(recursive: true, followLinks: false)) {
              if (_cancelled) break;
              if (entity is File &&
                  kAudioExtensions.contains(
                    p.extension(entity.path).toLowerCase(),
                  )) {
                files.add(p.normalize(p.absolute(entity.path)));
              }
            }
          } catch (e, st) {
            errors++;
            LocalLog.write(e, st);
          }
        } else if (kAudioExtensions.contains(p.extension(path).toLowerCase()) &&
            await File(path).exists()) {
          files.add(p.normalize(p.absolute(path)));
        }
      }
      final dir = await appDataDirectory();
      final covers = await Directory(
        p.join(dir.path, 'covers'),
      ).create(recursive: true);
      final existing = {
        for (final t in await db.select(db.tracks).get()) t.filePath: t,
      };
      for (final path in files) {
        if (_cancelled) break;
        try {
          final stat = await File(path).stat();
          final old = existing[path];
          if (old != null &&
              old.modifiedMs == stat.modified.millisecondsSinceEpoch &&
              old.fileSize == stat.size &&
              !old.isMissing) {
            if (old.isDeleted && reviveDeleted) await db.restoreTrack(old.id);
          } else {
            final metadata = await Isolate.run(() => parseTags(path));
            String? art;
            if (metadata.artBytes?.isNotEmpty ?? false) {
              // Hash based on bytes, independent of Dart's process hash seed.
              var hash = 2166136261;
              for (final byte in metadata.artBytes!) {
                hash = ((hash ^ byte) * 16777619) & 0xffffffff;
              }
              final image = File(
                p.join(covers.path, '${hash.toRadixString(16)}.jpg'),
              );
              if (!await image.exists()) {
                final bytes = metadata.artBytes!;
                final thumb = await Isolate.run(() {
                  final decoded = img.decodeImage(bytes);
                  return decoded == null
                      ? bytes
                      : img.encodeJpg(
                          img.copyResize(decoded, width: 512),
                          quality: 88,
                        );
                });
                await image.writeAsBytes(thumb);
              }
              art = image.path;
            } else {
              art = await _findFolderArt(p.dirname(path));
              if (art != null) {
                final folderImage = art;
                final thumbPath = p.join(
                  covers.path,
                  'folder_${_stableHash(folderImage)}.jpg',
                );
                final image = File(thumbPath);
                if (!await image.exists() ||
                    (await File(
                      folderImage,
                    ).lastModified()).isAfter(await image.lastModified())) {
                  await Isolate.run(() {
                    final decoded = img.decodeImage(
                      File(folderImage).readAsBytesSync(),
                    );
                    if (decoded != null) {
                      File(thumbPath).writeAsBytesSync(
                        img.encodeJpg(
                          img.copyResize(decoded, width: 512),
                          quality: 88,
                        ),
                      );
                    }
                  });
                }
                if (await image.exists()) art = image.path;
              }
            }
            final values = TracksCompanion(
              filePath: Value(path),
              title: Value(
                _clean(metadata.title) ?? p.basenameWithoutExtension(path),
              ),
              artist: Value(_clean(metadata.artist) ?? 'Unknown Artist'),
              album: Value(_clean(metadata.album) ?? 'Unknown Album'),
              albumArtist: Value(_clean(metadata.albumArtist)),
              rating: metadata.rating == null
                  ? const Value.absent()
                  : Value(metadata.rating!),
              durationMs: Value(metadata.durationMs),
              genre: Value(_clean(metadata.genre)),
              coverArtPath: Value(art),
              trackNumber: Value(metadata.trackNumber),
              discNumber: Value(metadata.discNumber),
              year: Value(metadata.year),
              fileSize: Value(stat.size),
              modifiedMs: Value(stat.modified.millisecondsSinceEpoch),
              isMissing: const Value(false),
              isDeleted: Value(old?.isDeleted == true && !reviveDeleted),
              dateAdded: Value(old?.dateAdded ?? DateTime.now()),
            );
            if (old == null) {
              await db
                  .into(db.tracks)
                  .insert(values, mode: InsertMode.insertOrIgnore);
            } else {
              await (db.update(
                db.tracks,
              )..where((t) => t.id.equals(old.id))).write(values);
            }
          }
        } catch (e, st) {
          errors++;
          LocalLog.write(e, st);
        }
        done++;
        onProgress?.call(
          ScanProgress(
            processed: done,
            total: files.length,
            running: true,
            errors: errors,
          ),
        );
      }
      // Only inspect rows inside the requested roots. A cancelled scan must not
      // mark undiscovered files missing, and a soft delete stays a soft delete.
      if (!_cancelled) {
        for (final track in existing.values) {
          if (!paths.any(
            (root) =>
                p.equals(root, track.filePath) ||
                p.isWithin(root, track.filePath),
          )) {
            continue;
          }
          final missing = !await File(track.filePath).exists();
          if (track.isMissing != missing) {
            await (db.update(db.tracks)..where((t) => t.id.equals(track.id)))
                .write(TracksCompanion(isMissing: Value(missing)));
          }
        }
      }
    } catch (e, st) {
      errors++;
      LocalLog.write(e, st);
    } finally {
      _running = false;
      onProgress?.call(
        ScanProgress(
          processed: done,
          total: files.length,
          errors: errors,
          cancelled: _cancelled,
        ),
      );
    }
  }

  String? _clean(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
  int _stableHash(String value) {
    var hash = 0;
    for (final code in value.codeUnits) {
      hash = (hash * 31 + code) & 0xffffffff;
    }
    return hash;
  }

  Future<String?> _findFolderArt(String folder) async {
    final images = <String, String>{};
    await for (final entry in Directory(folder).list(followLinks: false)) {
      if (entry is File &&
          kFolderArtExtensions.contains(
            p.extension(entry.path).toLowerCase(),
          )) {
        images[p.basenameWithoutExtension(entry.path).toLowerCase()] =
            entry.path;
      }
    }
    for (final name in kFolderArtNames) {
      if (images.containsKey(name)) return images[name];
    }
    return null;
  }
}
