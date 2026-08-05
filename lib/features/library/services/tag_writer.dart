import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata_god/metadata_god.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../main.dart';

/// Edited tag values. A null field means "leave this tag alone".
class TagEdit {
  const TagEdit({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.trackNumber,
    this.discNumber,
    this.year,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
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
    try {
      // writeMetadata replaces the whole tag block, so the untouched fields —
      // album art above all — have to be read back and written out again.
      final existing = await MetadataGod.readMetadata(file: track.filePath);
      await MetadataGod.writeMetadata(
        file: track.filePath,
        metadata: Metadata(
          title: edit.title ?? existing.title,
          artist: edit.artist ?? existing.artist,
          album: edit.album ?? existing.album,
          albumArtist: existing.albumArtist,
          genre: edit.genre ?? existing.genre,
          trackNumber: edit.trackNumber ?? existing.trackNumber,
          trackTotal: existing.trackTotal,
          discNumber: edit.discNumber ?? existing.discNumber,
          discTotal: existing.discTotal,
          year: edit.year ?? existing.year,
          durationMs: existing.durationMs,
          fileSize: existing.fileSize,
          picture: existing.picture,
        ),
      );
    } catch (e) {
      fileError = 'Library updated, but the file tags could not be written '
          '(${e.runtimeType})';
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

    return fileError;
  }
}

final tagWriterProvider =
    Provider<TagWriter>((ref) => TagWriter(ref.watch(databaseProvider)));
