import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';

/// Uses the locally installed ffmpeg. Nothing is downloaded or uploaded.
class LoudnessScanner {
  LoudnessScanner(this.db, {this.executable = 'ffmpeg'});
  final String executable;
  final AppDatabase db;
  bool cancelled = false;
  Process? _process;
  void cancel() {
    cancelled = true;
    _process?.kill();
  }

  static double? parseLoudness(String output) {
    final matches = RegExp(
      r'I:\s*(-?\d+(?:\.\d+)?) LUFS',
    ).allMatches(output).toList();
    if (matches.isEmpty) return null;
    final loudness = double.tryParse(matches.last.group(1)!);
    if (loudness == null || !loudness.isFinite || loudness <= -70) return null;
    return (-18 - loudness).clamp(-30, 30);
  }

  Future<int> scan(List<Track> tracks, void Function(int, int) progress) async {
    cancelled = false;
    var saved = 0;
    for (var i = 0; i < tracks.length; i++) {
      if (cancelled) break;
      final track = tracks[i];
      _process = await Process.start(executable, [
        '-hide_banner',
        '-nostats',
        '-i',
        track.filePath,
        '-vn',
        '-af',
        'ebur128=peak=true',
        '-f',
        'null',
        '-',
      ]);
      final stderr = _process!.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      final stdout = _process!.stdout.drain<void>();
      final exit = await _process!.exitCode;
      final output = await stderr;
      await stdout;
      _process = null;
      if (cancelled) break;
      final gain = parseLoudness(output);
      if (exit == 0 && gain != null) {
        await (db.update(db.tracks)..where((t) => t.id.equals(track.id))).write(
          TracksCompanion(replayGainDb: Value(gain)),
        );
        saved++;
      }
      progress(i + 1, tracks.length);
    }
    return saved;
  }
}
