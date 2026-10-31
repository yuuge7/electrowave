import '../../../core/app_paths.dart';
import 'extra_tags.dart';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart' as db;
import '../../../main.dart';

/// Edited tag values. A null field means "leave this tag alone".
class TagEdit {
  const TagEdit({
    this.albumArtist,
    this.rating,
    this.coverImagePath,
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.trackNumber,
    this.discNumber,
    this.year,
  });

  final String? albumArtist;
  final int? rating;
  final String? coverImagePath;
  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
}

/// Runs in a worker isolate: writing tags rewrites the file header and can
/// block for a noticeable moment on large files.
void writeTags(String path, TagEdit edit) {
  final current = readAllMetadata(File(path), getImage: false);
  if (current is Mp3Metadata) {
    final image = edit.coverImagePath == null
        ? null
        : File(edit.coverImagePath!).readAsBytesSync();
    writeId3Tags(
      path,
      textFrames: {
        if (edit.title != null) 'TIT2': edit.title!,
        if (edit.artist != null) 'TPE1': edit.artist!,
        if (edit.album != null) 'TALB': edit.album!,
        if (edit.albumArtist != null) 'TPE2': edit.albumArtist!,
        if (edit.genre != null) 'TCON': edit.genre!,
        if (edit.trackNumber != null) 'TRCK': '${edit.trackNumber}',
        if (edit.discNumber != null) 'TPOS': '${edit.discNumber}',
        if (edit.year != null) 'TDRC': '${edit.year}',
      },
      rating: edit.rating,
      artwork: image,
      mime: edit.coverImagePath?.toLowerCase().endsWith('.png') == true
          ? 'image/png'
          : 'image/jpeg',
    );
    return;
  }
  updateMetadata(File(path), (metadata) {
    if (edit.albumArtist != null || edit.rating != null) {
      switch (metadata) {
        case VorbisMetadata m:
          if (edit.albumArtist != null) {
            m.unknowns['ALBUMARTIST'] = edit.albumArtist!;
          }
          if (edit.rating != null) {
            m.unknowns['RATING'] = '${edit.rating! * 20}';
          }
        case ApeMetadata m:
          if (edit.albumArtist != null) m.albumArtist = edit.albumArtist;
          if (edit.rating != null) {
            throw UnsupportedError(
              'Rating tags are not supported for this format',
            );
          }
        default:
          throw UnsupportedError(
            'Album artist and rating tags are not supported for this format',
          );
      }
    }
    if (edit.coverImagePath != null) {
      final file = File(edit.coverImagePath!);
      metadata.setPictures([
        Picture(
          file.readAsBytesSync(),
          p.extension(file.path).toLowerCase() == '.png'
              ? 'image/png'
              : 'image/jpeg',
          PictureType.coverFront,
        ),
      ]);
    }
    if (edit.title != null) metadata.setTitle(edit.title);
    if (edit.artist != null) metadata.setArtist(edit.artist);
    if (edit.album != null) metadata.setAlbum(edit.album);
    if (edit.genre != null) metadata.setGenres([edit.genre!]);
    if (edit.trackNumber != null) metadata.setTrackNumber(edit.trackNumber);
    if (edit.discNumber != null) metadata.setCD(edit.discNumber, null);
    if (edit.year != null) metadata.setYear(DateTime(edit.year!));
  });
}

/// Applies tag edits to the audio file and the library row.
///
/// The library is always updated, even when the file write fails (read-only
/// storage, an unsupported container, a format the writer can't round-trip) —
/// otherwise a failed write would leave the user with no way to fix bad tags.
class TagWriter {
  TagWriter(this.database);

  final db.AppDatabase database;

  /// Returns null on full success, or a message describing why the file itself
  /// could not be updated while the library was.
  Future<String?> apply(db.Track track, TagEdit edit) async {
    String? fileError;
    String? libraryCover;
    if (edit.coverImagePath != null) {
      final image = File(edit.coverImagePath!);
      final stat = await image.stat();
      final folder = await Directory(
        p.join((await appDataDirectory()).path, 'covers'),
      ).create(recursive: true);
      final name =
          'custom_${image.path.hashCode.abs()}_${stat.modified.millisecondsSinceEpoch}_${stat.size}${p.extension(image.path)}';
      final target = File(p.join(folder.path, name));
      if (!await target.exists()) await image.copy(target.path);
      libraryCover = target.path;
    }

    // The writers cover mp3, mp4/m4a, flac and wav. An .ogg goes down none of
    // those branches and writeMetadata returns without touching the file or
    // throwing, so it has to be caught here — otherwise the edit would look
    // like it stuck and be undone by the next rescan.
    if (!{
      '.mp3',
      '.flac',
      '.m4a',
      '.mp4',
      '.wav',
      '.ape',
    }.contains(p.extension(track.filePath).toLowerCase())) {
      fileError =
          'Library updated, but Ogg files cannot have their tags '
          'rewritten — a rescan will restore the file\'s own tags.';
    } else {
      try {
        final path = track.filePath;
        await Isolate.run(() {
          final temp = File('$path.ewtag');
          try {
            File(path).copySync(temp.path);
            writeTags(temp.path, edit);
            temp.renameSync(path);
          } finally {
            if (temp.existsSync()) temp.deleteSync();
          }
        });
      } catch (e) {
        fileError =
            'Library updated, but the file tags could not be written '
            '(${e.runtimeType})';
      }
    }

    await database.updateTrackTags(
      track.id,
      title: edit.title == null ? const Value.absent() : Value(edit.title!),
      artist: edit.artist == null ? const Value.absent() : Value(edit.artist!),
      album: edit.album == null ? const Value.absent() : Value(edit.album!),
      genre: edit.genre == null ? const Value.absent() : Value(edit.genre),
      trackNumber: edit.trackNumber == null
          ? const Value.absent()
          : Value(edit.trackNumber),
      discNumber: edit.discNumber == null
          ? const Value.absent()
          : Value(edit.discNumber),
      year: edit.year == null ? const Value.absent() : Value(edit.year),
    );

    await (database.update(
      database.tracks,
    )..where((t) => t.id.equals(track.id))).write(
      db.TracksCompanion(
        albumArtist: edit.albumArtist == null
            ? const Value.absent()
            : Value(edit.albumArtist),
        rating: edit.rating == null
            ? const Value.absent()
            : Value(edit.rating!.clamp(0, 5)),
        coverArtPath: edit.coverImagePath == null
            ? const Value.absent()
            : Value(libraryCover),
        // Avoid a watcher immediately overwriting a deliberate library-only edit.
        modifiedMs: Value(
          await File(track.filePath).exists()
              ? (await File(
                  track.filePath,
                ).stat()).modified.millisecondsSinceEpoch
              : track.modifiedMs,
        ),
      ),
    );

    return fileError;
  }
}

final tagWriterProvider = Provider<TagWriter>(
  (ref) => TagWriter(ref.watch(databaseProvider)),
);
