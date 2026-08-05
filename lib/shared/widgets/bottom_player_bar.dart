import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../services/tray_service.dart';
import '../theme/app_theme.dart';
import '../../features/library/providers/library_provider.dart';
import '../../features/player/providers/player_provider.dart';
import '../../features/player/providers/queue_provider.dart';
import '../../features/player/providers/sleep_timer_provider.dart';
import '../../features/player/services/audio_engine.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../main.dart';

class BottomPlayerBar extends ConsumerWidget {
  const BottomPlayerBar({super.key});

  String _formatDuration(Duration? duration) {
    if (duration == null) return "00:00";
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final player = ref.watch(playerProvider);
    final engine = ref.read(audioEngineProvider);
    final playerTrack = ref.watch(currentTrackProvider);

    // The live row keeps the heart and any tag edit in step with the library
    // without reopening the file.
    final currentTrack = playerTrack == null
        ? null
        : switch (ref.watch(liveTrackProvider(playerTrack.id))) {
            AsyncData(:final value) => value ?? playerTrack,
            _ => playerTrack,
          };

    return Container(
      // Increased height slightly to give the internal elements more breathing room
      height: 110,
      // Using .all(16) gives it equal spacing on every side, perfectly centering it
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 1. The Seek Bar (Progress Slider)
          StreamBuilder<Duration>(
            stream: player.stream.position,
            builder: (context, positionSnapshot) {
              return StreamBuilder<Duration>(
                stream: player.stream.duration,
                builder: (context, durationSnapshot) {
                  final position = positionSnapshot.data ?? Duration.zero;
                  final duration = durationSnapshot.data ?? Duration.zero;

                  final maxDuration = duration.inMilliseconds > 0
                      ? duration.inMilliseconds.toDouble()
                      : 1.0;

                  final currentPosition = position.inMilliseconds.toDouble().clamp(0.0, maxDuration);

                  return Padding(
                    // Added top padding here so the slider doesn't touch the top border
                    padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 10.0),
                    child: Row(
                      children: [
                        Text(_formatDuration(position),
                            style: TextStyle(color: colors.textFaint, fontSize: 12)),
                        Expanded(
                          child: Slider(
                            activeColor: colors.accent,
                            inactiveColor: colors.border,
                            value: currentPosition,
                            max: maxDuration,
                            onChanged: (value) {
                              engine.noteUserActivity();
                              player.seek(Duration(milliseconds: value.toInt()));
                            },
                          ),
                        ),
                        Text(_formatDuration(duration),
                            style: TextStyle(color: colors.textFaint, fontSize: 12)),
                      ],
                    ),
                  );
                }
              );
            }
          ),

          // 2. Track Info, Playback, and Volume Controls
          Expanded(
            child: Padding(
              // Kept horizontal padding, adjusted bottom padding to match the top visually
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
              child: Row(
                children: [
                  // Left: Track Info with Cover Art
                  Expanded(
                    flex: 1,
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colors.surfaceAlt,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: currentTrack?.coverArtPath != null
                              ? Image.file(
                                  File(currentTrack!.coverArtPath!),
                                  fit: BoxFit.cover,
                                  cacheWidth: (48 *
                                          MediaQuery.devicePixelRatioOf(context))
                                      .round(),
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(Icons.music_note,
                                          color: colors.textFaint, size: 24),
                                )
                              : Icon(Icons.music_note,
                                  color: colors.textFaint, size: 24),
                        ),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(currentTrack?.title ?? 'No Track',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(currentTrack?.artist ?? 'Select a track',
                                style: TextStyle(color: colors.textFaint, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        // Favourite the playing track without hunting for it
                        // in the library.
                        if (currentTrack != null)
                          IconButton(
                            tooltip: currentTrack.isFavorite
                                ? 'Remove from favorites'
                                : 'Add to favorites',
                            icon: Icon(
                              currentTrack.isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 20,
                            ),
                            color: currentTrack.isFavorite
                                ? colors.accent
                                : colors.textFaint,
                            onPressed: () => ref
                                .read(databaseProvider)
                                .setFavorite(
                                    currentTrack.id, !currentTrack.isFavorite),
                          ),
                      ],
                    ),
                  ),

                  // Center: Full Playback Controls
                  Expanded(
                    flex: 2,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Consumer(builder: (context, ref, _) {
                          final isShuffle = ref.watch(shuffleProvider);
                          return IconButton(
                            icon: const Icon(Icons.shuffle),
                            color: isShuffle ? colors.accent : colors.textFaint,
                            onPressed: () {
                              engine.noteUserActivity();
                              ref.read(shuffleProvider.notifier).toggle();
                            },
                          );
                        }),

                        IconButton(
                          icon: const Icon(Icons.skip_previous),
                          color: colors.textPrimary,
                          onPressed: () {
                            engine.noteUserActivity();
                            ref.read(playbackControllerProvider).playPreviousTrack();
                          },
                        ),

                        StreamBuilder<bool>(
                          stream: player.stream.playing,
                          builder: (context, snapshot) {
                            final isPlaying = snapshot.data ?? false;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                iconSize: 45,
                                icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                                color: colors.accent,
                                onPressed: () {
                                  engine.noteUserActivity();
                                  if (isPlaying) {
                                    player.pause();
                                  } else {
                                    player.play();
                                  }
                                },
                              ),
                            );
                          },
                        ),

                        IconButton(
                          icon: const Icon(Icons.skip_next),
                          color: colors.textPrimary,
                          onPressed: () {
                            engine.noteUserActivity();
                            ref.read(playbackControllerProvider).playNextTrack();
                          },
                        ),

                        Consumer(builder: (context, ref, _) {
                          final repeatMode = ref.watch(repeatModeProvider);
                          IconData icon = Icons.repeat;
                          Color color = colors.textFaint;

                          if (repeatMode == PlaybackRepeatMode.all) {
                            color = colors.accent;
                          } else if (repeatMode == PlaybackRepeatMode.one) {
                            icon = Icons.repeat_one;
                            color = colors.accent;
                          }

                          return IconButton(
                            icon: Icon(icon),
                            color: color,
                            onPressed: () {
                              engine.noteUserActivity();
                              ref.read(repeatModeProvider.notifier).cycle();
                            },
                          );
                        }),
                      ],
                    ),
                  ),

                  // Right: Volume Control
                  Expanded(
                    flex: 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const _SpeedButton(),
                        const _SleepTimerButton(),

                        // Queue panel toggle (like Spotify's queue button)
                        Consumer(builder: (context, ref, _) {
                          final queueVisible =
                              ref.watch(queuePanelVisibleProvider);
                          return IconButton(
                            tooltip: 'Queue',
                            icon: const Icon(Icons.queue_music, size: 22),
                            color:
                                queueVisible ? colors.accent : colors.textFaint,
                            onPressed: () => ref
                                .read(queuePanelVisibleProvider.notifier)
                                .toggle(),
                          );
                        }),

                        StreamBuilder<double>(
                          stream: player.stream.volume,
                          builder: (context, snapshot) {
                            final volume = snapshot.data ?? 100.0;
                            IconData volumeIcon = Icons.volume_up;
                            if (volume == 0) {
                              volumeIcon = Icons.volume_off;
                            } else if (volume < 50) {
                              volumeIcon = Icons.volume_down;
                            }

                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(volumeIcon, color: colors.textFaint),
                                  onPressed: () {
                                    engine.noteUserActivity();
                                    player.setVolume(volume == 0.0 ? 100.0 : 0.0);
                                  },
                                ),
                                SizedBox(
                                  width: 100,
                                  child: Slider(
                                    activeColor: colors.textPrimary,
                                    inactiveColor: colors.border,
                                    value: volume.clamp(0.0, 100.0),
                                    max: 100.0,
                                    onChanged: (value) {
                                      engine.noteUserActivity();
                                      player.setVolume(value);
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        // Hide to tray: window disappears, music keeps
                        // playing, tray icon brings it back (like Spotify)
                        Consumer(builder: (context, ref, _) {
                          final trayReady = ref.watch(trayReadyProvider);
                          if (!trayReady) return const SizedBox.shrink();
                          return IconButton(
                            tooltip: 'Hide to tray (keeps playing)',
                            icon: const Icon(Icons.close_fullscreen, size: 20),
                            color: colors.textFaint,
                            onPressed: () => windowManager.hide(),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick playback-speed picker. The value itself lives in settings, so it
/// survives a restart and applies to every track.
class _SpeedButton extends ConsumerWidget {
  const _SpeedButton();

  static const _choices = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final rate = ref.watch(
        settingsControllerProvider.select((settings) => settings.playbackRate));

    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      color: colors.surfaceAlt,
      onSelected: (value) =>
          ref.read(settingsControllerProvider.notifier).setPlaybackRate(value),
      itemBuilder: (context) => [
        for (final choice in _choices)
          PopupMenuItem(
            value: choice,
            child: Text(
              '${choice.toStringAsFixed(2)}×',
              style: TextStyle(
                color: (choice - rate).abs() < 0.01
                    ? colors.accent
                    : colors.textSecondary,
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(
          '${rate.toStringAsFixed(2)}×',
          style: TextStyle(
            color: rate == 1.0 ? colors.textFaint : colors.accent,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Sleep timer control: presets, a custom duration, or "end of current track".
/// Shows the countdown while one is running.
class _SleepTimerButton extends ConsumerWidget {
  const _SleepTimerButton();

  String _formatRemaining(Duration remaining) {
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    if (minutes >= 60) {
      return '${remaining.inHours}h ${minutes % 60}m';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _askCustom(BuildContext context, WidgetRef ref) async {
    final colors = context.colors;
    final controller = TextEditingController(text: '20');

    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Sleep timer', style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Minutes',
            labelStyle: TextStyle(color: colors.textFaint),
            enabledBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: colors.border)),
            focusedBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: colors.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textFaint)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: Text('Start',
                style: TextStyle(
                    color: colors.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (minutes != null && minutes > 0) {
      ref
          .read(sleepTimerProvider.notifier)
          .startDuration(Duration(minutes: minutes));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final timer = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);

    return PopupMenuButton<String>(
      tooltip: 'Sleep timer',
      color: colors.surfaceAlt,
      onSelected: (value) {
        switch (value) {
          case 'cancel':
            notifier.cancel();
          case 'extend':
            notifier.extend15();
          case 'end_of_track':
            notifier.startEndOfTrack();
          case 'custom':
            _askCustom(context, ref);
          default:
            final minutes = int.tryParse(value);
            if (minutes != null) {
              notifier.startDuration(Duration(minutes: minutes));
            }
        }
      },
      itemBuilder: (context) => [
        if (timer != null) ...[
          PopupMenuItem(
            value: 'extend',
            child: Text('+15 minutes',
                style: TextStyle(color: colors.textSecondary)),
          ),
          PopupMenuItem(
            value: 'cancel',
            child: Text('Cancel timer',
                style: TextStyle(color: colors.textSecondary)),
          ),
          const PopupMenuDivider(),
        ],
        for (final minutes in [15, 30, 45, 60])
          PopupMenuItem(
            value: '$minutes',
            child: Text('$minutes minutes',
                style: TextStyle(color: colors.textSecondary)),
          ),
        PopupMenuItem(
          value: 'custom',
          child: Text('Custom…', style: TextStyle(color: colors.textSecondary)),
        ),
        PopupMenuItem(
          value: 'end_of_track',
          child: Text('End of current track',
              style: TextStyle(color: colors.textSecondary)),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bedtime,
                size: 20,
                color: timer == null ? colors.textFaint : colors.accent),
            if (timer != null) ...[
              const SizedBox(width: 4),
              Text(
                timer.endOfTrack
                    ? 'End'
                    : _formatRemaining(timer.remaining),
                style: TextStyle(
                    color: colors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
