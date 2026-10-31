import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../main.dart';
import '../../settings/providers/wrapped_stats_provider.dart';

/// Which page of the Stats tab is open.
enum StatsMode { overview, songs }

/// Kept in a provider so the chosen page survives switching tabs.
class StatsModeNotifier extends Notifier<StatsMode> {
  @override
  StatsMode build() => StatsMode.overview;

  void set(StatsMode mode) => state = mode;
}

final statsModeProvider = NotifierProvider<StatsModeNotifier, StatsMode>(
  StatsModeNotifier.new,
);

/// Every library track with its numbers for the period picked in Stats.
///
/// Auto-disposed: the query re-runs whenever listening time is flushed, which
/// is pointless once the Songs page is closed.
final songStatsProvider = StreamProvider.autoDispose<List<SongStat>>((ref) {
  final database = ref.watch(databaseProvider);
  final range = statsRange(ref.watch(statsStateProvider));
  return database.watchSongStats(from: range.from, to: range.to);
});

/// Booked plays of one track, all time, oldest first.
final trackPlayTimesProvider = StreamProvider.autoDispose
    .family<List<DateTime>, int>((ref, trackId) {
      return ref.watch(databaseProvider).watchPlayTimes(trackId);
    });

/// Measured listening stretches of one track, all time, oldest first.
final trackListeningSessionsProvider = StreamProvider.autoDispose
    .family<List<ListeningSessionEntry>, int>((ref, trackId) {
      return ref.watch(databaseProvider).watchListeningSessionsFor(trackId);
    });

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "October 2026", "2026" or "All time" for the selected filter.
String statsPeriodLabel(StatsState state) => switch (state.filter) {
  StatsFilter.monthly => '${_monthNames[state.month - 1]} ${state.year}',
  StatsFilter.yearly => '${state.year}',
  StatsFilter.allTime => 'All time',
};

/// Listening time with the precision a single song needs: "1h 05m", "12m 30s",
/// "45s".
String formatListened(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  if (minutes > 0) return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  return '${seconds}s';
}
