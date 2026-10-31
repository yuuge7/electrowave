import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:electrowave/core/database/app_database.dart';
import 'package:electrowave/main.dart';
import 'package:electrowave/features/library/providers/scan_provider.dart';
import 'package:electrowave/features/player/services/metadata_scanner.dart';
import 'package:electrowave/features/settings/providers/settings_provider.dart';
import 'package:electrowave/features/settings/services/settings_persistence.dart';

class FixedSettings extends SettingsController {
  @override
  AppSettings build() => const AppSettings();
}

class MemoryPersistence extends SettingsPersistence {
  @override
  Future<void> save(AppSettings settings) async {}
}

class ControlledScanner extends MetadataScanner {
  ControlledScanner(super.db, void Function(ScanProgress) progress)
    : super(onProgress: progress);
  final calls = <List<String>>[];
  final pending = <Completer<void>>[];
  @override
  Future<void> scanPaths(
    List<String> paths, {
    bool reviveDeleted = false,
  }) async {
    calls.add(paths);
    final done = Completer<void>();
    pending.add(done);
    onProgress!(const ScanProgress(running: true));
    await done.future;
    onProgress!(const ScanProgress());
  }
}

void main() {
  test(
    'adding files during a scan queues the actual paths instead of losing them',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      late ControlledScanner scanner;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          settingsControllerProvider.overrideWith(FixedSettings.new),
          settingsPersistenceProvider.overrideWithValue(MemoryPersistence()),
          metadataScannerFactoryProvider.overrideWithValue(
            (database, progress) =>
                scanner = ControlledScanner(database, progress),
          ),
        ],
      );
      final root = await Directory.systemTemp.createTemp(
        'electrowave-concurrent-scan-',
      );
      final firstPath = '${root.path}/first.mp3',
          secondPath = '${root.path}/second.mp3';
      final controller = container.read(scanProvider.notifier);
      final first = controller.importPaths([firstPath]);
      while (scanner.calls.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await controller.importPaths([secondPath]);
      expect(scanner.calls.length, 1);
      scanner.pending.first.complete();
      await first;
      while (scanner.calls.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(scanner.calls[1], [secondPath]);
      scanner.pending[1].complete();
      await Future<void>.delayed(Duration.zero);
      container.dispose();
      await db.close();
      await root.delete();
    },
  );
}
