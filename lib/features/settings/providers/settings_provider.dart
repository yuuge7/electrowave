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

final settingsPersistenceProvider =
    Provider<SettingsPersistence>((ref) => SettingsPersistence());

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

  Future<void> _restore() async {
    final saved = await _persistence.load();
    state = saved;
    await _applyToPlayer(saved);
  }

  Future<void> _applyToPlayer(AppSettings settings) async {
    final engine = ref.read(audioEngineProvider);
    await engine.setRate(settings.playbackRate);
    await engine.applyAudioSettings(settings);
    engine.setInactivityTimeout(settings.inactivityStopTimeout);
  }

  Future<void> _update(AppSettings next, {bool audio = false}) async {
    state = next;
    unawaited(_persistence.save(next));
    if (audio) await _applyToPlayer(next);
  }

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
    final preset = kEqPresets[name];
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
