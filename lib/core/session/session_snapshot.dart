/// Everything Electrowave remembers between launches.
///
/// Tracks are stored as database IDs (never file paths) so a "repair links"
/// relocation, which rewrites every path, doesn't invalidate the session.
class SessionSnapshot {
  /// The track that was loaded in the player when the app was last closed.
  final int? currentTrackId;

  /// How far into [currentTrackId] playback had reached.
  final int positionMs;

  /// Player volume, 0-100 (media_kit's scale).
  final double volume;

  final bool shuffle;

  /// Serialized [PlaybackRepeatMode]: 'off', 'all' or 'one'.
  final String repeatMode;

  /// The playback context — the exact list the user started playback from.
  final List<int> contextTrackIds;

  /// Index of the current track inside [contextTrackIds].
  final int contextIndex;

  /// The manual "Add to queue" list, in order.
  final List<int> manualQueueTrackIds;

  final bool playingFromManualQueue;

  /// Which tab of the navigation rail was open (0-3).
  final int navIndex;

  /// The playlist the user had opened in the Playlists tab.
  final int? selectedPlaylistId;

  final bool queuePanelVisible;

  const SessionSnapshot({
    this.currentTrackId,
    this.positionMs = 0,
    this.volume = 100.0,
    this.shuffle = false,
    this.repeatMode = 'off',
    this.contextTrackIds = const [],
    this.contextIndex = -1,
    this.manualQueueTrackIds = const [],
    this.playingFromManualQueue = false,
    this.navIndex = 0,
    this.selectedPlaylistId,
    this.queuePanelVisible = false,
  });

  Map<String, dynamic> toJson() => {
        'version': 1,
        'currentTrackId': currentTrackId,
        'positionMs': positionMs,
        'volume': volume,
        'shuffle': shuffle,
        'repeatMode': repeatMode,
        'contextTrackIds': contextTrackIds,
        'contextIndex': contextIndex,
        'manualQueueTrackIds': manualQueueTrackIds,
        'playingFromManualQueue': playingFromManualQueue,
        'navIndex': navIndex,
        'selectedPlaylistId': selectedPlaylistId,
        'queuePanelVisible': queuePanelVisible,
      };

  /// Tolerant parsing: a half-written or older session file must never stop
  /// the app from starting, so every field falls back to its default.
  factory SessionSnapshot.fromJson(Map<String, dynamic> json) {
    List<int> intList(Object? raw) {
      if (raw is! List) return const [];
      return raw.whereType<num>().map((n) => n.toInt()).toList();
    }

    int? optionalInt(Object? raw) => raw is num ? raw.toInt() : null;

    return SessionSnapshot(
      currentTrackId: optionalInt(json['currentTrackId']),
      positionMs: optionalInt(json['positionMs']) ?? 0,
      volume: (json['volume'] is num)
          ? (json['volume'] as num).toDouble().clamp(0.0, 100.0)
          : 100.0,
      shuffle: json['shuffle'] == true,
      repeatMode: json['repeatMode'] is String ? json['repeatMode'] as String : 'off',
      contextTrackIds: intList(json['contextTrackIds']),
      contextIndex: optionalInt(json['contextIndex']) ?? -1,
      manualQueueTrackIds: intList(json['manualQueueTrackIds']),
      playingFromManualQueue: json['playingFromManualQueue'] == true,
      navIndex: optionalInt(json['navIndex']) ?? 0,
      selectedPlaylistId: optionalInt(json['selectedPlaylistId']),
      queuePanelVisible: json['queuePanelVisible'] == true,
    );
  }

  /// Cheap equality check so we skip disk writes when nothing moved.
  bool sameAs(SessionSnapshot other) {
    return currentTrackId == other.currentTrackId &&
        positionMs == other.positionMs &&
        volume == other.volume &&
        shuffle == other.shuffle &&
        repeatMode == other.repeatMode &&
        contextIndex == other.contextIndex &&
        playingFromManualQueue == other.playingFromManualQueue &&
        navIndex == other.navIndex &&
        selectedPlaylistId == other.selectedPlaylistId &&
        queuePanelVisible == other.queuePanelVisible &&
        _sameIds(contextTrackIds, other.contextTrackIds) &&
        _sameIds(manualQueueTrackIds, other.manualQueueTrackIds);
  }

  static bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
