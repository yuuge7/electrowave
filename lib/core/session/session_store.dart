import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'session_snapshot.dart';

/// Reads and writes `session.json` next to the database, inside the
/// Electrowave folder.
///
/// Session state is deliberately kept out of the SQLite database: the backup
/// / import feature swaps the whole database file, and "what was playing on
/// this machine" should not travel with a library backup.
class SessionStore {
  static const String _fileName = 'session.json';

  static Future<File> _sessionFile() async {
    final docsFolder = await getApplicationDocumentsDirectory();
    final appFolder = Directory(p.join(docsFolder.path, 'Electrowave'));
    if (!await appFolder.exists()) {
      await appFolder.create(recursive: true);
    }
    return File(p.join(appFolder.path, _fileName));
  }

  /// Returns the last saved session, or null when there is none (or the file
  /// is unreadable — a broken session must never block startup).
  static Future<SessionSnapshot?> load() async {
    try {
      final file = await _sessionFile();
      if (!await file.exists()) return null;

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      return SessionSnapshot.fromJson(decoded);
    } catch (e) {
      debugPrint('Session load failed: $e');
      return null;
    }
  }

  /// Writes via a temp file + rename so a crash mid-write can never leave a
  /// truncated session behind.
  static Future<void> save(SessionSnapshot snapshot) async {
    try {
      final file = await _sessionFile();
      final tempFile = File('${file.path}.tmp');
      await tempFile.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      await tempFile.rename(file.path);
    } catch (e) {
      debugPrint('Session save failed: $e');
    }
  }

  /// Drops the saved session. Used when the database is replaced by an
  /// import, since the stored track IDs then point at a different library.
  static Future<void> clear() async {
    try {
      final file = await _sessionFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Session clear failed: $e');
    }
  }
}
