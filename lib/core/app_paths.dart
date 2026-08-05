import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Everything Electrowave writes lives in one folder next to the database:
/// `Documents/Electrowave`. Kept in one place so the session file, the
/// settings file and the backup service can never disagree about where it is.
Future<Directory> appDataDirectory() async {
  final docsFolder = await getApplicationDocumentsDirectory();
  final appFolder = Directory(p.join(docsFolder.path, 'Electrowave'));
  if (!await appFolder.exists()) {
    await appFolder.create(recursive: true);
  }
  return appFolder;
}
