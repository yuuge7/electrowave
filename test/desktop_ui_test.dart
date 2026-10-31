import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:electrowave/core/database/app_database.dart';
import 'package:electrowave/main.dart';
import 'package:electrowave/features/library/views/track_table.dart';
import 'package:electrowave/features/player/providers/queue_provider.dart';
import 'package:electrowave/shared/theme/app_theme.dart';

void main() {
  testWidgets('50,000-track list builds only visible rows', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tracks = List.generate(
      50000,
      (i) => Track(
        id: i,
        filePath: '/$i.flac',
        title: 'Track $i',
        artist: 'Artist',
        album: 'Album',
        durationMs: 60000,
        isDeleted: false,
        isMissing: i == 1,
        rating: 0,
        totalPlayCount: 0,
        isFavorite: false,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(body: TrackTable(tracks: tracks)),
        ),
      ),
    );
    expect(find.text('Track 0'), findsOneWidget);
    expect(find.text('Track 49999'), findsNothing);
    expect(tester.widgetList(find.byType(InkWell)).length, lessThan(200));
    expect(find.byTooltip('File missing'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });

  testWidgets('Ctrl/Shift selection, queue bulk action and removal undo work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    for (var i = 0; i < 4; i++) {
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              filePath: '/$i.wav',
              title: 'Song $i',
              artist: 'Artist',
              album: 'Album',
              durationMs: 1000,
            ),
          );
    }
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          home: Scaffold(
            body: StreamBuilder(
              stream: db.watchLibrary(),
              builder: (context, snapshot) => snapshot.hasData
                  ? TrackTable(tracks: snapshot.data!)
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song 0'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Song 2'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(find.text('2 selected'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Song 3'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Queue'));
    await tester.pump();
    expect(container.read(queueProvider).manualQueue.map((t) => t.title), [
      'Song 0',
      'Song 2',
      'Song 3',
    ]);
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(
      (await tester.runAsync(
        () => db.watchLibrary().first,
      ))!.map((t) => t.title),
      ['Song 1'],
    );
    await tester.tap(find.text('Undo'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect((await tester.runAsync(() => db.watchLibrary().first))!.length, 4);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    container.dispose();
    await tester.runAsync(db.close);
  });
}
