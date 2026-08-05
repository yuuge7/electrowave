import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../shared/theme/app_theme.dart';
import '../services/tag_writer.dart';

/// Fix a track's tags in place. Writes the audio file *and* the library row,
/// so a later rescan won't undo the edit.
class TagEditorDialog extends ConsumerStatefulWidget {
  const TagEditorDialog({super.key, required this.track});

  final db.Track track;

  @override
  ConsumerState<TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends ConsumerState<TagEditorDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.track.title);
  late final TextEditingController _artist =
      TextEditingController(text: widget.track.artist);
  late final TextEditingController _album =
      TextEditingController(text: widget.track.album);
  late final TextEditingController _genre =
      TextEditingController(text: widget.track.genre ?? '');
  late final TextEditingController _trackNumber =
      TextEditingController(text: widget.track.trackNumber?.toString() ?? '');
  late final TextEditingController _discNumber =
      TextEditingController(text: widget.track.discNumber?.toString() ?? '');
  late final TextEditingController _year =
      TextEditingController(text: widget.track.year?.toString() ?? '');

  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _genre.dispose();
    _trackNumber.dispose();
    _discNumber.dispose();
    _year.dispose();
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        style: TextStyle(color: colors.textPrimary),
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        inputFormatters:
            numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: colors.textFaint),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: colors.accent),
          ),
        ),
      ),
    );
  }

  /// Empty means "clear this tag" for text fields the file may not have; an
  /// unchanged field is simply written back as it was.
  Future<void> _save() async {
    setState(() => _saving = true);

    int? parsed(TextEditingController controller) {
      final text = controller.text.trim();
      if (text.isEmpty) return null;
      return int.tryParse(text);
    }

    final edit = TagEdit(
      title: _title.text.trim().isEmpty
          ? widget.track.title
          : _title.text.trim(),
      artist: _artist.text.trim().isEmpty
          ? widget.track.artist
          : _artist.text.trim(),
      album:
          _album.text.trim().isEmpty ? widget.track.album : _album.text.trim(),
      genre: _genre.text.trim(),
      trackNumber: parsed(_trackNumber),
      discNumber: parsed(_discNumber),
      year: parsed(_year),
    );

    final error = await ref.read(tagWriterProvider).apply(widget.track, edit);

    if (!mounted) return;
    Navigator.pop(context);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.orangeAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Edit tags', style: TextStyle(color: colors.textPrimary)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('Title', _title),
              _field('Artist', _artist),
              _field('Album', _album),
              _field('Genre', _genre),
              Row(
                children: [
                  Expanded(
                      child: _field('Track no.', _trackNumber, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field('Disc no.', _discNumber, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Year', _year, numeric: true)),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: colors.textFaint)),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: colors.accent),
                )
              : Text('Save',
                  style: TextStyle(
                      color: colors.accent, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
