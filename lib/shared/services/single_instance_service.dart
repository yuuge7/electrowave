import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

/// Guarantees only one Electrowave instance runs at a time.
///
/// The first instance listens on a local socket (unix domain socket on
/// Linux/macOS, loopback TCP on Windows). A second launch connects to it,
/// sends "SHOW" — which makes the running instance un-hide and focus its
/// window — and then exits.
class SingleInstanceService {
  static const int _windowsPort = 47831;
  static ServerSocket? _server;

  static bool get _supported =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  static String _socketPath() {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    final base = (runtimeDir != null && runtimeDir.isNotEmpty)
        ? runtimeDir
        : Directory.systemTemp.path;
    return p.join(base, 'electrowave.sock');
  }

  static InternetAddress _address() {
    if (Platform.isWindows) return InternetAddress.loopbackIPv4;
    return InternetAddress(_socketPath(), type: InternetAddressType.unix);
  }

  static int get _port => Platform.isWindows ? _windowsPort : 0;

  /// Returns true when this process is the primary instance. Returns false
  /// when another instance is already running — it has been told to show
  /// itself and the caller should exit immediately.
  static Future<bool> ensurePrimary() async {
    if (!_supported) return true;

    try {
      await _bind();
      return true;
    } on SocketException {
      // Either an instance is running, or a stale unix socket file was
      // left behind by a crash.
      if (await _notifyExisting()) return false;

      if (!Platform.isWindows) {
        try {
          File(_socketPath()).deleteSync();
          await _bind();
          return true;
        } catch (e) {
          debugPrint('Single-instance rebind failed: $e');
        }
      }
      // Never block the launch over lock plumbing.
      return true;
    }
  }

  static Future<void> _bind() async {
    _server = await ServerSocket.bind(_address(), _port);
    _server!.listen((client) {
      client.listen((data) async {
        if (utf8.decode(data).trim() == 'SHOW') {
          await windowManager.show();
          await windowManager.focus();
        }
        client.destroy();
      }, onError: (_) => client.destroy());
    });
  }

  /// Tries to tell an already-running instance to show its window.
  static Future<bool> _notifyExisting() async {
    try {
      final socket = await Socket.connect(
        _address(),
        _port,
        timeout: const Duration(seconds: 2),
      );
      socket.add(utf8.encode('SHOW\n'));
      await socket.flush();
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }

  /// Releases the lock socket (call on quit).
  static Future<void> dispose() async {
    await _server?.close();
    _server = null;
    if (!Platform.isWindows) {
      try {
        File(_socketPath()).deleteSync();
      } catch (_) {}
    }
  }
}
