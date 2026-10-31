import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../shared/widgets/retry_message.dart';
import '../providers/scan_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/library_provider.dart';
import 'browse_views.dart';
import 'track_table.dart';

final searchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'Library search');
  ref.onDispose(node.dispose);
  return node;
});

final librarySearchControllerProvider = Provider<TextEditingController>((ref) {
  final controller = TextEditingController(text: ref.read(searchQueryProvider));
  ref.listen(searchQueryProvider, (_, query) {
    if (controller.text != query) controller.text = query;
  });
  ref.onDispose(controller.dispose);
  return controller;
});

class LibraryView extends ConsumerWidget {
  const LibraryView({super.key});

  void _showScanSheet(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

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
              title: Text(
                'Scan Entire Folder',
                style: TextStyle(color: colors.textPrimary),
              ),
              subtitle: Text(
                'Finds all music in a directory',
                style: TextStyle(color: colors.textFaint, fontSize: 12),
              ),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(scanProvider.notifier).addFolder();
              },
            ),
            ListTile(
              leading: Icon(Icons.queue_music, color: colors.accent),
              title: Text(
                'Add Specific Files',
                style: TextStyle(color: colors.textPrimary),
              ),
              subtitle: Text(
                'Select individual tracks to add',
                style: TextStyle(color: colors.textFaint, fontSize: 12),
              ),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(scanProvider.notifier).addFiles();
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
      controller: ref.watch(librarySearchControllerProvider),
      focusNode: ref.watch(searchFocusProvider),
      style: TextStyle(color: colors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search songs, artists, or albums...',
        hintStyle: TextStyle(color: colors.textFaint),
        prefixIcon: Icon(Icons.search, color: colors.textFaint),
        suffixIcon: ref.watch(searchQueryProvider).isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () =>
                    ref.read(searchQueryProvider.notifier).updateQuery(''),
              ),
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
    final compact =
        MediaQuery.sizeOf(context).width < 1050 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.2;

    void setMode(LibraryBrowseMode value) {
      ref.read(browseDetailProvider.notifier).close();
      ref.read(selectedSmartListProvider.notifier).select(null);
      ref.read(libraryBrowseModeProvider.notifier).set(value);
    }

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (compact)
          DropdownButton<LibraryBrowseMode>(
            value: mode,
            borderRadius: BorderRadius.circular(8),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            items: [
              for (final value in LibraryBrowseMode.values)
                DropdownMenuItem(
                  value: value,
                  child: Text(switch (value) {
                    LibraryBrowseMode.tracks => 'Tracks',
                    LibraryBrowseMode.albums => 'Albums',
                    LibraryBrowseMode.artists => 'Artists',
                    LibraryBrowseMode.folders => 'Folders',
                    LibraryBrowseMode.genres => 'Genres',
                    LibraryBrowseMode.years => 'Years',
                  }),
                ),
            ],
            onChanged: (value) {
              if (value != null) setMode(value);
            },
          )
        else
          SegmentedButton<LibraryBrowseMode>(
            segments: const [
              ButtonSegment(
                value: LibraryBrowseMode.tracks,
                icon: Icon(Icons.music_note),
                label: Text('Tracks'),
              ),
              ButtonSegment(
                value: LibraryBrowseMode.albums,
                icon: Icon(Icons.album),
                label: Text('Albums'),
              ),
              ButtonSegment(
                value: LibraryBrowseMode.artists,
                icon: Icon(Icons.person),
                label: Text('Artists'),
              ),
              ButtonSegment(
                value: LibraryBrowseMode.folders,
                icon: Icon(Icons.folder),
                label: Text('Folders'),
              ),
              ButtonSegment(
                value: LibraryBrowseMode.genres,
                icon: Icon(Icons.category),
                label: Text('Genres'),
              ),
              ButtonSegment(
                value: LibraryBrowseMode.years,
                icon: Icon(Icons.calendar_today),
                label: Text('Years'),
              ),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              setMode(selection.first);
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
                        color: option == sort
                            ? colors.accent
                            : colors.textFaint,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        librarySortLabel(option),
                        style: TextStyle(color: colors.textSecondary),
                      ),
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
                  Text(
                    'Sort: ${librarySortLabel(sort)}',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        if (compact)
          DropdownButton<SmartList>(
            value: smartList,
            hint: const Text('All tracks'),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            items: [
              const DropdownMenuItem<SmartList>(child: Text('All tracks')),
              for (final list in SmartList.values)
                DropdownMenuItem(
                  value: list,
                  child: Text(smartListLabel(list)),
                ),
            ],
            onChanged: (value) {
              ref.read(browseDetailProvider.notifier).close();
              ref.read(selectedSmartListProvider.notifier).select(value);
              ref
                  .read(libraryBrowseModeProvider.notifier)
                  .set(LibraryBrowseMode.tracks);
            },
          )
        else
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
                color: smartList == list
                    ? colors.onAccent
                    : colors.textSecondary,
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
        onBack: () => ref.read(selectedSmartListProvider.notifier).select(null),
      );
    }

    final detail = ref.watch(browseDetailProvider);
    if (detail != null) {
      void close() => ref.read(browseDetailProvider.notifier).close();
      switch (detail.mode) {
        case LibraryBrowseMode.albums:
          return TrackListPage(
            title: detail.key.split('\u0000').first,
            subtitle: detail.key.split('\u0000').length > 1
                ? detail.key.split('\u0000')[1]
                : 'Album',
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
        case LibraryBrowseMode.genres:
        case LibraryBrowseMode.years:
          return TrackListPage(
            title: detail.key,
            subtitle: detail.mode == LibraryBrowseMode.genres
                ? 'Genre'
                : 'Year',
            tracksAsync: ref.watch(
              categoryTracksProvider((mode: detail.mode, key: detail.key)),
            ),
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
      case LibraryBrowseMode.genres:
      case LibraryBrowseMode.years:
        return const CategoriesList();
      case LibraryBrowseMode.tracks:
        final libraryAsync = ref.watch(libraryProvider);
        return libraryAsync.when(
          data: (tracks) =>
              tracks.isEmpty && ref.watch(searchQueryProvider).isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.library_music_outlined,
                        size: 64,
                        color: context.colors.accent,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Your music. Your library.',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add a folder to begin. Your files stay on this computer.',
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.read(scanProvider.notifier).addFolder(),
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('Add your music folder'),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Drop files or folders into this window. Double-click a track to play.\nCtrl+F searches. Press ? for keyboard shortcuts.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : TrackTable(tracks: tracks),
          loading: () => Center(
            child: CircularProgressIndicator(color: context.colors.accent),
          ),
          error: (err, stack) =>
              RetryMessage(onRetry: () => ref.invalidate(libraryProvider)),
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
        tooltip: 'Add music',
        onPressed: () => _showScanSheet(context, ref),
        child: Icon(Icons.add, color: colors.onAccent),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 24,
              bottom: 8,
            ),
            child: _searchField(context, ref),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: 8,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _controls(context, ref),
            ),
          ),
          if (ref.watch(scanProvider).running)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: ref.watch(scanProvider).total == 0
                        ? null
                        : ref.watch(scanProvider).processed /
                              ref.watch(scanProvider).total,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Scanning ${ref.watch(scanProvider).processed} / ${ref.watch(scanProvider).total}',
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(scanProvider.notifier).cancel(),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(child: _body(context, ref)),
        ],
      ),
    );
  }
}
