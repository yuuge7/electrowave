import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';

import 'core/database/app_database.dart';
import 'shared/widgets/main_shell.dart';

Future<void> applyPendingDatabaseImport() async {
  try {
    // Note: Make sure this path exactly matches where _getDbFile() saves your database!
    // Often it is getApplicationSupportDirectory() or getApplicationDocumentsDirectory()
    final docDir = await getApplicationDocumentsDirectory(); 
    final dbFile = File('${docDir.path}/local_player_db.sqlite');
    final pendingFile = File('${docDir.path}/pending_import.sqlite');

    if (await pendingFile.exists()) {
      // 1. Delete the SQLite temporary files so they don't corrupt the new import
      final walFile = File('${dbFile.path}-wal');
      final shmFile = File('${dbFile.path}-shm');
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();

      // 2. Overwrite the real db with the pending backup
      await pendingFile.copy(dbFile.path);
      
      // 3. Clean up the pending file
      await pendingFile.delete();
      debugPrint("Pending import applied successfully on startup!");
    }
  } catch (e) {
    debugPrint("Error applying pending import: $e");
  }
}

// Global database instance provided via Riverpod
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Intercept and apply the database before starting the app
  await applyPendingDatabaseImport();

  // Initialize native media playback engine
  MediaKit.ensureInitialized();
  
  // Initialize Rust-based metadata extraction
  MetadataGod.initialize();

  runApp(
    const ProviderScope(
      child: LocalPlayerApp(),
    ),
  );
}

class LocalPlayerApp extends StatelessWidget {
  const LocalPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Electrowave',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.greenAccent,
        useMaterial3: true,
      ),
      // This now correctly points to the MainShell layout
      home: const MainShell(), 
    );
  }
}