import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../main.dart'; // Import to access databaseProvider

// Provides a reactive stream of all tracks in the database
final libraryProvider = StreamProvider<List<Track>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.tracks).watch();
});