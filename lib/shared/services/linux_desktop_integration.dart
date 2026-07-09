import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

/// Installs the freedesktop integration files Electrowave needs for its
/// taskbar/launcher icon on Linux.
///
/// Desktop environments map a running window to a .desktop file via the
/// window's app_id (Wayland) / WM_CLASS (X11), which for this app is
/// APPLICATION_ID from linux/CMakeLists.txt. The .desktop file must be
/// named exactly `<app_id>.desktop` or the taskbar shows a generic icon.
class LinuxDesktopIntegration {
  static const _appId = 'com.example.electrowave';

  static Future<void> ensureInstalled() async {
    if (!Platform.isLinux) return;
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;
      final dataHome = Platform.environment['XDG_DATA_HOME'] ??
          p.join(home, '.local', 'share');

      // 1. Icon into the user hicolor theme, named after the app id so
      // Icon= below resolves everywhere (taskbar, launcher, switcher).
      final iconFile = File(p.join(
          dataHome, 'icons', 'hicolor', '512x512', 'apps', '$_appId.png'));
      if (!await iconFile.exists()) {
        await iconFile.parent.create(recursive: true);
        final data = await rootBundle.load('web/music.png');
        await iconFile.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }

      // 2. Desktop entry pointing at the currently running binary.
      final exec = await File('/proc/self/exe').resolveSymbolicLinks();
      final desktopFile =
          File(p.join(dataHome, 'applications', '$_appId.desktop'));

      final exists = await desktopFile.exists();
      // Debug runs may launch from a throwaway bundle; don't let them
      // steal Exec= from an installed release build.
      if (exists && !kReleaseMode) return;

      final content = '''
[Desktop Entry]
Version=1.0
Name=Electrowave
GenericName=Media Player
Comment=Play local music
Exec="$exec"
Icon=$_appId
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Player;
StartupWMClass=$_appId
''';

      if (!exists || await desktopFile.readAsString() != content) {
        await desktopFile.parent.create(recursive: true);
        await desktopFile.writeAsString(content);
        // Best effort; DEs usually pick up the change on their own.
        Process.run('update-desktop-database', [desktopFile.parent.path]);
      }
    } catch (e) {
      debugPrint('Linux desktop integration skipped: $e');
    }
  }
}
