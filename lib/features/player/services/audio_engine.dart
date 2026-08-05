import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../settings/services/settings_persistence.dart';
import '../providers/player_provider.dart';

/// mpv-level audio processing: playback speed, equalizer, ReplayGain, and the
/// "stop when nobody is around" timer.
///
/// These drive libmpv's own filter chain rather than any platform effect API,
/// so the behaviour is identical on Windows, Linux and macOS.
class AudioEngine {
  AudioEngine(this.player);

  final Player player;

  NativePlayer? get _native {
    final platform = player.platform;
    return platform is NativePlayer ? platform : null;
  }

  /// Last settings seen, so the chain can be rebuilt on a speed change without
  /// the settings controller being involved.
  AppSettings? _settings;

  /// Remembered so it can be re-applied after every track load — mpv resets
  /// speed when a new file is opened.
  double _desiredRate = 1.0;

  double get rate => _desiredRate;

  /// Time-stretch filter, tuned for music rather than mpv's speech-oriented
  /// defaults, most preferred first.
  ///
  /// mpv's automatic pitch correction inserts plain `scaletempo` with a 60 ms
  /// stride, which chorus/warbles audibly on music at any speed off 1.0.
  /// `scaletempo2` is the WSOLA implementation Chromium uses for the same job
  /// and is transparent by comparison; a longer analysis window than its 12 ms
  /// default suits sustained musical tones. The legacy filter is kept as a
  /// fallback with a much shorter stride and heavy overlap, which is the usual
  /// fix for its warbling.
  static const _stretchFilters = <String>[
    'scaletempo2=search-interval=30:window-size=20',
    'scaletempo=stride=28:overlap=0.9:search=20',
  ];

  String? _stretchFilter;
  bool _stretchProbed = false;

  /// Finds a stretch filter this libmpv build actually has. [NativePlayer]'s
  /// `setProperty` discards libmpv's return code, so the only way to know an
  /// `af` string was accepted is to read the chain back — mpv rejects the
  /// whole list if one filter is unknown and leaves the previous one in place.
  Future<void> _probeStretchFilter(NativePlayer native) async {
    if (_stretchProbed) return;
    _stretchProbed = true;

    for (final filter in _stretchFilters) {
      final name = filter.split('=').first;
      try {
        await native.setProperty('af', filter);
        if ((await native.getProperty('af')).contains(name)) {
          _stretchFilter = filter;
          // Exactly one stretcher in the chain: mpv would otherwise insert its
          // own on top of ours and the two would fight over the speed.
          await native.setProperty('audio-pitch-correction', 'no');
          debugPrint('[electrowave] time-stretch filter: $filter');
          return;
        }
      } catch (_) {
        // Try the next candidate.
      }
    }

    // Nothing usable — leave mpv to do its own (worse) correction.
    debugPrint('[electrowave] no time-stretch filter available in this libmpv');
    try {
      await native.setProperty('audio-pitch-correction', 'yes');
    } catch (_) {}
  }

  /// Rebuild the `af` chain: time-stretcher (only off 1.0×, so normal-speed
  /// playback is bit-for-bit untouched) followed by the EQ bands. An empty
  /// chain clears all filters, so a disabled/flat EQ costs nothing.
  Future<void> _applyFilterChain() async {
    final native = _native;
    if (native == null) return;
    await _probeStretchFilter(native);

    final settings = _settings;
    final filters = <String>[
      if (_desiredRate != 1.0 && _stretchFilter != null) _stretchFilter!,
    ];

    if (settings != null && settings.eqEnabled) {
      for (var i = 0; i < kEqBandFrequencies.length; i++) {
        final gain = i < settings.eqGainsDb.length ? settings.eqGainsDb[i] : 0.0;
        // Skip inaudible bands to keep the chain short.
        if (gain.abs() < 0.1) continue;
        filters.add(
          'equalizer=f=${kEqBandFrequencies[i]}:t=o:w=2'
          ':g=${gain.toStringAsFixed(1)}',
        );
      }
    }

    try {
      await native.setProperty('af', filters.join(','));
    } catch (_) {
      // An unsupported filter must not take playback down.
    }
  }

  /// Playback speed. The filter chain is rebuilt *before* the speed changes so
  /// the time-stretcher is already in place — otherwise the first frames come
  /// out pitch-shifted.
  Future<void> setRate(double rate) async {
    _desiredRate = rate.clamp(0.5, 2.0);
    await _applyFilterChain();
    await player.setRate(_desiredRate);
  }

  /// mpv resets speed on every new file; call this after opening a track.
  Future<void> reapplyRate() async {
    if (_desiredRate == 1.0) return;
    await player.setRate(_desiredRate);
  }

  /// Apply EQ + ReplayGain from [settings].
  Future<void> applyAudioSettings(AppSettings settings) async {
    _settings = settings;
    final native = _native;
    if (native == null) return;

    await _applyFilterChain();
    try {
      await native.setProperty('replaygain', switch (settings.replayGain) {
        ReplayGainMode.off => 'no',
        ReplayGainMode.track => 'track',
        ReplayGainMode.album => 'album',
      });
    } catch (_) {
      // An unsupported property must not take playback down.
    }
  }

  // ---------------------------------------------------------------------
  // Stop when unattended
  // ---------------------------------------------------------------------

  Timer? _inactivityTimer;
  Duration? _inactivityTimeout;

  /// Applied from the settings controller; null disables the check.
  void setInactivityTimeout(Duration? timeout) {
    _inactivityTimeout = timeout;
    _restartInactivityTimer();
  }

  /// Push the auto-stop deadline back. Called for anything the user actually
  /// did: a click in the app, a media key, a tray control. Deliberately *not*
  /// called for automatic track advances — those aren't the user being present.
  void noteUserActivity() => _restartInactivityTimer();

  void _restartInactivityTimer() {
    _inactivityTimer?.cancel();
    final timeout = _inactivityTimeout;
    if (timeout == null) {
      _inactivityTimer = null;
      return;
    }
    _inactivityTimer = Timer(timeout, () {
      if (!player.state.playing) return;
      unawaited(player.pause());
    });
  }

  void dispose() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }
}

final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = AudioEngine(ref.watch(playerProvider));
  ref.onDispose(engine.dispose);
  return engine;
});
