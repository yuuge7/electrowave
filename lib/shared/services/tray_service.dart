import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether the system tray icon was successfully created.
/// The "hide to tray" button is only shown when this is true, so the
/// window can never be hidden with no way to bring it back.
class TrayReadyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final trayReadyProvider =
    NotifierProvider<TrayReadyNotifier, bool>(TrayReadyNotifier.new);
