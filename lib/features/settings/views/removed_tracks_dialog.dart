import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../../../shared/theme/app_theme.dart';
import '../../library/providers/library_provider.dart';

/// Removing a track from the library is a soft delete, so its play history
/// survives. This is where those rows come back — or go for good.
///
/// Either way the audio file on disk is never touched.
class RemovedTracksDialog extends ConsumerWidget {
  const RemovedTracksDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final removedAsync = ref.watch(deletedTracksProvider);
    final database = ref.read(databaseProvider);

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Removed tracks', style: TextStyle(color: colors.textPrimary)),
      content: SizedBox(
        width: 520,
        height: 420,
        child: removedAsync.when(
          data: (tracks) {
            if (tracks.isEmpty) {
              return Center(
                child: Text('Nothing has been removed.',
                    style: TextStyle(color: colors.textFaint)),
              );
            }
            return ListView.separated(
              itemCount: tracks.length,
              separatorBuilder: (context, index) =>
                  Divider(color: colors.border, height: 1),
              itemBuilder: (context, index) {
                final track = tracks[index];
                return ListTile(
                  title: Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textPrimary)),
                  subtitle: Text('${track.artist} • ${track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: colors.textFaint, fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => database.restoreTrack(track.id),
                        child: Text('Restore',
                            style: TextStyle(color: colors.accent)),
                      ),
                      IconButton(
                        tooltip: 'Delete permanently (keeps the file on disk)',
                        icon: const Icon(Icons.delete_forever,
                            color: Colors.redAccent, size: 20),
                        onPressed: () => database.purgeTrack(track.id),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          loading: () =>
              Center(child: CircularProgressIndicator(color: colors.accent)),
          error: (err, stack) => Center(
              child:
                  Text('Error: $err', style: const TextStyle(color: Colors.red))),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final removed = await database.emptyTrash();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$removed tracks deleted permanently.'),
                backgroundColor: colors.accent,
              ),
            );
          },
          child: const Text('Empty list',
              style: TextStyle(color: Colors.redAccent)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close',
              style:
                  TextStyle(color: colors.accent, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
