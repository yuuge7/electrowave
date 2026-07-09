import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import '../../../core/database/app_database.dart' as db;
import 'queue_provider.dart';

// --- 1. REPEAT AND SHUFFLE STATES ---

// Renamed to avoid collision with Flutter's built-in RepeatMode
enum PlaybackRepeatMode { off, all, one }

class RepeatModeNotifier extends Notifier<PlaybackRepeatMode> {
  @override
  PlaybackRepeatMode build() => PlaybackRepeatMode.off;
  
  void cycle() {
    state = state == PlaybackRepeatMode.off ? PlaybackRepeatMode.all 
          : state == PlaybackRepeatMode.all ? PlaybackRepeatMode.one 
          : PlaybackRepeatMode.off;
  }
}
final repeatModeProvider = NotifierProvider<RepeatModeNotifier, PlaybackRepeatMode>(RepeatModeNotifier.new);

class ShuffleNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  
  void toggle() => state = !state;
}
final shuffleProvider = NotifierProvider<ShuffleNotifier, bool>(ShuffleNotifier.new);


// --- 2. CURRENT TRACK NOTIFIER ---

class CurrentTrackNotifier extends Notifier<db.Track?> {
  @override
  db.Track? build() => null;

  void setTrack(db.Track? track) {
    state = track;
  }
}
final currentTrackProvider = NotifierProvider<CurrentTrackNotifier, db.Track?>(CurrentTrackNotifier.new);


// --- 3. PLAYBACK CONTROLLER ---
// This safely gives our functions access to all providers without WidgetRef/Ref type errors

class PlaybackController {
  final Ref ref;
  PlaybackController(this.ref);

  void _play(db.Track track) {
    ref.read(currentTrackProvider.notifier).setTrack(track);
    ref.read(playerProvider).open(Media(track.filePath));
  }

  /// Entry point for the UI: the user clicked the track at [index] inside
  /// [tracks] (a playlist, the library, search results...). That list
  /// becomes the playback context that next/previous walk through.
  void playFromContext(List<db.Track> tracks, int index) {
    if (index < 0 || index >= tracks.length) return;
    ref.read(queueProvider.notifier).setContext(tracks, index);
    _play(tracks[index]);
  }

  /// Plays [track] immediately without touching the context, and resumes
  /// the context afterwards (used when tapping a manual-queue item).
  void playQueuedTrackNow(db.Track track) {
    final queue = ref.read(queueProvider);
    final queueIndex = queue.manualQueue.indexWhere((t) => t.id == track.id);
    if (queueIndex != -1) {
      ref.read(queueProvider.notifier).removeFromQueue(queueIndex);
    }
    ref.read(queueProvider.notifier).markPlayingFromManualQueue();
    _play(track);
  }

  void playNextTrack({bool fromCompletion = false}) {
    final repeatMode = ref.read(repeatModeProvider);
    final currentTrack = ref.read(currentTrackProvider);
    final queueNotifier = ref.read(queueProvider.notifier);

    // Repeat-one only loops on natural completion; a manual "next" still
    // advances (Spotify behavior).
    if (repeatMode == PlaybackRepeatMode.one && fromCompletion) {
      if (currentTrack != null) {
        ref.read(playerProvider).open(Media(currentTrack.filePath));
      }
      return;
    }

    // The manual queue always plays before the context resumes.
    final queued = queueNotifier.popManualQueue();
    if (queued != null) {
      _play(queued);
      return;
    }

    final queue = ref.read(queueProvider);
    final context = queue.context;
    if (context.isEmpty) return;

    if (ref.read(shuffleProvider)) {
      final random = Random();
      int nextIndex = random.nextInt(context.length);
      // Avoid immediately repeating the same track when there's a choice.
      if (context.length > 1 && nextIndex == queue.contextIndex) {
        nextIndex = (nextIndex + 1) % context.length;
      }
      queueNotifier.moveToContextIndex(nextIndex);
      _play(context[nextIndex]);
      return;
    }

    // While a manual-queue track plays, contextIndex still points at the
    // track it interrupted, so +1 resumes the context correctly.
    int nextIndex = queue.contextIndex + 1;
    if (nextIndex >= context.length) {
      if (repeatMode == PlaybackRepeatMode.all) {
        nextIndex = 0;
      } else {
        return;
      }
    }
    queueNotifier.moveToContextIndex(nextIndex);
    _play(context[nextIndex]);
  }

  void playPreviousTrack() {
    final player = ref.read(playerProvider);

    if (player.state.position > const Duration(seconds: 3)) {
      player.seek(Duration.zero);
      return;
    }

    final queue = ref.read(queueProvider);
    final context = queue.context;
    if (context.isEmpty) {
      player.seek(Duration.zero);
      return;
    }

    // From a manual-queue track, "previous" returns to the context track
    // it interrupted.
    if (queue.playingFromManualQueue) {
      if (queue.contextIndex >= 0 && queue.contextIndex < context.length) {
        ref
            .read(queueProvider.notifier)
            .moveToContextIndex(queue.contextIndex);
        _play(context[queue.contextIndex]);
      } else {
        player.seek(Duration.zero);
      }
      return;
    }

    final prevIndex = queue.contextIndex - 1;
    if (prevIndex < 0) {
      player.seek(Duration.zero);
      return;
    }
    ref.read(queueProvider.notifier).moveToContextIndex(prevIndex);
    _play(context[prevIndex]);
  }
}

final playbackControllerProvider = Provider((ref) => PlaybackController(ref));


// --- 4. PLAYER PROVIDER ---

final playerProvider = Provider<Player>((ref) {
  final player = Player();
  
  player.setPlaylistMode(PlaylistMode.none);

  player.stream.completed.listen((completed) {
    if (completed) {
      Future.microtask(() {
        ref.read(playbackControllerProvider).playNextTrack(fromCompletion: true);
      });
    }
  });
  
  ref.onDispose(() {
    player.dispose();
  });
  
  return player;
});