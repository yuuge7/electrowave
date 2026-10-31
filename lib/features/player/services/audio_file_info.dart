import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

String describeAudioFile(String path) {
  final file = File(path);
  final metadata = readMetadata(file, getImage: false);
  int? depth;
  int? bitrate = metadata.bitrate;
  final reader = file.openSync();
  try {
    final head = reader.readSync(12);
    String text(List<int> bytes) => String.fromCharCodes(bytes);
    if (head.length >= 12 && text(head.sublist(0, 4)) == 'fLaC') {
      reader.setPositionSync(8);
      final info = reader.readSync(34);
      if (info.length == 34) {
        depth = (((info[12] & 1) << 4) | (info[13] >> 4)) + 1;
      }
    } else if (head.length == 12 &&
        ['RIFF', 'FORM'].contains(text(head.sublist(0, 4)))) {
      final wave = text(head.sublist(0, 4)) == 'RIFF';
      var offset = 12;
      while (offset + 8 <= reader.lengthSync()) {
        reader.setPositionSync(offset);
        final chunk = reader.readSync(8);
        final size = ByteData.sublistView(
          chunk,
        ).getUint32(4, wave ? Endian.little : Endian.big);
        if (offset + 8 + size > reader.lengthSync()) break;
        if (wave && text(chunk.sublist(0, 4)) == 'fmt ' && size >= 16) {
          reader.setPositionSync(offset + 8);
          final format = ByteData.sublistView(reader.readSync(16));
          depth = format.getUint16(14, Endian.little);
          bitrate = format.getUint32(8, Endian.little) * 8;
          break;
        }
        if (!wave && text(chunk.sublist(0, 4)) == 'COMM' && size >= 8) {
          reader.setPositionSync(offset + 8 + 6);
          depth = ByteData.sublistView(
            reader.readSync(2),
          ).getUint16(0, Endian.big);
          break;
        }
        offset += 8 + size + (size.isOdd ? 1 : 0);
      }
    }
  } finally {
    reader.closeSync();
  }
  final rate = metadata.sampleRate;
  if (p.extension(path).toLowerCase() == '.flac' &&
      (metadata.duration?.inMilliseconds ?? 0) > 0) {
    bitrate = (file.lengthSync() * 8000 / metadata.duration!.inMilliseconds)
        .round();
  }
  return [
    p.extension(path).replaceFirst('.', '').toUpperCase(),
    if (rate != null) '${rate / 1000} kHz',
    if (depth != null) '$depth-bit',
    if (bitrate != null) '${(bitrate / 1000).round()} kb/s',
  ].join(' · ');
}
