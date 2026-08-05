import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../main.dart';
import '../../../shared/theme/app_theme.dart';
import '../../player/services/metadata_scanner.dart';
import '../providers/library_provider.dart';
import 'browse_views.dart';
import 'track_table.dart';

class LibraryView extends ConsumerWidget {
  const LibraryView({super.key});

  void _showScanSheet(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final database = ref.read(databaseProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.create_new_folder, color: colors.accent),
              title: Text('Scan Entire Folder',
                  style: TextStyle(color: colors.textPrimary)),
              subtitle: Text('Finds all music in a directory',
                  style: TextStyle(color: colors.textFaint, fontSize: 12)),
              onTap: () async {
                Navigator.pop(context);
                await MetadataScanner(database).scanDirectory();
              },
            ),
            ListTile(
              leading: Icon(Icons.queue_music, color: colors.accent),
              title: Text('Add Specific Files',
                  style: TextStyle(color: colors.textPrimary)),
              subtitle: Text('Select individual tracks to add',
                  style: TextStyle(color: colors.textFaint, fontSize: 12)),
              onTap: () async {
                Navigator.pop(context);
                await MetadataScanner(database).scanSpecificFiles();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return TextField(
      style: TextStyle(color: colors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search songs, artists, or albums...',
        hintStyle: TextStyle(color: colors.textFaint),
        prefixIcon: Icon(Icons.search, color: colors.textFaint),
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent, width: 1),
        ),
      ),
      onChanged: (value) =>
          ref.read(searchQueryProvider.notifier).updateQuery(value),
    );
  }

  /// Browse mode + sort + the smart-list chips, all of which reset the
  /// drill-down so the body can never show a stale album.
  Widget _controls(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final mode = ref.watch(libraryBrowseModeProvider);
    final sort = ref.watch(librarySortProvider);
    final smartList = ref.watch(selectedSmartListProvider);

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<LibraryBrowseMode>(
          segments: const [
            ButtonSegment(
                value: LibraryBrowseMode.tracks,
                icon: Icon(Icons.music_note),
                label: Text('Tracks')),
            ButtonSegment(
                value: LibraryBrowseMode.albums,
                icon: Icon(Icons.album),
                label: Text('Albums')),
            ButtonSegment(
                value: LibraryBrowseMode.artists,
                icon: Icon(Icons.person),
                label: Text('Artists')),
            ButtonSegment(
                value: LibraryBrowseMode.folders,
                icon: Icon(Icons.folder),
                label: Text('Folders')),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            ref.read(browseDetailProvider.notifier).close();
            ref.read(selectedSmartListProvider.notifier).select(null);
            ref.read(libraryBrowseModeProvider.notifier).set(selection.first);
          },
        ),
        if (mode == LibraryBrowseMode.tracks && smartList == null)
          PopupMenuButton<db.LibrarySort>(
            tooltip: 'Sort',
            color: colors.surfaceAlt,
            onSelected: (value) =>
                ref.read(librarySortProvider.notifier).set(value),
            itemBuilder: (context) => [
              for (final option in db.LibrarySort.values)
                PopupMenuItem(
                  value: option,
                  child: Row(
                    children: [
                      Icon(
                        option == sort ? Icons.check : Icons.sort,
                        size: 16,
                        color: option == sort ? colors.accent : colors.textFaint,
                      ),
                      const SizedBox(width: 8),
                      Text(librarySortLabel(option),
                          style: TextStyle(color: colors.textSecondary)),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort, size: 16, color: colors.textFaint),
                  const SizedBox(width: 8),
                  Text('Sort: ${librarySortLabel(sort)}',
                      style: TextStyle(color: colors.textSecondary)),
                ],
              ),
            ),
          ),
        for (final list in SmartList.values)
          FilterChip(
            label: Text(smartListLabel(list)),
            selected: smartList == list,
            showCheckmark: false,
            avatar: Icon(
              switch (list) {
                SmartList.favorites => Icons.favorite,
                SmartList.recentlyAdded => Icons.new_releases_outlined,
                SmartList.recentlyPlayed => Icons.history,
                SmartList.mostPlayed => Icons.local_fire_department_outlined,
              },
              size: 16,
              color: smartList == list ? colors.onAccent : colors.textFaint,
            ),
            selectedColor: colors.accent,
            backgroundColor: colors.surface,
            labelStyle: TextStyle(
              color: smartList == list ? colors.onAccent : colors.textSecondary,
            ),
            side: BorderSide(color: colors.border),
            onSelected: (selected) {
              ref.read(browseDetailProvider.notifier).close();
              ref
                  .read(selectedSmartListProvider.notifier)
                  .select(selected ? list : null);
            },
          ),
      ],
    );
  }

  Widget _body(BuildContext context, WidgetRef ref) {
    final smartList = ref.watch(selectedSmartListProvider);
    if (smartList != null) {
      return TrackListPage(
        title: smartListLabel(smartList),
        subtitle: switch (smartList) {
          SmartList.favorites => 'Tracks you hearted',
          SmartList.recentlyAdded => 'Newest in your library',
          SmartList.recentlyPlayed => 'What you played last',
          SmartList.mostPlayed => 'Your most played tracks',
        },
        tracksAsync: ref.watch(smartListTracksProvider(smartList)),
        onBack: () =>
            ref.read(selectedSmartListProvider.notifier).select(null),
      );
    }

    final detail = ref.watch(browseDetailProvider);
    if (detail != null) {
      void close() => ref.read(browseDetailProvider.notifier).close();
      switch (detail.mode) {
        case LibraryBrowseMode.albums:
          return TrackListPage(
            title: detail.key,
            subtitle: 'Album',
            tracksAsync: ref.watch(albumTracksProvider(detail.key)),
            onBack: close,
            showAlbum: false,
          );
        case LibraryBrowseMode.artists:
          return TrackListPage(
            title: detail.key,
            subtitle: 'Artist',
            tracksAsync: ref.watch(artistTracksProvider(detail.key)),
            onBack: close,
          );
        case LibraryBrowseMode.folders:
          return TrackListPage(
            title: detail.key.split(RegExp(r'[/\\]')).last,
            subtitle: detail.key,
            tracksAsync: ref.watch(folderTracksProvider(detail.key)),
            onBack: close,
          );
        case LibraryBrowseMode.tracks:
          ref.read(browseDetailProvider.notifier).close();
      }
    }

    switch (ref.watch(libraryBrowseModeProvider)) {
      case LibraryBrowseMode.albums:
        return const AlbumsGrid();
      case LibraryBrowseMode.artists:
        return const ArtistsList();
      case LibraryBrowseMode.folders:
        return const FoldersList();
      case LibraryBrowseMode.tracks:
        final libraryAsync = ref.watch(libraryProvider);
        return libraryAsync.when(
          data: (tracks) => TrackTable(tracks: tracks),
          loading: () => Center(
              child: CircularProgressIndicator(color: context.colors.accent)),
          error: (err, stack) => Center(
              child:
                  Text('Error: $err', style: const TextStyle(color: Colors.red))),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.accent,
        onPressed: () => _showScanSheet(context, ref),
        child: Icon(Icons.add, color: colors.onAccent),
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 8),
            child: _searchField(context, ref),
          ),
          Padding(
            padding:
                const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _controls(context, ref),
            ),
          ),
          Expanded(child: _body(context, ref)),
        ],
      ),
    );
  }
}
