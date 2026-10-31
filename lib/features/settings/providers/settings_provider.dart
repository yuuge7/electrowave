import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../player/services/audio_engine.dart';
import '../services/settings_persistence.dart';

/// The version baked into the build, so About can never drift from the
/// released binary the way a hardcoded string does. Falls back to the build
/// number only when it adds information.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  if (info.version.isEmpty) return 'unknown';
  return info.buildNumber.isEmpty
      ? info.version
      : '${info.version} (build ${info.buildNumber})';
});

final settingsPersistenceProvider = Provider<SettingsPersistence>(
  (ref) => SettingsPersistence(),
);

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Loads persisted settings on first build and pushes the audio-affecting ones
/// (speed, EQ, ReplayGain, auto-stop) into the player whenever they change.
class SettingsController extends Notifier<AppSettings> {
  SettingsPersistence get _persistence => ref.read(settingsPersistenceProvider);

  @override
  AppSettings build() {
    Future.microtask(_restore);
    return const AppSettings();
  }

  bool _touched = false;
  Future<void> _audioPending = Future.value();
  Future<void> _restore() async {
    final saved = await _persistence.load();
    if (!ref.mounted || _touched) return;
    state = saved;
    await _applyToPlayer(saved);
  }

  Future<void> _applyToPlayer(AppSettings settings) {
    _audioPending = _audioPending.then((_) => _applyAudio(settings));
    return _audioPending;
  }

  Future<void> _applyAudio(AppSettings settings) async {
    if (!ref.mounted) return;
    final engine = ref.read(audioEngineProvider);
    await engine.setRate(settings.playbackRate);
    await engine.applyAudioSettings(settings);
    engine.setInactivityTimeout(settings.inactivityStopTimeout);
  }

  Future<void> _update(AppSettings next, {bool audio = false}) async {
    _touched = true;
    state = next;
    unawaited(_persistence.save(next));
    if (audio) await _applyToPlayer(next);
  }

  Future<void> updatePreferences(AppSettings settings, {bool audio = false}) =>
      _update(settings, audio: audio);

  Future<void> setPreamp(double gain) =>
      _update(state.copyWith(eqPreampDb: gain.clamp(-24, 0)), audio: true);
  Future<void> setCrossfade(double seconds) =>
      _update(state.copyWith(crossfadeSeconds: seconds.clamp(0, 12)));
  Future<void> setAudioDevice(String name) =>
      _update(state.copyWith(audioDevice: name), audio: true);
  Future<void> setExclusive(bool enabled) async {
    final next = enabled
        ? state.copyWith(
            exclusiveMode: true,
            playbackRate: 1,
            eqEnabled: false,
            replayGain: ReplayGainMode.off,
            crossfadeSeconds: 0,
          )
        : state.copyWith(exclusiveMode: false);
    await _update(next, audio: true);
    if (enabled) await ref.read(audioEngineProvider).player.setVolume(100);
  }

  Future<void> setTextScale(double scale) =>
      _update(state.copyWith(textScale: scale.clamp(0.85, 1.6)));
  Future<void> saveEqPreset(String name) => _update(
    state.copyWith(
      eqUserPresets: {
        ...state.eqUserPresets,
        name: List<double>.from(state.eqGainsDb),
      },
    ),
  );
  Future<void> importEqPresets(Map<String, List<double>> presets) => _update(
    state.copyWith(eqUserPresets: {...state.eqUserPresets, ...presets}),
  );

  Future<void> setThemeMode(AppThemeMode mode) =>
      _update(state.copyWith(themeMode: mode));

  Future<void> setPlaybackRate(double rate) =>
      _update(state.copyWith(playbackRate: rate.clamp(0.5, 2.0)), audio: true);

  Future<void> setEqEnabled(bool enabled) =>
      _update(state.copyWith(eqEnabled: enabled), audio: true);

  Future<void> setEqBand(int index, double gainDb) {
    if (index < 0 || index >= kEqBandFrequencies.length) {
      return Future.value();
    }
    final gains = List<double>.from(state.eqGainsDb);
    while (gains.length < kEqBandFrequencies.length) {
      gains.add(0);
    }
    gains[index] = gainDb.clamp(-kEqMaxGainDb, kEqMaxGainDb);
    return _update(state.copyWith(eqGainsDb: gains), audio: true);
  }

  /// Applies one of [kEqPresets]. Unknown names are ignored.
  Future<void> applyEqPreset(String name) {
    final preset = state.eqUserPresets[name] ?? kEqPresets[name];
    if (preset == null) return Future.value();
    return _update(
      state.copyWith(eqGainsDb: List<double>.from(preset), eqEnabled: true),
      audio: true,
    );
  }

  Future<void> resetEq() => _update(
    state.copyWith(
      eqGainsDb: List<double>.filled(kEqBandFrequencies.length, 0),
    ),
    audio: true,
  );

  Future<void> setReplayGain(ReplayGainMode mode) =>
      _update(state.copyWith(replayGain: mode), audio: true);

  /// 0 disables the no-interaction auto-stop.
  Future<void> setInactivityStopMinutes(int minutes) => _update(
    state.copyWith(inactivityStopMinutes: minutes < 0 ? 0 : minutes),
    audio: true,
  );
}
