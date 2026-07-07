import 'package:drift/drift.dart';

// The main library of local files
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get filePath => text().unique()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  IntColumn get durationMs => integer()();
  TextColumn get genre => text().nullable()();
  
  // Stores the path to the cached cover art image
  TextColumn get albumArtPath => text().nullable()(); 
  
  // FIXED: Removed the extra () at the end
  DateTimeColumn get dateAdded => dateTime().withDefault(currentDateAndTime)();
  
  IntColumn get totalPlayCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayed => dateTime().nullable()();
}

// Logs every playback event to build the Leaderboard
class PlaybackLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId => integer().references(Tracks, #id)();
  
  // FIXED: Removed the extra () at the end
  DateTimeColumn get playedAt => dateTime().withDefault(currentDateAndTime)();
}