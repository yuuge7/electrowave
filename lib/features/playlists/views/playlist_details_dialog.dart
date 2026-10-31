import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/smart_rules.dart';
import '../../../main.dart';

class PlaylistDetailsDialog extends ConsumerStatefulWidget {
  const PlaylistDetailsDialog({super.key, required this.playlist});
  final Playlist playlist;
  @override
  ConsumerState<PlaylistDetailsDialog> createState() =>
      _PlaylistDetailsDialogState();
}

class _PlaylistDetailsDialogState extends ConsumerState<PlaylistDetailsDialog> {
  final _folder = TextEditingController(),
      _genre = TextEditingController(),
      _artist = TextEditingController(),
      _plays = TextEditingController(),
      _rating = TextEditingController(),
      _added = TextEditingController(),
      _year = TextEditingController();
  bool _smart = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _folder.text = widget.playlist.folder ?? '';
    _smart = widget.playlist.rulesJson != null;
    if (_smart) {
      final rules = SmartRules.decode(widget.playlist.rulesJson!);
      _genre.text = rules.genre ?? '';
      _artist.text = rules.artist ?? '';
      _plays.text = '${rules.minimumPlays}';
      _rating.text = '${rules.minimumRating}';
      _added.text = rules.addedSinceYear?.toString() ?? '';
      _year.text = rules.year?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _folder,
      _genre,
      _artist,
      _plays,
      _rating,
      _added,
      _year,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    int? number(TextEditingController c) => int.tryParse(c.text.trim());
    for (final c in [_plays, _rating, _added, _year]) {
      if (c.text.isNotEmpty && (number(c) == null || number(c)! < 0)) {
        setState(() => _error = 'Use non-negative whole numbers.');
        return;
      }
    }
    if ((number(_rating) ?? 0) > 5) {
      setState(() => _error = 'Rating must be between 0 and 5.');
      return;
    }
    final rules = SmartRules(
      genre: text(_genre),
      artist: text(_artist),
      minimumPlays: number(_plays) ?? 0,
      minimumRating: number(_rating) ?? 0,
      addedSinceYear: number(_added),
      year: number(_year),
    );
    final db = ref.read(databaseProvider);
    await (db.update(
      db.playlists,
    )..where((p) => p.id.equals(widget.playlist.id))).write(
      PlaylistsCompanion(
        folder: Value(text(_folder)),
        rulesJson: Value(_smart ? rules.encode() : null),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Organize ${widget.playlist.name}'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _folder,
              decoration: const InputDecoration(
                labelText: 'Playlist folder',
                hintText: 'e.g. Work, Gym',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Smart playlist'),
              subtitle: const Text(
                'Automatically include tracks matching all rules.',
              ),
              value: _smart,
              onChanged: (value) => setState(() => _smart = value),
            ),
            if (_smart) ...[
              for (final entry in <String, TextEditingController>{
                'Genre is': _genre,
                'Artist contains': _artist,
                'Plays at least': _plays,
                'Rating at least (0–5)': _rating,
                'Added in or after year': _added,
                'Release year is': _year,
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: entry.value,
                    decoration: InputDecoration(labelText: entry.key),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Blank rules match everything. Manual members are kept if you switch back to a regular playlist.',
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
