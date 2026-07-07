import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// --- TABLE DEFINITIONS ---

class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get filePath => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  IntColumn get durationMs => integer()();
  TextColumn get coverArtPath => text().nullable()();
  TextColumn get genre => text().nullable()();
}

class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}

class PlaylistTracks extends Table {
  IntColumn get playlistId => integer()();
  IntColumn get trackId => integer()();
  
  @override
  Set<Column> get primaryKey => {playlistId, trackId}; 
}

// NEW: Tracks every single time a song is played so we can build historical stats
class PlaybackHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId => integer()();
  DateTimeColumn get playedAt => dateTime()(); // Logs the exact date and time
}

// --- DATABASE CLASS ---

@DriftDatabase(tables: [Tracks, Playlists, PlaylistTracks, PlaybackHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Bumped to version 5 for the new history table
  @override
  int get schemaVersion => 5; 
  
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(tracks, tracks.coverArtPath);
        }
        if (from < 3) {
          await m.addColumn(tracks, tracks.genre);
        }
        if (from < 4) {
          await m.createTable(playlists);
          await m.createTable(playlistTracks);
        }
        if (from < 5) {
          // Create the new history table safely
          await m.createTable(playbackHistory);
        }
      },
    );
  }
}

// --- CONNECTION LOGIC ---

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final docsFolder = await getApplicationDocumentsDirectory();
    
    // 1. Define the new Electrowave directory
    final appFolder = Directory(p.join(docsFolder.path, 'Electrowave'));
    
    // 2. Create the directory if it doesn't exist yet
    if (!await appFolder.exists()) {
      await appFolder.create(recursive: true);
    }

    final newDbFile = File(p.join(appFolder.path, 'local_player_db.sqlite'));
    final oldDbFile = File(p.join(docsFolder.path, 'local_player_db.sqlite'));

    // 3. Auto-Migration: Move the old database to the new folder if it exists
    if (await oldDbFile.exists() && !await newDbFile.exists()) {
      await oldDbFile.rename(newDbFile.path);
    }

    return NativeDatabase.createInBackground(newDbFile);
  });
}