import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/database/app_database.dart' as db;
import '../../settings/services/settings_persistence.dart';
import 'audio_engine.dart' show buildFilterChain;

/// A second, short-lived player for auditioning songs — the playlist track
/// picker uses it so trying a song out never touches the real player.
///
/// The queue, the current track and its position stay exactly where they
/// were, and nothing is booked as a play or as listening time: the scrobbler
/// and the session saver only watch the main player.
///
/// Only one of the two is ever audible. Starting a preview pauses the main
/// player; the main player starting (a media key, the tray) pauses the
/// preview. Music that was playing before the first preview resumes on
/// [stop] or [dispose].
class PreviewPlayer extends ChangeNotifier {
  PreviewPlayer(this._main, {this.settings}) {
    _subscriptions.add(
      _main.stream.playing.listen((playing) {
        if (playing && _playing) unawaited(_player?.pause());
      }),
    );
  }

  final Player _main;

  /// EQ and ReplayGain, so a song sounds the way it will in the playlist.
  final AppSettings? settings;

  Player? _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  db.Track? _track;
  bool _playing = false;
  String? _error;
  bool _resumeMain = false;
  bool _disposed = false;

  /// The song being previewed, or null when nothing is loaded.
  db.Track? get track => _track;
  bool get playing => _playing;

  /// Why the last song could not be played, if it couldn't.
  String? get error => _error;

  /// Created on first use, so opening the picker costs nothing until a song
  /// is actually previewed.
  Player get player => _player ??= _create();

  Player _create() {
    final player = Player();
    unawaited(player.setPlaylistMode(PlaylistMode.none));

    _subscriptions.add(
      player.stream.playing.listen((playing) {
        if (playing == _playing) return;
        _playing = playing;
        _notify();
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((message) {
        if (_track == null) return;
        _error = message;
        _notify();
      }),
    );
    // mpv also reports errors it recovers from; audio actually advancing
    // proves the song plays, so drop the message then.
    _subscriptions.add(
      player.stream.position.listen((position) {
        if (_error == null || position <= Duration.zero) return;
        _error = null;
        _notify();
      }),
    );

    unawaited(_applySettings(player));
    return player;
  }

  Future<void> _applySettings(Player player) async {
    final settings = this.settings;
    final native = player.platform;
    if (settings == null || native is! NativePlayer) return;
    try {
      final chain = buildFilterChain(settings: settings, stretchFilter: null);
      if (chain.isNotEmpty) await native.setProperty('af', chain);
      await native.setProperty('replaygain', switch (settings.replayGain) {
        ReplayGainMode.off => 'no',
        ReplayGainMode.track => 'track',
        ReplayGainMode.album => 'album',
      });
    } catch (e) {
      // A preview without EQ beats no preview.
      debugPrint('Preview: audio settings not applied: $e');
    }
  }

  /// Starts [track] from the top, replacing whatever was being previewed.
  Future<void> play(db.Track track) async {
    if (_disposed) return;
    if (_main.state.playing) {
      _resumeMain = true;
      await _main.pause();
    }

    _track = track;
    _error = null;
    _notify();

    final player = this.player;
    if (!File(track.filePath).existsSync()) {
      await player.stop();
      _error = 'File not found';
      _notify();
      return;
    }

    await player.setVolume(_main.state.volume);
    await player.open(Media(track.filePath));
  }

  /// Play/pause for the loaded song; replays it once it has finished.
  Future<void> toggle() async {
    final current = _track;
    final player = _player;
    if (current == null || player == null || _error != null) return;

    if (_playing) {
      await player.pause();
      return;
    }
    if (_main.state.playing) {
      _resumeMain = true;
      await _main.pause();
    }
    if (player.state.completed) {
      await play(current);
      return;
    }
    await player.play();
  }

  Future<void> seek(Duration position) async => _player?.seek(position);

  /// Ends the preview and gives the main player back its music.
  Future<void> stop() async {
    _track = null;
    _error = null;
    _notify();
    await _player?.stop();
    _resumeMainPlayer();
  }

  void _resumeMainPlayer() {
    if (!_resumeMain) return;
    _resumeMain = false;
    if (!_main.state.playing) unawaited(_main.play());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    final player = _player;
    _player = null;
    // Silence the preview before the main player comes back in.
    unawaited(() async {
      if (player != null) {
        await player.stop();
        await player.dispose();
      }
      _resumeMainPlayer();
    }());
    super.dispose();
  }
}
