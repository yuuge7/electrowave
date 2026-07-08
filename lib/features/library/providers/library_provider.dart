import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../main.dart'; // Import to access databaseProvider

// Provides a reactive stream of all active tracks in the database
final libraryProvider = StreamProvider<List<Track>>((ref) {
  final db = ref.watch(databaseProvider);
  
  // SOFT DELETE LOGIC: Only fetch tracks where isDeleted is strictly false.
  return (db.select(db.tracks)..where((t) => t.isDeleted.equals(false))).watch();
});