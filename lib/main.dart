import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'core/database/app_database.dart';
import 'shared/widgets/main_shell.dart';

Future<void> applyPendingDatabaseImport() async {
  try {
    final dir = await getApplicationDocumentsDirectory(); // (or SupportDirectory, whichever you are using)
    
    // 1. Target the specific Electrowave subfolder
    final appDir = Directory(p.join(dir.path, 'Electrowave'));
    
    // 2. Point to the files INSIDE that subfolder
    final dbFile = File(p.join(appDir.path, 'local_player_db.sqlite'));
    final pendingFile = File(p.join(appDir.path, 'pending_import.sqlite'));

    debugPrint("=== BOOT LOOKING FOR: ${pendingFile.path} ===");

    if (await pendingFile.exists()) {
      debugPrint("Found pending import! Overwriting database...");
      
      final walFile = File('${dbFile.path}-wal');
      final shmFile = File('${dbFile.path}-shm');
      
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();

      await pendingFile.copy(dbFile.path);
      await pendingFile.delete();

      await File(p.join(appDir.path, 'import_success.flag')).create();
      
      debugPrint("Pending import applied successfully on startup!");
    } else {
      debugPrint("No pending import found. Normal boot sequence.");
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

Future<bool> checkAndConsumeImportFlag() async {
  try {
    final dir = await getApplicationDocumentsDirectory(); 
    final appDir = Directory(p.join(dir.path, 'Electrowave'));
    final flagFile = File(p.join(appDir.path, 'import_success.flag'));

    if (await flagFile.exists()) {
      await flagFile.delete(); // Consume the flag so it only triggers once
      return true;
    }
    return false;
  } catch (e) {
    return false;
  }
}