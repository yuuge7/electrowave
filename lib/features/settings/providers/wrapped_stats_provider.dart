import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../main.dart';

enum StatsFilter { monthly, yearly, allTime }

// --- STATE MANAGER FOR UI FILTERS ---
class StatsState {
  final StatsFilter filter;
  final int month;
  final int year;

  StatsState({required this.filter, required this.month, required this.year});

  StatsState copyWith({StatsFilter? filter, int? month, int? year}) {
    return StatsState(
      filter: filter ?? this.filter,
      month: month ?? this.month,
      year: year ?? this.year,
    );
  }
}

class StatsNotifier extends Notifier<StatsState> {
  @override
  StatsState build() {
    final now = DateTime.now();
    return StatsState(filter: StatsFilter.allTime, month: now.month, year: now.year);
  }

  void setFilter(StatsFilter filter) => state = state.copyWith(filter: filter);
  void setMonth(int month) => state = state.copyWith(month: month);
  void setYear(int year) => state = state.copyWith(year: year);
}

final statsStateProvider = NotifierProvider<StatsNotifier, StatsState>(StatsNotifier.new);

// --- DATA CLASSES ---
class TopItem {
  final String title;
  final String subtitle;
  final int plays;
  final int durationMs;
  TopItem({required this.title, required this.subtitle, required this.plays, required this.durationMs});
}

class WrappedData {
  final int totalDurationMs;
  final List<TopItem> topTracks;
  final List<TopItem> topArtists;
  WrappedData({required this.totalDurationMs, required this.topTracks, required this.topArtists});
}

// --- THE SQL AGGREGATION PROVIDER ---
final wrappedStatsProvider = FutureProvider<WrappedData>((ref) async {
  final db = ref.watch(databaseProvider);
  final state = ref.watch(statsStateProvider);

  DateTime? start;
  DateTime? end;

  // Calculate strict date boundaries based on the selected filter
  if (state.filter == StatsFilter.monthly) {
    start = DateTime(state.year, state.month, 1);
    end = DateTime(state.year, state.month + 1, 1).subtract(const Duration(seconds: 1));
  } else if (state.filter == StatsFilter.yearly) {
    start = DateTime(state.year, 1, 1);
    end = DateTime(state.year + 1, 1, 1).subtract(const Duration(seconds: 1));
  }

  String whereClause = '';
  List<Variable<Object>> variables = [];

  // Drift safely converts Dart DateTime objects into Unix epoch seconds for SQLite
  if (start != null && end != null) {
    whereClause = 'WHERE h.played_at >= ? AND h.played_at <= ?';
    variables.add(Variable<DateTime>(start));
    variables.add(Variable<DateTime>(end));
  }

  // 1. Total Time Query
  final durationResult = await db.customSelect(
    'SELECT SUM(t.duration_ms) as total FROM playback_history h INNER JOIN tracks t ON h.track_id = t.id $whereClause',
    variables: variables,
  ).getSingle();
  final totalDuration = durationResult.read<int?>('total') ?? 0;

  // 2. Top Tracks Query
  final tracksResult = await db.customSelect(
    '''
    SELECT t.title, t.artist, COUNT(h.id) as plays, SUM(t.duration_ms) as time 
    FROM playback_history h 
    INNER JOIN tracks t ON h.track_id = t.id 
    $whereClause 
    GROUP BY t.id 
    ORDER BY time DESC 
    LIMIT 10
    ''',
    variables: variables,
  ).get();
  
  final topTracks = tracksResult.map((row) => TopItem(
    title: row.read<String>('title'),
    subtitle: row.read<String>('artist'),
    plays: row.read<int>('plays'),
    durationMs: row.read<int?>('time') ?? 0,
  )).toList();

  // 3. Top Artists Query
  final artistsResult = await db.customSelect(
    '''
    SELECT t.artist, COUNT(h.id) as plays, SUM(t.duration_ms) as time 
    FROM playback_history h 
    INNER JOIN tracks t ON h.track_id = t.id 
    $whereClause 
    GROUP BY t.artist 
    ORDER BY time DESC 
    LIMIT 10
    ''',
    variables: variables,
  ).get();

  final topArtists = artistsResult.map((row) => TopItem(
    title: row.read<String>('artist'),
    subtitle: 'Artist',
    plays: row.read<int>('plays'),
    durationMs: row.read<int?>('time') ?? 0,
  )).toList();

  return WrappedData(totalDurationMs: totalDuration, topTracks: topTracks, topArtists: topArtists);
});