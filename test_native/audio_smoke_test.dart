import 'package:electrowave/features/settings/views/equalizer_dialog.dart';
import 'package:electrowave/features/settings/views/settings_view.dart';
import 'package:electrowave/shared/services/window_state_service.dart';
import 'package:electrowave/features/library/services/tag_writer.dart';
import 'package:electrowave/features/player/providers/session_provider.dart';
import 'package:electrowave/core/session/session_store.dart';
import 'package:electrowave/features/library/services/loudness_scanner.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:electrowave/shared/providers/navigation_provider.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path/path.dart' as p;
import 'package:electrowave/core/app_paths.dart';
import 'package:electrowave/core/database/app_database.dart';
import 'package:electrowave/core/local_log.dart';
import 'package:electrowave/main.dart';
import 'package:electrowave/features/player/providers/player_provider.dart';
import 'package:electrowave/features/player/providers/queue_provider.dart';
import 'package:electrowave/features/player/services/audio_engine.dart';
import 'package:electrowave/features/player/services/scrobbling_service.dart';
import 'package:electrowave/features/settings/providers/settings_provider.dart';
import 'package:electrowave/features/settings/services/settings_persistence.dart';
import '../test/support/audio_fixture.dart';

class RenderOnlyWindow extends WindowStateService {
  @override
  Future<void> restore() async {}
  @override
  Future<void> save() async {}
  @override
  Future<void> setMini(bool value) async {
    mini = value;
  }

  @override
  void dispose() {}
}

class RenderOnlySession extends SessionController {
  RenderOnlySession(super.ref);
  @override
  Future<void> restore() async {}
  @override
  Future<void> flush() async {}
}

class MemorySettings extends SettingsPersistence {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

Future<void> until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Native playback condition timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['ELECTROWAVE_MPV'];
  if (library == null) {
    throw StateError(
      'Set ELECTROWAVE_MPV to the local mpv shared library before running native tests.',
    );
  }
  MediaKit.ensureInitialized(libmpv: library);
  late Directory root;
  late Player player;
  late ProviderContainer container;
  late AppDatabase db;
  late List<Track> tracks;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('electrowave-native-');
    overrideAppDataDirectory(root);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tracks = [];
    for (var i = 0; i < 3; i++) {
      final file = await writeWav(p.join(root.path, '$i.wav'), seconds: 6);
      final id = await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              filePath: file.path,
              title: 'Track $i',
              artist: 'Test',
              album: 'Test',
              durationMs: 6000,
            ),
          );
      tracks.add((await db.trackById(id))!);
    }
    player = Player(configuration: const PlayerConfiguration(muted: true));
    container = ProviderContainer(
      overrides: [
        windowStateServiceProvider.overrideWithValue(RenderOnlyWindow()),
        appVersionProvider.overrideWith((ref) async => 'test'),
        sessionControllerProvider.overrideWith((ref) => RenderOnlySession(ref)),
        databaseProvider.overrideWithValue(db),
        playerProvider.overrideWithValue(player),
        settingsPersistenceProvider.overrideWithValue(MemorySettings()),
      ],
    );
    container.read(playbackControllerProvider);
    container.read(settingsControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  tearDown(() async {
    await player.stop();
    container.dispose();
    await player.dispose();
    await db.close();
    await SessionStore.flush();
    await LocalLog.flush();
    overrideAppDataDirectory(null);
    await root.delete(recursive: true);
  });
  testWidgets(
    'desktop shell renders library, settings, now playing and scaled text',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          if (call.method == 'getBounds') {
            return {'x': 10.0, 'y': 10.0, 'width': 1200.0, 'height': 800.0};
          }
          if (call.method.startsWith('is')) return false;
          return null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('electrowave/media'),
        (_) async => null,
      );
      await tester.runAsync(() async {
        final font = File(
          Platform.isWindows
              ? 'C:/Windows/Fonts/segoeui.ttf'
              : '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        );
        if (await font.exists()) {
          final bytes = await font.readAsBytes();
          for (final name in ['Roboto', 'Segoe UI']) {
            await (FontLoader(
              name,
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          }
        }
        final icon = File(
          'C:/Flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        );
        if (await icon.exists()) {
          await (FontLoader('MaterialIcons')..addFont(
                Future.value(ByteData.sublistView(await icon.readAsBytes())),
              ))
              .load();
        }
      });
      container.read(currentTrackProvider.notifier).setTrack(tracks.first);
      container.read(queueProvider.notifier).setContext(tracks, 0);
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: key, child: const ElectrowaveApp()),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), null);
      Future<void> capture(String name) async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final file = File(p.join('build', 'verification', name));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      }

      await tester.runAsync(() => capture('library.png'));
      container.read(navIndexProvider.notifier).set(3);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => capture('settings.png'));
      await tester.tap(find.byTooltip('Now playing'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(tester.takeException(), null);
      await tester.runAsync(() => capture('now-playing.png'));
      await tester.tap(find.byTooltip('Now playing'));
      await tester.pump(const Duration(milliseconds: 200));
      container.read(navIndexProvider.notifier).set(1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), null);
      await tester.runAsync(() => capture('playlists.png'));
      container.read(navIndexProvider.notifier).set(3);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Equalizer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(EqualizerDialog), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.runAsync(() => capture('equalizer.png'));
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Mini player'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      tester.view.physicalSize = const Size(460, 200);
      await tester.pump();
      expect(tester.takeException(), null);
      await tester.runAsync(() => capture('mini-player.png'));
      tester.view.physicalSize = const Size(1200, 800);
      await tester.tap(find.byTooltip('Return to full player'));
      await tester.pump(const Duration(milliseconds: 200));
      await container
          .read(settingsControllerProvider.notifier)
          .setTextScale(1.6);
      tester.view.physicalSize = const Size(960, 640);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), null);
      await tester.runAsync(() => capture('settings-large-text.png'));
      // Exercise the supported minimum window, including the queue restored
      // from a previous session, rather than only a wide desktop canvas.
      await container.read(settingsControllerProvider.notifier).setTextScale(1);
      container.read(navIndexProvider.notifier).set(0);
      tester.view.physicalSize = const Size(720, 520);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => capture('library-minimum.png'));
      expect(tester.takeException(), null);
      container.read(queuePanelVisibleProvider.notifier).set(true);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => capture('library-minimum-queue.png'));
      expect(tester.takeException(), null);
      container.read(queuePanelVisibleProvider.notifier).set(false);
      await tester.pump();
      await tester.tap(find.byTooltip('Player options'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Now playing'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.settings).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SettingsView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('electrowave/media'),
        null,
      );
    },
  );

  test(
    'ffmpeg loudness scanner measures local audio and saves normalization gain',
    () async {
      final executable = Platform.environment['ELECTROWAVE_FFMPEG'];
      if (executable == null) {
        throw StateError(
          'Set ELECTROWAVE_FFMPEG to run the native loudness test',
        );
      }
      await writeWav(tracks.first.filePath, seconds: 3, tone: true);
      final progress = <int>[];
      final count = await LoudnessScanner(
        db,
        executable: executable,
      ).scan([tracks.first], (done, total) => progress.add(done));
      expect(count, 1);
      expect(progress, [1]);
      final gain = (await db.trackById(tracks.first.id))!.replayGainDb;
      expect(gain, isNotNull);
      expect(gain!.isFinite, true);
      final engine = container.read(audioEngineProvider);
      await engine.applyAudioSettings(
        const AppSettings(replayGain: ReplayGainMode.track),
      );
      await engine.setTrackGain(gain);
      expect(
        double.parse(
          await (player.platform as NativePlayer).getProperty(
            'replaygain-fallback',
          ),
        ),
        closeTo(gain, 0.01),
      );
    },
  );

  test(
    'MP3 tag edits preserve playable audio and do not accumulate duplicate headers',
    () async {
      final executable = Platform.environment['ELECTROWAVE_FFMPEG']!;
      await writeWav(tracks.first.filePath, seconds: 3, tone: true);
      final mp3 = p.join(root.path, 'roundtrip.mp3');
      final result = await Process.run(executable, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-i',
        tracks.first.filePath,
        '-codec:a',
        'libmp3lame',
        '-ar',
        '44100',
        '-ac',
        '2',
        mp3,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      writeTags(
        mp3,
        const TagEdit(
          title: 'Roundtrip',
          albumArtist: 'Test artist',
          rating: 4,
        ),
      );
      final length = await File(mp3).length();
      writeTags(
        mp3,
        const TagEdit(
          title: 'Roundtrip',
          albumArtist: 'Test artist',
          rating: 5,
        ),
      );
      expect(await File(mp3).length(), length);
      await player.open(Media(mp3));
      await until(() => player.state.position.inMilliseconds > 300);
      expect(player.state.duration.inMilliseconds, greaterThan(2500));
      // Start with a legacy saved EQ enabled, the case missed by the old
      // test that merely read the uninitialized graph back from mpv.
      final engine = container.read(audioEngineProvider);
      await engine.applyAudioSettings(
        AppSettings.fromJson({
          'eqEnabled': true,
          'eqGainsDb': [6, 2, -2, 2, 5],
        }),
      );
      final errors = <String>[];
      final sub = player.stream.error.listen(errors.add);
      await player.open(Media(mp3));
      await until(() => player.state.position.inMilliseconds > 1200);
      expect(player.state.playlist.medias.single.uri, Media(mp3).uri);
      expect(player.state.audioParams.sampleRate, greaterThan(0));
      expect(errors, isEmpty);
      for (final preset in kEqPresets.values) {
        await engine.applyAudioSettings(
          AppSettings(eqEnabled: true, eqGainsDb: preset),
        );
        await player.open(Media(mp3));
        await until(() => player.state.position.inMilliseconds > 400);
        expect(player.state.audioParams.sampleRate, greaterThan(0));
        expect(errors, isEmpty);
      }
      await sub.cancel();
    },
  );

  test(
    'native playlist preloads, advances once, respects manual queue and keeps playing',
    () async {
      final controller = container.read(playbackControllerProvider);
      controller.playFromContext(tracks, 0);
      await until(
        () =>
            player.state.playlist.medias.length == 2 &&
            player.state.position.inMilliseconds > 200,
      );
      expect(
        player.state.playlist.medias[1].uri,
        Media(tracks[1].filePath).uri,
      );
      container.read(queueProvider.notifier).playNext(tracks[2]);
      await until(
        () =>
            player.state.playlist.medias.length == 2 &&
            player.state.playlist.medias[1].uri ==
                Media(tracks[2].filePath).uri,
      );
      await player.seek(const Duration(milliseconds: 5400));
      await until(
        () => container.read(currentTrackProvider)?.id == tracks[2].id,
      );
      await until(() => player.state.position.inMilliseconds > 300);
      expect(container.read(queueProvider).manualQueue, isEmpty);
      expect(player.state.playing, true);
      expect(container.read(queueProvider).contextIndex, 0);
      await player.seek(const Duration(milliseconds: 5400));
      await until(
        () => container.read(currentTrackProvider)?.id == tracks[1].id,
      );
      expect(container.read(queueProvider).contextIndex, 1);
    },
  );
  test(
    'Play at the end restarts the displayed song after gapless transitions',
    () async {
      final controller = container.read(playbackControllerProvider);
      controller.playFromContext(tracks, 0);
      await until(() => player.state.position.inMilliseconds > 200);
      for (var i = 1; i < tracks.length; i++) {
        await player.seek(const Duration(milliseconds: 5500));
        await until(
          () => container.read(currentTrackProvider)?.id == tracks[i].id,
        );
        await until(
          () =>
              player.state.position.inMilliseconds > 200 &&
              player.state.position.inMilliseconds < 2000,
        );
      }
      await player.seek(const Duration(milliseconds: 5500));
      await until(() => player.state.completed);
      await controller.togglePlayback();
      await until(
        () =>
            player.state.position.inMilliseconds > 300 &&
            player.state.position.inMilliseconds < 2000,
      );
      expect(container.read(currentTrackProvider)?.id, tracks.last.id);
      expect(
        player.state.playlist.medias[player.state.playlist.index].uri,
        Media(tracks.last.filePath).uri,
      );
      expect(player.state.playing, true);
    },
  );
  test('real MP3 with saved EQ keeps playing instead of skipping', () async {
    final sample = Platform.environment['ELECTROWAVE_AUDIO_SAMPLE'];
    if (sample == null) return;
    final settingsPath = Platform.environment['ELECTROWAVE_SETTINGS_SAMPLE'];
    final settings = settingsPath == null
        ? const AppSettings()
        : AppSettings.fromJson(
            jsonDecode(await File(settingsPath).readAsString()),
          );
    await container.read(audioEngineProvider).applyAudioSettings(settings);
    final actual = tracks.first.copyWith(filePath: sample, durationMs: 180000);
    final errors = <String>[];
    final subscription = player.stream.error.listen(errors.add);
    container.read(playbackControllerProvider).playFromContext([
      actual,
      ...tracks.skip(1),
    ], 0);
    try {
      await until(() => player.state.position.inMilliseconds > 2500);
    } finally {
      await subscription.cancel();
    }
    expect(container.read(currentTrackProvider)?.id, actual.id);
    expect(player.state.playing, true);
    expect(
      player.state.playlist.medias[player.state.playlist.index].uri,
      Media(sample).uri,
    );
    expect(errors, isEmpty);
  }, skip: Platform.environment['ELECTROWAVE_AUDIO_SAMPLE'] == null);
  test(
    'rapid opens and preloading always settle on the final requested track',
    () async {
      final controller = container.read(playbackControllerProvider);
      for (var turn = 0; turn < 6; turn++) {
        final finalIndex = turn % tracks.length;
        controller.playFromContext(tracks, (finalIndex + 1) % tracks.length);
        container
            .read(queueProvider.notifier)
            .playNext(tracks[(finalIndex + 2) % tracks.length]);
        controller.playFromContext(tracks, finalIndex);
        await until(
          () =>
              player.state.position.inMilliseconds > 200 &&
              player.state.playlist.medias[player.state.playlist.index].uri ==
                  Media(tracks[finalIndex].filePath).uri,
        );
        expect(container.read(currentTrackProvider)?.id, tracks[finalIndex].id);
        expect(container.read(queueProvider).contextIndex, finalIndex);
        await player.pause();
      }
    },
  );
  test(
    'ten-band EQ with preamp and speed is accepted by mpv and audio advances',
    () async {
      final controller = container.read(playbackControllerProvider);
      controller.playFromContext(tracks, 0);
      await until(() => player.state.position.inMilliseconds > 200);
      final engine = container.read(audioEngineProvider);
      await engine.applyAudioSettings(
        const AppSettings(
          eqEnabled: true,
          eqGainsDb: [4, 3, 2, 1, 0, -1, -2, 1, 2, 3],
          eqPreampDb: -3,
        ),
      );
      await engine.setRate(1.25);
      final native = player.platform as NativePlayer;
      final chain = await native.getProperty('af');
      expect(chain, contains('equalizer'));
      expect(chain, isNot(contains('volume=')));
      final gain =
          double.tryParse(await native.getProperty('volume-gain')) ??
          double.parse(await native.getProperty('replaygain-fallback'));
      expect(gain, closeTo(-7, 0.01));
      expect(chain, contains('scaletempo2'));
      final position = player.state.position;
      await until(
        () =>
            player.state.position >
            position + const Duration(milliseconds: 300),
      );
      expect(player.state.rate, 1.25);
      expect(container.read(currentTrackProvider)?.id, tracks.first.id);
      await native.setProperty('audio-exclusive', 'no');
      await native.setProperty('audio-device', 'auto');
    },
  );
  test(
    'optional crossfade changes track early, restores volume and keeps preloading',
    () async {
      final controller = container.read(playbackControllerProvider);
      container.read(scrobblingServiceProvider);
      await container.read(settingsControllerProvider.notifier).setCrossfade(1);
      await player.setVolume(40);
      controller.playFromContext(tracks, 0);
      await until(
        () =>
            player.state.playlist.medias.length == 2 &&
            player.state.position.inMilliseconds > 200,
      );
      await player.seek(const Duration(milliseconds: 5100));
      await until(
        () => container.read(currentTrackProvider)?.id == tracks[1].id,
      );
      await until(
        () =>
            player.state.volume >= 39 &&
            player.state.playlist.medias.length >= 2,
      );
      expect(player.state.playing, true);
      expect(container.read(queueProvider).contextIndex, 1);
    },
  );
}
