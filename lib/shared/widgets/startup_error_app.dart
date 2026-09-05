import 'dart:io';

import 'package:flutter/material.dart';

/// Shown instead of the player when a native dependency the app cannot run
/// without failed to load.
///
/// The one that actually bites is libmpv on Linux: `package:media_kit` does
/// not bundle it, it dlopens the system copy, and the throw happens inside
/// `main()` before `runApp()`. Unguarded that kills the process with an empty
/// screen and a message only visible to whoever launched the binary from a
/// terminal — which from a desktop launcher reads as "the app doesn't start".
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  /// The package name differs per distribution and the wrong one sends people
  /// down a long detour, so name all three.
  static const _linuxHint = '''
Electrowave plays audio through libmpv, which comes from your distribution:

  Arch / CachyOS   sudo pacman -S mpv
  Debian / Ubuntu  sudo apt install libmpv2   (or libmpv-dev)
  Fedora / RHEL    sudo dnf install mpv-libs

If libmpv is installed somewhere the loader does not look, point at it
directly and relaunch:

  LIBMPV_LIBRARY_PATH=/usr/lib/libmpv.so.2 electrowave
''';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Electrowave',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Electrowave cannot start',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text('The audio engine failed to load.'),
                  const SizedBox(height: 24),
                  SelectableText(
                    message,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12, height: 1.5),
                  ),
                  if (Platform.isLinux) ...[
                    const SizedBox(height: 24),
                    const SelectableText(
                      _linuxHint,
                      style: TextStyle(
                          fontFamily: 'monospace', fontSize: 12, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
