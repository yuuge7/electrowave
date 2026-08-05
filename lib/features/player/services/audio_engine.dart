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

  /// The chain mpv last accepted, so a rejected one can be rolled back instead
  /// of leaving the audio output dead.
  String _appliedChain = '';

  /// Rebuild the `af` chain. An empty chain clears all filters, so a disabled
  /// or flat EQ costs nothing.
  ///
  /// Two ordering rules matter, and getting either wrong silently kills
  /// playback rather than just the effect:
  ///
  /// 1. The EQ goes in as **one** `lavfi` graph, not one bridged filter per
  ///    band. Every entry in `af` is a separate node mpv has to negotiate
  ///    formats across; five bands plus a stretcher is six nodes, and if that
  ///    reinitialization fails mpv disables audio entirely — on an audio-only
  ///    file that looks like a track frozen at 0:00.
  /// 2. The time-stretcher is **last**. It is the filter that consumes the
  ///    speed change, so anything after it would be handed a stream whose
  ///    rate no longer matches what mpv negotiated.
  Future<void> _applyFilterChain() async {
    final native = _native;
    if (native == null) return;
    await _probeStretchFilter(native);

    final useStretcher = _desiredRate != 1.0 && _stretchFilter != null;
    final chain = buildFilterChain(
      settings: _settings,
      stretchFilter: useStretcher ? _stretchFilter : null,
    );

    if (await _setChain(native, chain, wantsStretcher: useStretcher)) return;

    // mpv refused the chain. Fall back to the EQ alone and hand speed back to
    // mpv's own (worse, but working) pitch correction rather than leaving the
    // player with no audio filter graph at all.
    debugPrint('[electrowave] af chain rejected: $chain');
    final eqOnly = buildFilterChain(settings: _settings, stretchFilter: null);
    if (eqOnly != chain &&
        await _setChain(native, eqOnly, wantsStretcher: false)) {
      return;
    }

    // Even that failed: clear the chain so playback keeps working unfiltered.
    debugPrint('[electrowave] falling back to an empty af chain');
    await _setChain(native, '', wantsStretcher: false);
  }

  /// Sets `af` and verifies mpv took it — [NativePlayer.setProperty] discards
  /// libmpv's return code, so the chain has to be read back.
  Future<bool> _setChain(
    NativePlayer native,
    String chain, {
    required bool wantsStretcher,
  }) async {
    try {
      // Exactly one stretcher in the chain: with correction left on, mpv
      // inserts its own on top of ours and the two fight over the speed.
      await native.setProperty(
          'audio-pitch-correction', wantsStretcher ? 'no' : 'yes');
      await native.setProperty('af', chain);

      final applied = await native.getProperty('af');
      if (!_chainApplied(chain, applied)) return false;

      _appliedChain = chain;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// mpv normalizes what it reports back (`lavfi.graph=...`, added defaults),
  /// so this checks that every filter asked for is present rather than
  /// comparing strings.
  bool _chainApplied(String requested, String applied) {
    if (requested.isEmpty) return true;
    for (final name in _filterNames(requested)) {
      if (!applied.contains(name)) return false;
    }
    return true;
  }

  Iterable<String> _filterNames(String chain) sync* {
    if (chain.contains('lavfi')) yield 'equalizer';
    final stretch = _stretchFilter;
    if (stretch != null && chain.contains(stretch.split('=').first)) {
      yield stretch.split('=').first;
    }
  }

  /// Re-asserts the chain mpv last accepted. Opening a file rebuilds the audio
  /// output, and a chain that was cleared by a failed apply would otherwise
  /// stay gone for the rest of the session.
  Future<void> reapplyFilterChain() async {
    final native = _native;
    if (native == null) return;
    if (_appliedChain.isEmpty && _desiredRate == 1.0) return;
    await _applyFilterChain();
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
    if (_desiredRate == 1.0 && _appliedChain.isEmpty) return;
    await reapplyFilterChain();
    if (_desiredRate != 1.0) await player.setRate(_desiredRate);
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

/// Builds the mpv `af` string for [settings] and an optional [stretchFilter].
///
/// The EQ bands are wrapped in a single `lavfi=[...]` graph: the brackets keep
/// ffmpeg's comma-separated graph syntax from being read as mpv's own filter
/// separator, and the whole equalizer ends up as one node in mpv's chain
/// instead of one per band. The stretcher always comes last so it is the
/// filter that absorbs the speed change.
String buildFilterChain({
  required AppSettings? settings,
  required String? stretchFilter,
}) {
  final parts = <String>[];

  if (settings != null && settings.eqEnabled) {
    final bands = <String>[];
    for (var i = 0; i < kEqBandFrequencies.length; i++) {
      final gain = i < settings.eqGainsDb.length ? settings.eqGainsDb[i] : 0.0;
      // Skip inaudible bands to keep the graph short.
      if (gain.abs() < 0.1) continue;
      bands.add('equalizer=f=${kEqBandFrequencies[i]}:t=o:w=2'
          ':g=${gain.toStringAsFixed(1)}');
    }
    if (bands.isNotEmpty) parts.add('lavfi=[${bands.join(',')}]');
  }

  if (stretchFilter != null) parts.add(stretchFilter);

  return parts.join(',');
}

final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = AudioEngine(ref.watch(playerProvider));
  ref.onDispose(engine.dispose);
  return engine;
});
