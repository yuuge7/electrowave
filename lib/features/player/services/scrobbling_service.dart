import 'dart:async';

import 'package:flutter/foundation.dart'; // Added for debugPrint
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../providers/player_provider.dart';
import '../../../core/database/app_database.dart' as db;

/// Playback tracking: play counts for the smart lists and leaderboards, plus
/// the measured listening time behind Stats → "Time listened".
///
/// Both numbers come out of the same measurement — the audio that actually
/// left the player — so they cannot drift apart. A play is booked once a
/// quarter of the track has really been *heard*; where the playhead happens to
/// sit is never enough on its own, because `open()` is asynchronous and the
/// position stream keeps reporting the outgoing file for a moment after the
/// current track has already changed.
final scrobblingServiceProvider = Provider<void>((ref) {
  final player = ref.watch(playerProvider);
  final database = ref.watch(databaseProvider);

  // -------------------------------------------------------------------------
  // Measured listening time
  // -------------------------------------------------------------------------
  //
  // Derived from how far the position actually advanced rather than from
  // wall-clock time, so pauses cost nothing and the figure means "this much
  // audio was heard" at any playback speed.

  /// The row this track's time is being written to, held as a *Future* rather
  /// than an id so it can be claimed synchronously. A track change resets the
  /// fields below while a flush may still be awaiting the database; an `await`
  /// in front of the assignment would let the incoming track adopt the
  /// outgoing track's row and blank it on the way past.
  Future<int>? listenSession;

  /// When audio first came out for this session, so the row is stamped with
  /// the moment listening began rather than the moment of the first flush up
  /// to [listenFlushInterval] later.
  DateTime? listenStartedAt;

  int listenedMs = 0;
  int savedListenedMs = 0;
  Duration? lastListenPosition;
  var lastListenFlush = DateTime.now();

  /// Position ticks arrive a few times a second; anything bigger than this is
  /// a seek or a track change, not listening.
  ///
  /// Scaled by the playback rate: at speed *r* the playhead covers *r* seconds
  /// of audio per second of wall clock, so a fixed window would start dropping
  /// real listening as soon as the rate was turned up.
  Duration maxListenStep() => Duration(
        milliseconds: (2000 * player.state.rate.clamp(1.0, 4.0)).round(),
      );

  /// Writes are throttled: losing the tail of a session to a kill costs a few
  /// seconds of precision, and the row is topped up on every track change.
  const listenFlushInterval = Duration(seconds: 15);

  /// Persists the running total. Idempotent — it writes an absolute value, so
  /// calling it more often than needed only costs a write.
  ///
  /// Everything it writes is captured before the first `await`, so a track
  /// change landing mid-flush can no longer zero the outgoing row.
  Future<void> flushListening(db.Track? track) async {
    lastListenFlush = DateTime.now();
    if (track == null) return;

    final ms = listenedMs;
    if (ms == savedListenedMs) return;
    // Ignore stretches too short to be listening (a click through a queue).
    if (ms < 1000) return;

    savedListenedMs = ms;
    final session = listenSession ??=
        database.startListeningSession(track.id, startedAt: listenStartedAt);
    await database.saveListenedMs(await session, ms);
  }

  // -------------------------------------------------------------------------
  // Play counting
  // -------------------------------------------------------------------------

  /// Audio heard since *this* playback of the track began. Separate from
  /// [listenedMs], which spans the whole session: a track left on repeat keeps
  /// one session row but has to count one play per lap.
  int playListenedMs = 0;
  bool playCounted = false;

  void startNewPlay() {
    playListenedMs = 0;
    playCounted = false;
  }

  // Closes the outgoing track's session while it is still the current track,
  // so its time is booked against the right row.
  db.Track? trackBeingMeasured;
  ref.listen(currentTrackProvider, (previous, next) {
    if (previous?.id == next?.id) return;
    unawaited(flushListening(previous));
    listenSession = null;
    listenStartedAt = null;
    listenedMs = 0;
    savedListenedMs = 0;
    lastListenPosition = null;
    startNewPlay();
    trackBeingMeasured = next;
  });

  final subscription = player.stream.position.listen((position) async {
    final currentTrack = ref.read(currentTrackProvider);
    if (currentTrack == null) return;
    trackBeingMeasured = currentTrack;

    // A restored session reopens the last track already deep into it while
    // paused — that must not count as a play.
    if (!player.state.playing) return;

    final previousPosition = lastListenPosition;
    lastListenPosition = position;

    // Nothing to compare against yet. The first tick after a track change is
    // also the one that can still carry the *outgoing* file's position, so it
    // is only ever adopted as a baseline.
    if (previousPosition == null) return;

    final step = position - previousPosition;

    // The playhead went back to the top: a repeat-one lap, the previous
    // button, or a seek home. Whatever follows is a new play and has to earn
    // its own quarter before it counts.
    if (step < Duration.zero && position < const Duration(seconds: 1)) {
      startNewPlay();
    }

    // Seeks, restarts and track changes all show up as steps outside the
    // window and are dropped rather than counted.
    if (step <= Duration.zero || step > maxListenStep()) return;

    listenedMs += step.inMilliseconds;
    playListenedMs += step.inMilliseconds;
    listenStartedAt ??= DateTime.now();

    if (DateTime.now().difference(lastListenFlush) >= listenFlushInterval) {
      unawaited(flushListening(currentTrack));
    }

    if (playCounted) return;

    final duration = currentTrack.durationMs > 0
        ? Duration(milliseconds: currentTrack.durationMs)
        : player.state.duration;
    if (duration.inMilliseconds == 0) return;

    // A quarter of the track actually heard. Both sides are media time, so the
    // threshold means the same thing at every playback speed.
    if (playListenedMs * 4 >= duration.inMilliseconds) {
      playCounted = true; // Mark as logged

      await database.recordPlay(currentTrack.id);
      debugPrint('Scrobbled (a quarter heard): ${currentTrack.title}');
    }
  });

  // A pause is the last reliable moment to persist: a quit from the tray or a
  // kill never reaches onDispose.
  final pauseSubscription = player.stream.playing.listen((playing) {
    if (!playing) unawaited(flushListening(trackBeingMeasured));
  });

  ref.onDispose(() {
    subscription.cancel();
    pauseSubscription.cancel();
    unawaited(flushListening(trackBeingMeasured));
  });
});
