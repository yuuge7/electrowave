import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../player/providers/player_provider.dart';
import '../../player/providers/queue_provider.dart';
import '../providers/wrapped_stats_provider.dart';
import '../services/backup_service.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  void _handleExport(BuildContext context, WidgetRef ref) async {
    final success = await ref.read(backupServiceProvider).exportDatabase();
    if (context.mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup exported successfully!', style: TextStyle(color: Colors.black)), 
          backgroundColor: Colors.greenAccent
        )
      );
    }
  }

  void _handleImport(BuildContext context, WidgetRef ref) async {
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
      builder: (dialogContext) => const Center(
        child: CircularProgressIndicator(color: Colors.greenAccent)
      ),
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
          backgroundColor: const Color(0xFF181818),
          title: const Text('Import Ready', style: TextStyle(color: Colors.greenAccent)),
          content: const Text(
            'Backup file has been staged successfully!\n\nBecause Windows locks active databases, the app must be restarted to apply the new library.', 
            style: TextStyle(color: Colors.white70)
          ),
          actions: [
            TextButton(
              onPressed: () => exit(0), 
              child: const Text('Close App Now', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        )
      );
    }
  }

  void _startRelocationFlow(BuildContext context, WidgetRef ref) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your new Music folder',
    );

    if (selectedDirectory != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scanning new folder and repairing links...', style: TextStyle(color: Colors.black)), backgroundColor: Colors.greenAccent)
      );

      final database = ref.read(databaseProvider);
      final count = await ref.read(backupServiceProvider).relocateLibrary(selectedDirectory, database);

      if (context.mounted) {
         showDialog(
           context: context,
           barrierDismissible: false,
           builder: (context) => AlertDialog(
             backgroundColor: const Color(0xFF181818),
             title: const Text('Migration Complete', style: TextStyle(color: Colors.greenAccent)),
             content: Text(
               'Successfully repaired $count file paths!\n\nThe app will now restart to apply changes.',
               style: const TextStyle(color: Colors.white70)
             ),
             actions: [
               TextButton(
                 onPressed: () => exit(0),
                 child: const Text('Restart Now', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
               ),
             ]
           )
         );
      }
    }
  }

  void _confirmClearLibrary(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF181818),
        title: const Text('Clear Library', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Wipe entire database? Files remain safe.', 
          style: TextStyle(color: Colors.white70)
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final database = ref.read(databaseProvider);
              final player = ref.read(playerProvider);
              
              await player.stop();
              ref.read(currentTrackProvider.notifier).setTrack(null);
              ref.read(queueProvider.notifier).reset();

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text('Database Management', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: const Color(0xFF181818),
            iconColor: Colors.blueAccent,
            textColor: Colors.blueAccent,
            leading: const Icon(Icons.download),
            title: const Text('Export Backup'),
            subtitle: const Text('Save a copy of your library, playlists, and history.', style: TextStyle(color: Colors.grey)),
            onTap: () => _handleExport(context, ref),
          ),
          const SizedBox(height: 8),

          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: const Color(0xFF181818),
            iconColor: Colors.orangeAccent,
            textColor: Colors.orangeAccent,
            leading: const Icon(Icons.upload),
            title: const Text('Import Backup'),
            subtitle: const Text('Restore your library from a previous backup file.', style: TextStyle(color: Colors.grey)),
            onTap: () => _handleImport(context, ref),
          ),
          const SizedBox(height: 8),

          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: const Color(0xFF181818),
            iconColor: Colors.purpleAccent,
            textColor: Colors.purpleAccent,
            leading: const Icon(Icons.sync_alt),
            title: const Text('Repair Broken Links'),
            subtitle: const Text('Use this if you moved your music to a new folder or OS.', style: TextStyle(color: Colors.grey)),
            onTap: () => _startRelocationFlow(context, ref),
          ),
          const SizedBox(height: 8),

          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: const Color(0xFF181818),
            iconColor: Colors.redAccent,
            textColor: Colors.redAccent,
            leading: const Icon(Icons.delete_forever),
            title: const Text('Clear Entire Library'),
            subtitle: const Text('Wipes the database so you can scan a fresh folder.', style: TextStyle(color: Colors.grey)),
            onTap: () => _confirmClearLibrary(context, ref),
          ),

          const SizedBox(height: 32),
    
          const Text('About', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            tileColor: const Color(0xFF181818),
            leading: const Icon(Icons.info_outline, color: Colors.white),
            title: const Text('Local Player', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Version 1.0.0', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}