import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'core/database/app_database.dart';
import 'core/session/session_store.dart';
import 'features/settings/providers/settings_provider.dart';
import 'shared/theme/app_theme.dart';
import 'shared/services/linux_desktop_integration.dart';
import 'shared/services/single_instance_service.dart';
import 'shared/widgets/main_shell.dart';
import 'shared/widgets/startup_error_app.dart';

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

      // The saved session points at track IDs from the *old* database, so it
      // would restore the wrong songs against the imported library.
      await SessionStore.clear();

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

  // Needed for hide-to-tray (show/hide/focus the native window)
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    // Single instance: if Electrowave is already running, tell it to show
    // its window and exit this process.
    if (!await SingleInstanceService.ensurePrimary()) {
      exit(0);
    }
  }

  // Install .desktop file + icon so the taskbar/launcher shows our icon
  await LinuxDesktopIntegration.ensureInstalled();

  // Intercept and apply the database before starting the app
  await applyPendingDatabaseImport();

  // Initialize native media playback engine.
  //
  // On Linux libmpv is a *system* library — package:media_kit dlopens it and
  // bundles nothing — so a machine without the mpv package throws right here,
  // before runApp(). Unguarded that kills the process with no window and no
  // message anywhere except the terminal nobody launched it from, which is
  // indistinguishable from the app simply not starting. Show the reason
  // instead.
  String? engineError;
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    engineError = '$e';
    debugPrint('Audio engine unavailable: $e');
  }

  if (engineError != null) {
    runApp(StartupErrorApp(message: engineError));
    return;
  }

  runApp(
    const ProviderScope(
      child: LocalPlayerApp(),
    ),
  );
}

class LocalPlayerApp extends ConsumerWidget {
  const LocalPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      settingsControllerProvider.select((settings) => settings.themeMode),
    );

    return MaterialApp(
      title: 'Electrowave',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: toFlutterThemeMode(themeMode),
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