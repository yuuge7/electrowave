import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart';
import 'package:electrowave/core/database/app_database.dart';

/// Audio containers the scanner picks up.
const Set<String> kAudioExtensions = {'.mp3', '.flac', '.m4a', '.ogg', '.wav'};

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

class MetadataScanner {
  final AppDatabase db;
  MetadataScanner(this.db);

  // --- OPTION 1: Scan a whole folder ---
  Future<void> scanDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;

    final dir = Directory(selectedDirectory);
    final files = dir.listSync(recursive: true).whereType<File>().toList();

    await _processFiles(files);
  }

  // --- OPTION 2: Scan specific files ---
  Future<void> scanSpecificFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['mp3', 'flac', 'm4a', 'ogg', 'wav'],
    );
    if (result == null) return;

    final files = result.paths.where((path) => path != null).map((path) => File(path!)).toList();

    await _processFiles(files);
  }

  // --- THE CORE PROCESSING ENGINE ---
  Future<void> _processFiles(List<File> files) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final coversDir = Directory(p.join(docsDir.path, '.local_player_covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    for (var file in files) {
      if (kAudioExtensions.contains(p.extension(file.path).toLowerCase())) {
        try {
          // Check if this file is already in the database
          final existingTrack = await (db.select(db.tracks)..where((t) => t.filePath.equals(file.path))).getSingleOrNull();

          if (existingTrack != null) {
            if (existingTrack.isDeleted) {
              // IT WAS DELETED! Resurrect it by flipping the switch back to false.
              await (db.update(db.tracks)..where((t) => t.id.equals(existingTrack.id))).write(
                const TracksCompanion(
                  isDeleted: Value(false),
                ),
              );
              debugPrint('Revived deleted track: ${file.path}');
            } else {
              // Known and active. Backfill the tag fields added later so a
              // rescan fills in album ordering for an old library, then skip.
              await _backfill(existingTrack);
              continue;
            }
          } else {
            // IT'S A BRAND NEW SONG! Extract metadata and insert it.
            final metadata = await MetadataGod.readMetadata(file: file.path);
            String? coverArtPath;

            if (metadata.picture?.data != null) {
              final albumName = metadata.album ?? 'Unknown Album';
              final artistName = metadata.artist ?? 'Unknown Artist';

              final fileName = '${albumName.hashCode}_${artistName.hashCode}.jpg';
              final imageFile = File(p.join(coversDir.path, fileName));

              if (!await imageFile.exists()) {
                await imageFile.writeAsBytes(metadata.picture!.data);
              }
              coverArtPath = imageFile.path;
            } else {
              // No embedded art: fall back to a cover image sitting in the
              // same folder. Referenced in place — no need to copy it.
              coverArtPath = await _findFolderArt(p.dirname(file.path));
            }

            await db.into(db.tracks).insert(
              TracksCompanion.insert(
                filePath: file.path,
                title: metadata.title ?? 'Unknown Title',
                artist: metadata.artist ?? 'Unknown Artist',
                album: metadata.album ?? 'Unknown Album',
                durationMs: metadata.duration?.inMilliseconds ?? 0,
                genre: Value(metadata.genre),
                coverArtPath: Value(coverArtPath),
                trackNumber: Value(metadata.trackNumber),
                discNumber: Value(metadata.discNumber),
                year: Value(metadata.year),
                dateAdded: Value(DateTime.now()),
              ),
            );
            debugPrint('Inserted new track: ${file.path}');
          }
        } catch (e) {
          debugPrint('Error scanning ${file.path}: $e');
        }
      }
    }
  }

  /// Fills in the columns that didn't exist when an older library was scanned:
  /// track/disc numbers, year, the date the row was added and folder art.
  Future<void> _backfill(Track track) async {
    // dateAdded is the marker for "this row predates the extra columns", so
    // each old row is re-read exactly once — files that genuinely carry no
    // numbering tags don't get re-parsed on every later scan.
    if (track.dateAdded != null) return;

    final needsNumbering = track.trackNumber == null &&
        track.discNumber == null &&
        track.year == null;
    final needsArt = track.coverArtPath == null;

    try {
      final metadata = needsNumbering
          ? await MetadataGod.readMetadata(file: track.filePath)
          : null;
      final art =
          needsArt ? await _findFolderArt(p.dirname(track.filePath)) : null;

      await (db.update(db.tracks)..where((t) => t.id.equals(track.id))).write(
        TracksCompanion(
          trackNumber: metadata == null
              ? const Value.absent()
              : Value(metadata.trackNumber),
          discNumber: metadata == null
              ? const Value.absent()
              : Value(metadata.discNumber),
          year: metadata == null ? const Value.absent() : Value(metadata.year),
          coverArtPath: art == null ? const Value.absent() : Value(art),
          // Unknown for pre-existing rows; stamping them now at least gives
          // "Recently added" something to sort on.
          dateAdded: track.dateAdded == null
              ? Value(DateTime.now())
              : const Value.absent(),
        ),
      );
    } catch (e) {
      debugPrint('Backfill failed for ${track.filePath}: $e');
    }
  }

  /// Folders are looked up once and cached: a scan walks an album directory
  /// track by track, so this would otherwise stat the same files repeatedly.
  final Map<String, String?> _folderArtCache = {};

  Future<String?> _findFolderArt(String folderPath) async {
    if (_folderArtCache.containsKey(folderPath)) {
      return _folderArtCache[folderPath];
    }

    String? found;
    try {
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        // Index the folder's image files once, then pick by preference order
        // so 'cover.jpg' wins over 'thumb.png' regardless of listing order.
        final images = <String, String>{};
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path).toLowerCase();
          if (!kFolderArtExtensions.contains(ext)) continue;
          final stem = p.basenameWithoutExtension(entity.path).toLowerCase();
          images.putIfAbsent(stem, () => entity.path);
        }

        for (final name in kFolderArtNames) {
          if (images.containsKey(name)) {
            found = images[name];
            break;
          }
        }
        // Nothing conventionally named: accept a lone image in the folder.
        if (found == null && images.length == 1) {
          found = images.values.first;
        }
      }
    } on FileSystemException {
      // Unreadable directory: treat as "no art".
    }

    _folderArtCache[folderPath] = found;
    return found;
  }
}
