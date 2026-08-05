import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:electrowave/core/database/app_database.dart';
import 'package:electrowave/features/settings/services/settings_persistence.dart';

Future<int> _insertTrack(
  AppDatabase db, {
  required String title,
  String artist = 'Artist',
  String album = 'Album',
  int durationMs = 200000,
  int? trackNumber,
}) {
  return db.into(db.tracks).insert(
        TracksCompanion.insert(
          filePath: 'C:/music/$title.mp3',
          title: title,
          artist: artist,
          album: album,
          durationMs: durationMs,
          trackNumber: Value(trackNumber),
          dateAdded: Value(DateTime.now()),
        ),
      );
}

void main() {
  group('AppSettings', () {
    test('round trips through JSON', () {
      const settings = AppSettings(
        themeMode: AppThemeMode.light,
        playbackRate: 1.25,
        eqEnabled: true,
        eqGainsDb: [3, -2, 0, 4.5, 1],
        replayGain: ReplayGainMode.album,
        inactivityStopMinutes: 120,
      );

      final decoded = AppSettings.fromJson(settings.toJson());

      expect(decoded.themeMode, AppThemeMode.light);
      expect(decoded.playbackRate, 1.25);
      expect(decoded.eqEnabled, isTrue);
      expect(decoded.eqGainsDb, [3, -2, 0, 4.5, 1]);
      expect(decoded.replayGain, ReplayGainMode.album);
      expect(decoded.inactivityStopMinutes, 120);
      expect(decoded.inactivityStopTimeout, const Duration(minutes: 120));
    });

    test('falls back to defaults on junk', () {
      final decoded = AppSettings.fromJson(<String, dynamic>{
        'themeMode': 'neon',
        'playbackRate': 9,
        'eqGainsDb': [1, 2],
        'replayGain': 'sometimes',
        'inactivityStopMinutes': -5,
      });

      expect(decoded.themeMode, AppThemeMode.dark);
      // Out-of-range speed is clamped rather than dropped.
      expect(decoded.playbackRate, 2.0);
      // Wrong band count is replaced by a flat curve.
      expect(decoded.eqGainsDb, [0, 0, 0, 0, 0]);
      expect(decoded.replayGain, ReplayGainMode.off);
      expect(decoded.inactivityStopMinutes, 0);
      expect(decoded.inactivityStopTimeout, isNull);
    });

    test('every preset matches the band count', () {
      for (final entry in kEqPresets.entries) {
        expect(entry.value.length, kEqBandFrequencies.length,
            reason: 'preset ${entry.key}');
        for (final gain in entry.value) {
          expect(gain.abs() <= kEqMaxGainDb, isTrue,
              reason: 'preset ${entry.key}');
        }
      }
    });
  });

  group('AppDatabase', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('recordPlay feeds play counts and the recently/most played lists',
        () async {
      final first = await _insertTrack(db, title: 'One');
      final second = await _insertTrack(db, title: 'Two');

      await db.recordPlay(first);
      await db.recordPlay(first);
      await db.recordPlay(second);

      final mostPlayed = await db.watchMostPlayed().first;
      expect(mostPlayed.map((t) => t.id), [first, second]);
      expect(mostPlayed.first.totalPlayCount, 2);

      final recentlyPlayed = await db.watchRecentlyPlayed().first;
      expect(recentlyPlayed.length, 2);
      expect(recentlyPlayed.every((t) => t.lastPlayed != null), isTrue);

      await db.clearPlayHistory();
      expect(await db.watchMostPlayed().first, isEmpty);
    });

    test('favorites only list hearted, non-deleted tracks', () async {
      final kept = await _insertTrack(db, title: 'Kept');
      final removed = await _insertTrack(db, title: 'Removed');

      await db.setFavorite(kept, true);
      await db.setFavorite(removed, true);
      await (db.update(db.tracks)..where((t) => t.id.equals(removed)))
          .write(const TracksCompanion(isDeleted: Value(true)));

      final favorites = await db.watchFavorites().first;
      expect(favorites.map((t) => t.id), [kept]);
    });

    test('removed tracks can be restored or purged', () async {
      final id = await _insertTrack(db, title: 'Gone');
      await db.recordPlay(id);
      await (db.update(db.tracks)..where((t) => t.id.equals(id)))
          .write(const TracksCompanion(isDeleted: Value(true)));

      expect((await db.watchDeletedTracks().first).map((t) => t.id), [id]);

      await db.restoreTrack(id);
      expect(await db.watchDeletedTracks().first, isEmpty);

      await (db.update(db.tracks)..where((t) => t.id.equals(id)))
          .write(const TracksCompanion(isDeleted: Value(true)));
      expect(await db.emptyTrash(), 1);
      expect(await db.trackById(id), isNull);
    });

    test('playlist keeps a manual order across adds, reorders and removals',
        () async {
      final playlistId = await db
          .into(db.playlists)
          .insert(PlaylistsCompanion.insert(name: 'Mix'));
      final a = await _insertTrack(db, title: 'A');
      final b = await _insertTrack(db, title: 'B');
      final c = await _insertTrack(db, title: 'C');

      for (final id in [a, b, c]) {
        await db.addTrackToPlaylist(playlistId, id);
      }
      expect((await db.watchPlaylistTracks(playlistId).first).map((t) => t.id),
          [a, b, c]);

      await db.reorderPlaylist(playlistId, [c, a, b]);
      expect((await db.watchPlaylistTracks(playlistId).first).map((t) => t.id),
          [c, a, b]);

      // Adding again must not duplicate or disturb the order.
      await db.addTrackToPlaylist(playlistId, a);
      expect((await db.watchPlaylistTracks(playlistId).first).map((t) => t.id),
          [c, a, b]);

      await db.removeTrackFromPlaylist(playlistId, a);
      final remaining = await (db.select(db.playlistTracks)
            ..where((pt) => pt.playlistId.equals(playlistId)))
          .get();
      // Positions are normalized, so no gaps are left behind.
      expect(remaining.map((row) => row.position).toList()..sort(), [0, 1]);
    });

    test('albums group by name and flag compilations', () async {
      await _insertTrack(db, title: 'S1', artist: 'A1', album: 'Solo');
      await _insertTrack(db, title: 'S2', artist: 'A1', album: 'Solo');
      await _insertTrack(db, title: 'C1', artist: 'A1', album: 'Comp');
      await _insertTrack(db, title: 'C2', artist: 'A2', album: 'Comp');

      final albums = await db.watchAlbums().first;
      final byName = {for (final album in albums) album.album: album};

      expect(byName['Solo']!.artist, 'A1');
      expect(byName['Solo']!.trackCount, 2);
      expect(byName['Comp']!.artist, 'Various artists');
    });

    test('measured listening time accumulates per session', () async {
      final id = await _insertTrack(db, title: 'Long');

      final session = await db.startListeningSession(id);
      await db.saveListenedMs(session, 30000);
      // Absolute value, not a delta: a re-save must not double-count.
      await db.saveListenedMs(session, 45000);

      expect(await db.watchTotalListenedMs().first, 45000);

      final ranked = await db.watchTracksByListeningTime().first;
      expect(ranked.single.track.id, id);
      expect(ranked.single.listenedMs, 45000);
    });
  });
}
