import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/theme/app_theme.dart';
import '../../library/views/browse_views.dart';
import '../../player/providers/player_provider.dart';
import '../../settings/providers/wrapped_stats_provider.dart';
import '../providers/song_stats_provider.dart';
import 'song_stats_dialog.dart';

enum _SortKey { title, artist, plays, listened, skips, lastPlayed }

/// Stats → Songs: every library track with its numbers for the selected
/// period, sortable by any column. Clicking a row opens the song's details.
class SongStatsTable extends ConsumerStatefulWidget {
  const SongStatsTable({super.key});

  @override
  ConsumerState<SongStatsTable> createState() => _SongStatsTableState();
}

class _SongStatsTableState extends ConsumerState<SongStatsTable> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  _SortKey _sort = _SortKey.plays;
  bool _descending = true;
  bool _playedOnly = false;

  static const double _rankWidth = 44;
  static const double _playsWidth = 64;
  static const double _listenedWidth = 88;
  static const double _skipsWidth = 64;
  static const double _lastPlayedWidth = 112;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Text columns start A→Z, number columns start biggest first — the order
  /// someone clicking that header almost always wants.
  void _onHeaderTap(_SortKey key) {
    setState(() {
      if (_sort == key) {
        _descending = !_descending;
      } else {
        _sort = key;
        _descending = key != _SortKey.title && key != _SortKey.artist;
      }
    });
  }

  List<SongStat> _visible(List<SongStat> stats) {
    final needle = _searchController.text.trim().toLowerCase();
    final rows = [
      for (final stat in stats)
        if (!(_playedOnly && stat.plays == 0 && stat.starts == 0) &&
            (needle.isEmpty ||
                stat.track.title.toLowerCase().contains(needle) ||
                stat.track.artist.toLowerCase().contains(needle) ||
                stat.track.album.toLowerCase().contains(needle)))
          stat,
    ];

    int byTitle(SongStat a, SongStat b) =>
        a.track.title.toLowerCase().compareTo(b.track.title.toLowerCase());

    int primary(SongStat a, SongStat b) => switch (_sort) {
          _SortKey.title => byTitle(a, b),
          _SortKey.artist => a.track.artist
              .toLowerCase()
              .compareTo(b.track.artist.toLowerCase()),
          _SortKey.plays => a.plays != b.plays
              ? a.plays.compareTo(b.plays)
              : a.listenedMs.compareTo(b.listenedMs),
          _SortKey.listened => a.listenedMs != b.listenedMs
              ? a.listenedMs.compareTo(b.listenedMs)
              : a.plays.compareTo(b.plays),
          _SortKey.skips => a.skips != b.skips
              ? a.skips.compareTo(b.skips)
              : a.starts.compareTo(b.starts),
          _SortKey.lastPlayed => (a.lastPlayed ?? DateTime(0))
              .compareTo(b.lastPlayed ?? DateTime(0)),
        };

    rows.sort((a, b) {
      // Never-played songs stay at the bottom of "Last played" either way.
      if (_sort == _SortKey.lastPlayed &&
          (a.lastPlayed == null) != (b.lastPlayed == null)) {
        return a.lastPlayed == null ? 1 : -1;
      }
      final result = primary(a, b);
      if (result != 0) return _descending ? -result : result;
      return byTitle(a, b);
    });
    return rows;
  }

  void _openDetails(List<SongStat> visible, int index) {
    SongStatsDialog.show(
      context,
      stat: visible[index],
      // The table on screen becomes the playback context, like every other
      // track list in the app.
      onPlay: () => ref.read(playbackControllerProvider).playFromContext(
            [for (final stat in visible) stat.track],
            index,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statsAsync = ref.watch(songStatsProvider);
    final period = statsPeriodLabel(ref.watch(statsStateProvider));

    return statsAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: colors.accent)),
      error: (err, stack) => Center(
          child: Text('Could not load song stats: $err',
              style: const TextStyle(color: Colors.red))),
      data: (stats) {
        final visible = _visible(stats);
        final playedCount =
            stats.where((s) => s.plays > 0 || s.starts > 0).length;

        return Column(
          children: [
            _toolbar(colors, stats.length, playedCount, period),
            _header(colors),
            Divider(height: 1, color: colors.border),
            Expanded(child: _list(colors, stats, visible)),
          ],
        );
      },
    );
  }

  Widget _toolbar(
      ElectrowaveColors colors, int total, int played, String period) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search title, artist or album',
                hintStyle: TextStyle(color: colors.textFaint),
                prefixIcon:
                    Icon(Icons.search, color: colors.textFaint, size: 18),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon:
                            Icon(Icons.clear, color: colors.textFaint, size: 18),
                        onPressed: () =>
                            setState(() => _searchController.clear()),
                      ),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: colors.border)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: colors.accent)),
              ),
            ),
          ),
          const SizedBox(width: 16),
          FilterChip(
            label: const Text('Played in this period'),
            selected: _playedOnly,
            showCheckmark: false,
            labelStyle: TextStyle(
              color: _playedOnly ? colors.accent : colors.textFaint,
              fontSize: 12,
            ),
            backgroundColor: Colors.transparent,
            selectedColor: colors.accent.withValues(alpha: 0.15),
            side: BorderSide(
                color: _playedOnly ? colors.accent : colors.border),
            onSelected: (value) => setState(() => _playedOnly = value),
          ),
          const Spacer(),
          Text(
            '$played of $total songs played · $period',
            style: TextStyle(color: colors.textFaint, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _header(ElectrowaveColors colors) {
    Widget label(String text, _SortKey key, {bool numeric = false}) {
      final active = _sort == key;
      final style = TextStyle(
        color: active ? colors.accent : colors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );
      final arrow = Icon(
        _descending ? Icons.arrow_downward : Icons.arrow_upward,
        size: 13,
        color: colors.accent,
      );
      return InkWell(
        onTap: () => _onHeaderTap(key),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment:
                numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (active && numeric) ...[arrow, const SizedBox(width: 2)],
              Flexible(
                child: Text(text,
                    style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (active && !numeric) ...[const SizedBox(width: 2), arrow],
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const SizedBox(width: _rankWidth + 36 + 12),
          Expanded(flex: 3, child: label('Title', _SortKey.title)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: label('Artist', _SortKey.artist)),
          SizedBox(
              width: _playsWidth,
              child: label('Plays', _SortKey.plays, numeric: true)),
          SizedBox(
              width: _listenedWidth,
              child: label('Listened', _SortKey.listened, numeric: true)),
          SizedBox(
              width: _skipsWidth,
              child: Tooltip(
                message: 'Started, then stopped before a quarter was heard',
                child: label('Skips', _SortKey.skips, numeric: true),
              )),
          SizedBox(
              width: _lastPlayedWidth,
              child:
                  label('Last played', _SortKey.lastPlayed, numeric: true)),
        ],
      ),
    );
  }

  Widget _list(ElectrowaveColors colors, List<SongStat> all,
      List<SongStat> visible) {
    if (visible.isEmpty) {
      final message = all.isEmpty
          ? 'Your library is empty. Scan a folder first.'
          : _searchController.text.trim().isNotEmpty
              ? 'No songs match that search.'
              : 'Nothing played in this period.';
      return Center(
          child: Text(message, style: TextStyle(color: colors.textFaint)));
    }

    final currentId = ref.watch(currentTrackProvider)?.id;

    return Scrollbar(
      controller: _scrollController,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: visible.length,
        itemExtent: 52,
        itemBuilder: (context, index) {
          final stat = visible[index];
          final track = stat.track;
          final isCurrent = track.id == currentId;

          TextStyle number(int value) => TextStyle(
                color: value == 0 ? colors.textFaint : colors.textSecondary,
                fontSize: 13,
                fontFeatures: const [FontFeature.tabularFigures()],
              );

          return InkWell(
            onTap: () => _openDetails(visible, index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: _rankWidth,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: colors.textFaint,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  ArtThumb(path: track.coverArtPath, size: 36, radius: 6),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? colors.accent : colors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: _playsWidth,
                    child: Text('${stat.plays}',
                        textAlign: TextAlign.end, style: number(stat.plays)),
                  ),
                  SizedBox(
                    width: _listenedWidth,
                    child: Text(
                      stat.listenedMs == 0
                          ? '0'
                          : formatListened(stat.listenedMs),
                      textAlign: TextAlign.end,
                      style: number(stat.listenedMs),
                    ),
                  ),
                  SizedBox(
                    width: _skipsWidth,
                    child: Tooltip(
                      message: stat.starts == 0
                          ? 'Not started in this period'
                          : '${stat.skips} of ${stat.starts} starts',
                      child: Text('${stat.skips}',
                          textAlign: TextAlign.end, style: number(stat.skips)),
                    ),
                  ),
                  SizedBox(
                    width: _lastPlayedWidth,
                    child: Text(
                      stat.lastPlayed == null
                          ? '—'
                          : formatPlayedDate(stat.lastPlayed!),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: stat.lastPlayed == null
                            ? colors.textFaint
                            : colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "Today", "Yesterday", "4 days ago", then a plain date.
String formatPlayedDate(DateTime when) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final daysAgo = today.difference(day).inDays;
  if (daysAgo <= 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  if (daysAgo < 7) return '$daysAgo days ago';
  return DateFormat('d MMM yyyy').format(when);
}
