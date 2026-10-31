import 'package:watcher/watcher.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../player/services/metadata_scanner.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../core/local_log.dart';
import '../../../core/database/app_database.dart';

final metadataScannerFactoryProvider =
    Provider<
      MetadataScanner Function(AppDatabase, void Function(ScanProgress))
    >(
      (ref) =>
          (database, progress) =>
              MetadataScanner(database, onProgress: progress),
    );

final scanProvider = NotifierProvider<ScanController, ScanProgress>(
  ScanController.new,
);

class ScanController extends Notifier<ScanProgress> {
  late MetadataScanner _scanner;
  final List<StreamSubscription<WatchEvent>> _watchers = [];
  Timer? _debounce;
  List<String> _folders = [];
  bool _rescanPending = false;
  final Set<String> _pendingPaths = {};
  int _watchRevision = 0;

  @override
  ScanProgress build() {
    _scanner = ref.read(metadataScannerFactoryProvider)(
      ref.read(databaseProvider),
      (value) {
        if (!ref.mounted) return;
        state = value;
        if (!value.running && _pendingPaths.isNotEmpty) {
          final paths = _pendingPaths.toList();
          _pendingPaths.clear();
          scheduleMicrotask(
            () => _scanner.scanPaths(paths, reviveDeleted: true),
          );
        } else if (!value.running && _rescanPending) {
          _rescanPending = false;
          scheduleMicrotask(rescan);
        }
      },
    );
    ref.listen(settingsControllerProvider.select((s) => s.libraryFolders), (
      _,
      folders,
    ) {
      if (_folders.join('\n') == folders.join('\n')) return;
      _folders = List.of(folders);
      scheduleMicrotask(() {
        if (!ref.mounted) return;
        unawaited(_watch());
        unawaited(rescan());
      });
    }, fireImmediately: true);
    ref.onDispose(() {
      _watchRevision++;
      _scanner.cancel();
      _debounce?.cancel();
      for (final watcher in _watchers) {
        unawaited(watcher.cancel());
      }
    });
    scheduleMicrotask(() async {
      final database = ref.read(databaseProvider);
      final tracks = await database.select(database.tracks).get();
      if (ref.mounted && _folders.isEmpty && tracks.isNotEmpty) {
        await _scanner.scanPaths(tracks.map((t) => t.filePath).toList());
      }
    });
    return const ScanProgress();
  }

  Future<void> _watch() async {
    final revision = ++_watchRevision;
    for (final watcher in _watchers) {
      await watcher.cancel();
    }
    _watchers.clear();
    if (revision != _watchRevision || !ref.mounted) return;
    for (final folder in _folders) {
      try {
        if (await Directory(folder).exists()) {
          if (revision != _watchRevision || !ref.mounted) return;
          _watchers.add(
            DirectoryWatcher(folder).events.listen((_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(seconds: 2), rescan);
            }, onError: (Object error) => LocalLog.write(error)),
          );
        }
      } catch (e, st) {
        LocalLog.write(e, st);
      }
    }
  }

  void cancel() {
    _rescanPending = false;
    _pendingPaths.clear();
    _scanner.cancel();
  }

  Future<void> rescan() async {
    if (state.running) {
      _rescanPending = true;
      return;
    }
    if (_folders.isNotEmpty) await _scanner.scanPaths(_folders);
  }

  Future<void> addFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    await importPaths([path]);
  }

  Future<void> removeFolder(String path) async {
    final controller = ref.read(settingsControllerProvider.notifier);
    await controller.updatePreferences(
      ref
          .read(settingsControllerProvider)
          .copyWith(libraryFolders: _folders.where((p) => p != path).toList()),
    );
  }

  Future<void> importPaths(List<String> paths) async {
    final folders = <String>[..._folders];
    for (final path in paths) {
      if (await FileSystemEntity.isDirectory(path) && !folders.contains(path)) {
        folders.add(path);
      }
    }
    final controller = ref.read(settingsControllerProvider.notifier);
    await controller.updatePreferences(
      ref.read(settingsControllerProvider).copyWith(libraryFolders: folders),
    );
    if (state.running) {
      _pendingPaths.addAll(paths);
      return;
    }
    await _scanner.scanPaths(paths, reviveDeleted: true);
  }

  Future<void> addFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: kAudioExtensions.map((s) => s.substring(1)).toList(),
    );
    if (result != null) {
      await importPaths(result.paths.whereType<String>().toList());
    }
  }
}
