import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import '../../../core/app_paths.dart';
import '../../../core/local_log.dart';
import '../../../main.dart';
import '../../library/providers/scan_provider.dart';
import '../../library/services/file_exchange.dart';
import '../../library/services/loudness_scanner.dart';
import '../../player/providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../services/backup_service.dart';

Future<void> openLocalFolder(String path) async {
  if (Platform.isWindows) {
    await Process.run('explorer.exe', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else {
    await Process.run('xdg-open', [path]);
  }
}

class DesktopSettings extends ConsumerWidget {
  const DesktopSettings({super.key});
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e, st) {
      LocalLog.write(e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not complete this action. Check file permissions and try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final player = ref.watch(playerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Desktop & library',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        ListTile(
          title: const Text('Text size'),
          subtitle: Slider(
            label: '${(settings.textScale * 100).round()}%',
            value: settings.textScale,
            min: 0.85,
            max: 1.6,
            divisions: 15,
            onChanged: controller.setTextScale,
          ),
        ),
        StreamBuilder<List<AudioDevice>>(
          stream: player.stream.audioDevices,
          initialData: player.state.audioDevices,
          builder: (context, snapshot) {
            final devices = <String, AudioDevice>{
              'auto': AudioDevice.auto(),
              for (final d in snapshot.data ?? <AudioDevice>[]) d.name: d,
            };
            return ListTile(
              title: const Text('Audio output'),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: devices.containsKey(settings.audioDevice)
                      ? settings.audioDevice
                      : 'auto',
                  items: [
                    for (final d in devices.values)
                      DropdownMenuItem(
                        value: d.name,
                        child: Text(
                          d.name == 'auto' ? 'System default' : d.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      _run(context, () => controller.setAudioDevice(v));
                    }
                  },
                ),
              ),
            );
          },
        ),
        SwitchListTile(
          title: const Text('Exclusive output'),
          subtitle: const Text(
            'Request direct access to the output device. Disables crossfade. For bit-perfect playback, also turn EQ and normalization off, set speed to 1× and volume to 100%.',
          ),
          value: settings.exclusiveMode,
          onChanged: (value) =>
              _run(context, () => controller.setExclusive(value)),
        ),
        ListTile(
          title: Text(
            'Crossfade: ${settings.crossfadeSeconds.toStringAsFixed(1)} seconds',
          ),
          subtitle: Slider(
            label: '${settings.crossfadeSeconds.toStringAsFixed(1)} s',
            value: settings.crossfadeSeconds,
            min: 0,
            max: 12,
            divisions: 24,
            onChanged: settings.exclusiveMode ? null : controller.setCrossfade,
          ),
        ),
        const Divider(),
        Row(
          children: [
            const Expanded(child: Text('Library folders')),
            TextButton.icon(
              onPressed: () => _run(
                context,
                () => ref.read(scanProvider.notifier).addFolder(),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add folder'),
            ),
            IconButton(
              tooltip: 'Rescan folders',
              onPressed: () => ref.read(scanProvider.notifier).rescan(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (settings.libraryFolders.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Add folders to scan on startup and watch for changes.',
            ),
          ),
        for (final folder in settings.libraryFolders)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(folder),
            subtitle: const Text('Watched for changes'),
            trailing: IconButton(
              tooltip: 'Stop watching this folder',
              onPressed: () =>
                  ref.read(scanProvider.notifier).removeFolder(folder),
              icon: const Icon(Icons.close),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Automatic backups'),
          subtitle: Text(
            settings.backupFolder ??
                'Choose a folder. Weekly backups keep the latest five.',
          ),
          trailing: settings.backupFolder == null
              ? null
              : IconButton(
                  tooltip: 'Disable automatic backups',
                  onPressed: () => controller.updatePreferences(
                    settings.copyWith(clearBackupFolder: true),
                  ),
                  icon: const Icon(Icons.close),
                ),
          onTap: () => _run(context, () async {
            final path = await FilePicker.platform.getDirectoryPath(
              dialogTitle: 'Choose automatic backup folder',
            );
            if (path == null) return;
            final next = settings.copyWith(backupFolder: path);
            await controller.updatePreferences(next);
            await ref.read(backupServiceProvider).automaticBackup(next);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Automatic backups enabled. First backup saved.',
                  ),
                ),
              );
            }
          }),
        ),
        ListTile(
          leading: const Icon(Icons.copy_all),
          title: const Text('Find duplicate tracks'),
          subtitle: const Text(
            'Compare title, artist and duration. Choose which copies to remove.',
          ),
          onTap: () => showDialog(
            context: context,
            builder: (_) => const DuplicateFinderDialog(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.volume_up_outlined),
          title: const Text('Scan ReplayGain loudness'),
          subtitle: const Text(
            'Measure local files with ffmpeg. Requires ffmpeg installed on this computer.',
          ),
          onTap: () => showDialog(
            context: context,
            builder: (_) => const LoudnessScanDialog(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.table_chart_outlined),
          title: const Text('Export listening stats as CSV'),
          onTap: () => _run(context, () async {
            final path = await FilePicker.platform.saveFile(
              fileName: 'electrowave-stats.csv',
              type: FileType.custom,
              allowedExtensions: ['csv'],
            );
            if (path != null) {
              await FileExchange(ref.read(databaseProvider)).exportStats(path);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Stats exported.')),
                );
              }
            }
          }),
        ),
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('Open app data folder'),
          subtitle: const Text(
            'Place a file named portable beside the app to store data there instead.',
          ),
          onTap: () => _run(
            context,
            () async => openLocalFolder((await appDataDirectory()).path),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open logs folder'),
          subtitle: const Text(
            'Crash logs stay on this computer. Nothing is sent anywhere.',
          ),
          onTap: () => _run(
            context,
            () async => openLocalFolder((await LocalLog.directory()).path),
          ),
        ),
      ],
    );
  }
}

class DuplicateFinderDialog extends ConsumerWidget {
  const DuplicateFinderDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AlertDialog(
    title: const Text('Duplicate tracks'),
    content: SizedBox(
      width: 640,
      height: 440,
      child: StreamBuilder(
        stream: ref.watch(databaseProvider).watchLibrary(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = findDuplicates(snapshot.data!);
          if (groups.isEmpty) {
            return const Center(child: Text('No likely duplicates found.'));
          }
          return ListView(
            children: [
              for (final group in groups)
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(
                          '${group.first.artist} — ${group.first.title}',
                        ),
                        subtitle: Text(
                          '${group.length} copies. Removing a copy keeps its file and play history.',
                        ),
                      ),
                      for (final track in group)
                        ListTile(
                          dense: true,
                          title: Text(track.filePath),
                          subtitle: Text(
                            '${(track.durationMs / 1000).round()} s',
                          ),
                          trailing: TextButton(
                            onPressed: () => ref
                                .read(databaseProvider)
                                .softDeleteMany([track.id]),
                            child: const Text('Remove this copy'),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

class LoudnessScanDialog extends ConsumerStatefulWidget {
  const LoudnessScanDialog({super.key});
  @override
  ConsumerState<LoudnessScanDialog> createState() => _LoudnessScanDialogState();
}

class _LoudnessScanDialogState extends ConsumerState<LoudnessScanDialog> {
  LoudnessScanner? _scanner;
  int _done = 0, _total = 0;
  bool _running = false;
  String _message =
      'Measures loudness without changing your audio. Enable volume normalization to use the saved results.';
  @override
  void dispose() {
    _scanner?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _running = true);
    final scanner = LoudnessScanner(ref.read(databaseProvider));
    _scanner = scanner;
    try {
      final tracks = await ref.read(databaseProvider).watchLibrary().first;
      final saved = await scanner.scan(tracks, (done, total) {
        if (mounted) {
          setState(() {
            _done = done;
            _total = total;
          });
        }
      });
      if (mounted) {
        setState(
          () => _message =
              '${scanner.cancelled ? 'Cancelled. ' : ''}Saved loudness for $saved tracks.',
        );
      }
    } on ProcessException {
      if (mounted) {
        setState(
          () => _message =
              'ffmpeg was not found. Install ffmpeg, add it to PATH, and try again.',
        );
      }
    } catch (e, st) {
      LocalLog.write(e, st);
      if (mounted) {
        setState(
          () => _message =
              'Could not read a file. Check your music folders and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ReplayGain scanner'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_message),
          if (_running) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            Text('Scanning $_done / $_total'),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          _scanner?.cancel();
          Navigator.pop(context);
        },
        child: Text(_running ? 'Cancel' : 'Close'),
      ),
      if (!_running)
        FilledButton(onPressed: _start, child: const Text('Scan library')),
    ],
  );
}
