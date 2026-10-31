import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;
import 'package:electrowave/core/app_paths.dart';
import 'package:electrowave/core/local_log.dart';
import 'package:electrowave/features/library/services/extra_tags.dart';
import 'package:electrowave/features/library/services/tag_writer.dart';
import 'package:electrowave/features/player/services/metadata_scanner.dart';
import 'package:electrowave/features/settings/services/settings_persistence.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('electrowave-storage-test-');
    overrideAppDataDirectory(root);
  });
  tearDown(() async {
    await LocalLog.flush();
    overrideAppDataDirectory(null);
    await root.delete(recursive: true);
  });

  test(
    'legacy data migration copies database WAL settings and covers once and retains originals',
    () async {
      final docs = await Directory(p.join(root.path, 'Documents')).create();
      final old = await Directory(p.join(docs.path, 'Electrowave')).create();
      await File(
        p.join(old.path, 'local_player_db.sqlite'),
      ).writeAsString('database');
      await File(
        p.join(old.path, 'local_player_db.sqlite-wal'),
      ).writeAsString('wal');
      await File(p.join(old.path, 'settings.json')).writeAsString('{}');
      final covers = await Directory(
        p.join(docs.path, '.local_player_covers'),
      ).create();
      await File(p.join(covers.path, 'cover.jpg')).writeAsBytes([1, 2, 3]);
      final target = await Directory(p.join(root.path, 'support')).create();
      await migrateLegacyData(docs, target);
      expect(
        await File(p.join(target.path, databaseFileName)).readAsString(),
        'database',
      );
      expect(
        await File(p.join(target.path, '$databaseFileName-wal')).readAsString(),
        'wal',
      );
      expect(
        await File(p.join(target.path, 'covers', 'cover.jpg')).readAsBytes(),
        [1, 2, 3],
      );
      await File(p.join(old.path, 'settings.json')).writeAsString('changed');
      await migrateLegacyData(docs, target);
      expect(
        await File(p.join(target.path, 'settings.json')).readAsString(),
        '{}',
      );
      expect(
        await File(p.join(old.path, 'local_player_db.sqlite')).exists(),
        true,
      );
    },
  );

  test(
    'settings writes serialize and old five-band EQ migrates without losing the curve',
    () async {
      final persistence = SettingsPersistence();
      final writes = [
        for (var i = 0; i < 20; i++)
          persistence.save(AppSettings(textScale: 1 + i / 100)),
      ];
      await Future.wait(writes);
      expect((await persistence.load()).textScale, 1.19);
      final old = AppSettings.fromJson({
        'eqGainsDb': [3, -2, 1, 4, 0],
      });
      expect(old.eqGainsDb, [3, 3, -2, -2, 1, 1, 4, 4, 0, 0]);
      final current = AppSettings(
        backupFolder: '/backup',
        libraryFolders: ['/music'],
        eqUserPresets: {'Mine': List.filled(10, 2.0)},
        crossfadeSeconds: 2,
        eqPreampDb: -3,
      );
      final restored = AppSettings.fromJson(current.toJson());
      expect(restored.eqUserPresets, current.eqUserPresets);
      expect(restored.backupFolder, '/backup');
      expect(restored.crossfadeSeconds, 2);
    },
  );

  test('logs rotate locally and keep a bounded set', () async {
    final directory = await LocalLog.directory();
    final file = File(p.join(directory.path, 'electrowave.log'));
    for (var i = 0; i < 6; i++) {
      await file.writeAsString('x' * (1024 * 1024 + 1));
      LocalLog.write('error $i');
      await LocalLog.flush();
    }
    expect((await directory.list().toList()).length, 4);
    expect(await file.readAsString(), contains('error 5'));
  });

  test(
    'MP3 ratings write interoperable POPM and album artist tags and are read back',
    () async {
      final file = File(p.join(root.path, 'tagged.mp3'));
      await file.writeAsBytes([73, 68, 51, 4, 0, 0, 0, 0, 0, 0]);
      writeTags(
        file.path,
        const TagEdit(
          title: 'Intro',
          artist: 'Guest',
          album: 'Compilation',
          albumArtist: 'Various artists',
          rating: 4,
        ),
      );
      final metadata = readAllMetadata(file, getImage: false) as Mp3Metadata;
      expect(readId3Rating(file), 196);
      expect(metadata.bandOrOrchestra, 'Various artists');
      final parsed = parseTags(file.path, withImage: false);
      expect(parsed.rating, 4);
      expect(parsed.albumArtist, 'Various artists');
    },
  );

  test(
    'MP4 identity keeps guest artist separate from album artist without loading audio',
    () async {
      Uint8List atom(String name, List<int> payload) {
        final bytes = Uint8List(payload.length + 8);
        final data = ByteData.sublistView(bytes);
        data.setUint32(0, bytes.length);
        bytes.setRange(4, 8, latin1.encode(name));
        bytes.setRange(8, bytes.length, payload);
        return bytes;
      }

      List<int> value(String text) =>
          atom('data', [0, 0, 0, 1, 0, 0, 0, 0, ...utf8.encode(text)]);
      final metadata = atom(
        'moov',
        atom(
          'udta',
          atom('meta', [
            0,
            0,
            0,
            0,
            ...atom('ilst', [
              ...atom('aART', value('Album artist')),
              ...atom('\u00a9ART', value('Guest singer')),
            ]),
          ]),
        ),
      );
      final file = File(p.join(root.path, 'identity.m4a'));
      await file.writeAsBytes(metadata);
      final result = readMp4Identity(file);
      expect(result['aART'], 'Album artist');
      expect(result['\u00a9ART'], 'Guest singer');
    },
  );
}
