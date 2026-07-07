import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import '../../../core/database/app_database.dart' as db;
import '../../library/providers/library_provider.dart';

// --- 1. REPEAT AND SHUFFLE STATES ---

// Renamed to avoid collision with Flutter's built-in RepeatMode
enum PlaybackRepeatMode { off, all, one }

class RepeatModeNotifier extends Notifier<PlaybackRepeatMode> {
  @override
  PlaybackRepeatMode build() => PlaybackRepeatMode.off;
  
  void cycle() {
    state = state == PlaybackRepeatMode.off ? PlaybackRepeatMode.all 
          : state == PlaybackRepeatMode.all ? PlaybackRepeatMode.one 
          : PlaybackRepeatMode.off;
  }
}
final repeatModeProvider = NotifierProvider<RepeatModeNotifier, PlaybackRepeatMode>(RepeatModeNotifier.new);

class ShuffleNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  
  void toggle() => state = !state;
}
final shuffleProvider = NotifierProvider<ShuffleNotifier, bool>(ShuffleNotifier.new);


// --- 2. CURRENT TRACK NOTIFIER ---

class CurrentTrackNotifier extends Notifier<db.Track?> {
  @override
  db.Track? build() => null;

  void setTrack(db.Track? track) {
    state = track;
  }
}
final currentTrackProvider = NotifierProvider<CurrentTrackNotifier, db.Track?>(CurrentTrackNotifier.new);


// --- 3. PLAYBACK CONTROLLER ---
// This safely gives our functions access to all providers without WidgetRef/Ref type errors

class PlaybackController {
  final Ref ref;
  PlaybackController(this.ref);

  void playNextTrack() {
    final player = ref.read(playerProvider);
    final repeatMode = ref.read(repeatModeProvider);
    final isShuffle = ref.read(shuffleProvider);
    final currentTrack = ref.read(currentTrackProvider);
    
    final libraryState = ref.read(libraryProvider);
    final allTracks = libraryState.value ?? [];

    if (allTracks.isEmpty) return;

    if (repeatMode == PlaybackRepeatMode.one) {
      if (currentTrack != null) {
        player.open(Media(currentTrack.filePath));
      }
      return;
    }

    if (isShuffle) {
      final random = Random();
      final nextTrack = allTracks[random.nextInt(allTracks.length)];
      ref.read(currentTrackProvider.notifier).setTrack(nextTrack);
      player.open(Media(nextTrack.filePath));
      return;
    }

    if (currentTrack != null) {
      int currentIndex = allTracks.indexWhere((t) => t.id == currentTrack.id);
      if (currentIndex != -1) {
        int nextIndex = currentIndex + 1;
        
        if (nextIndex >= allTracks.length) {
          if (repeatMode == PlaybackRepeatMode.all) {
            nextIndex = 0; 
          } else {
            return; 
          }
        }
        
        final nextTrack = allTracks[nextIndex];
        ref.read(currentTrackProvider.notifier).setTrack(nextTrack);
        player.open(Media(nextTrack.filePath));
      }
    }
  }

  void playPreviousTrack() {
    final player = ref.read(playerProvider);
    final position = player.state.position;
    
    if (position > const Duration(seconds: 3)) {
      player.seek(Duration.zero);
      return;
    }

    final currentTrack = ref.read(currentTrackProvider);
    final libraryState = ref.read(libraryProvider);
    final allTracks = libraryState.value ?? [];

    if (allTracks.isEmpty) return;

    if (currentTrack != null) {
      int currentIndex = allTracks.indexWhere((t) => t.id == currentTrack.id);
      if (currentIndex > 0) {
        final prevTrack = allTracks[currentIndex - 1];
        ref.read(currentTrackProvider.notifier).setTrack(prevTrack);
        player.open(Media(prevTrack.filePath));
      } else {
        player.seek(Duration.zero);
      }
    }
  }
}

final playbackControllerProvider = Provider((ref) => PlaybackController(ref));


// --- 4. PLAYER PROVIDER ---

final playerProvider = Provider<Player>((ref) {
  final player = Player();
  
  player.setPlaylistMode(PlaylistMode.none);

  player.stream.completed.listen((completed) {
    if (completed) {
      Future.microtask(() {
        ref.read(playbackControllerProvider).playNextTrack();
      });
    }
  });
  
  ref.onDispose(() {
    player.dispose();
  });
  
  return player;
});