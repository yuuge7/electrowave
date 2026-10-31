import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart' as db;
import '../../../shared/theme/app_theme.dart';
import '../../player/providers/player_provider.dart';
import '../../player/providers/queue_provider.dart';
import '../services/tag_writer.dart';
import 'add_to_playlist_dialog.dart';
import 'bulk_tag_editor.dart';
import 'track_actions.dart';
import 'browse_views.dart' show ArtThumb;

/// Virtualized rows keep a 50,000-track library from constructing 50,000 widgets.
class TrackTable extends ConsumerStatefulWidget {
  const TrackTable({
    super.key,
    required this.tracks,
    this.emptyMessage = 'No tracks found.',
    this.showAlbum = true,
    this.onRemoveFromPlaylist,
  });
  final List<db.Track> tracks;
  final String emptyMessage;
  final bool showAlbum;
  final Future<void> Function(List<db.Track>)? onRemoveFromPlaylist;
  @override
  ConsumerState<TrackTable> createState() => _TrackTableState();
}

class _TrackTableState extends ConsumerState<TrackTable> {
  final Set<int> _selected = {};
  int _anchor = 0;
  final _focus = FocusNode(debugLabel: 'Track list');
  final _scroll = ScrollController();
  bool? _clickShift, _clickControl;
  double _rowExtent = 54;
  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<db.Track> get selected =>
      widget.tracks.where((t) => _selected.contains(t.id)).toList();
  void _select(int index) {
    final keyboard = HardwareKeyboard.instance;
    setState(() {
      if (_clickShift ?? keyboard.isShiftPressed) {
        final start = _anchor < index ? _anchor : index,
            end = _anchor > index ? _anchor : index;
        for (
          var i = start.clamp(0, widget.tracks.length - 1);
          i <= end && i < widget.tracks.length;
          i++
        ) {
          _selected.add(widget.tracks[i].id);
        }
      } else if (_clickControl ??
          (keyboard.isControlPressed || keyboard.isMetaPressed)) {
        final id = widget.tracks[index].id;
        if (!_selected.add(id)) _selected.remove(id);
        _anchor = index;
      } else {
        _selected
          ..clear()
          ..add(widget.tracks[index].id);
        _anchor = index;
      }
      _clickShift = null;
      _clickControl = null;
    });
    _focus.requestFocus();
  }

  Future<void> _remove() async {
    final tracks = selected;
    if (tracks.isEmpty) return;
    final database = ref.read(tagWriterProvider).database;
    if (widget.onRemoveFromPlaylist != null) {
      await widget.onRemoveFromPlaylist!(tracks);
    } else {
      await database.softDeleteMany(tracks.map((t) => t.id).toList());
      if (mounted) {
        showUndo(
          context,
          'Removed ${tracks.length} tracks.',
          () => database.softDeleteMany(
            tracks.map((t) => t.id).toList(),
            deleted: false,
          ),
        );
      }
    }
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = ref.watch(currentTrackProvider)?.id;
    if (widget.tracks.isEmpty) return Center(child: Text(widget.emptyMessage));
    final chosen = selected;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final showAlbum = widget.showAlbum && constraints.maxWidth >= 900;
        final showRating = constraints.maxWidth >= 760;
        final showTime = constraints.maxWidth >= 400;
        final showFavorite = constraints.maxWidth >= 500;
        _rowExtent = (MediaQuery.textScalerOf(
          context,
        ).scale(compact ? 40 : 34)).clamp(compact ? 58.0 : 54.0, 90.0);
        return Focus(
          focusNode: _focus,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (HardwareKeyboard.instance.isControlPressed &&
                event.logicalKey == LogicalKeyboardKey.keyA) {
              setState(() => _selected.addAll(widget.tracks.map((t) => t.id)));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter &&
                widget.tracks.isNotEmpty) {
              ref
                  .read(playbackControllerProvider)
                  .playFromContext(
                    widget.tracks,
                    _anchor.clamp(0, widget.tracks.length - 1),
                  );
              return KeyEventResult.handled;
            }
            if (!HardwareKeyboard.instance.isControlPressed &&
                (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                    event.logicalKey == LogicalKeyboardKey.arrowDown)) {
              final index =
                  (_anchor +
                          (event.logicalKey == LogicalKeyboardKey.arrowDown
                              ? 1
                              : -1))
                      .clamp(0, widget.tracks.length - 1);
              _select(index);
              if (_scroll.hasClients) {
                _scroll.jumpTo(
                  (index * _rowExtent - _scroll.position.viewportDimension / 2)
                      .clamp(0, _scroll.position.maxScrollExtent),
                );
              }
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.delete) {
              _remove();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              setState(_selected.clear);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            children: [
              if (chosen.isNotEmpty)
                Material(
                  color: colors.surfaceAlt,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        spacing: 8,
                        children: [
                          Text('${chosen.length} selected'),
                          IconButton(
                            tooltip: 'Clear selection',
                            onPressed: () => setState(_selected.clear),
                            icon: const Icon(Icons.close),
                          ),
                          TextButton.icon(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) =>
                                  AddToPlaylistDialog(tracks: chosen),
                            ),
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('Playlist'),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              for (final t in chosen) {
                                ref.read(queueProvider.notifier).addToQueue(t);
                              }
                            },
                            icon: const Icon(Icons.queue_music),
                            label: const Text('Queue'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              for (final t in chosen) {
                                await ref
                                    .read(tagWriterProvider)
                                    .database
                                    .setFavorite(t.id, true);
                              }
                            },
                            icon: const Icon(Icons.favorite),
                            label: const Text('Favorite'),
                          ),
                          TextButton.icon(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => BulkTagEditor(tracks: chosen),
                            ),
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit tags'),
                          ),
                          TextButton.icon(
                            onPressed: _remove,
                            icon: const Icon(Icons.remove_circle_outline),
                            label: const Text('Remove'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(60, 8, 12, 8),
                child: Row(
                  children: [
                    const Expanded(flex: 3, child: Text('Title')),
                    if (!compact)
                      const Expanded(flex: 2, child: Text('Artist')),
                    if (showAlbum)
                      const Expanded(flex: 2, child: Text('Album')),
                    if (showRating)
                      const SizedBox(width: 80, child: Text('Rating')),
                    if (showTime)
                      const SizedBox(width: 60, child: Text('Time')),
                    SizedBox(width: showFavorite ? 80 : 40),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  itemExtent: _rowExtent,
                  itemCount: widget.tracks.length,
                  itemBuilder: (context, index) {
                    final track = widget.tracks[index];
                    final color = track.isMissing
                        ? colors.textFaint
                        : (track.id == current
                              ? colors.accent
                              : colors.textPrimary);
                    Widget label(String text, {int flex = 2}) => Expanded(
                      flex: flex,
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color),
                      ),
                    );
                    return Semantics(
                      selected: _selected.contains(track.id),
                      label:
                          '${track.title}, ${track.artist}${track.isMissing ? ', file missing' : ''}',
                      child: Material(
                        color: _selected.contains(track.id)
                            ? colors.accent.withValues(alpha: 0.13)
                            : Colors.transparent,
                        child: InkWell(
                          onTapDown: (_) {
                            _clickShift =
                                HardwareKeyboard.instance.isShiftPressed;
                            _clickControl =
                                HardwareKeyboard.instance.isControlPressed ||
                                HardwareKeyboard.instance.isMetaPressed;
                          },
                          onTap: () => _select(index),
                          onDoubleTap: track.isMissing
                              ? null
                              : () => ref
                                    .read(playbackControllerProvider)
                                    .playFromContext(widget.tracks, index),
                          onSecondaryTapDown: (d) {
                            if (!_selected.contains(track.id)) {
                              setState(
                                () => _selected
                                  ..clear()
                                  ..add(track.id),
                              );
                            }
                            showTrackActions(
                              context,
                              ref,
                              selected,
                              d.globalPosition,
                              removeFromPlaylist:
                                  widget.onRemoveFromPlaylist == null
                                  ? null
                                  : () =>
                                        widget.onRemoveFromPlaylist!(selected),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Tooltip(
                                    message: track.isMissing
                                        ? 'File missing'
                                        : track.title,
                                    child: ArtThumb(
                                      path: track.coverArtPath,
                                      size: 36,
                                    ),
                                  ),
                                ),
                                if (compact)
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: color),
                                        ),
                                        Text(
                                          track.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: colors.textFaint,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  label(track.title, flex: 3),
                                if (!compact) const SizedBox(width: 8),
                                if (!compact) label(track.artist),
                                if (showAlbum) label(track.album),
                                if (showRating)
                                  SizedBox(
                                    width: 80,
                                    child: PopupMenuButton<int>(
                                      tooltip: 'Rate ${track.title}',
                                      initialValue: track.rating,
                                      onSelected: (rating) async {
                                        final error = await ref
                                            .read(tagWriterProvider)
                                            .apply(
                                              track,
                                              TagEdit(rating: rating),
                                            );
                                        if (error != null && context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(content: Text(error)),
                                          );
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        for (var i = 0; i <= 5; i++)
                                          PopupMenuItem(
                                            value: i,
                                            child: Text(
                                              i == 0 ? 'Unrated' : '$i stars',
                                            ),
                                          ),
                                      ],
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (track.rating == 0)
                                              Icon(
                                                Icons.star_border,
                                                size: 16,
                                                color: colors.textFaint,
                                              )
                                            else
                                              for (
                                                var i = 0;
                                                i < track.rating;
                                                i++
                                              )
                                                Icon(
                                                  Icons.star,
                                                  size: 12,
                                                  color: colors.accent,
                                                ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                if (showTime)
                                  SizedBox(
                                    width: 60,
                                    child: Text(
                                      '${track.durationMs ~/ 60000}:${((track.durationMs ~/ 1000) % 60).toString().padLeft(2, '0')}',
                                      style: TextStyle(color: colors.textFaint),
                                    ),
                                  ),
                                if (showFavorite)
                                  IconButton(
                                    tooltip: track.isFavorite
                                        ? 'Remove favorite'
                                        : 'Favorite',
                                    icon: Icon(
                                      track.isFavorite
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 18,
                                    ),
                                    color: track.isFavorite
                                        ? colors.accent
                                        : colors.textFaint,
                                    onPressed: () => ref
                                        .read(tagWriterProvider)
                                        .database
                                        .setFavorite(
                                          track.id,
                                          !track.isFavorite,
                                        ),
                                  ),
                                Builder(
                                  builder: (buttonContext) => IconButton(
                                    tooltip: 'Track actions',
                                    icon: const Icon(Icons.more_vert),
                                    onPressed: () {
                                      final box =
                                          buttonContext.findRenderObject()
                                              as RenderBox;
                                      showTrackActions(
                                        buttonContext,
                                        ref,
                                        [track],
                                        box.localToGlobal(Offset.zero),
                                        removeFromPlaylist:
                                            widget.onRemoveFromPlaylist == null
                                            ? null
                                            : () =>
                                                  widget.onRemoveFromPlaylist!([
                                                    track,
                                                  ]),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
