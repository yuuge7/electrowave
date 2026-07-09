import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../services/tray_service.dart';
import '../../features/player/providers/player_provider.dart';
import '../../features/player/providers/queue_provider.dart';

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
    final player = ref.watch(playerProvider);
    final currentTrack = ref.watch(currentTrackProvider);

    return Container(
      // Increased height slightly to give the internal elements more breathing room
      height: 110,
      // Using .all(16) gives it equal spacing on every side, perfectly centering it
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
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
                        Text(_formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        Expanded(
                          child: Slider(
                            activeColor: Colors.greenAccent,
                            inactiveColor: Colors.white24,
                            value: currentPosition,
                            max: maxDuration,
                            onChanged: (value) {
                              player.seek(Duration(milliseconds: value.toInt()));
                            },
                          ),
                        ),
                        Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
                            color: Colors.grey.shade900,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: currentTrack?.coverArtPath != null
                              ? Image.file(
                                  File(currentTrack!.coverArtPath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => 
                                      const Icon(Icons.music_note, color: Colors.grey, size: 24),
                                )
                              : const Icon(Icons.music_note, color: Colors.grey, size: 24),
                        ),
                        const SizedBox(width: 12),
                        
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(currentTrack?.title ?? 'No Track', 
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(currentTrack?.artist ?? 'Select a track', 
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
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
                            color: isShuffle ? Colors.greenAccent : Colors.grey,
                            onPressed: () {
                              ref.read(shuffleProvider.notifier).toggle();
                            },
                          );
                        }),
                        
                        IconButton(
                          icon: const Icon(Icons.skip_previous),
                          color: Colors.white,
                          onPressed: () => ref.read(playbackControllerProvider).playPreviousTrack(),
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
                                color: Colors.greenAccent,
                                onPressed: () {
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
                          color: Colors.white,
                          onPressed: () => ref.read(playbackControllerProvider).playNextTrack(),
                        ),
                        
                        Consumer(builder: (context, ref, _) {
                          final repeatMode = ref.watch(repeatModeProvider);
                          IconData icon = Icons.repeat;
                          Color color = Colors.grey;
                          
                          if (repeatMode == PlaybackRepeatMode.all) {
                            color = Colors.greenAccent;
                          } else if (repeatMode == PlaybackRepeatMode.one) {
                            icon = Icons.repeat_one;
                            color = Colors.greenAccent;
                          }
                          
                          return IconButton(
                            icon: Icon(icon),
                            color: color,
                            onPressed: () {
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
                        // Queue panel toggle (like Spotify's queue button)
                        Consumer(builder: (context, ref, _) {
                          final queueVisible =
                              ref.watch(queuePanelVisibleProvider);
                          return IconButton(
                            tooltip: 'Queue',
                            icon: const Icon(Icons.queue_music, size: 22),
                            color:
                                queueVisible ? Colors.greenAccent : Colors.grey,
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
                                  icon: Icon(volumeIcon, color: Colors.grey),
                                  onPressed: () {
                                    player.setVolume(volume == 0.0 ? 100.0 : 0.0);
                                  },
                                ),
                                SizedBox(
                                  width: 100,
                                  child: Slider(
                                    activeColor: Colors.white,
                                    inactiveColor: Colors.white24,
                                    value: volume.clamp(0.0, 100.0),
                                    max: 100.0,
                                    onChanged: (value) {
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
                            color: Colors.grey,
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