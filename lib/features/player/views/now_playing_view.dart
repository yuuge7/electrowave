import '../services/audio_file_info.dart';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/database/app_database.dart';
import '../../library/views/browse_views.dart';
import '../providers/player_provider.dart';
import '../providers/queue_provider.dart';
import '../../../shared/theme/app_theme.dart';

final lyricsProvider = FutureProvider.family<String, int>((ref, id) async {
  final track = ref.read(currentTrackProvider);
  if (track == null || track.id != id) return '';
  final path = track.filePath;
  return Isolate.run(() {
    for (final extension in ['.lrc', '.txt']) {
      final file = File(p.setExtension(path, extension));
      if (file.existsSync()) return file.readAsStringSync();
    }
    try {
      return readMetadata(File(path), getImage: false).lyrics ?? '';
    } catch (_) {
      return '';
    }
  });
});

class NowPlayingView extends ConsumerWidget {
  const NowPlayingView({super.key, required this.onClose});
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    if (track == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose a track to start listening.'),
            TextButton(
              onPressed: onClose,
              child: const Text('Back to library'),
            ),
          ],
        ),
      );
    }
    final queue = ref.watch(queueProvider);
    final next = [
      ...queue.manualQueue,
      ...queue.upcomingFromContext,
    ].where((t) => !t.isMissing).take(6).toList();
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (track.coverArtPath != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
            child: Image.file(
              File(track.coverArtPath!),
              fit: BoxFit.cover,
              cacheWidth: 800,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ColoredBox(color: colors.background.withValues(alpha: 0.85)),
        SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Close now playing',
                    onPressed: onClose,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'NOW PLAYING',
                    style: TextStyle(letterSpacing: 2, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final art = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ArtThumb(
                        path: track.coverArtPath,
                        size: constraints.maxWidth > 760 ? 320 : 220,
                        radius: 12,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        track.title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                        '${track.artist} · ${track.album}',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      const PlaybackControls(),
                      const SizedBox(height: 16),
                      _AudioInfo(track: track),
                    ],
                  );
                  final words = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lyrics',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      ref
                          .watch(lyricsProvider(track.id))
                          .when(
                            data: (text) => SelectableText(
                              text.isEmpty
                                  ? 'Add a .lrc or .txt file beside this track to see lyrics here.'
                                  : text
                                        .replaceAll(
                                          RegExp(r'\[\d+:\d+(?:\.\d+)?\]'),
                                          '',
                                        )
                                        .trim(),
                              style: TextStyle(
                                fontSize: 18,
                                height: 1.8,
                                color: colors.textSecondary,
                              ),
                            ),
                            loading: () => const CircularProgressIndicator(),
                            error: (_, _) =>
                                const Text('Lyrics could not be read.'),
                          ),
                    ],
                  );
                  return constraints.maxWidth > 760
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 360, child: art),
                            const SizedBox(width: 48),
                            Expanded(child: words),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [art, const SizedBox(height: 32), words],
                        );
                },
              ),
              const SizedBox(height: 32),
              Text('Up next', style: Theme.of(context).textTheme.titleLarge),
              for (final item in next)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ArtThumb(path: item.coverArtPath, size: 40),
                  title: Text(item.title),
                  subtitle: Text(item.artist),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

final audioFileInfoProvider = FutureProvider.family<String, String>(
  (ref, path) => Isolate.run(() => describeAudioFile(path)),
);

class _AudioInfo extends ConsumerWidget {
  const _AudioInfo({required this.track});
  final Track track;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
    ref.watch(audioFileInfoProvider(track.filePath)).value ??
        p.extension(track.filePath).toUpperCase(),
    style: TextStyle(color: context.colors.textFaint, fontSize: 12),
  );
}

class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous track',
          onPressed: () =>
              ref.read(playbackControllerProvider).playPreviousTrack(),
          icon: const Icon(Icons.skip_previous),
        ),
        StreamBuilder<bool>(
          stream: player.stream.playing,
          initialData: player.state.playing,
          builder: (_, snapshot) => IconButton.filled(
            tooltip: snapshot.data == true ? 'Pause' : 'Play',
            onPressed: () =>
                ref.read(playbackControllerProvider).togglePlayback(),
            icon: Icon(snapshot.data == true ? Icons.pause : Icons.play_arrow),
          ),
        ),
        IconButton(
          tooltip: 'Next track',
          onPressed: () => ref.read(playbackControllerProvider).playNextTrack(),
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }
}

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, required this.onExpand});
  final VoidCallback onExpand;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    return Material(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                ArtThumb(path: track?.coverArtPath, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track?.title ?? 'Electrowave',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        track?.artist ?? 'Choose music in your library',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.colors.textFaint),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Return to full player',
                  onPressed: onExpand,
                  icon: const Icon(Icons.open_in_full),
                ),
              ],
            ),
            const Spacer(),
            const PlaybackControls(),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
