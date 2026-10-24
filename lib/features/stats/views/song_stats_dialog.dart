import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/theme/app_theme.dart';
import '../../library/views/browse_views.dart';
import '../../settings/providers/wrapped_stats_provider.dart';
import '../providers/song_stats_provider.dart';
import 'song_stats_table.dart' show formatPlayedDate;

/// Everything known about one song: its numbers for the period picked in
/// Stats, its all-time numbers, and plays per month.
class SongStatsDialog extends ConsumerWidget {
  const SongStatsDialog({super.key, required this.initial, this.onPlay});

  /// Shown until the live row arrives, and kept if the song leaves the list.
  final SongStat initial;
  final VoidCallback? onPlay;

  static Future<void> show(
    BuildContext context, {
    required SongStat stat,
    VoidCallback? onPlay,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => SongStatsDialog(initial: stat, onPlay: onPlay),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final statsState = ref.watch(statsStateProvider);
    final trackId = initial.track.id;

    // Live, so the numbers move while the song is playing.
    var stat = initial;
    for (final row in ref.watch(songStatsProvider).value ?? const <SongStat>[]) {
      if (row.track.id == trackId) {
        stat = row;
        break;
      }
    }
    final track = stat.track;

    final playTimes =
        ref.watch(trackPlayTimesProvider(trackId)).value ?? const <DateTime>[];
    final sessions = ref.watch(trackListeningSessionsProvider(trackId)).value ??
        const <ListeningSessionEntry>[];

    final lifetimeListened =
        sessions.fold<int>(0, (sum, s) => sum + s.listenedMs);
    final lifetimeSkips =
        sessions.where((s) => s.listenedMs * 4 < track.durationMs).length;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, track),
              if (statsState.filter != StatsFilter.allTime) ...[
                const SizedBox(height: 20),
                _sectionLabel(context, statsPeriodLabel(statsState)),
                _tiles([
                  _Tile('Plays', '${stat.plays}'),
                  _Tile('Time listened', formatListened(stat.listenedMs)),
                  _Tile('Skips', '${stat.skips}',
                      hint: _skipHint(stat.skips, stat.starts)),
                  _Tile('Last played', _date(stat.lastPlayed)),
                ]),
              ],
              const SizedBox(height: 20),
              _sectionLabel(context, 'All time'),
              _tiles([
                _Tile('Plays', '${playTimes.length}'),
                _Tile('Time listened', formatListened(lifetimeListened)),
                _Tile('Skips', '$lifetimeSkips',
                    hint: _skipHint(lifetimeSkips, sessions.length)),
                _Tile(
                  'Avg. per start',
                  sessions.isEmpty
                      ? '—'
                      : formatListened(lifetimeListened ~/ sessions.length),
                  hint: track.durationMs > 0 && sessions.isNotEmpty
                      ? '${(100 * lifetimeListened / sessions.length / track.durationMs).round()}% of the song'
                      : null,
                ),
                _Tile('First played',
                    _date(playTimes.isEmpty ? null : playTimes.first)),
                _Tile('Last played',
                    _date(playTimes.isEmpty ? null : playTimes.last)),
                _Tile('Added', _date(track.dateAdded)),
                _Tile('Length', formatListened(track.durationMs)),
              ]),
              const SizedBox(height: 24),
              _MonthlyPlaysChart(
                playTimes: playTimes,
                endMonth: _chartEndMonth(statsState),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Close',
                        style: TextStyle(color: colors.textFaint)),
                  ),
                  if (onPlay != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: colors.onAccent,
                      ),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Play'),
                      onPressed: () {
                        onPlay!();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The chart follows the period picked in Stats: a year shows that year, a
  /// month shows the year leading up to it, all-time shows the last 12 months.
  DateTime _chartEndMonth(StatsState state) {
    final now = DateTime.now();
    return switch (state.filter) {
      StatsFilter.monthly => DateTime(state.year, state.month),
      StatsFilter.yearly => DateTime(state.year, 12),
      StatsFilter.allTime => DateTime(now.year, now.month),
    };
  }

  static String? _skipHint(int skips, int starts) =>
      starts == 0 ? null : '$skips of $starts starts';

  static String _date(DateTime? when) =>
      when == null ? '—' : formatPlayedDate(when);

  Widget _header(BuildContext context, Track track) {
    final colors = context.colors;
    return Row(
      children: [
        ArtThumb(path: track.coverArtPath, size: 72, radius: 10),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${track.artist} — ${track.album}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textFaint, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close',
          icon: Icon(Icons.close, color: colors.textFaint, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: context.colors.accent,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _tiles(List<_Tile> tiles) {
    return LayoutBuilder(builder: (context, constraints) {
      const spacing = 8.0;
      const perRow = 4;
      final width = (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final tile in tiles) SizedBox(width: width, child: tile),
        ],
      );
    });
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textFaint, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          // Always laid out, so tiles with and without a hint line up.
          Text(hint ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textFaint, fontSize: 10)),
        ],
      ),
    );
  }
}

/// Plays per month for the 12 months ending at [endMonth]. One series, so no
/// legend; only the busiest month carries a number, the rest show theirs on
/// hover.
class _MonthlyPlaysChart extends StatelessWidget {
  const _MonthlyPlaysChart({required this.playTimes, required this.endMonth});

  final List<DateTime> playTimes;
  final DateTime endMonth;

  static const double _plotHeight = 110;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final months = [
      for (var i = 11; i >= 0; i--) DateTime(endMonth.year, endMonth.month - i),
    ];
    final counts = List<int>.filled(12, 0);
    for (final played in playTimes) {
      for (var i = 0; i < 12; i++) {
        if (played.year == months[i].year && played.month == months[i].month) {
          counts[i]++;
          break;
        }
      }
    }
    final peak = counts.reduce(max);
    final peakIndex = counts.lastIndexOf(peak);
    final shortMonth = DateFormat('MMM');
    final longMonth = DateFormat('MMMM yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Plays per month',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        Text(
          '${DateFormat('MMM yyyy').format(months.first)} – '
          '${DateFormat('MMM yyyy').format(months.last)}',
          style: TextStyle(color: colors.textFaint, fontSize: 11),
        ),
        const SizedBox(height: 12),
        if (peak == 0)
          SizedBox(
            height: _plotHeight + 41,
            child: Center(
              child: Text('No plays in these months.',
                  style: TextStyle(color: colors.textFaint, fontSize: 12)),
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 12; i++)
                Expanded(
                  child: Tooltip(
                    message: '${longMonth.format(months[i])}: '
                        '${counts[i]} ${counts[i] == 1 ? 'play' : 'plays'}',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: _plotHeight + 20,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (i == peakIndex)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text('${counts[i]}',
                                      style: TextStyle(
                                          color: colors.textSecondary,
                                          fontSize: 11)),
                                ),
                              Center(
                                child: Container(
                                  width: 22,
                                  height: _plotHeight * counts[i] / peak,
                                  decoration: BoxDecoration(
                                    color: colors.accent,
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(4)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 1, color: colors.border),
                        const SizedBox(height: 4),
                        Text(shortMonth.format(months[i]),
                            style: TextStyle(
                                color: colors.textFaint, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
