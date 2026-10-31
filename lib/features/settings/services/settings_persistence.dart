import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_paths.dart';

enum AppThemeMode { system, light, dark }

/// ReplayGain mode, applied by mpv itself (it reads the gain tags).
enum ReplayGainMode { off, track, album }

/// Fixed EQ band centre frequencies, in Hz.
const List<int> kEqBandFrequencies = [
  31,
  62,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

const double kEqMaxGainDb = 12;

/// Named EQ curves, gains parallel to [kEqBandFrequencies].
const Map<String, List<double>> kEqPresets = {
  'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'Bass boost': [6, 7, 5, 3, 1, 0, 0, 0, 0, 0],
  'Treble boost': [0, 0, 0, 0, 0, 0, 1, 3, 5, 7],
  'Vocal': [-3, -2, -1, 0, 2, 4, 3, 2, 0, -1],
  'Rock': [5, 4, 2, 0, -1, -1, 1, 3, 4, 5],
  'Electronic': [6, 5, 3, 1, -2, -2, 0, 2, 4, 5],
  'Loudness': [6, 5, 3, 1, -2, -2, 0, 2, 4, 6],
};

/// Selectable "stop after this long without the user touching anything"
/// values, in minutes. 0 disables the check.
const List<int> kInactivityStopChoicesMinutes = [0, 30, 60, 120, 240, 480];

/// User settings that aren't part of the library database.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.dark,
    this.playbackRate = 1.0,
    this.eqEnabled = false,
    this.eqGainsDb = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.replayGain = ReplayGainMode.off,
    this.eqPreampDb = 0,
    this.crossfadeSeconds = 0,
    this.audioDevice = 'auto',
    this.exclusiveMode = false,
    this.textScale = 1,
    this.libraryFolders = const [],
    this.backupFolder,
    this.eqUserPresets = const {},
    this.inactivityStopMinutes = 0,
  });

  final double eqPreampDb;
  final double crossfadeSeconds;
  final String audioDevice;
  final bool exclusiveMode;
  final double textScale;
  final List<String> libraryFolders;
  final String? backupFolder;
  final Map<String, List<double>> eqUserPresets;
  final AppThemeMode themeMode;
  final double playbackRate;
  final bool eqEnabled;

  /// Gain per band in dB, parallel to [kEqBandFrequencies].
  final List<double> eqGainsDb;
  final ReplayGainMode replayGain;

  /// Stop playback after this many minutes without any user interaction.
  /// 0 turns the check off. Unlike the sleep timer this keeps re-arming, so it
  /// only fires when the listener really has walked away.
  final int inactivityStopMinutes;

  /// Null when disabled.
  Duration? get inactivityStopTimeout => inactivityStopMinutes > 0
      ? Duration(minutes: inactivityStopMinutes)
      : null;

  AppSettings copyWith({
    double? eqPreampDb,
    double? crossfadeSeconds,
    String? audioDevice,
    bool? exclusiveMode,
    double? textScale,
    List<String>? libraryFolders,
    String? backupFolder,
    bool clearBackupFolder = false,
    Map<String, List<double>>? eqUserPresets,
    AppThemeMode? themeMode,
    double? playbackRate,
    bool? eqEnabled,
    List<double>? eqGainsDb,
    ReplayGainMode? replayGain,
    int? inactivityStopMinutes,
  }) {
    return AppSettings(
      eqPreampDb: eqPreampDb ?? this.eqPreampDb,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      audioDevice: audioDevice ?? this.audioDevice,
      exclusiveMode: exclusiveMode ?? this.exclusiveMode,
      textScale: textScale ?? this.textScale,
      libraryFolders: libraryFolders ?? this.libraryFolders,
      backupFolder: clearBackupFolder
          ? null
          : (backupFolder ?? this.backupFolder),
      eqUserPresets: eqUserPresets ?? this.eqUserPresets,
      themeMode: themeMode ?? this.themeMode,
      playbackRate: playbackRate ?? this.playbackRate,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqGainsDb: eqGainsDb ?? this.eqGainsDb,
      replayGain: replayGain ?? this.replayGain,
      inactivityStopMinutes:
          inactivityStopMinutes ?? this.inactivityStopMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
    'eqPreampDb': eqPreampDb,
    'crossfadeSeconds': crossfadeSeconds,
    'audioDevice': audioDevice,
    'exclusiveMode': exclusiveMode,
    'textScale': textScale,
    'libraryFolders': libraryFolders,
    'backupFolder': backupFolder,
    'eqUserPresets': eqUserPresets,
    'themeMode': themeMode.name,
    'playbackRate': playbackRate,
    'eqEnabled': eqEnabled,
    'eqGainsDb': eqGainsDb,
    'replayGain': replayGain.name,
    'inactivityStopMinutes': inactivityStopMinutes,
  };

  static AppSettings fromJson(Map<String, dynamic> json) {
    List<double> gains() {
      final raw = json['eqGainsDb'];
      if (raw is! List) return List<double>.filled(10, 0);
      final parsed = [
        for (final value in raw)
          (value is num ? value.toDouble() : 0.0).clamp(
            -kEqMaxGainDb,
            kEqMaxGainDb,
          ),
      ];
      // Tolerate a settings file written by a build with a different band
      // count rather than throwing the whole file away.
      if (parsed.length == 5) {
        return [
          parsed[0],
          parsed[0],
          parsed[1],
          parsed[1],
          parsed[2],
          parsed[2],
          parsed[3],
          parsed[3],
          parsed[4],
          parsed[4],
        ];
      }
      if (parsed.length != kEqBandFrequencies.length) {
        return List<double>.filled(kEqBandFrequencies.length, 0);
      }
      return parsed;
    }

    return AppSettings(
      eqPreampDb: ((json['eqPreampDb'] as num?)?.toDouble() ?? 0).clamp(-24, 0),
      crossfadeSeconds: ((json['crossfadeSeconds'] as num?)?.toDouble() ?? 0)
          .clamp(0, 12),
      audioDevice: json['audioDevice'] as String? ?? 'auto',
      exclusiveMode: json['exclusiveMode'] == true,
      textScale: ((json['textScale'] as num?)?.toDouble() ?? 1).clamp(
        0.85,
        1.6,
      ),
      libraryFolders:
          (json['libraryFolders'] as List?)?.whereType<String>().toList() ?? [],
      backupFolder: json['backupFolder'] as String?,
      eqUserPresets: {
        for (final entry
            in (json['eqUserPresets'] is Map
                ? (json['eqUserPresets'] as Map).entries
                : <MapEntry>[]))
          if (entry.key is String &&
              entry.value is List &&
              (entry.value as List).length == 10)
            entry.key as String: (entry.value as List)
                .map((n) => (n is num ? n.toDouble() : 0.0).clamp(-12.0, 12.0))
                .toList(),
      },
      themeMode: AppThemeMode.values.firstWhere(
        (mode) => mode.name == json['themeMode'],
        orElse: () => AppThemeMode.dark,
      ),
      playbackRate: ((json['playbackRate'] as num?)?.toDouble() ?? 1.0).clamp(
        0.5,
        2.0,
      ),
      eqEnabled: json['eqEnabled'] as bool? ?? false,
      eqGainsDb: gains(),
      replayGain: ReplayGainMode.values.firstWhere(
        (mode) => mode.name == json['replayGain'],
        orElse: () => ReplayGainMode.off,
      ),
      inactivityStopMinutes: switch (json['inactivityStopMinutes']) {
        final num minutes when minutes >= 0 => minutes.toInt(),
        _ => 0,
      },
    );
  }
}

class SettingsPersistence {
  Future<void> _pending = Future.value();
  File? _file;

  Future<File> _settingsFile() async {
    if (_file != null) return _file!;
    final dir = await appDataDirectory();
    _file = File(p.join(dir.path, 'settings.json'));
    return _file!;
  }

  Future<AppSettings> load() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return const AppSettings();
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return const AppSettings();
      return AppSettings.fromJson(json);
    } catch (e) {
      debugPrint('Settings load failed: $e');
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) {
    _pending = _pending.then((_) => _save(settings));
    return _pending;
  }

  Future<void> _save(AppSettings settings) async {
    try {
      final file = await _settingsFile();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(settings.toJson()), flush: true);
      await temp.rename(file.path);
    } catch (e) {
      // Best effort; a settings write must never break playback.
      debugPrint('Settings save failed: $e');
    }
  }
}
