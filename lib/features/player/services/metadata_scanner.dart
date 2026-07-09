import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart';
import 'package:electrowave/core/database/app_database.dart';

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
      allowedExtensions: ['mp3', 'flac', 'm4a', 'wav'],
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
      if (file.path.endsWith('.mp3') || file.path.endsWith('.flac') || file.path.endsWith('.m4a') || file.path.endsWith('.wav')) {
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
              // It exists and is active. Skip it to save time.
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
}