import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../shared/theme/app_theme.dart';
import '../../library/providers/library_provider.dart';
import '../../library/views/browse_views.dart';
import '../../player/providers/player_provider.dart';
import '../../player/services/audio_engine.dart';
import '../providers/playlists_provider.dart';

/// Multi-select browser over the whole library.
///
/// Pops a `List<int>` of chosen track ids in the order they should be
/// appended, or null if the user backed out. Selection deliberately survives
/// search and sort changes: building a long playlist means searching "live",
/// ticking a few, searching "1979", ticking a few more.
///
/// Pass [playlistId] to grey out songs that playlist already holds.
class TrackPickerDialog extends ConsumerStatefulWidget {
  const TrackPickerDialog({
    super.key,
    required this.title,
    this.playlistId,
    this.confirmLabel = 'Add',
  });

  final String title;
  final int? playlistId;
  final String confirmLabel;

  @override
  ConsumerState<TrackPickerDialog> createState() => _TrackPickerDialogState();

  /// Opens the picker and returns the chosen ids, or null on cancel.
  static Future<List<int>?> show(
    BuildContext context, {
    required String title,
    int? playlistId,
    String confirmLabel = 'Add',
  }) {
    return showDialog<List<int>>(
      context: context,
      builder: (context) => TrackPickerDialog(
        title: title,
        playlistId: playlistId,
        confirmLabel: confirmLabel,
      ),
    );
  }
}

class _TrackPickerDialogState extends ConsumerState<TrackPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// Chosen ids in tick order — that order is the order they get appended in.
  final List<int> _selected = [];
  final Set<int> _selectedLookup = {};

  /// Query text the stream actually runs on. Kept behind the controller by a
  /// short debounce so a fast typist doesn't open a database query per letter.
  String _search = '';
  Timer? _debounce;

  db.LibrarySort _sort = db.LibrarySort.title;
  bool _selectedOnly = false;
  bool _hideAdded = false;

  /// Row that anchors a shift-click range.
  int? _anchorIndex;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _search = value;
        _anchorIndex = null;
      });
    });
  }

  void _setSelected(int trackId, bool selected) {
    if (selected) {
      if (_selectedLookup.add(trackId)) _selected.add(trackId);
    } else {
      if (_selectedLookup.remove(trackId)) _selected.remove(trackId);
    }
  }

  /// Plain tap toggles one row and re-anchors. Shift-tap selects everything
  /// between the anchor and the tapped row, which is what makes picking fifty
  /// songs bearable.
  void _onRowTap(int index, List<db.Track> visible, Set<int> alreadyIn) {
    setState(() {
      final anchor = _anchorIndex;
      if (HardwareKeyboard.instance.isShiftPressed &&
          anchor != null &&
          anchor < visible.length) {
        for (var i = min(anchor, index); i <= max(anchor, index); i++) {
          final id = visible[i].id;
          if (alreadyIn.contains(id)) continue;
          _setSelected(id, true);
        }
      } else {
        final id = visible[index].id;
        _setSelected(id, !_selectedLookup.contains(id));
      }
      _anchorIndex = index;
    });
  }

  /// The rows the list is actually showing, after the filter chips.
  List<db.Track> _visible(List<db.Track> tracks, Set<int> alreadyIn) => [
        for (final track in tracks)
          if (!(_selectedOnly && !_selectedLookup.contains(track.id)) &&
              !(_hideAdded && alreadyIn.contains(track.id)))
            track,
      ];

  /// Of those, the ones that can still be added.
  List<db.Track> _selectable(List<db.Track> visible, Set<int> alreadyIn) => [
        for (final track in visible)
          if (!alreadyIn.contains(track.id)) track,
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = MediaQuery.sizeOf(context);

    final alreadyIn = widget.playlistId == null
        ? const <int>{}
        : ref.watch(playlistTrackIdsProvider(widget.playlistId!)).value ??
            const <int>{};

    final libraryAsync = ref.watch(
      trackPickerLibraryProvider((search: _search, sort: _sort)),
    );

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: max(360, size.height * 0.85),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(colors),
            _toolbar(colors),
            Divider(height: 1, color: colors.border),
            Expanded(
              child: libraryAsync.when(
                data: (tracks) => _list(
                    colors, tracks, _visible(tracks, alreadyIn), alreadyIn),
                loading: () => Center(
                    child: CircularProgressIndicator(color: colors.accent)),
                error: (err, stack) => Center(
                  child: Text('Could not load the library: $err',
                      style: const TextStyle(color: Colors.red)),
                ),
              ),
            ),
            Divider(height: 1, color: colors.border),
            _footer(
              colors,
              _visible(libraryAsync.value ?? const [], alreadyIn),
              alreadyIn,
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ElectrowaveColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: Icon(Icons.close, color: colors.textFaint, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(ElectrowaveColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: colors.textPrimary),
                  onChanged: (value) {
                    _onSearchChanged(value);
                    // Repaint now so the clear button appears with the text
                    // instead of waiting out the debounce.
                    setState(() {});
                  },
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
                            icon: Icon(Icons.clear,
                                color: colors.textFaint, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                              setState(() {});
                            },
                          ),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colors.border)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colors.accent)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text('Sort',
                  style: TextStyle(color: colors.textFaint, fontSize: 12)),
              const SizedBox(width: 8),
              DropdownButton<db.LibrarySort>(
                value: _sort,
                underline: const SizedBox.shrink(),
                dropdownColor: colors.surfaceAlt,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
                icon: Icon(Icons.arrow_drop_down, color: colors.textFaint),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _sort = value;
                    _anchorIndex = null;
                  });
                },
                items: [
                  for (final sort in db.LibrarySort.values)
                    DropdownMenuItem(
                      value: sort,
                      child: Text(librarySortLabel(sort)),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip(
                colors,
                label: 'Selected only',
                selected: _selectedOnly,
                onTap: () => setState(() {
                  _selectedOnly = !_selectedOnly;
                  _anchorIndex = null;
                }),
              ),
              if (widget.playlistId != null) ...[
                const SizedBox(width: 8),
                _chip(
                  colors,
                  label: 'Hide songs already added',
                  selected: _hideAdded,
                  onTap: () => setState(() {
                    _hideAdded = !_hideAdded;
                    _anchorIndex = null;
                  }),
                ),
              ],
              const Spacer(),
              Text(
                '${_selected.length} selected',
                style: TextStyle(
                  color: _selected.isEmpty ? colors.textFaint : colors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(
    ElectrowaveColors colors, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.accent.withValues(alpha: 0.15) : null,
          border: Border.all(color: selected ? colors.accent : colors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.accent : colors.textFaint,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  /// Plays [track] right now without disturbing the playback context: the
  /// context picks up again once the preview ends, so auditioning a song from
  /// the picker doesn't cost the user their queue.
  void _togglePreview(db.Track track, bool isCurrent, bool isPlaying) {
    final player = ref.read(playerProvider);
    ref.read(audioEngineProvider).noteUserActivity();
    if (isCurrent) {
      isPlaying ? player.pause() : player.play();
      return;
    }
    ref.read(playbackControllerProvider).playQueuedTrackNow(track);
  }

  Widget _previewButton(ElectrowaveColors colors, db.Track track) {
    final isCurrent = ref.watch(currentTrackProvider)?.id == track.id;
    final player = ref.watch(playerProvider);

    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, snapshot) {
        final isPlaying = isCurrent && (snapshot.data ?? false);
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          iconSize: 20,
          tooltip: isPlaying ? 'Pause preview' : 'Preview this song',
          icon: Icon(
            isPlaying ? Icons.pause_circle_filled : Icons.play_circle_outline,
            color: isCurrent ? colors.accent : colors.textFaint,
          ),
          onPressed: () => _togglePreview(track, isCurrent, isPlaying),
        );
      },
    );
  }

  Widget _list(ElectrowaveColors colors, List<db.Track> tracks,
      List<db.Track> visible, Set<int> alreadyIn) {
    if (visible.isEmpty) {
      return Center(
        child: Text(
          _selectedOnly
              ? 'Nothing selected yet.'
              : tracks.isEmpty && _search.trim().isEmpty
                  ? 'Your library is empty. Scan a folder first.'
                  : 'No songs match that search.',
          style: TextStyle(color: colors.textFaint),
        ),
      );
    }

    return Scrollbar(
      controller: _scrollController,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final track = visible[index];
          final added = alreadyIn.contains(track.id);
          final checked = _selectedLookup.contains(track.id);

          return InkWell(
            onTap: added ? null : () => _onRowTap(index, visible, alreadyIn),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: checked ? colors.accent.withValues(alpha: 0.08) : null,
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: added
                        ? Icon(Icons.check_circle,
                            color: colors.textFaint, size: 18)
                        : Checkbox(
                            value: checked,
                            visualDensity: VisualDensity.compact,
                            activeColor: colors.accent,
                            checkColor: colors.onAccent,
                            side: BorderSide(color: colors.border),
                            onChanged: (_) =>
                                _onRowTap(index, visible, alreadyIn),
                          ),
                  ),
                  ArtThumb(path: track.coverArtPath, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                added ? colors.textFaint : colors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${track.artist} — ${track.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: colors.textFaint, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _previewButton(colors, track),
                  const SizedBox(width: 8),
                  Text(
                    added ? 'In playlist' : _formatDurationMs(track.durationMs),
                    style: TextStyle(color: colors.textFaint, fontSize: 11),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _footer(
      ElectrowaveColors colors, List<db.Track> visible, Set<int> alreadyIn) {
    final selectable = _selectable(visible, alreadyIn);
    final allChosen = selectable.isNotEmpty &&
        selectable.every((track) => _selectedLookup.contains(track.id));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: selectable.isEmpty
                ? null
                : () => setState(() {
                      for (final track in selectable) {
                        _setSelected(track.id, !allChosen);
                      }
                    }),
            icon: Icon(allChosen ? Icons.remove_done : Icons.done_all,
                size: 16, color: colors.textSecondary),
            label: Text(
              allChosen
                  ? 'Deselect these ${selectable.length}'
                  : 'Select all ${selectable.length}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ),
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _selected.clear();
                _selectedLookup.clear();
                _anchorIndex = null;
              }),
              child: Text('Clear selection',
                  style: TextStyle(color: colors.textFaint, fontSize: 12)),
            ),
          const Spacer(),
          Text(
            'Shift-click to pick a range',
            style: TextStyle(color: colors.textFaint, fontSize: 11),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textFaint)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
            ),
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, List<int>.of(_selected)),
            child: Text(_selected.isEmpty
                ? widget.confirmLabel
                : '${widget.confirmLabel} ${_selected.length}'),
          ),
        ],
      ),
    );
  }
}

String _formatDurationMs(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
