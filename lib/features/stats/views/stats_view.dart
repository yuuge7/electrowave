import '../../../shared/widgets/retry_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart' show TrackListeningStat;
import '../../../shared/theme/app_theme.dart';
import '../../settings/providers/wrapped_stats_provider.dart';
import '../providers/song_stats_provider.dart';
import 'song_stats_table.dart';

class StatsView extends ConsumerWidget {
  const StatsView({super.key});

  String _formatDurationStr(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours;
    final minutes = (duration.inMinutes % 60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final state = ref.watch(statsStateProvider);
    final notifier = ref.read(statsStateProvider.notifier);
    final wrappedAsync = ref.watch(wrappedStatsProvider);
    final listenedAsync = ref.watch(totalListenedMsProvider);
    final listeningStatsAsync = ref.watch(listeningTimeStatsProvider);
    final mode = ref.watch(statsModeProvider);

    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final years = List.generate(
      DateTime.now().year - 2024 + 1,
      (index) => 2024 + index,
    );

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Your Stats',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // --- TIME FILTERS ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                SegmentedButton<StatsMode>(
                  segments: const [
                    ButtonSegment(
                      value: StatsMode.overview,
                      icon: Icon(Icons.leaderboard),
                      label: Text('Overview'),
                    ),
                    ButtonSegment(
                      value: StatsMode.songs,
                      icon: Icon(Icons.music_note),
                      label: Text('Songs'),
                    ),
                  ],
                  selected: {mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      ref.read(statsModeProvider.notifier).set(selection.first),
                ),
                DropdownButton<StatsFilter>(
                  dropdownColor: colors.surfaceAlt,
                  value: state.filter,
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.bold,
                  ),
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                      value: StatsFilter.monthly,
                      child: Text('Monthly'),
                    ),
                    DropdownMenuItem(
                      value: StatsFilter.yearly,
                      child: Text('Yearly'),
                    ),
                    DropdownMenuItem(
                      value: StatsFilter.allTime,
                      child: Text('All-Time'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) notifier.setFilter(val);
                  },
                ),

                if (state.filter == StatsFilter.monthly) ...[
                  DropdownButton<int>(
                    dropdownColor: colors.surfaceAlt,
                    value: state.month,
                    style: TextStyle(color: colors.textPrimary),
                    underline: const SizedBox(),
                    items: List.generate(12, (index) {
                      return DropdownMenuItem(
                        value: index + 1,
                        child: Text(months[index]),
                      );
                    }),
                    onChanged: (val) {
                      if (val != null) notifier.setMonth(val);
                    },
                  ),
                ],

                if (state.filter != StatsFilter.allTime)
                  DropdownButton<int>(
                    dropdownColor: colors.surfaceAlt,
                    value: state.year,
                    style: TextStyle(color: colors.textPrimary),
                    underline: const SizedBox(),
                    items: years.map((y) {
                      return DropdownMenuItem(
                        value: y,
                        child: Text(y.toString()),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) notifier.setYear(val);
                    },
                  ),
              ],
            ),
          ),

          Divider(color: colors.border),

          // --- PER-SONG TABLE ---
          if (mode == StatsMode.songs)
            const Expanded(child: SongStatsTable())
          else
            // --- WRAPPED DATA RENDERER ---
            Expanded(
              child: wrappedAsync.when(
                data: (data) {
                  final measuredMs = switch (listenedAsync) {
                    AsyncData(:final value) => value,
                    _ => 0,
                  };

                  if (data.totalDurationMs == 0 && measuredMs == 0) {
                    return Center(
                      child: Text(
                        'No listening history found for this period.',
                        style: TextStyle(color: colors.textFaint),
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 1000 ||
                          constraints.maxHeight < 500) {
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _totalCard(
                              context,
                              label: 'Total Time Listened',
                              value: _formatDurationStr(data.totalDurationMs),
                              hint: 'Full length of every track you played',
                              expand: false,
                            ),
                            const SizedBox(height: 16),
                            _totalCard(
                              context,
                              label: 'Time Listened (measured)',
                              value: _formatDurationStr(measuredMs),
                              hint:
                                  'Audio that actually played — skips excluded',
                              expand: false,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 360,
                              child: Row(
                                children: [
                                  _buildLeaderboard(
                                    context,
                                    'Top Tracks',
                                    data.topTracks,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 360,
                              child: Row(
                                children: [
                                  _buildLeaderboard(
                                    context,
                                    'Top Artists',
                                    data.topArtists,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 360,
                              child: Row(
                                children: [
                                  _buildListeningBoard(
                                    context,
                                    ref,
                                    listeningStatsAsync,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                _totalCard(
                                  context,
                                  label: 'Total Time Listened',
                                  value: _formatDurationStr(
                                    data.totalDurationMs,
                                  ),
                                  hint: 'Full length of every track you played',
                                ),
                                const SizedBox(width: 16),
                                _totalCard(
                                  context,
                                  label: 'Time Listened (measured)',
                                  value: _formatDurationStr(measuredMs),
                                  hint:
                                      'Audio that actually played — skips excluded',
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLeaderboard(
                                    context,
                                    'Top Tracks',
                                    data.topTracks,
                                  ),
                                  const SizedBox(width: 24),
                                  _buildLeaderboard(
                                    context,
                                    'Top Artists',
                                    data.topArtists,
                                  ),
                                  const SizedBox(width: 24),
                                  _buildListeningBoard(
                                    context,
                                    ref,
                                    listeningStatsAsync,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => Center(
                  child: CircularProgressIndicator(color: colors.accent),
                ),
                error: (err, stack) => RetryMessage(
                  onRetry: () => ref.invalidate(wrappedStatsProvider),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalCard(
    BuildContext context, {
    required String label,
    required String value,
    required String hint,
    bool expand = true,
  }) {
    final colors = context.colors;
    final card = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: colors.textFaint, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textFaint, fontSize: 11),
          ),
        ],
      ),
    );
    return expand ? Expanded(child: card) : card;
  }

  Widget _boardShell(BuildContext context, String title, Widget child) {
    final colors = context.colors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.accent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboard(
    BuildContext context,
    String title,
    List<TopItem> items,
  ) {
    final colors = context.colors;
    return _boardShell(
      context,
      title,
      items.isEmpty
          ? Center(
              child: Text(
                'Not enough data.',
                style: TextStyle(color: colors.textFaint),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  Divider(color: colors.border, height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: Text(
                    '#${index + 1}',
                    style: TextStyle(
                      color: colors.textFaint,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item.subtitle} • ${item.plays} plays',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                  trailing: Text(
                    _formatDurationStr(item.durationMs),
                    style: TextStyle(color: colors.accent, fontSize: 12),
                  ),
                );
              },
            ),
    );
  }

  /// Ranked by measured playback rather than play counts.
  Widget _buildListeningBoard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<TrackListeningStat>> statsAsync,
  ) {
    final colors = context.colors;
    return _boardShell(
      context,
      'Time Listened',
      statsAsync.when(
        data: (stats) => stats.isEmpty
            ? Center(
                child: Text(
                  'Nothing measured yet.',
                  style: TextStyle(color: colors.textFaint),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: stats.length,
                separatorBuilder: (context, index) =>
                    Divider(color: colors.border, height: 1),
                itemBuilder: (context, index) {
                  final stat = stats[index];
                  return ListTile(
                    leading: Text(
                      '#${index + 1}',
                      style: TextStyle(
                        color: colors.textFaint,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    title: Text(
                      stat.track.title,
                      style: TextStyle(color: colors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      stat.track.artist,
                      style: TextStyle(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      _formatDurationStr(stat.listenedMs),
                      style: TextStyle(color: colors.accent, fontSize: 12),
                    ),
                  );
                },
              ),
        loading: () =>
            Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (err, stack) => RetryMessage(
          onRetry: () => ref.invalidate(listeningTimeStatsProvider),
        ),
      ),
    );
  }
}
