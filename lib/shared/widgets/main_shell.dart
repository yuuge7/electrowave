import 'package:desktop_drop/desktop_drop.dart';
import '../services/window_state_service.dart';
import '../services/system_media_service.dart';
import '../../features/library/providers/scan_provider.dart';
import '../../features/library/services/file_exchange.dart';
import '../../features/player/views/now_playing_view.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../features/settings/services/backup_service.dart';
import '../../core/local_log.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/navigation_provider.dart';
import '../theme/app_theme.dart';
import '../services/single_instance_service.dart';
import '../services/tray_service.dart';
import '../../features/library/views/library_view.dart';
import '../../features/playlists/views/playlists_view.dart';
import '../../features/stats/views/stats_view.dart';
import '../../features/settings/views/settings_view.dart';
import '../../features/player/providers/player_provider.dart';
import '../../features/player/providers/queue_provider.dart';
import '../../features/player/providers/session_provider.dart';
import '../../features/player/services/audio_engine.dart';
import '../../features/player/services/scrobbling_service.dart';
import 'bottom_player_bar.dart';
import 'queue_panel.dart';

import '../../../main.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with TrayListener {
  AppLifecycleListener? _lifecycleListener;
  late final WindowStateService _window;
  bool _mini = false, _nowPlaying = false, _dragging = false;
  bool _changingMini = false;

  final List<Widget> _screens = [
    const LibraryView(),
    const PlaylistsView(),
    const StatsView(),
    const SettingsView(),
  ];

  @override
  void initState() {
    super.initState();
    _window = ref.read(windowStateServiceProvider);
    HardwareKeyboard.instance.addHandler(_handleHardwareKeys);
    _initTray();
    unawaited(_window.restore());
    ref.read(playbackControllerProvider);
    SingleInstanceService.onFiles = (paths) => _importFiles(paths);
    _initSessionPersistence();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (launchFiles.isNotEmpty) {
        await _importFiles(launchFiles);
        launchFiles = [];
      }
      bool justImported = await checkAndConsumeImportFlag();

      if (justImported && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: context.colors.surface,
            title: Text(
              'Import Successful',
              style: TextStyle(color: context.colors.accent),
            ),
            content: Text(
              'Your database has been loaded!\n\nDid you move your music to a new folder or switch operating systems? (If songs won\'t play, you need to repair the links).',
              style: TextStyle(color: context.colors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Same Location (Skip)',
                  style: TextStyle(color: context.colors.textFaint),
                ),
              ),
              TextButton(
                onPressed: () {
                  // 1. Close the dialog
                  Navigator.pop(context);

                  // 2. Switch the active tab to the Settings view (Index 3)
                  ref.read(navIndexProvider.notifier).set(3);
                },
                child: Text(
                  'New Location (Repair Links)',
                  style: TextStyle(
                    color: context.colors.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeys);
    trayManager.removeListener(this);
    _lifecycleListener?.dispose();
    _window.dispose();
    SingleInstanceService.onFiles = null;
    super.dispose();
  }

  // --- SESSION PERSISTENCE (resume where the user left off) ---

  void _initSessionPersistence() {
    final session = ref.read(sessionControllerProvider);

    // Put the previous session back: track, position, queue, playlist, tab.
    unawaited(session.restore());

    // Closing the window (the X button) asks the app to exit — write the
    // session before that happens. Losing focus / hiding to tray are cheap
    // extra checkpoints; flush() is a no-op when nothing changed.
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        await session.flush();
        await _window.save();
        return AppExitResponse.exit;
      },
      onInactive: () => unawaited(session.flush()),
      onHide: () => unawaited(session.flush()),
      onPause: () => unawaited(session.flush()),
    );
  }

  Future<void> _importFiles(List<String> paths) async {
    final music = <String>[];
    for (final path in paths) {
      if (path.toLowerCase().endsWith('.m3u') ||
          path.toLowerCase().endsWith('.m3u8')) {
        try {
          await FileExchange(ref.read(databaseProvider)).importPlaylist(path);
        } catch (e, st) {
          LocalLog.write(e, st);
        }
      } else {
        music.add(path);
      }
    }
    if (music.isNotEmpty) {
      await ref.read(scanProvider.notifier).importPaths(music);
    }
  }

  Future<void> _toggleMini() async {
    if (_changingMini) return;
    _changingMini = true;
    try {
      final next = !_mini;
      if (next && mounted) setState(() => _mini = true);
      await _window.setMini(next);
      if (mounted) setState(() => _mini = next);
    } finally {
      _changingMini = false;
    }
  }

  void _shortcuts() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: const SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Text(
              'Space                 Play / pause\nCtrl+F                Search library\nLeft / Right          Seek 5 seconds\nCtrl+Left / Right    Previous / next track\nCtrl+Up / Down       Volume up / down\nCtrl+M               Mini player\nCtrl+N                Now playing\nCtrl+A                Select all tracks\nShift+click          Select a range\nCtrl+click            Toggle selection\nEnter                   Play focused track\nDelete                 Remove selected tracks\n?                           This help',
              style: TextStyle(height: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // --- SYSTEM TRAY (hide-to-tray like Spotify) ---

  Future<void> _initTray() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;
    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
      );
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show_window', label: 'Show Electrowave'),
            MenuItem.separator(),
            MenuItem(key: 'play_pause', label: 'Play / Pause'),
            MenuItem(key: 'previous', label: 'Previous'),
            MenuItem(key: 'next', label: 'Next'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Quit'),
          ],
        ),
      );
      trayManager.addListener(this);
      ref.read(trayReadyProvider.notifier).set(true);
    } catch (e) {
      // No tray available (e.g. missing appindicator) — keep the hide
      // button hidden so the window can't become unreachable.
      debugPrint('Tray unavailable: $e');
    }
  }

  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final playbackController = ref.read(playbackControllerProvider);
    // A tray control is the user being present: push back the auto-stop.
    ref.read(audioEngineProvider).noteUserActivity();

    switch (menuItem.key) {
      case 'show_window':
        await windowManager.show();
        await windowManager.focus();
      case 'play_pause':
        playbackController.togglePlayback();
      case 'previous':
        playbackController.playPreviousTrack();
      case 'next':
        playbackController.playNextTrack();
      case 'quit':
        await ref.read(sessionControllerProvider).flush();
        await SingleInstanceService.dispose();
        await trayManager.destroy();
        await windowManager.destroy();
    }
  }

  // --- KEYBOARD SHORTCUTS ---

  bool _isTypingInTextField() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;
    return focusedContext.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _handleHardwareKeys(KeyEvent event) {
    if (event is KeyDownEvent) {
      final mediaKey =
          event.logicalKey == LogicalKeyboardKey.mediaPlayPause ||
          event.logicalKey == LogicalKeyboardKey.mediaTrackNext ||
          event.logicalKey == LogicalKeyboardKey.mediaTrackPrevious;
      if (!mediaKey && ModalRoute.of(context)?.isCurrent == false) return false;
      final player = ref.read(playerProvider);
      final playbackController = ref.read(playbackControllerProvider);
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      ref.read(audioEngineProvider).noteUserActivity();

      if (ctrl && event.logicalKey == LogicalKeyboardKey.keyF) {
        ref.read(navIndexProvider.notifier).set(0);
        setState(() => _nowPlaying = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(searchFocusProvider).requestFocus();
        });
        return true;
      }
      if (!_isTypingInTextField()) {
        if (event.character == '?') {
          _shortcuts();
          return true;
        }
        if (ctrl && event.logicalKey == LogicalKeyboardKey.keyM) {
          _toggleMini();
          return true;
        }
        if (ctrl && event.logicalKey == LogicalKeyboardKey.keyN) {
          setState(() => _nowPlaying = !_nowPlaying);
          return true;
        }
        if (ctrl &&
            (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.arrowDown)) {
          playbackController.setVolume(
            (player.state.volume +
                    (event.logicalKey == LogicalKeyboardKey.arrowUp ? 5 : -5))
                .clamp(0, 100),
          );
          return true;
        }
        if (!ctrl &&
            (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowRight)) {
          final target =
              player.state.position +
              Duration(
                seconds: event.logicalKey == LogicalKeyboardKey.arrowRight
                    ? 5
                    : -5,
              );
          playbackController.seek(
            Duration(
              milliseconds: target.inMilliseconds.clamp(
                0,
                player.state.duration.inMilliseconds,
              ),
            ),
          );
          return true;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
        playbackController.togglePlayback();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.mediaTrackNext) {
        playbackController.playNextTrack();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.mediaTrackPrevious) {
        playbackController.playPreviousTrack();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.space &&
          !_isTypingInTextField()) {
        playbackController.togglePlayback();
        return true;
      } else if (ctrl &&
          event.logicalKey == LogicalKeyboardKey.arrowRight &&
          !_isTypingInTextField()) {
        playbackController.playNextTrack();
        return true;
      } else if (ctrl &&
          event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          !_isTypingInTextField()) {
        playbackController.playPreviousTrack();
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(scrobblingServiceProvider);
    ref.watch(scanProvider);
    ref.watch(systemMediaProvider);
    ref.listen(settingsControllerProvider, (previous, next) {
      if (previous?.backupFolder != next.backupFolder &&
          next.backupFolder != null) {
        unawaited(
          ref
              .read(backupServiceProvider)
              .automaticBackup(next)
              .catchError((Object e, StackTrace st) => LocalLog.write(e, st)),
        );
      }
    });
    final selectedIndex = ref.watch(navIndexProvider);

    final colors = context.colors;

    if (_mini) return Scaffold(body: MiniPlayer(onExpand: _toggleMini));
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        await _importFiles(details.files.map((f) => f.path).toList());
      },
      child: Listener(
        onPointerDown: (_) => ref.read(audioEngineProvider).noteUserActivity(),
        child: Stack(
          children: [
            Scaffold(
              backgroundColor: colors.background,
              body: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final dockQueue = constraints.maxWidth >= 1150;
                        final compactRail = constraints.maxHeight < 480;
                        return Stack(
                          children: [
                            Row(
                              children: [
                                NavigationRail(
                                  selectedIndex: selectedIndex,
                                  onDestinationSelected: (index) {
                                    setState(() => _nowPlaying = false);
                                    ref
                                        .read(navIndexProvider.notifier)
                                        .set(index);
                                  },
                                  backgroundColor: colors.surface,
                                  labelType: compactRail
                                      ? NavigationRailLabelType.none
                                      : NavigationRailLabelType.all,
                                  selectedIconTheme: IconThemeData(
                                    color: colors.accent,
                                  ),
                                  unselectedIconTheme: IconThemeData(
                                    color: colors.textFaint,
                                  ),
                                  selectedLabelTextStyle: Theme.of(context)
                                      .textTheme
                                      .labelMedium!
                                      .copyWith(color: colors.accent),
                                  unselectedLabelTextStyle: Theme.of(context)
                                      .textTheme
                                      .labelMedium!
                                      .copyWith(color: colors.textFaint),
                                  scrollable: true,
                                  trailingAtBottom: true,
                                  trailing: compactRail
                                      ? PopupMenuButton<String>(
                                          tooltip: 'Player options',
                                          icon: const Icon(Icons.more_horiz),
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'now',
                                              child: Text('Now playing'),
                                            ),
                                            PopupMenuItem(
                                              value: 'mini',
                                              child: Text('Mini player'),
                                            ),
                                            PopupMenuItem(
                                              value: 'help',
                                              child: Text('Keyboard shortcuts'),
                                            ),
                                          ],
                                          onSelected: (value) {
                                            switch (value) {
                                              case 'now':
                                                setState(
                                                  () => _nowPlaying =
                                                      !_nowPlaying,
                                                );
                                              case 'mini':
                                                _toggleMini();
                                              case 'help':
                                                _shortcuts();
                                            }
                                          },
                                        )
                                      : Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            IconButton(
                                              tooltip: 'Now playing',
                                              isSelected: _nowPlaying,
                                              onPressed: () => setState(
                                                () =>
                                                    _nowPlaying = !_nowPlaying,
                                              ),
                                              icon: const Icon(
                                                Icons.album_outlined,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Mini player',
                                              onPressed: _toggleMini,
                                              icon: const Icon(
                                                Icons.picture_in_picture_alt,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Keyboard shortcuts',
                                              onPressed: _shortcuts,
                                              icon: const Icon(Icons.keyboard),
                                            ),
                                            const SizedBox(height: 8),
                                          ],
                                        ),
                                  destinations: const [
                                    NavigationRailDestination(
                                      icon: Icon(Icons.library_music),
                                      label: Text('Library'),
                                    ),
                                    NavigationRailDestination(
                                      icon: Icon(Icons.featured_play_list),
                                      label: Text('Playlists'),
                                    ),
                                    NavigationRailDestination(
                                      icon: Icon(Icons.bar_chart),
                                      label: Text('Stats'),
                                    ),
                                    NavigationRailDestination(
                                      icon: Icon(Icons.settings),
                                      label: Text('Settings'),
                                    ),
                                  ],
                                ),

                                Expanded(
                                  child: _nowPlaying
                                      ? NowPlayingView(
                                          onClose: () => setState(
                                            () => _nowPlaying = false,
                                          ),
                                        )
                                      : _screens[selectedIndex],
                                ),

                                // Spotify-style queue side panel
                                if (dockQueue &&
                                    ref.watch(queuePanelVisibleProvider))
                                  const QueuePanel(),
                              ],
                            ),
                            if (!dockQueue &&
                                ref.watch(queuePanelVisibleProvider))
                              const Positioned(
                                top: 0,
                                right: 0,
                                bottom: 0,
                                child: Material(
                                  elevation: 12,
                                  child: QueuePanel(),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),

                  const BottomPlayerBar(),
                ],
              ),
            ),
            if (_dragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: colors.background.withValues(alpha: 0.93),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.library_add, size: 64, color: colors.accent),
                        const SizedBox(height: 16),
                        const Text(
                          'Drop music files, folders or M3U playlists',
                          style: TextStyle(fontSize: 24),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
