import 'dart:io';
import 'dart:async';
import 'core/app_paths.dart';
import 'core/local_log.dart';
import 'features/settings/services/backup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'core/database/app_database.dart';
import 'features/settings/providers/settings_provider.dart';
import 'shared/theme/app_theme.dart';
import 'shared/services/linux_desktop_integration.dart';
import 'shared/services/single_instance_service.dart';
import 'shared/widgets/main_shell.dart';
import 'shared/widgets/startup_error_app.dart';

Future<void> applyPendingDatabaseImport() async {
  try {
    await BackupService().applyPendingImport();
  } catch (e, st) {
    LocalLog.write(e, st);
  }
}

// Global database instance provided via Riverpod
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => unawaited(db.close()));
  return db;
});

void main(List<String> arguments) {
  runZonedGuarded(
    () async {
      await _start(arguments);
    },
    (error, stack) {
      LocalLog.write(error, stack);
    },
  );
}

List<String> launchFiles = [];
Future<void> _start(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  launchFiles = arguments.where((path) => !path.startsWith('-')).toList();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    LocalLog.write(details.exception, details.stack);
  };

  // Needed for hide-to-tray (show/hide/focus the native window)
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    // Single instance: if Electrowave is already running, tell it to show
    // its window and exit this process.
    if (!await SingleInstanceService.ensurePrimary(arguments)) {
      exit(0);
    }
  }

  await appDataDirectory();

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

  runApp(const ProviderScope(child: ElectrowaveApp()));
}

class ElectrowaveApp extends ConsumerWidget {
  const ElectrowaveApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      settingsControllerProvider.select((settings) => settings.themeMode),
    );

    return MaterialApp(
      title: 'Electrowave',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(
            ref.watch(settingsControllerProvider).textScale,
          ),
        ),
        child: child!,
      ),
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
    final appDir = await appDataDirectory();
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
