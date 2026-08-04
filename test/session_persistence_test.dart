import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:electrowave/core/session/session_snapshot.dart';
import 'package:electrowave/features/player/providers/session_provider.dart';

void main() {
  group('SessionSnapshot', () {
    test('survives a JSON round trip', () {
      const original = SessionSnapshot(
        currentTrackId: 42,
        positionMs: 91000,
        volume: 63.5,
        shuffle: true,
        repeatMode: 'one',
        contextTrackIds: [7, 42, 13],
        contextIndex: 1,
        manualQueueTrackIds: [99],
        playingFromManualQueue: true,
        navIndex: 2,
        selectedPlaylistId: 5,
        queuePanelVisible: true,
      );

      final decoded = SessionSnapshot.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.sameAs(original), isTrue);
      expect(decoded.currentTrackId, 42);
      expect(decoded.positionMs, 91000);
      expect(decoded.volume, 63.5);
      expect(decoded.repeatMode, 'one');
      expect(decoded.contextTrackIds, [7, 42, 13]);
      expect(decoded.manualQueueTrackIds, [99]);
    });

    test('falls back to defaults on a corrupt file', () {
      final decoded = SessionSnapshot.fromJson(<String, dynamic>{
        'currentTrackId': 'not-a-number',
        'positionMs': null,
        'volume': 999,
        'contextTrackIds': ['a', 3, null],
        'contextIndex': 'x',
      });

      expect(decoded.currentTrackId, isNull);
      expect(decoded.positionMs, 0);
      expect(decoded.volume, 100.0);
      expect(decoded.contextTrackIds, [3]);
      expect(decoded.contextIndex, -1);
      expect(decoded.repeatMode, 'off');
      expect(decoded.navIndex, 0);
    });

    test('sameAs detects a moved position', () {
      const a = SessionSnapshot(currentTrackId: 1, positionMs: 1000);
      const b = SessionSnapshot(currentTrackId: 1, positionMs: 6000);

      expect(a.sameAs(a), isTrue);
      expect(a.sameAs(b), isFalse);
    });
  });

  group('remapContextIndex', () {
    test('keeps the index when nothing was deleted', () {
      expect(
        remapContextIndex(
          savedIds: [10, 20, 30],
          savedIndex: 2,
          survivingIds: {10, 20, 30},
          restoredLength: 3,
        ),
        2,
      );
    });

    test('shifts down when earlier tracks were deleted', () {
      expect(
        remapContextIndex(
          savedIds: [10, 20, 30, 40],
          savedIndex: 3,
          survivingIds: {30, 40},
          restoredLength: 2,
        ),
        1,
      );
    });

    test('lands on the survivors before a deleted current track', () {
      expect(
        remapContextIndex(
          savedIds: [10, 20, 30],
          savedIndex: 1,
          survivingIds: {10, 30},
          restoredLength: 2,
        ),
        1,
      );
    });

    test('clamps when the deleted track was last', () {
      expect(
        remapContextIndex(
          savedIds: [10, 20],
          savedIndex: 1,
          survivingIds: {10},
          restoredLength: 1,
        ),
        0,
      );
    });

    test('returns -1 for an empty or unusable context', () {
      expect(
        remapContextIndex(
          savedIds: [10],
          savedIndex: 0,
          survivingIds: {},
          restoredLength: 0,
        ),
        -1,
      );
      expect(
        remapContextIndex(
          savedIds: [10, 20],
          savedIndex: -1,
          survivingIds: {10, 20},
          restoredLength: 2,
        ),
        -1,
      );
    });
  });
}
