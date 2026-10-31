import '../../features/library/views/browse_views.dart';
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
  String _time(Duration duration) =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final player = ref.watch(playerProvider);
    final controller = ref.read(playbackControllerProvider);
    final engine = ref.read(audioEngineProvider);
    final snapshot = ref.watch(currentTrackProvider);
    final track = snapshot == null
        ? null
        : ref.watch(liveTrackProvider(snapshot.id)).value ?? snapshot;
    final info = Row(
      children: [
        ArtThumb(path: track?.coverArtPath, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track?.title ?? 'No track selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                track?.artist ?? 'Choose music from your library',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textFaint, fontSize: 12),
              ),
            ],
          ),
        ),
        if (track != null)
          IconButton(
            tooltip: track.isFavorite ? 'Remove favorite' : 'Favorite',
            icon: Icon(
              track.isFavorite ? Icons.favorite : Icons.favorite_border,
              size: 20,
            ),
            color: track.isFavorite ? colors.accent : colors.textFaint,
            onPressed: () => ref
                .read(databaseProvider)
                .setFavorite(track.id, !track.isFavorite),
          ),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Shuffle',
          isSelected: ref.watch(shuffleProvider),
          onPressed: () => ref.read(shuffleProvider.notifier).toggle(),
          icon: const Icon(Icons.shuffle, size: 20),
        ),
        IconButton(
          tooltip: 'Previous track',
          onPressed: controller.playPreviousTrack,
          icon: const Icon(Icons.skip_previous),
        ),
        StreamBuilder<bool>(
          stream: player.stream.playing,
          initialData: player.state.playing,
          builder: (_, s) => IconButton.filled(
            tooltip: s.data == true ? 'Pause' : 'Play',
            onPressed: () => player.playOrPause(),
            icon: Icon(s.data == true ? Icons.pause : Icons.play_arrow),
          ),
        ),
        IconButton(
          tooltip: 'Next track',
          onPressed: controller.playNextTrack,
          icon: const Icon(Icons.skip_next),
        ),
        IconButton(
          tooltip: 'Repeat: ${ref.watch(repeatModeProvider).name}',
          isSelected: ref.watch(repeatModeProvider) != PlaybackRepeatMode.off,
          onPressed: () => ref.read(repeatModeProvider.notifier).cycle(),
          icon: Icon(
            ref.watch(repeatModeProvider) == PlaybackRepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
            size: 20,
          ),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SpeedButton(),
        const _SleepTimerButton(),
        IconButton(
          tooltip: 'Show queue',
          isSelected: ref.watch(queuePanelVisibleProvider),
          onPressed: () =>
              ref.read(queuePanelVisibleProvider.notifier).toggle(),
          icon: const Icon(Icons.queue_music, size: 20),
        ),
        if (ref.watch(trayReadyProvider))
          IconButton(
            tooltip: 'Hide to tray',
            onPressed: () => windowManager.hide(),
            icon: const Icon(Icons.close_fullscreen, size: 20),
          ),
      ],
    );
    final volume = StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (_, s) {
        final value = (s.data ?? 100).clamp(0.0, 100.0);
        return SizedBox(
          width: 164,
          child: Row(
            children: [
              IconButton(
                tooltip: value == 0 ? 'Unmute' : 'Mute',
                onPressed: () => controller.setVolume(value == 0 ? 100 : 0),
                icon: Icon(
                  value == 0 ? Icons.volume_off : Icons.volume_up,
                  size: 20,
                ),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  max: 100,
                  semanticFormatterCallback: (v) =>
                      'Volume ${v.round()} percent',
                  onChanged: controller.setVolume,
                ),
              ),
            ],
          ),
        );
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1120;
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<Duration>(
                stream: player.stream.position,
                initialData: player.state.position,
                builder: (_, position) => StreamBuilder<Duration>(
                  stream: player.stream.duration,
                  initialData: player.state.duration,
                  builder: (_, duration) {
                    final max = (duration.data ?? Duration.zero).inMilliseconds
                        .toDouble();
                    final current = (position.data ?? Duration.zero)
                        .inMilliseconds
                        .toDouble()
                        .clamp(0.0, max > 0 ? max : 1.0);
                    return Row(
                      children: [
                        Text(
                          _time(position.data ?? Duration.zero),
                          style: TextStyle(
                            color: colors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: current,
                            max: max > 0 ? max : 1,
                            semanticFormatterCallback: (v) =>
                                'Seek to ${_time(Duration(milliseconds: v.round()))}',
                            onChanged: max <= 0
                                ? null
                                : (v) {
                                    engine.noteUserActivity();
                                    controller.seek(
                                      Duration(milliseconds: v.round()),
                                    );
                                  },
                          ),
                        ),
                        Text(
                          _time(duration.data ?? Duration.zero),
                          style: TextStyle(
                            color: colors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (compact) ...[
                Row(
                  children: [
                    Expanded(child: info),
                    actions,
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [controls, const SizedBox(width: 16), volume],
                ),
              ] else
                Row(
                  children: [
                    Expanded(child: info),
                    controls,
                    const SizedBox(width: 12),
                    actions,
                    volume,
                  ],
                ),
            ],
          ),
        );
      },
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
      settingsControllerProvider.select((settings) => settings.playbackRate),
    );

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
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.accent),
            ),
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
            child: Text(
              'Start',
              style: TextStyle(
                color: colors.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
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
            child: Text(
              '+15 minutes',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          PopupMenuItem(
            value: 'cancel',
            child: Text(
              'Cancel timer',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          const PopupMenuDivider(),
        ],
        for (final minutes in [15, 30, 45, 60])
          PopupMenuItem(
            value: '$minutes',
            child: Text(
              '$minutes minutes',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
        PopupMenuItem(
          value: 'custom',
          child: Text('Custom…', style: TextStyle(color: colors.textSecondary)),
        ),
        PopupMenuItem(
          value: 'end_of_track',
          child: Text(
            'End of current track',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bedtime,
              size: 20,
              color: timer == null ? colors.textFaint : colors.accent,
            ),
            if (timer != null) ...[
              const SizedBox(width: 4),
              Text(
                timer.endOfTrack ? 'End' : _formatRemaining(timer.remaining),
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
