import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:electrowave/core/database/app_database.dart';

Future<int> _insertTrack(
  AppDatabase db,
  String title, {
  int durationMs = 200000,
  bool deleted = false,
}) {
  return db
      .into(db.tracks)
      .insert(
        TracksCompanion.insert(
          filePath: 'C:/music/$title.mp3',
          title: title,
          artist: 'Artist',
          album: 'Album',
          durationMs: durationMs,
          isDeleted: Value(deleted),
        ),
      );
}

Future<void> _play(AppDatabase db, int trackId, DateTime at) => db
    .into(db.playbackHistory)
    .insert(PlaybackHistoryCompanion.insert(trackId: trackId, playedAt: at));

Future<void> _listen(AppDatabase db, int trackId, DateTime at, int ms) => db
    .into(db.listeningSessions)
    .insert(
      ListeningSessionsCompanion(
        trackId: Value(trackId),
        startedAt: Value(at),
        listenedMs: Value(ms),
      ),
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  final march = DateTime(2026, 3, 10, 12);
  final may = DateTime(2026, 5, 2, 8);
  final mayLater = DateTime(2026, 5, 20, 21, 30);

  Future<void> seed(int songA) async {
    await _play(db, songA, march);
    await _play(db, songA, may);
    await _play(db, songA, mayLater);
    // Heard in full, then abandoned after 20 s of a 200 s song.
    await _listen(db, songA, march, 200000);
    await _listen(db, songA, may, 20000);
    await _listen(db, songA, mayLater, 150000);
  }

  test('lists every live track, with zeros for unplayed ones', () async {
    final songA = await _insertTrack(db, 'A');
    final songB = await _insertTrack(db, 'B');
    final removed = await _insertTrack(db, 'Gone', deleted: true);
    await seed(songA);
    await _play(db, removed, may);

    final stats = await db.watchSongStats().first;
    final byId = {for (final s in stats) s.track.id: s};

    expect(byId.keys, unorderedEquals([songA, songB]));

    final a = byId[songA]!;
    expect(a.plays, 3);
    expect(a.listenedMs, 370000);
    expect(a.starts, 3);
    expect(a.skips, 1);
    expect(a.firstPlayed, march);
    expect(a.lastPlayed, mayLater);

    final b = byId[songB]!;
    expect(b.plays, 0);
    expect(b.listenedMs, 0);
    expect(b.starts, 0);
    expect(b.skips, 0);
    expect(b.firstPlayed, isNull);
    expect(b.lastPlayed, isNull);
  });

  test('limits every number to the half-open date range', () async {
    final songA = await _insertTrack(db, 'A');
    await seed(songA);

    final stats = await db
        .watchSongStats(from: DateTime(2026, 5), to: DateTime(2026, 6))
        .first;
    final a = stats.single;

    expect(a.plays, 2);
    expect(a.listenedMs, 170000);
    expect(a.starts, 2);
    expect(a.skips, 1);
    expect(a.firstPlayed, may);
    expect(a.lastPlayed, mayLater);

    final empty = await db.watchSongStats(from: DateTime(2026, 6)).first;
    expect(empty.single.plays, 0);
    expect(empty.single.listenedMs, 0);
  });

  test('per-track history comes back oldest first', () async {
    final songA = await _insertTrack(db, 'A');
    await _play(db, songA, mayLater);
    await _play(db, songA, march);
    await _listen(db, songA, may, 5000);

    expect(await db.watchPlayTimes(songA).first, [march, mayLater]);
    final sessions = await db.watchListeningSessionsFor(songA).first;
    expect(sessions.single.listenedMs, 5000);
  });
}
