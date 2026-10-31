import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'app_paths.dart';

class LocalLog {
  static Future<void> _pending = Future.value();
  static Future<Directory> directory() async {
    final dir = Directory(p.join((await appDataDirectory()).path, 'logs'));
    return dir.create(recursive: true);
  }

  static void write(Object error, [StackTrace? stack]) {
    _pending = _pending
        .then((_) async {
          final dir = await directory();
          final file = File(p.join(dir.path, 'electrowave.log'));
          if (await file.exists() && await file.length() > 1024 * 1024) {
            for (var i = 2; i >= 0; i--) {
              final old = File(i == 0 ? file.path : '${file.path}.$i');
              if (await old.exists()) {
                final next = File('${file.path}.${i + 1}');
                if (await next.exists()) await next.delete();
                await old.rename(next.path);
              }
            }
          }
          await file.writeAsString(
            '${DateTime.now().toIso8601String()} $error\n${stack ?? ''}\n',
            mode: FileMode.append,
            flush: true,
          );
        })
        .catchError((Object e) {
          debugPrint('Could not write local log: $e');
        });
  }

  static Future<void> flush() => _pending;
}
