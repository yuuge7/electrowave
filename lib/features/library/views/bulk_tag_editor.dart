import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/database/app_database.dart';
import '../services/tag_writer.dart';

class BulkTagEditor extends ConsumerStatefulWidget {
  const BulkTagEditor({super.key, required this.tracks});
  final List<Track> tracks;
  @override
  ConsumerState<BulkTagEditor> createState() => _BulkTagEditorState();
}

class _BulkTagEditorState extends ConsumerState<BulkTagEditor> {
  final _fields = {
    for (final name in [
      'Title',
      'Artist',
      'Album',
      'Album artist',
      'Genre',
      'Year',
      'Disc',
    ])
      name: TextEditingController(),
  };
  String? _cover;
  bool _saving = false;
  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    String? text(String key) =>
        _fields[key]!.text.trim().isEmpty ? null : _fields[key]!.text.trim();
    final edit = TagEdit(
      title: text('Title'),
      artist: text('Artist'),
      album: text('Album'),
      albumArtist: text('Album artist'),
      genre: text('Genre'),
      year: int.tryParse(text('Year') ?? ''),
      discNumber: int.tryParse(text('Disc') ?? ''),
      coverImagePath: _cover,
    );
    var warnings = 0;
    try {
      for (final track in widget.tracks) {
        if (await ref.read(tagWriterProvider).apply(track, edit) != null) {
          warnings++;
        }
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              warnings == 0
                  ? 'Tags saved.'
                  : 'Library updated. $warnings files could not have all tags written.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save tags. Check that the files are writable and try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Edit ${widget.tracks.length} tracks'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Only fields you fill in will change. Blank fields keep the existing values.',
            ),
            for (final entry in _fields.entries)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: entry.value,
                  decoration: InputDecoration(labelText: entry.key),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['jpg', 'jpeg', 'png'],
                      );
                      if (result != null && mounted) {
                        setState(() => _cover = result.files.single.path);
                      }
                    },
              icon: const Icon(Icons.image),
              label: Text(
                _cover == null ? 'Choose cover art' : 'Cover art selected',
              ),
            ),
            if (_saving) const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Save tags'),
      ),
    ],
  );
}
