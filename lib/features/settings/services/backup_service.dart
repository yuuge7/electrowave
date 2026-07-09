import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart'; 
import '../../../core/database/app_database.dart' as db; 

final backupServiceProvider = Provider((ref) => BackupService());

class BackupService {
  // Helper to get the exact path to your SQLite database inside the Electrowave folder
  Future<File> _getDbFile() async {
    final docsFolder = await getApplicationDocumentsDirectory();
    final appFolder = Directory(p.join(docsFolder.path, 'Electrowave'));
    
    // Ensure the folder exists before trying to import/export
    if (!await appFolder.exists()) {
      await appFolder.create(recursive: true);
    }
    
    return File(p.join(appFolder.path, 'local_player_db.sqlite'));
  }

  Future<bool> exportDatabase() async {
    try {
      final dbFile = await _getDbFile();
      if (!await dbFile.exists()) return false;

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Library Backup',
        fileName: 'local_player_backup.sqlite',
        type: FileType.custom,
        allowedExtensions: ['sqlite', 'db'],
      );

      if (outputFile == null) return false; 

      await dbFile.copy(outputFile);
      return true;
    } catch (e) {
      debugPrint('Export error: $e');
      return false;
    }
  }

  // importDatabase renamed to stageImport for clarity
  Future<bool> stageImport(String backupFilePath) async {
    try {
      final sourceFile = File(backupFilePath);
      final dbFile = await _getDbFile();
      
      // FIX: Use p.join to handle Windows (\) and Linux (/) slashes automatically
      final pendingFile = File(p.join(dbFile.parent.path, 'pending_import.sqlite'));
      
      await sourceFile.copy(pendingFile.path);
      debugPrint("=== STAGING SAVED TO: ${pendingFile.path} ===");
      return true;
    } catch (e) {
      debugPrint('Stage error: $e');
      return false;
    }
  }

  /// CROSS-OS MIGRATION ENGINE
  /// Scans a new directory and intelligently updates all database paths
  Future<int> relocateLibrary(String newRootPath, db.AppDatabase database) async {
    try {
      final tracks = await database.select(database.tracks).get();
      final dir = Directory(newRootPath);

      // 1. Get all files in the new directory
      final List<FileSystemEntity> files = await dir.list(recursive: true).toList();

      // 2. Create a fast lookup map of: filename -> new absolute path
      final fileMap = <String, String>{};
      for (var file in files) {
        if (file is File) {
          final name = p.basename(file.path);
          fileMap[name] = file.path;
        }
      }

      int updatedCount = 0;

      // 3. Update paths in the database if the raw filename matches
      for (var track in tracks) {
        // Regex splits by BOTH Windows (\) and Linux (/) slashes safely
        final filename = track.filePath.split(RegExp(r'[/\\]')).last;

        if (fileMap.containsKey(filename)) {
          final newPath = fileMap[filename]!;
          if (newPath != track.filePath) {
            await (database.update(database.tracks)..where((t) => t.id.equals(track.id)))
                .write(db.TracksCompanion(filePath: Value(newPath)));
            updatedCount++;
          }
        }
      }
      return updatedCount;
    } catch (e) {
      debugPrint('Relocate error: $e');
      return 0;
    }
  }
}