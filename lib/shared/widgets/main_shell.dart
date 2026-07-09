import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../services/tray_service.dart';
import '../../features/library/views/library_view.dart';
import '../../features/playlists/views/playlists_view.dart';
import '../../features/stats/views/stats_view.dart';
import '../../features/settings/views/settings_view.dart';
import '../../features/player/providers/player_provider.dart';
import '../../features/player/services/scrobbling_service.dart';
import 'bottom_player_bar.dart';

// ADDED THIS IMPORT: Adjust the relative path to main.dart if your folder structure requires it!
import '../../../main.dart'; 

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with TrayListener {
  int _selectedIndex = 0;

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

    // ADDED THIS BLOCK: Check for the import flag right after the shell draws
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool justImported = await checkAndConsumeImportFlag();
      
      if (justImported && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF181818),
            title: const Text('Import Successful', style: TextStyle(color: Colors.greenAccent)),
            content: const Text(
              'Your database has been loaded!\n\nDid you move your music to a new folder or switch operating systems? (If songs won\'t play, you need to repair the links).',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Same Location (Skip)', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () {
                  // 1. Close the dialog
                  Navigator.pop(context);
                  
                  // 2. Switch the active tab to the Settings view (Index 3)
                  setState(() {
                    _selectedIndex = 3;
                  });
                },
                child: const Text('New Location (Repair Links)', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
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
    super.dispose();
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

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) => setState(() => _selectedIndex = index),
                  backgroundColor: const Color(0xFF181818),
                  labelType: NavigationRailLabelType.all, 
                  selectedIconTheme: const IconThemeData(color: Colors.greenAccent),
                  unselectedIconTheme: const IconThemeData(color: Colors.grey),
                  selectedLabelTextStyle: const TextStyle(color: Colors.greenAccent),
                  unselectedLabelTextStyle: const TextStyle(color: Colors.grey),
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
                  child: _screens[_selectedIndex],
                ),
              ],
            ),
          ),
          
          const BottomPlayerBar(),
        ],
      ),
    );
  }
}