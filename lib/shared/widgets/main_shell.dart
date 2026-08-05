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

// ADDED THIS IMPORT: Adjust the relative path to main.dart if your folder structure requires it!
import '../../../main.dart'; 

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with TrayListener {
  AppLifecycleListener? _lifecycleListener;

  final List<Widget> _screens = [
    const LibraryView(),
    const PlaylistsView(), 
    const StatsView(),
    const SettingsView(),
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKeys);
    _initTray();
    _initSessionPersistence();

    // ADDED THIS BLOCK: Check for the import flag right after the shell draws
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool justImported = await checkAndConsumeImportFlag();

      if (justImported && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: context.colors.surface,
            title: Text('Import Successful',
                style: TextStyle(color: context.colors.accent)),
            content: Text(
              'Your database has been loaded!\n\nDid you move your music to a new folder or switch operating systems? (If songs won\'t play, you need to repair the links).',
              style: TextStyle(color: context.colors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Same Location (Skip)',
                    style: TextStyle(color: context.colors.textFaint)),
              ),
              TextButton(
                onPressed: () {
                  // 1. Close the dialog
                  Navigator.pop(context);
                  
                  // 2. Switch the active tab to the Settings view (Index 3)
                  ref.read(navIndexProvider.notifier).set(3);
                },
                child: Text('New Location (Repair Links)',
                    style: TextStyle(
                        color: context.colors.accent,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          )
        );
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeys);
    trayManager.removeListener(this);
    _lifecycleListener?.dispose();
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
        return AppExitResponse.exit;
      },
      onInactive: () => unawaited(session.flush()),
      onHide: () => unawaited(session.flush()),
      onPause: () => unawaited(session.flush()),
    );
  }

  // --- SYSTEM TRAY (hide-to-tray like Spotify) ---

  Future<void> _initTray() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;
    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
      );
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show_window', label: 'Show Electrowave'),
        MenuItem.separator(),
        MenuItem(key: 'play_pause', label: 'Play / Pause'),
        MenuItem(key: 'previous', label: 'Previous'),
        MenuItem(key: 'next', label: 'Next'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit'),
      ]));
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
    final player = ref.read(playerProvider);
    final playbackController = ref.read(playbackControllerProvider);
    // A tray control is the user being present: push back the auto-stop.
    ref.read(audioEngineProvider).noteUserActivity();

    switch (menuItem.key) {
      case 'show_window':
        await windowManager.show();
        await windowManager.focus();
      case 'play_pause':
        player.state.playing ? player.pause() : player.play();
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
      final player = ref.read(playerProvider);
      final playbackController = ref.read(playbackControllerProvider);
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      ref.read(audioEngineProvider).noteUserActivity();

      if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
        player.state.playing ? player.pause() : player.play();
        return true;
      }
      else if (event.logicalKey == LogicalKeyboardKey.mediaTrackNext) {
        playbackController.playNextTrack();
        return true;
      }
      else if (event.logicalKey == LogicalKeyboardKey.mediaTrackPrevious) {
        playbackController.playPreviousTrack();
        return true;
      }
      else if (event.logicalKey == LogicalKeyboardKey.space && !_isTypingInTextField()) {
        player.state.playing ? player.pause() : player.play();
        return true;
      }
      else if (ctrl && event.logicalKey == LogicalKeyboardKey.arrowRight && !_isTypingInTextField()) {
        playbackController.playNextTrack();
        return true;
      }
      else if (ctrl && event.logicalKey == LogicalKeyboardKey.arrowLeft && !_isTypingInTextField()) {
        playbackController.playPreviousTrack();
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(scrobblingServiceProvider);
    final selectedIndex = ref.watch(navIndexProvider);

    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) =>
                      ref.read(navIndexProvider.notifier).set(index),
                  backgroundColor: colors.surface,
                  labelType: NavigationRailLabelType.all,
                  selectedIconTheme: IconThemeData(color: colors.accent),
                  unselectedIconTheme: IconThemeData(color: colors.textFaint),
                  selectedLabelTextStyle: TextStyle(color: colors.accent),
                  unselectedLabelTextStyle: TextStyle(color: colors.textFaint),
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
                  child: _screens[selectedIndex],
                ),

                // Spotify-style queue side panel
                if (ref.watch(queuePanelVisibleProvider)) const QueuePanel(),
              ],
            ),
          ),
          
          const BottomPlayerBar(),
        ],
      ),
    );
  }
}