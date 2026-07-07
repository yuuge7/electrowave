import 'package:flutter/foundation.dart'; // Added for debugPrint
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../providers/player_provider.dart';
import '../../../core/database/app_database.dart' as db;

final scrobblingServiceProvider = Provider<void>((ref) {
  final player = ref.watch(playerProvider);
  final database = ref.watch(databaseProvider);
  
  // Keeps track of the current track ID so we only log it once per play
  int? lastScrobbledTrackId;

  player.stream.position.listen((position) async {
    final currentTrack = ref.read(currentTrackProvider);
    if (currentTrack == null) return;

    // Reset the tracker if the position drops near zero 
    if (position.inSeconds < 1) {
      lastScrobbledTrackId = null;
    }

    // If we already logged this specific track during this playback, do nothing
    if (lastScrobbledTrackId == currentTrack.id) return;

    final duration = player.state.duration;
    if (duration.inMilliseconds == 0) return;

    // Calculate how far we are into the song
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    
    // Trigger exactly when it crosses the 25% threshold
    if (ratio >= 0.25) {
      lastScrobbledTrackId = currentTrack.id; // Mark as logged
      
      await database.into(database.playbackHistory).insert(
        db.PlaybackHistoryCompanion.insert(
          trackId: currentTrack.id,
          playedAt: DateTime.now(),
        ),
      );
      debugPrint('Scrobbled (25% reached): ${currentTrack.title}'); // Swapped print for debugPrint
    }
  });
});