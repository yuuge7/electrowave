import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart' as db;

/// Everything the player needs to decide what plays next.
class QueueState {
  /// The playback context: the exact list the user started playback from
  /// (a playlist, the library, filtered search results...).
  /// Next/previous walk this list — never anything else.
  final List<db.Track> context;

  /// Index of the current context track. Stays put while the manual queue
  /// plays, so the context resumes exactly where it was interrupted.
  final int contextIndex;

  /// User-queued tracks ("Add to queue"). They always play before the
  /// context resumes, each exactly once, in the order they were added.
  final List<db.Track> manualQueue;

  /// True while the current track came from [manualQueue] rather than
  /// [context].
  final bool playingFromManualQueue;

  const QueueState({
    this.context = const [],
    this.contextIndex = -1,
    this.manualQueue = const [],
    this.playingFromManualQueue = false,
  });

  QueueState copyWith({
    List<db.Track>? context,
    int? contextIndex,
    List<db.Track>? manualQueue,
    bool? playingFromManualQueue,
  }) {
    return QueueState(
      context: context ?? this.context,
      contextIndex: contextIndex ?? this.contextIndex,
      manualQueue: manualQueue ?? this.manualQueue,
      playingFromManualQueue:
          playingFromManualQueue ?? this.playingFromManualQueue,
    );
  }

  /// Context tracks still ahead of the current one (what plays after the
  /// manual queue empties).
  List<db.Track> get upcomingFromContext {
    if (contextIndex < 0 || contextIndex + 1 >= context.length) {
      return const [];
    }
    return context.sublist(contextIndex + 1);
  }
}

class QueueNotifier extends Notifier<QueueState> {
  @override
  QueueState build() => const QueueState();

  /// Replaces the playback context (user clicked a track inside a list).
  void setContext(List<db.Track> tracks, int index) {
    state = state.copyWith(
      context: List.unmodifiable(tracks),
      contextIndex: index,
      playingFromManualQueue: false,
    );
  }

  void addToQueue(db.Track track) {
    state = state.copyWith(manualQueue: [...state.manualQueue, track]);
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= state.manualQueue.length) return;
    final updated = [...state.manualQueue]..removeAt(index);
    state = state.copyWith(manualQueue: updated);
  }

  void clearQueue() {
    state = state.copyWith(manualQueue: const []);
  }

  /// Takes the next manual-queue track, or null when the queue is empty.
  db.Track? popManualQueue() {
    if (state.manualQueue.isEmpty) return null;
    final next = state.manualQueue.first;
    state = state.copyWith(
      manualQueue: state.manualQueue.sublist(1),
      playingFromManualQueue: true,
    );
    return next;
  }

  /// Marks the current track as coming from the manual queue without
  /// consuming anything (used when the user taps a queued item directly).
  void markPlayingFromManualQueue() {
    state = state.copyWith(playingFromManualQueue: true);
  }

  /// Moves playback to [index] within the current context.
  void moveToContextIndex(int index) {
    state = state.copyWith(
      contextIndex: index,
      playingFromManualQueue: false,
    );
  }

  void reset() {
    state = const QueueState();
  }
}

final queueProvider =
    NotifierProvider<QueueNotifier, QueueState>(QueueNotifier.new);

/// Whether the Spotify-style queue side panel is open.
class QueuePanelVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void close() => state = false;
}

final queuePanelVisibleProvider =
    NotifierProvider<QueuePanelVisibleNotifier, bool>(
        QueuePanelVisibleNotifier.new);
