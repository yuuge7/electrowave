import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../core/session/session_snapshot.dart';
import '../../../core/session/session_store.dart';
import '../../../main.dart';
import '../../../shared/providers/navigation_provider.dart';
import '../../playlists/providers/playlists_provider.dart';
import 'player_provider.dart';
import 'queue_provider.dart';

/// Restores the previous session on launch and keeps `session.json` up to
/// date while the app runs.
///
/// What survives a restart: the loaded track and its position, the playback
/// context (the playlist / library selection next & previous walk), the
/// manual queue, shuffle, repeat, volume, the open tab, the open playlist and
/// the queue panel.
///
/// Playback is always restored **paused** — launching the app should never
/// start blasting music on its own.
class SessionController {
  SessionController(this.ref) {
    _attachListeners();
    ref.onDispose(() {
      _saveTimer?.cancel();
      for (final subscription in _subscriptions) {
        subscription.cancel();
      }
    });
  }

  final Ref ref;

  /// Position moves constantly; only write it once every few seconds.
  static const Duration _positionSaveInterval = Duration(seconds: 5);

  /// Coalesces the bursts of changes a single user action produces.
  static const Duration _saveDebounce = Duration(milliseconds: 500);

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _saveTimer;

  bool _restoreStarted = false;

  /// Saving is disabled until the previous session has been read back, so an
  /// empty startup state can never overwrite it.
  bool _saveEnabled = false;

  SessionSnapshot? _lastSaved;
  int _lastSavedPositionMs = 0;

  // --- RESTORE ---

  /// Loads the saved session and pushes it back into the providers and the
  /// player. Safe to call more than once; only the first call does work.
  Future<void> restore() async {
    if (_restoreStarted) return;
    _restoreStarted = true;

    try {
      final snapshot = await SessionStore.load();
      if (snapshot != null) {
        await _apply(snapshot);
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
    } finally {
      _saveEnabled = true;
    }
  }

  Future<void> _apply(SessionSnapshot snapshot) async {
    final database = ref.read(databaseProvider);

    // Resolve every stored ID in one query. Tracks the user deleted in the
    // meantime simply drop out of the restored lists.
    final ids = <int>{
      ...snapshot.contextTrackIds,
      ...snapshot.manualQueueTrackIds,
      if (snapshot.currentTrackId != null) snapshot.currentTrackId!,
    };

    final Map<int, db.Track> byId = {};
    if (ids.isNotEmpty) {
      final rows = await (database.select(database.tracks)
            ..where((t) => t.id.isIn(ids) & t.isDeleted.equals(false)))
          .get();
      for (final track in rows) {
        byId[track.id] = track;
      }
    }

    final context = [
      for (final id in snapshot.contextTrackIds)
        if (byId[id] != null) byId[id]!,
    ];

    final manualQueue = [
      for (final id in snapshot.manualQueueTrackIds)
        if (byId[id] != null) byId[id]!,
    ];

    ref.read(queueProvider.notifier).restore(
          context: context,
          contextIndex: remapContextIndex(
            savedIds: snapshot.contextTrackIds,
            savedIndex: snapshot.contextIndex,
            survivingIds: byId.keys.toSet(),
            restoredLength: context.length,
          ),
          manualQueue: manualQueue,
          playingFromManualQueue: snapshot.playingFromManualQueue,
        );

    ref.read(shuffleProvider.notifier).set(snapshot.shuffle);
    ref.read(repeatModeProvider.notifier).set(_parseRepeatMode(snapshot.repeatMode));
    ref.read(navIndexProvider.notifier).set(snapshot.navIndex);
    ref.read(queuePanelVisibleProvider.notifier).set(snapshot.queuePanelVisible);

    // Only reopen a playlist that still exists.
    if (snapshot.selectedPlaylistId != null) {
      final playlist = await (database.select(database.playlists)
            ..where((pl) => pl.id.equals(snapshot.selectedPlaylistId!)))
          .getSingleOrNull();
      if (playlist != null) {
        ref.read(selectedPlaylistIdProvider.notifier).select(playlist.id);
      }
    }

    final player = ref.read(playerProvider);
    await player.setVolume(snapshot.volume.clamp(0.0, 100.0));

    final track = snapshot.currentTrackId == null
        ? null
        : byId[snapshot.currentTrackId];

    // A track whose file moved or vanished is skipped: the context stays, so
    // "next" still works.
    if (track == null || !File(track.filePath).existsSync()) {
      if (track != null) {
        debugPrint('Session: file missing for "${track.title}", skipping reload.');
      }
      return;
    }

    ref.read(currentTrackProvider.notifier).setTrack(track);
    _lastSavedPositionMs = snapshot.positionMs;

    final start = Duration(
      milliseconds: snapshot.positionMs < 0 ? 0 : snapshot.positionMs,
    );

    // `start` makes mpv load the file already positioned; opening with
    // play: false leaves it paused where the user left off.
    await player.open(Media(track.filePath, start: start), play: false);

    if (start > const Duration(seconds: 2)) {
      unawaited(_ensureSeeked(player, start));
    }
  }

  /// Some backends report position 0 after a paused load even though `start`
  /// was set. Once the file is demuxed, nudge it into place — unless the user
  /// already pressed play or moved the slider.
  Future<void> _ensureSeeked(Player player, Duration target) async {
    try {
      await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 5));

      if (player.state.playing) return;
      if (player.state.position > const Duration(seconds: 2)) return;
      if (target >= player.state.duration) return;

      await player.seek(target);
    } catch (e) {
      debugPrint('Session seek-after-load skipped: $e');
    }
  }

  PlaybackRepeatMode _parseRepeatMode(String raw) {
    switch (raw) {
      case 'all':
        return PlaybackRepeatMode.all;
      case 'one':
        return PlaybackRepeatMode.one;
      default:
        return PlaybackRepeatMode.off;
    }
  }

  String _serializeRepeatMode(PlaybackRepeatMode mode) {
    switch (mode) {
      case PlaybackRepeatMode.all:
        return 'all';
      case PlaybackRepeatMode.one:
        return 'one';
      case PlaybackRepeatMode.off:
        return 'off';
    }
  }

  // --- SAVE ---

  void _attachListeners() {
    // Every discrete piece of state that should survive a restart.
    ref.listen(currentTrackProvider, (_, _) => _scheduleSave());
    ref.listen(queueProvider, (_, _) => _scheduleSave());
    ref.listen(shuffleProvider, (_, _) => _scheduleSave());
    ref.listen(repeatModeProvider, (_, _) => _scheduleSave());
    ref.listen(navIndexProvider, (_, _) => _scheduleSave());
    ref.listen(selectedPlaylistIdProvider, (_, _) => _scheduleSave());
    ref.listen(queuePanelVisibleProvider, (_, _) => _scheduleSave());

    final player = ref.read(playerProvider);

    _subscriptions.add(player.stream.position.listen((position) {
      final delta = (position.inMilliseconds - _lastSavedPositionMs).abs();
      if (delta < _positionSaveInterval.inMilliseconds) return;
      _lastSavedPositionMs = position.inMilliseconds;
      _scheduleSave();
    }));

    // Pausing is a good moment to persist the exact position.
    _subscriptions.add(player.stream.playing.listen((_) => _scheduleSave()));
    _subscriptions.add(player.stream.volume.listen((_) => _scheduleSave()));
  }

  SessionSnapshot _currentSnapshot() {
    final player = ref.read(playerProvider);
    final queue = ref.read(queueProvider);
    final track = ref.read(currentTrackProvider);

    return SessionSnapshot(
      currentTrackId: track?.id,
      positionMs: track == null ? 0 : player.state.position.inMilliseconds,
      volume: player.state.volume,
      shuffle: ref.read(shuffleProvider),
      repeatMode: _serializeRepeatMode(ref.read(repeatModeProvider)),
      contextTrackIds: [for (final t in queue.context) t.id],
      contextIndex: queue.contextIndex,
      manualQueueTrackIds: [for (final t in queue.manualQueue) t.id],
      playingFromManualQueue: queue.playingFromManualQueue,
      navIndex: ref.read(navIndexProvider),
      selectedPlaylistId: ref.read(selectedPlaylistIdProvider),
      queuePanelVisible: ref.read(queuePanelVisibleProvider),
    );
  }

  void _scheduleSave() {
    if (!_saveEnabled) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => unawaited(_write()));
  }

  Future<void> _write() async {
    if (!_saveEnabled) return;

    final snapshot = _currentSnapshot();
    final previous = _lastSaved;
    if (previous != null && previous.sameAs(snapshot)) return;

    _lastSaved = snapshot;
    _lastSavedPositionMs = snapshot.positionMs;
    await SessionStore.save(snapshot);
  }

  /// Writes the session right now. Called when the app is about to quit or
  /// go to the background, so the last few seconds aren't lost.
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _write();
  }
}

final sessionControllerProvider = Provider<SessionController>((ref) {
  return SessionController(ref);
});

/// The saved index points into the list as it was when the session was
/// written; tracks deleted since then shift everything after them.
///
/// Anchors on the track that was playing: its new index is simply the number
/// of tracks before it that survived. When the anchor itself is gone, that
/// same count is where playback should resume from.
int remapContextIndex({
  required List<int> savedIds,
  required int savedIndex,
  required Set<int> survivingIds,
  required int restoredLength,
}) {
  if (restoredLength == 0) return -1;
  if (savedIndex < 0 || savedIndex >= savedIds.length) return -1;

  var survivorsBefore = 0;
  for (var i = 0; i < savedIndex; i++) {
    if (survivingIds.contains(savedIds[i])) survivorsBefore++;
  }

  if (survivingIds.contains(savedIds[savedIndex])) return survivorsBefore;
  return survivorsBefore.clamp(0, restoredLength - 1);
}
