import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _MainShellState extends ConsumerState<MainShell> {
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
    super.dispose();
  }

  bool _handleHardwareKeys(KeyEvent event) {
    if (event is KeyDownEvent) {
      final player = ref.read(playerProvider);
      final playbackController = ref.read(playbackControllerProvider);

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