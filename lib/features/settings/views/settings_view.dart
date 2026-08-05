import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../../shared/theme/app_theme.dart';
import '../../player/providers/player_provider.dart';
import '../../player/providers/queue_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/wrapped_stats_provider.dart';
import '../services/backup_service.dart';
import '../services/settings_persistence.dart';
import 'equalizer_dialog.dart';
import 'removed_tracks_dialog.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  void _handleExport(BuildContext context, WidgetRef ref) async {
    final success = await ref.read(backupServiceProvider).exportDatabase();
    if (context.mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup exported successfully!',
              style: TextStyle(color: context.colors.onAccent)),
          backgroundColor: context.colors.accent,
        )
      );
    }
  }

  void _handleImport(BuildContext context, WidgetRef ref) async {
    final colors = context.colors;
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Library Backup',
      type: FileType.custom,
      allowedExtensions: ['sqlite', 'db'],
    );

    if (result == null || result.files.single.path == null) return;
    final backupPath = result.files.single.path!;

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          Center(child: CircularProgressIndicator(color: colors.accent)),
    );

    // STAGE the file instead of trying to overwrite the locked database
    final success = await ref.read(backupServiceProvider).stageImport(backupPath);

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (context.mounted && success) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text('Import Ready', style: TextStyle(color: colors.accent)),
          content: Text(
            'Backup file has been staged successfully!\n\nBecause Windows locks active databases, the app must be restarted to apply the new library.',
            style: TextStyle(color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => exit(0),
              child: Text('Close App Now',
                  style: TextStyle(
                      color: colors.accent, fontWeight: FontWeight.bold)),
            ),
          ],
        )
      );
    }
  }

  void _startRelocationFlow(BuildContext context, WidgetRef ref) async {
    final colors = context.colors;
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your new Music folder',
    );

    if (selectedDirectory != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Scanning new folder and repairing links...',
                style: TextStyle(color: colors.onAccent)),
            backgroundColor: colors.accent),
      );

      final database = ref.read(databaseProvider);
      final count = await ref.read(backupServiceProvider).relocateLibrary(selectedDirectory, database);

      if (context.mounted) {
         showDialog(
           context: context,
           barrierDismissible: false,
           builder: (context) => AlertDialog(
             backgroundColor: colors.surface,
             title: Text('Migration Complete',
                 style: TextStyle(color: colors.accent)),
             content: Text(
               'Successfully repaired $count file paths!\n\nThe app will now restart to apply changes.',
               style: TextStyle(color: colors.textSecondary),
             ),
             actions: [
               TextButton(
                 onPressed: () => exit(0),
                 child: Text('Restart Now',
                     style: TextStyle(
                         color: colors.accent, fontWeight: FontWeight.bold)),
               ),
             ]
           )
         );
      }
    }
  }

  void _confirmClearLibrary(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Clear Library', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Wipe entire database? Files remain safe.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textFaint)),
          ),
          TextButton(
            onPressed: () async {
              final database = ref.read(databaseProvider);
              final player = ref.read(playerProvider);

              await player.stop();
              ref.read(currentTrackProvider.notifier).setTrack(null);
              ref.read(queueProvider.notifier).reset();

              await database.delete(database.listeningSessions).go();
              await database.delete(database.playbackHistory).go();
              await database.delete(database.playlistTracks).go();
              await database.delete(database.playlists).go();
              await database.delete(database.tracks).go();

              ref.invalidate(wrappedStatsProvider);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      )
    );
  }

  void _confirmClearHistory(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Clear Play History',
            style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Deletes play counts, last-played dates and measured listening time. '
          'Your tracks and playlists stay exactly as they are.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textFaint)),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(databaseProvider).clearPlayHistory();
              ref.invalidate(wrappedStatsProvider);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(text,
        style: TextStyle(
            color: context.colors.accent, fontWeight: FontWeight.bold));
  }

  Widget _card(BuildContext context, {required Widget child}) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }

  Widget _appearanceSection(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final mode = ref.watch(
        settingsControllerProvider.select((settings) => settings.themeMode));

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme', style: TextStyle(color: colors.textPrimary)),
          const SizedBox(height: 4),
          Text('Follow the system, or pin light or dark.',
              style: TextStyle(color: colors.textFaint, fontSize: 12)),
          const SizedBox(height: 12),
          SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(
                  value: AppThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('System')),
              ButtonSegment(
                  value: AppThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('Light')),
              ButtonSegment(
                  value: AppThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('Dark')),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => ref
                .read(settingsControllerProvider.notifier)
                .setThemeMode(selection.first),
          ),
        ],
      ),
    );
  }

  Widget _playbackSection(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Playback speed',
                  style: TextStyle(color: colors.textPrimary)),
              const Spacer(),
              Text('${settings.playbackRate.toStringAsFixed(2)}×',
                  style: TextStyle(
                      color: colors.accent, fontWeight: FontWeight.bold)),
            ],
          ),
          Text('Pitch-preserving, and re-applied to every track.',
              style: TextStyle(color: colors.textFaint, fontSize: 12)),
          Slider(
            value: settings.playbackRate.clamp(0.5, 2.0),
            min: 0.5,
            max: 2.0,
            divisions: 30,
            activeColor: colors.accent,
            inactiveColor: colors.border,
            label: '${settings.playbackRate.toStringAsFixed(2)}×',
            onChanged: controller.setPlaybackRate,
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => controller.setPlaybackRate(1.0),
                child: Text('Reset to 1.00×',
                    style: TextStyle(color: colors.textFaint)),
              ),
            ],
          ),
          Divider(color: colors.border),
          const SizedBox(height: 8),

          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.graphic_eq, color: colors.accent),
            title: Text('Equalizer', style: TextStyle(color: colors.textPrimary)),
            subtitle: Text(
              settings.eqEnabled ? '5-band EQ is on' : '5-band EQ is off',
              style: TextStyle(color: colors.textFaint, fontSize: 12),
            ),
            trailing: Icon(Icons.chevron_right, color: colors.textFaint),
            onTap: () => showDialog(
              context: context,
              builder: (context) => const EqualizerDialog(),
            ),
          ),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Volume normalization',
                        style: TextStyle(color: colors.textPrimary)),
                    Text('Uses the ReplayGain tags in your files.',
                        style: TextStyle(color: colors.textFaint, fontSize: 12)),
                  ],
                ),
              ),
              DropdownButton<ReplayGainMode>(
                value: settings.replayGain,
                dropdownColor: colors.surfaceAlt,
                underline: const SizedBox(),
                style: TextStyle(color: colors.textPrimary),
                items: const [
                  DropdownMenuItem(
                      value: ReplayGainMode.off, child: Text('Off')),
                  DropdownMenuItem(
                      value: ReplayGainMode.track, child: Text('Per track')),
                  DropdownMenuItem(
                      value: ReplayGainMode.album, child: Text('Per album')),
                ],
                onChanged: (value) {
                  if (value != null) controller.setReplayGain(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stop when unattended',
                        style: TextStyle(color: colors.textPrimary)),
                    Text(
                      'Stops playback after this long with no interaction at '
                      'all. Any click or media key resets it.',
                      style: TextStyle(color: colors.textFaint, fontSize: 12),
                    ),
                  ],
                ),
              ),
              DropdownButton<int>(
                value: kInactivityStopChoicesMinutes
                        .contains(settings.inactivityStopMinutes)
                    ? settings.inactivityStopMinutes
                    : 0,
                dropdownColor: colors.surfaceAlt,
                underline: const SizedBox(),
                style: TextStyle(color: colors.textPrimary),
                items: [
                  for (final minutes in kInactivityStopChoicesMinutes)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(switch (minutes) {
                        0 => 'Off',
                        final m when m < 60 => '$m min',
                        final m when m == 60 => '1 hour',
                        final m => '${m ~/ 60} hours',
                      }),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) controller.setInactivityStopMinutes(value);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Settings',
            style: TextStyle(
                color: colors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _sectionTitle(context, 'Appearance'),
          const SizedBox(height: 8),
          _appearanceSection(context, ref),

          const SizedBox(height: 32),
          _sectionTitle(context, 'Playback'),
          const SizedBox(height: 8),
          _playbackSection(context, ref),

          const SizedBox(height: 32),
          _sectionTitle(context, 'Library'),
          const SizedBox(height: 8),

          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: colors.surface,
            iconColor: colors.textSecondary,
            textColor: colors.textPrimary,
            leading: const Icon(Icons.restore_from_trash),
            title: const Text('Removed tracks'),
            subtitle: Text(
                'Restore soft-deleted tracks, or delete them for good.',
                style: TextStyle(color: colors.textFaint)),
            onTap: () => showDialog(
              context: context,
              builder: (context) => const RemovedTracksDialog(),
            ),
          ),
          const SizedBox(height: 8),

          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: colors.surface,
            iconColor: Colors.orangeAccent,
            textColor: Colors.orangeAccent,
            leading: const Icon(Icons.history_toggle_off),
            title: const Text('Clear Play History'),
            subtitle: Text(
                'Resets play counts, stats and measured listening time.',
                style: TextStyle(color: colors.textFaint)),
            onTap: () => _confirmClearHistory(context, ref),
          ),

          const SizedBox(height: 32),
          _sectionTitle(context, 'Database Management'),
          const SizedBox(height: 8),

          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: colors.surface,
            iconColor: Colors.blueAccent,
            textColor: Colors.blueAccent,
            leading: const Icon(Icons.download),
            title: const Text('Export Backup'),
            subtitle: Text('Save a copy of your library, playlists, and history.',
                style: TextStyle(color: colors.textFaint)),
            onTap: () => _handleExport(context, ref),
          ),
          const SizedBox(height: 8),

          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: colors.surface,
            iconColor: Colors.orangeAccent,
            textColor: Colors.orangeAccent,
            leading: const Icon(Icons.upload),
            title: const Text('Import Backup'),
            subtitle: Text('Restore your library from a previous backup file.',
                style: TextStyle(color: colors.textFaint)),
            onTap: () => _handleImport(context, ref),
          ),
          const SizedBox(height: 8),

          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: colors.surface,
            iconColor: Colors.purpleAccent,
            textColor: Colors.purpleAccent,
            leading: const Icon(Icons.sync_alt),
            title: const Text('Repair Broken Links'),
            subtitle: Text('Use this if you moved your music to a new folder or OS.',
                style: TextStyle(color: colors.textFaint)),
            onTap: () => _startRelocationFlow(context, ref),
          ),
          const SizedBox(height: 8),

          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: colors.surface,
            iconColor: Colors.redAccent,
            textColor: Colors.redAccent,
            leading: const Icon(Icons.delete_forever),
            title: const Text('Clear Entire Library'),
            subtitle: Text('Wipes the database so you can scan a fresh folder.',
                style: TextStyle(color: colors.textFaint)),
            onTap: () => _confirmClearLibrary(context, ref),
          ),

          const SizedBox(height: 32),

          _sectionTitle(context, 'About'),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: colors.surface,
            leading: Icon(Icons.info_outline, color: colors.textPrimary),
            title: Text('Electrowave', style: TextStyle(color: colors.textPrimary)),
            subtitle: Text('Version 1.0.0', style: TextStyle(color: colors.textFaint)),
          ),
        ],
      ),
    );
  }
}
