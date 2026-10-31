import '../services/listening_tail.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import '../../../core/local_log.dart';
import '../../settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import '../../../core/database/app_database.dart' as db;
import '../services/audio_engine.dart';
import 'queue_provider.dart';
import 'sleep_timer_provider.dart';

// --- 1. REPEAT AND SHUFFLE STATES ---

// Renamed to avoid collision with Flutter's built-in RepeatMode
enum PlaybackRepeatMode { off, all, one }

class RepeatModeNotifier extends Notifier<PlaybackRepeatMode> {
  @override
  PlaybackRepeatMode build() => PlaybackRepeatMode.off;

  void cycle() {
    state = state == PlaybackRepeatMode.off
        ? PlaybackRepeatMode.all
        : state == PlaybackRepeatMode.all
        ? PlaybackRepeatMode.one
        : PlaybackRepeatMode.off;
  }

  void set(PlaybackRepeatMode mode) => state = mode;
}

final repeatModeProvider =
    NotifierProvider<RepeatModeNotifier, PlaybackRepeatMode>(
      RepeatModeNotifier.new,
    );

class ShuffleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void set(bool value) => state = value;
}

final shuffleProvider = NotifierProvider<ShuffleNotifier, bool>(
  ShuffleNotifier.new,
);

// --- 2. CURRENT TRACK NOTIFIER ---

class CurrentTrackNotifier extends Notifier<db.Track?> {
  @override
  db.Track? build() => null;

  void setTrack(db.Track? track) {
    state = track;
  }
}

final currentTrackProvider = NotifierProvider<CurrentTrackNotifier, db.Track?>(
  CurrentTrackNotifier.new,
);

// --- 3. PLAYBACK CONTROLLER ---
// This safely gives our functions access to all providers without WidgetRef/Ref type errors

class NextTrack {
  const NextTrack(this.track, this.queue);
  final db.Track track;
  final QueueState queue;
}

/// One decision shared by gapless preloading, manual next, and unit tests.
NextTrack? chooseNext(
  QueueState queue, {
  required bool shuffle,
  required PlaybackRepeatMode repeat,
  db.Track? current,
  bool completed = true,
  Random? random,
}) {
  if (repeat == PlaybackRepeatMode.one &&
      completed &&
      current != null &&
      !current.isMissing &&
      !current.isDeleted) {
    return NextTrack(current, queue);
  }
  final manual = [...queue.manualQueue];
  while (manual.isNotEmpty) {
    final track = manual.removeAt(0);
    if (!track.isMissing && !track.isDeleted) {
      return NextTrack(
        track,
        queue.copyWith(manualQueue: manual, playingFromManualQueue: true),
      );
    }
  }
  final available = <int>[
    for (var i = 0; i < queue.context.length; i++)
      if (!queue.context[i].isMissing && !queue.context[i].isDeleted) i,
  ];
  if (available.isEmpty) return null;
  int? index;
  if (shuffle) {
    final alternatives = available
        .where((i) => i != queue.contextIndex)
        .toList();
    final choices = alternatives.isEmpty ? available : alternatives;
    index = choices[(random ?? Random()).nextInt(choices.length)];
  } else {
    for (final i in available) {
      if (i > queue.contextIndex) {
        index = i;
        break;
      }
    }
    if (index == null && repeat == PlaybackRepeatMode.all) {
      index = available.first;
    }
  }
  if (index == null) return null;
  return NextTrack(
    queue.context[index],
    queue.copyWith(
      contextIndex: index,
      manualQueue: manual,
      playingFromManualQueue: false,
    ),
  );
}

class PlaybackController {
  PlaybackController(this.ref) {
    final player = ref.read(playerProvider);
    _subscriptions.add(player.stream.playlist.listen(_onPlaylist));
    _subscriptions.add(player.stream.position.listen((_) => _maybeCrossfade()));
    _subscriptions.add(
      player.stream.completed.listen((done) {
        if (!done || _opening || _fading) return;
        final timer = ref.read(sleepTimerProvider);
        if (timer?.endOfTrack ?? false) {
          ref.read(sleepTimerProvider.notifier).fireNow();
          return;
        }
        // Native playlist transitions handle all preloaded tracks. Completion
        // is only emitted at its end (e.g. no next playable file).
        if (_prepared == null) playNextTrack(fromCompletion: true);
      }),
    );
    _subscriptions.add(
      player.stream.playing.listen((playing) {
        final tail = _tail;
        if (tail != null) {
          unawaited(playing ? tail.play() : tail.pause());
        }
      }),
    );
    ref.listen(queueProvider, (_, _) => _scheduleSync());
    ref.listen(shuffleProvider, (_, _) => _scheduleSync());
    ref.listen(repeatModeProvider, (_, _) => _scheduleSync());
    ref.listen(sleepTimerProvider, (_, _) => _scheduleSync());
    ref.onDispose(() {
      _disposed = true;
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      unawaited(_stopTail());
    });
  }
  final Ref ref;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  NextTrack? _prepared;
  String? _preparedUri;
  int _preparedIndex = -1;
  bool _opening = false,
      _syncing = false,
      _syncAgain = false,
      _disposed = false,
      _fading = false;
  int _generation = 0;
  Player? _tail;
  double? _fadeVolume;

  Future<void> _stopTail() async {
    final tail = _tail;
    _tail = null;
    if (tail != null) await tail.dispose();
    if (_fadeVolume case final volume?) {
      _fadeVolume = null;
      if (!_disposed) await ref.read(playerProvider).setVolume(volume);
    }
    _fading = false;
  }

  Future<void> _open(
    db.Track track, {
    bool play = true,
    Duration start = Duration.zero,
  }) async {
    final generation = ++_generation;
    await _stopTail();
    _opening = true;
    _prepared = null;
    try {
      if (!await File(track.filePath).exists()) {
        LocalLog.write('File missing: ${track.filePath}');
        // Marking the queue snapshot avoids retry loops before a rescan.
        final q = ref.read(queueProvider);
        ref
            .read(queueProvider.notifier)
            .replace(
              q.copyWith(
                context: q.context
                    .map(
                      (t) => t.id == track.id ? t.copyWith(isMissing: true) : t,
                    )
                    .toList(),
                manualQueue: q.manualQueue
                    .where((t) => t.id != track.id)
                    .toList(),
              ),
            );
        _opening = false;
        playNextTrack();
        return;
      }
      ref.read(currentTrackProvider.notifier).setTrack(track);
      final player = ref.read(playerProvider);
      await player.open(
        Playlist([Media(track.filePath, start: start)]),
        play: play,
      );
      if (generation != _generation) return;
      await ref.read(audioEngineProvider).reapplyRate();
      await ref.read(audioEngineProvider).setTrackGain(track.replayGainDb);
    } catch (e, st) {
      LocalLog.write(e, st);
    } finally {
      if (generation == _generation) {
        _opening = false;
        _scheduleSync();
      }
    }
  }

  Future<void> seek(Duration position) async {
    await _stopTail();
    await ref.read(playerProvider).seek(position);
  }

  Future<void> setVolume(double volume) async {
    await _stopTail();
    await ref.read(playerProvider).setVolume(volume.clamp(0, 100));
  }

  Future<void> restoreTrack(db.Track track, Duration start) =>
      _open(track, play: false, start: start);

  void playFromContext(List<db.Track> tracks, int index) {
    if (index < 0 || index >= tracks.length) return;
    ref.read(queueProvider.notifier).setContext(tracks, index);
    unawaited(_open(tracks[index]));
  }

  void playQueuedTrackNow(db.Track track) {
    final q = ref.read(queueProvider);
    ref
        .read(queueProvider.notifier)
        .replace(
          q.copyWith(
            manualQueue: q.manualQueue.where((t) => t.id != track.id).toList(),
            playingFromManualQueue: true,
          ),
        );
    unawaited(_open(track));
  }

  NextTrack? _next({bool completed = true}) => chooseNext(
    ref.read(queueProvider),
    shuffle: ref.read(shuffleProvider),
    repeat: ref.read(repeatModeProvider),
    current: ref.read(currentTrackProvider),
    completed: completed,
  );

  void playNextTrack({bool fromCompletion = false}) {
    final next = _next(completed: fromCompletion);
    if (next == null) return;
    ref.read(queueProvider.notifier).replace(next.queue);
    unawaited(_open(next.track));
  }

  void playPreviousTrack() {
    final player = ref.read(playerProvider);
    if (player.state.position > const Duration(seconds: 3)) {
      unawaited(player.seek(Duration.zero));
      return;
    }
    final q = ref.read(queueProvider);
    var index = q.playingFromManualQueue ? q.contextIndex : q.contextIndex - 1;
    while (index >= 0 && q.context[index].isMissing) {
      index--;
    }
    if (index < 0) {
      unawaited(player.seek(Duration.zero));
      return;
    }
    ref.read(queueProvider.notifier).moveToContextIndex(index);
    unawaited(_open(q.context[index]));
  }

  void _scheduleSync() {
    if (_disposed) return;
    _syncAgain = true;
    scheduleMicrotask(_syncUpcoming);
  }

  Future<void> _syncUpcoming() async {
    if (_syncing || _opening || _disposed || _fading) return;
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        final player = ref.read(playerProvider);
        if (ref.read(currentTrackProvider) == null ||
            player.state.playlist.medias.isEmpty) {
          break;
        }
        var next = (ref.read(sleepTimerProvider)?.endOfTrack ?? false)
            ? null
            : _next();
        // Stale flags can occur between a deletion and a watcher event.
        final attempted = <int>{};
        while (next != null && !await File(next.track.filePath).exists()) {
          if (!attempted.add(next.track.id)) {
            next = null;
            break;
          }
          final q = next.queue;
          ref
              .read(queueProvider.notifier)
              .replace(
                q.copyWith(
                  context: q.context
                      .map(
                        (t) => t.id == next!.track.id
                            ? t.copyWith(isMissing: true)
                            : t,
                      )
                      .toList(),
                ),
              );
          next = _next();
        }
        final index = player.state.playlist.index;
        _prepared = null;
        for (var i = player.state.playlist.medias.length - 1; i > index; i--) {
          await player.remove(i);
        }
        if (next != null) {
          _prepared = next;
          final media = Media(next.track.filePath);
          _preparedUri = media.uri;
          _preparedIndex = index + 1;
          await player.add(media);
        }
      } while (_syncAgain && !_opening && !_disposed);
    } catch (e, st) {
      LocalLog.write(e, st);
    } finally {
      _syncing = false;
    }
  }

  void _onPlaylist(Playlist playlist) {
    if (_opening ||
        _disposed ||
        playlist.index < 0 ||
        playlist.index >= playlist.medias.length) {
      return;
    }
    final next = _prepared;
    if (next == null ||
        playlist.index != _preparedIndex ||
        playlist.medias[playlist.index].uri != _preparedUri) {
      return;
    }
    _prepared = null;
    ref.read(currentTrackProvider.notifier).setTrack(next.track);
    ref.read(queueProvider.notifier).replace(next.queue);
    unawaited(ref.read(audioEngineProvider).reapplyRate());
    unawaited(
      ref.read(audioEngineProvider).setTrackGain(next.track.replayGainDb),
    );
    _scheduleSync();
  }

  Future<void> _maybeCrossfade() async {
    if (_fading || _opening || _prepared == null || _disposed) return;
    final settings = ref.read(settingsControllerProvider);
    final player = ref.read(playerProvider);
    final remaining = player.state.duration - player.state.position;
    if (settings.crossfadeSeconds <= 0 ||
        settings.exclusiveMode ||
        !player.state.playing ||
        remaining <= Duration.zero ||
        remaining.inMilliseconds > settings.crossfadeSeconds * 1000 ||
        player.state.duration.inSeconds < 5 ||
        (ref.read(sleepTimerProvider)?.endOfTrack ?? false)) {
      return;
    }
    _fading = true;
    final generation = _generation;
    final next = _prepared!;
    final outgoing = ref.read(currentTrackProvider);
    if (outgoing == null) {
      _fading = false;
      return;
    }
    final volume = player.state.volume;
    _fadeVolume = volume;
    final tail = Player();
    _tail = tail;
    var tailMs = 0;
    Duration? lastTail;
    final tailSubscription = tail.stream.position.listen((position) {
      final previous = lastTail;
      lastTail = position;
      if (_disposed ||
          previous == null ||
          !tail.state.playing ||
          ref.read(currentTrackProvider)?.id == outgoing.id && !_fading) {
        return;
      }
      final delta = (position - previous).inMilliseconds;
      if (delta > 0 && delta <= 2000 * settings.playbackRate) tailMs += delta;
    });
    final engine = AudioEngine(tail);
    try {
      await engine.applyAudioSettings(settings);
      await engine.setRate(settings.playbackRate);
      await tail.setVolume(0);
      await tail.open(Media(outgoing.filePath, start: player.state.position));
      if (generation != _generation || _disposed) return;
      await player.setVolume(0);
      await tail.setVolume(volume);
      _prepared = null;
      _opening = true;
      await player.open(Playlist([Media(next.track.filePath)]));
      ref.read(currentTrackProvider.notifier).setTrack(next.track);
      ref.read(queueProvider.notifier).replace(next.queue);
      _opening = false;
      await ref.read(audioEngineProvider).reapplyRate();
      final duration = remaining.inMilliseconds.clamp(100, 12000);
      while (generation == _generation && !_disposed && _tail == tail) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (!player.state.playing) continue;
        final progress = (player.state.position.inMilliseconds / duration)
            .clamp(0.0, 1.0);
        await tail.setVolume(volume * (1 - progress));
        await player.setVolume(volume * progress);
        if (progress >= 1) break;
      }
    } catch (e, st) {
      LocalLog.write(e, st);
    } finally {
      await tailSubscription.cancel();
      engine.dispose();
      if (tailMs > 0 && !_disposed) {
        ref.read(tailListeningProvider).add(TailListening(outgoing.id, tailMs));
      }
      _opening = false;
      if (_tail == tail) await _stopTail();
      _scheduleSync();
    }
  }
}

final playbackControllerProvider = Provider((ref) => PlaybackController(ref));

// --- 4. PLAYER PROVIDER ---

final playerProvider = Provider<Player>((ref) {
  final player = Player();

  player.setPlaylistMode(PlaylistMode.none);

  ref.onDispose(() {
    player.dispose();
  });

  return player;
});
