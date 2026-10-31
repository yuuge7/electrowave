import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:electrowave/core/database/app_database.dart';
import 'package:electrowave/features/settings/providers/wrapped_stats_provider.dart';
import 'package:electrowave/features/stats/views/song_stats_table.dart';
import 'package:electrowave/main.dart';
import 'package:electrowave/shared/theme/app_theme.dart';

void main() {
  testWidgets('songs table sorts and opens a song without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1, 12);

    final often = await db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            filePath: 'C:/music/often.mp3',
            title: 'Played Often',
            artist: 'Band',
            album: 'Record',
            durationMs: 180000,
            dateAdded: Value(DateTime(2025, 1, 1)),
          ),
        );
    await db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            filePath: 'C:/music/never.mp3',
            title: 'Never Played',
            artist: 'Other Band',
            album: 'Other Record',
            durationMs: 240000,
          ),
        );
    for (var i = 0; i < 4; i++) {
      await db
          .into(db.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              trackId: often,
              playedAt: thisMonth.add(Duration(hours: i)),
            ),
          );
    }
    await db
        .into(db.listeningSessions)
        .insert(
          ListeningSessionsCompanion(
            trackId: Value(often),
            startedAt: Value(thisMonth),
            listenedMs: const Value(500000),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          home: const Scaffold(body: SongStatsTable()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Default order is most played first.
    final oftenTop = tester.getTopLeft(find.text('Played Often')).dy;
    final neverTop = tester.getTopLeft(find.text('Never Played')).dy;
    expect(oftenTop, lessThan(neverTop));
    expect(find.text('1 of 2 songs played · All time'), findsOneWidget);

    // Title header sorts A→Z.
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Never Played')).dy,
      lessThan(tester.getTopLeft(find.text('Played Often')).dy),
    );

    // A month filter shows both the period and the all-time sections.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SongStatsTable)),
    );
    container.read(statsStateProvider.notifier).setFilter(StatsFilter.monthly);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Played Often'));
    await tester.pumpAndSettle();
    expect(find.text('All time'), findsOneWidget);
    expect(find.text('Plays per month'), findsOneWidget);
    expect(find.text('8m 20s'), findsWidgets);

    // Unmount first so drift's stream queries are cancelled, then close the
    // database on the real event loop: closing inside the fake-async zone
    // never completes.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
