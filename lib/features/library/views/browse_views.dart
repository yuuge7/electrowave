import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../shared/theme/app_theme.dart';
import '../../player/providers/player_provider.dart';
import '../providers/library_provider.dart';
import 'track_table.dart';
import 'track_actions.dart';
import '../../../main.dart';
import '../../../shared/widgets/retry_message.dart';

/// Album art thumbnail.
///
/// The decode is bounded by [size]: a full-resolution decode of oversized
/// embedded art fails where a downscaled decode of the same file succeeds,
/// which is what makes large covers fall back to the placeholder.
class ArtThumb extends StatelessWidget {
  const ArtThumb({
    super.key,
    required this.path,
    this.size = 48,
    this.radius = 8,
  });

  final String? path;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final placeholder = Icon(
      Icons.music_note,
      color: colors.textFaint,
      size: size * 0.5,
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: path == null
          ? placeholder
          : Image.file(
              File(path!),
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
    );
  }
}

String formatTotalMs(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

class AlbumsGrid extends ConsumerWidget {
  const AlbumsGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final albumsAsync = ref.watch(albumsProvider);

    return albumsAsync.when(
      data: (albums) {
        if (albums.isEmpty) {
          return Center(
            child: Text(
              'No albums yet.',
              style: TextStyle(color: colors.textFaint),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.78,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onSecondaryTapDown: (d) async {
                final tracks = await ref
                    .read(databaseProvider)
                    .watchAlbumTracks(album.album, albumArtist: album.artist)
                    .first;
                if (context.mounted) {
                  await showTrackActions(
                    context,
                    ref,
                    tracks,
                    d.globalPosition,
                  );
                }
              },
              onTap: () => ref
                  .read(browseDetailProvider.notifier)
                  .open(
                    LibraryBrowseMode.albums,
                    '${album.album}\u0000${album.artist}',
                  ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ArtThumb(
                      path: album.coverArtPath,
                      size: 400,
                      radius: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    album.album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${album.artist} • ${album.trackCount} tracks',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textFaint, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () =>
          Center(child: CircularProgressIndicator(color: colors.accent)),
      error: (err, stack) =>
          RetryMessage(onRetry: () => ref.invalidate(albumsProvider)),
    );
  }
}

class ArtistsList extends ConsumerWidget {
  const ArtistsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final artistsAsync = ref.watch(artistsProvider);

    return artistsAsync.when(
      data: (artists) {
        if (artists.isEmpty) {
          return Center(
            child: Text(
              'No artists yet.',
              style: TextStyle(color: colors.textFaint),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: artists.length,
          separatorBuilder: (context, index) =>
              Divider(color: colors.border, height: 1),
          itemBuilder: (context, index) {
            final artist = artists[index];
            return GestureDetector(
              onSecondaryTapDown: (d) async {
                final tracks = await ref
                    .read(databaseProvider)
                    .watchArtistTracks(artist.artist)
                    .first;
                if (context.mounted) {
                  await showTrackActions(
                    context,
                    ref,
                    tracks,
                    d.globalPosition,
                  );
                }
              },
              child: ListTile(
                leading: ArtThumb(path: artist.coverArtPath),
                title: Text(
                  artist.artist,
                  style: TextStyle(color: colors.textPrimary),
                ),
                subtitle: Text(
                  '${artist.albumCount} albums • ${artist.trackCount} tracks • '
                  '${formatTotalMs(artist.totalMs)}',
                  style: TextStyle(color: colors.textFaint, fontSize: 12),
                ),
                onTap: () => ref
                    .read(browseDetailProvider.notifier)
                    .open(LibraryBrowseMode.artists, artist.artist),
              ),
            );
          },
        );
      },
      loading: () =>
          Center(child: CircularProgressIndicator(color: colors.accent)),
      error: (err, stack) =>
          RetryMessage(onRetry: () => ref.invalidate(artistsProvider)),
    );
  }
}

class FoldersList extends ConsumerWidget {
  const FoldersList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final foldersAsync = ref.watch(foldersProvider);

    return foldersAsync.when(
      data: (folders) {
        if (folders.isEmpty) {
          return Center(
            child: Text(
              'No folders yet.',
              style: TextStyle(color: colors.textFaint),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: folders.length,
          separatorBuilder: (context, index) =>
              Divider(color: colors.border, height: 1),
          itemBuilder: (context, index) {
            final folder = folders[index];
            return GestureDetector(
              onSecondaryTapDown: (d) async {
                final tracks = await ref
                    .read(databaseProvider)
                    .watchFolderTracks(folder.path)
                    .first;
                if (context.mounted) {
                  await showTrackActions(
                    context,
                    ref,
                    tracks,
                    d.globalPosition,
                  );
                }
              },
              child: ListTile(
                leading: Icon(Icons.folder, color: colors.accent),
                title: Text(
                  folder.name,
                  style: TextStyle(color: colors.textPrimary),
                ),
                subtitle: Text(
                  '${folder.path} • ${folder.trackCount} tracks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textFaint, fontSize: 12),
                ),
                onTap: () => ref
                    .read(browseDetailProvider.notifier)
                    .open(LibraryBrowseMode.folders, folder.path),
              ),
            );
          },
        );
      },
      loading: () =>
          Center(child: CircularProgressIndicator(color: colors.accent)),
      error: (err, stack) =>
          RetryMessage(onRetry: () => ref.invalidate(foldersProvider)),
    );
  }
}

/// Header + track list for one album, artist, folder or smart list.
class TrackListPage extends ConsumerWidget {
  const TrackListPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.tracksAsync,
    required this.onBack,
    this.showAlbum = true,
  });

  final String title;
  final String subtitle;
  final AsyncValue<List<db.Track>> tracksAsync;
  final VoidCallback onBack;
  final bool showAlbum;

  void _playAll(WidgetRef ref, List<db.Track> tracks, {required bool shuffle}) {
    if (tracks.isEmpty) return;
    ref.read(shuffleProvider.notifier).set(shuffle);
    final index = shuffle ? Random().nextInt(tracks.length) : 0;
    ref.read(playbackControllerProvider).playFromContext(tracks, index);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return tracksAsync.when(
      data: (tracks) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  color: colors.textSecondary,
                  onPressed: onBack,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textFaint, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                  ),
                  onPressed: () => _playAll(ref, tracks, shuffle: false),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    side: BorderSide(color: colors.border),
                  ),
                  onPressed: () => _playAll(ref, tracks, shuffle: true),
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle'),
                ),
              ],
            ),
          ),
          Expanded(
            child: TrackTable(tracks: tracks, showAlbum: showAlbum),
          ),
        ],
      ),
      loading: () =>
          Center(child: CircularProgressIndicator(color: colors.accent)),
      error: (err, stack) => RetryMessage(
        onRetry: () {
          ref.invalidate(albumTracksProvider);
          ref.invalidate(artistTracksProvider);
          ref.invalidate(folderTracksProvider);
          ref.invalidate(smartListTracksProvider);
          ref.invalidate(categoryTracksProvider);
        },
      ),
    );
  }
}

final categoryTracksProvider =
    StreamProvider.family<
      List<db.Track>,
      ({LibraryBrowseMode mode, String key})
    >(
      (ref, query) => query.mode == LibraryBrowseMode.genres
          ? ref.watch(databaseProvider).watchGenre(query.key)
          : ref.watch(databaseProvider).watchYear(int.parse(query.key)),
    );

class CategoriesList extends ConsumerWidget {
  const CategoriesList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(libraryBrowseModeProvider);
    return ref
        .watch(libraryProvider)
        .when(
          data: (tracks) {
            final groups = <String, int>{};
            for (final t in tracks) {
              final key = mode == LibraryBrowseMode.genres
                  ? t.genre
                  : t.year?.toString();
              if (key != null && key.isNotEmpty) {
                groups[key] = (groups[key] ?? 0) + 1;
              }
            }
            final keys = groups.keys.toList()..sort();
            if (mode == LibraryBrowseMode.years) {
              keys.sort((a, b) => b.compareTo(a));
            }
            return ListView.builder(
              itemCount: keys.length,
              itemBuilder: (context, index) => ListTile(
                leading: Icon(
                  mode == LibraryBrowseMode.genres
                      ? Icons.category
                      : Icons.calendar_today,
                ),
                title: Text(keys[index]),
                subtitle: Text('${groups[keys[index]]} tracks'),
                onTap: () => ref
                    .read(browseDetailProvider.notifier)
                    .open(mode, keys[index]),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              RetryMessage(onRetry: () => ref.invalidate(libraryProvider)),
        );
  }
}
