import 'dart:async';

import 'package:flutter/foundation.dart'; // Added for debugPrint
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../providers/player_provider.dart';
import '../../../core/database/app_database.dart' as db;

/// Playback tracking: play counts for the smart lists and leaderboards, plus
/// the measured listening time behind Stats → "Time listened".
final scrobblingServiceProvider = Provider<void>((ref) {
  final player = ref.watch(playerProvider);
  final database = ref.watch(databaseProvider);

  // Keeps track of the current track ID so we only log it once per play
  int? lastScrobbledTrackId;

  // Measured listening time. Derived from how far the position actually
  // advanced rather than from wall-clock time, so pauses cost nothing and the
  // figure means "this much audio was heard" at any playback speed.
  int? listenSessionId;
  int listenedMs = 0;
  int savedListenedMs = 0;
  Duration? lastListenPosition;
  var lastListenFlush = DateTime.now();

  /// Position ticks arrive a few times a second; anything bigger than this is
  /// a seek or a track change, not listening.
  const maxListenStep = Duration(seconds: 2);

  /// Writes are throttled: losing the tail of a session to a kill costs a few
  /// seconds of precision, and the row is topped up on every track change.
  const listenFlushInterval = Duration(seconds: 15);

  /// Persists the running total. Idempotent — it writes an absolute value, so
  /// calling it more often than needed only costs a write.
  Future<void> flushListening(db.Track? track) async {
    lastListenFlush = DateTime.now();
    if (track == null || listenedMs == savedListenedMs) return;
    // Ignore stretches too short to be listening (a click through a queue).
    if (listenedMs < 1000) return;

    listenSessionId ??= await database.startListeningSession(track.id);
    savedListenedMs = listenedMs;
    await database.saveListenedMs(listenSessionId!, listenedMs);
  }

  // Closes the outgoing track's session while it is still the current track,
  // so its time is booked against the right row.
  db.Track? trackBeingMeasured;
  ref.listen(currentTrackProvider, (previous, next) {
    if (previous?.id == next?.id) return;
    unawaited(flushListening(previous));
    listenSessionId = null;
    listenedMs = 0;
    savedListenedMs = 0;
    lastListenPosition = null;
    trackBeingMeasured = next;
  });

  final subscription = player.stream.position.listen((position) async {
    final currentTrack = ref.read(currentTrackProvider);
    if (currentTrack == null) return;
    trackBeingMeasured = currentTrack;

    // A restored session reopens the last track already deep into it while
    // paused — that must not count as a play.
    if (!player.state.playing) return;

    // --- Measured listening time ---
    final previousPosition = lastListenPosition;
    lastListenPosition = position;
    if (previousPosition != null) {
      final step = position - previousPosition;
      // Seeks, restarts and track changes all show up as steps outside the
      // window and are dropped rather than counted.
      if (step > Duration.zero && step <= maxListenStep) {
        listenedMs += step.inMilliseconds;
        if (DateTime.now().difference(lastListenFlush) >= listenFlushInterval) {
          unawaited(flushListening(currentTrack));
        }
      }
    }

    // --- Play counting (scrobble at 25%) ---

    // Reset the tracker if the position drops near zero
    if (position.inSeconds < 1) {
      lastScrobbledTrackId = null;
    }

    // If we already logged this specific track during this playback, do nothing
    if (lastScrobbledTrackId == currentTrack.id) return;

    final duration = currentTrack.durationMs > 0
        ? Duration(milliseconds: currentTrack.durationMs)
        : player.state.duration;
    if (duration.inMilliseconds == 0) return;

    // Calculate how far we are into the song
    final ratio = position.inMilliseconds / duration.inMilliseconds;

    // Trigger exactly when it crosses the 25% threshold
    if (ratio >= 0.25) {
      lastScrobbledTrackId = currentTrack.id; // Mark as logged

      await database.recordPlay(currentTrack.id);
      debugPrint('Scrobbled (25% reached): ${currentTrack.title}'); // Swapped print for debugPrint
    }
  });

  ref.onDispose(() {
    subscription.cancel();
    unawaited(flushListening(trackBeingMeasured));
  });
});
