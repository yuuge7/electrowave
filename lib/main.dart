import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';

import 'core/database/app_database.dart';
import 'shared/widgets/main_shell.dart';

// Global database instance provided via Riverpod
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize native media playback engine
  MediaKit.ensureInitialized();
  
  // Initialize Rust-based metadata extraction
  MetadataGod.initialize();

  runApp(
    const ProviderScope(
      child: LocalPlayerApp(),
    ),
  );
}

class LocalPlayerApp extends StatelessWidget {
  const LocalPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Electrowave',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.greenAccent,
        useMaterial3: true,
      ),
      // This now correctly points to the MainShell layout
      home: const MainShell(), 
    );
  }
}