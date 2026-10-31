import 'package:screen_retriever/screen_retriever.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/app_paths.dart';
import '../../core/local_log.dart';
import 'package:path/path.dart' as p;

final windowStateServiceProvider = Provider<WindowStateService>(
  (ref) => WindowStateService(),
);

class WindowStateService with WindowListener {
  Timer? _timer;
  bool mini = false;
  Rect? _normal;
  bool _normalMaximized = false;
  Future<void> _saving = Future.value();
  Future<File> get _file async =>
      File(p.join((await appDataDirectory()).path, 'window.json'));
  Future<void> restore() async {
    try {
      final file = await _file;
      await windowManager.setMinimumSize(const Size(720, 520));
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        await windowManager.setSize(
          Size(
            (json['width'] as num).toDouble().clamp(720, 3000),
            (json['height'] as num).toDouble().clamp(520, 2000),
          ),
        );
        // Center on the active display so unplugged monitors never strand it.
        await windowManager.center();
        final x = (json['x'] as num?)?.toDouble(),
            y = (json['y'] as num?)?.toDouble();
        if (x != null && y != null) {
          final size = await windowManager.getSize();
          final bounds = Rect.fromLTWH(x, y, size.width, size.height);
          final displays = await screenRetriever.getAllDisplays();
          final visible = displays.any((d) {
            final origin = d.visiblePosition ?? Offset.zero;
            final area = d.visibleSize ?? d.size;
            final overlap = bounds.intersect(
              Rect.fromLTWH(origin.dx, origin.dy, area.width, area.height),
            );
            return overlap.width >= 80 && overlap.height >= 80;
          });
          if (visible) await windowManager.setPosition(Offset(x, y));
        }
        if (json['maximized'] == true) await windowManager.maximize();
      }
    } catch (e, st) {
      LocalLog.write(e, st);
    }
    windowManager.addListener(this);
  }

  Future<void> save() {
    _saving = _saving.then((_) => _save());
    return _saving;
  }

  Future<void> _save() async {
    if (mini || await windowManager.isMinimized()) return;
    try {
      final bounds = await windowManager.getBounds();
      final file = await _file;
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'x': bounds.left,
          'y': bounds.top,
          'width': bounds.width,
          'height': bounds.height,
          'maximized': await windowManager.isMaximized(),
        }),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (e, st) {
      LocalLog.write(e, st);
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), save);
  }

  @override
  void onWindowMove() => _schedule();
  @override
  void onWindowResize() => _schedule();
  Future<void> setMini(bool value) async {
    if (value == mini) return;
    if (value) {
      await save();
      _normal = await windowManager.getBounds();
      _normalMaximized = await windowManager.isMaximized();
      mini = true;
      if (await windowManager.isMaximized()) await windowManager.unmaximize();
      await windowManager.setMinimumSize(const Size(360, 160));
      await windowManager.setSize(const Size(460, 200));
      await windowManager.setAlwaysOnTop(true);
    } else {
      mini = false;
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(720, 520));
      if (_normal case final bounds?) await windowManager.setBounds(bounds);
      if (_normalMaximized) await windowManager.maximize();
    }
  }

  void dispose() {
    _timer?.cancel();
    windowManager.removeListener(this);
  }
}
