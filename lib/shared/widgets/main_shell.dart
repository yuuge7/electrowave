import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/library/views/library_view.dart';
import '../../features/playlists/views/playlists_view.dart';
import '../../features/stats/views/stats_view.dart'; // Add the new import
import '../../features/settings/views/settings_view.dart';
import '../../features/player/providers/player_provider.dart';
import '../../features/player/services/scrobbling_service.dart';
import 'bottom_player_bar.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _selectedIndex = 0;

  // Add the StatsView to your list of screens
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
                  // Add the new Stats destination here
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