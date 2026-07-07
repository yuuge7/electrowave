import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart';
import 'package:local_player/core/database/app_database.dart';

class MetadataScanner {
  final AppDatabase db;
  MetadataScanner(this.db);

  Future<void> scanFolder() async {
    // 1. Pick a directory
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;

    final dir = Directory(selectedDirectory);
    final files = dir.listSync(recursive: true);

    // Prepare a directory to store the extracted cover art
    final docsDir = await getApplicationDocumentsDirectory();
    final coversDir = Directory(p.join(docsDir.path, '.local_player_covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    for (var file in files) {
      if (file.path.endsWith('.mp3') || file.path.endsWith('.flac') || file.path.endsWith('.m4a')) {
        try {
          // 2. Extract metadata
          final metadata = await MetadataGod.readMetadata(file: file.path);
          
          String? coverArtPath;

          // 3. Extract and save the cover art if it exists
          if (metadata.picture?.data != null) {
            final albumName = metadata.album ?? 'Unknown Album';
            final artistName = metadata.artist ?? 'Unknown Artist';
            
            // Generate a unique filename based on album and artist to reuse images and save space
            final fileName = '${albumName.hashCode}_${artistName.hashCode}.jpg';
            final imageFile = File(p.join(coversDir.path, fileName));

            // Only write the file if it doesn't already exist from a previous track on the same album
            if (!await imageFile.exists()) {
              await imageFile.writeAsBytes(metadata.picture!.data);
            }
            
            coverArtPath = imageFile.path;
          }

          // 4. Save to database
          await db.into(db.tracks).insert(
            TracksCompanion.insert(
              filePath: file.path,
              title: metadata.title ?? 'Unknown Title',
              artist: metadata.artist ?? 'Unknown Artist',
              album: metadata.album ?? 'Unknown Album',
              durationMs: metadata.duration?.inMilliseconds ?? 0,
              genre: Value(metadata.genre),
              coverArtPath: Value(coverArtPath), // Added the new cover art path
            ),
            mode: InsertMode.insertOrReplace,
          );
        } catch (e) {
          debugPrint('Error scanning ${file.path}: $e');
        }
      }
    }
  }
}