import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

Future<File> writeWav(String path, {int seconds = 1, bool tone = false}) async {
  final bytes = ByteData(44 + 16000 * seconds);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + 16000 * seconds, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, 8000, Endian.little);
  bytes.setUint32(28, 16000, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, 16000 * seconds, Endian.little);
  if (tone) {
    for (var i = 0; i < 8000 * seconds; i++) {
      bytes.setInt16(
        44 + i * 2,
        (sin(i * 2 * pi * 440 / 8000) * 4000).round(),
        Endian.little,
      );
    }
  }
  final file = File(path);
  await file.parent.create(recursive: true);
  return file.writeAsBytes(bytes.buffer.asUint8List());
}
