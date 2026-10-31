import 'dart:io';
import 'dart:ui' as ui;

import 'package:electrowave/core/app_paths.dart';
import 'package:electrowave/core/database/app_database.dart';
import 'package:electrowave/core/session/session_snapshot.dart';
import 'package:electrowave/core/session/session_store.dart';
import 'package:electrowave/features/library/providers/scan_provider.dart';
import 'package:electrowave/features/player/providers/player_provider.dart';
import 'package:electrowave/features/player/providers/queue_provider.dart';
import 'package:electrowave/features/player/providers/session_provider.dart';
import 'package:electrowave/features/playlists/providers/playlists_provider.dart';
import 'package:electrowave/features/settings/providers/settings_provider.dart';
import 'package:electrowave/features/settings/providers/wrapped_stats_provider.dart';
import 'package:electrowave/main.dart';
import 'package:electrowave/shared/providers/navigation_provider.dart';
import 'package:electrowave/shared/services/window_state_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../test/support/audio_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real desktop startup, playback, navigation, resizing and restore',
    (tester) async {
      await windowManager.ensureInitialized();
      MediaKit.ensureInitialized();
      final root = await Directory.systemTemp.createTemp(
        'electrowave-desktop-qa-',
      );
      overrideAppDataDirectory(root);
      final source = Platform.environment['ELECTROWAVE_REPRO_DATABASE'];
      if (source != null) {
        await File(source).copy(p.join(root.path, databaseFileName));
      }
      final settings = Platform.environment['ELECTROWAVE_SETTINGS_SAMPLE'];
      if (settings != null) {
        await File(settings).copy(p.join(root.path, 'settings.json'));
      }
      final database = AppDatabase();
      if (source == null) {
        for (var i = 0; i < 4; i++) {
          final file = await writeWav(
            p.join(root.path, '$i.wav'),
            seconds: 30,
            tone: true,
          );
          await database
              .into(database.tracks)
              .insert(
                TracksCompanion.insert(
                  filePath: file.path,
                  title: 'Desktop track $i',
                  artist: 'Desktop test',
                  album: 'Test album',
                  durationMs: 30000,
                ),
              );
        }
      }
      final tracks = await database.watchLibrary().first;
      expect(tracks.length, greaterThanOrEqualTo(3));
      await database.recordPlay(tracks.first.id);
      await database.saveListenedMs(
        await database.startListeningSession(tracks.first.id),
        120000,
      );
      final playlistId = await database.createPlaylist('Desktop QA playlist');
      await database.addTracksToPlaylist(
        playlistId,
        tracks.take(4).map((t) => t.id).toList(),
      );
      await SessionStore.save(
        SessionSnapshot(
          currentTrackId: tracks.first.id,
          contextTrackIds: tracks.map((t) => t.id).toList(),
          contextIndex: 0,
          positionMs: 1000,
        ),
      );
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      final boundaryKey = GlobalKey();
      final output = Directory(
        Platform.environment['ELECTROWAVE_QA_OUTPUT'] ??
            p.join(root.path, 'screenshots'),
      );
      await output.create(recursive: true);
      Future<void> capture(String name) async {
        await tester.pump();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final picture = await boundary.toImage();
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        picture.dispose();
        await File(
          p.join(output.path, '$name.png'),
        ).writeAsBytes(bytes!.buffer.asUint8List());
      }

      Future<void> waitFor(bool Function() predicate, String reason) async {
        for (var i = 0; i < 150 && !predicate(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(predicate(), true, reason: reason);
      }

      await windowManager.setSize(const Size(1280, 800));
      await windowManager.show();
      await windowManager.focus();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundaryKey,
            child: const ElectrowaveApp(),
          ),
        ),
      );
      await waitFor(
        () =>
            container.read(currentTrackProvider) != null &&
            !container.read(scanProvider).running,
        'Session and library finish loading',
      );
      final player = container.read(playerProvider);
      expect(player.state.playing, false);
      await capture('native-startup');
      await tester.tap(find.byTooltip('Play').last);
      await waitFor(
        () => player.state.position.inMilliseconds > 2500,
        'Clicking Play produces advancing audio',
      );
      expect(container.read(currentTrackProvider)?.id, tracks.first.id);
      expect(player.state.playing, true);
      final native = player.platform as NativePlayer;
      final outputDriver = await native.getProperty('current-ao');
      debugPrint('Desktop audio output: $outputDriver');
      expect(
        outputDriver,
        isNot(anyOf('', 'null')),
        reason: 'A real audio device is active',
      );
      await capture('native-playing');
      await tester.tap(find.byTooltip('Pause').last);
      await tester.pump(const Duration(milliseconds: 300));
      final stoppedAt = player.state.position;
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        (player.state.position - stoppedAt).inMilliseconds.abs(),
        lessThan(250),
      );
      await tester.tap(find.text(tracks[1].title).first);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text(tracks[1].title).first);
      await waitFor(
        () =>
            container.read(currentTrackProvider)?.id == tracks[1].id &&
            player.state.position.inMilliseconds > 500,
        'Double-clicking a cover row plays that song',
      );
      await player.pause();
      await tester.tap(find.byTooltip('Track actions').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Edit tags...'), findsOneWidget);
      expect(find.text('More actions...'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));

      // A burst of clicks must resolve to the last selection, with metadata and
      // native audio describing the same track.
      final playback = container.read(playbackControllerProvider);
      for (var i = 0; i < 3; i++) {
        playback.playFromContext(tracks, i);
      }
      await waitFor(
        () =>
            player.state.playing && player.state.position.inMilliseconds > 700,
        'Rapid track changes settle and play',
      );
      expect(container.read(currentTrackProvider)?.id, tracks[2].id);
      expect(
        player.state.playlist.medias[player.state.playlist.index].uri,
        Media(tracks[2].filePath).uri,
      );
      await player.pause();

      await tester.tap(find.byTooltip('Now playing'));
      await tester.pump(const Duration(milliseconds: 500));
      await capture('native-now-playing');
      await tester.tap(find.text('Settings').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Equalizer'), findsOneWidget);
      await capture('native-settings');
      await tester.tap(find.text('Library').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'a b');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        player.state.playing,
        false,
        reason: 'Typing spaces must not play music',
      );
      await tester.tap(find.text('Settings').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Library').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        contains('a b'),
      );
      await tester.enterText(find.byType(TextField).first, '');

      await windowManager.setSize(const Size(720, 560));
      await tester.pump(const Duration(milliseconds: 700));
      await capture('native-small-library');
      await tester.tap(find.byTooltip('Player options'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await capture('native-small-options');
      await tester.tap(find.text('Now playing'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.library_music).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.byTooltip('Show queue'));
      await tester.pump(const Duration(milliseconds: 500));
      await capture('native-small-queue');
      container.read(queuePanelVisibleProvider.notifier).set(false);
      container.read(navIndexProvider.notifier).set(1);
      container.read(selectedPlaylistIdProvider.notifier).select(playlistId);
      await waitFor(
        () => container.read(playlistTracksProvider(playlistId)).hasValue,
        'Selected playlist loads its tracks',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await capture('native-small-playlists');
      expect(find.text('All playlists'), findsNothing);
      expect(find.byTooltip('All playlists'), findsOneWidget);
      container.read(navIndexProvider.notifier).set(2);
      await waitFor(
        () => container.read(wrappedStatsProvider).hasValue,
        'Stats finish loading actual listening history',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await capture('native-small-stats');
      container.read(navIndexProvider.notifier).set(3);
      await container
          .read(settingsControllerProvider.notifier)
          .setTextScale(1.6);
      await tester.pump(const Duration(milliseconds: 500));
      await capture('native-small-large-text');
      for (final tab in [0, 1, 2]) {
        container.read(navIndexProvider.notifier).set(tab);
        await tester.pump(const Duration(milliseconds: 400));
        await capture('native-large-text-tab-$tab');
      }
      container.read(navIndexProvider.notifier).set(3);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(
        find.text('Desktop & library'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(Scaffold).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await capture('native-small-audio-settings');
      await container.read(settingsControllerProvider.notifier).setTextScale(1);
      await windowManager.setSize(const Size(1280, 800));
      await tester.pump(const Duration(milliseconds: 500));
      await windowManager.maximize();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Mini player'));
      await tester.pump(const Duration(seconds: 1));
      await capture('native-mini');
      await tester.tap(find.byTooltip('Return to full player'));
      await tester.pump(const Duration(seconds: 1));
      expect((await windowManager.getSize()).width, greaterThan(1000));
      expect(await windowManager.isMaximized(), true);
      await windowManager.unmaximize();
      await container.read(sessionControllerProvider).flush();
      await container.read(windowStateServiceProvider).save();
      expect((await SessionStore.load())?.currentTrackId, tracks[2].id);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await player.stop();
      container.dispose();
      await database.close();
      // Recreate the app and services against the files actually written by
      // the first run, rather than only checking the serialized JSON.
      final reopenedDatabase = AppDatabase();
      final reopened = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(reopenedDatabase)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: reopened,
          child: const ElectrowaveApp(),
        ),
      );
      await waitFor(
        () =>
            reopened.read(currentTrackProvider)?.id == tracks[2].id &&
            reopened.read(playerProvider).state.playlist.medias.isNotEmpty,
        'Saved track is restored after restarting the app',
      );
      expect(reopened.read(playerProvider).state.playing, false);
      expect(reopened.read(queueProvider).contextIndex, 2);
      expect(reopened.read(selectedPlaylistIdProvider), playlistId);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await reopened.read(playerProvider).stop();
      reopened.dispose();
      await reopenedDatabase.close();
      overrideAppDataDirectory(null);
    },
  );
}
