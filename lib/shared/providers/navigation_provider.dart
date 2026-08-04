import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which tab of the navigation rail is open (0 Library, 1 Playlists,
/// 2 Stats, 3 Settings).
///
/// Kept in a provider rather than in [MainShell]'s local state so the session
/// layer can save it and restore it on the next launch.
class NavIndexNotifier extends Notifier<int> {
  static const int destinationCount = 4;

  @override
  int build() => 0;

  void set(int index) {
    if (index < 0 || index >= destinationCount) return;
    state = index;
  }
}

final navIndexProvider =
    NotifierProvider<NavIndexNotifier, int>(NavIndexNotifier.new);
