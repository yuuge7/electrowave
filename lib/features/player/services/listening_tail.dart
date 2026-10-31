import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TailListening {
  const TailListening(this.trackId, this.listenedMs);
  final int trackId, listenedMs;
}

final tailListeningProvider = Provider<StreamController<TailListening>>((ref) {
  final stream = StreamController<TailListening>.broadcast(sync: true);
  ref.onDispose(() => unawaited(stream.close()));
  return stream;
});
