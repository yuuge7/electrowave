import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

int? readId3Rating(File file) {
  final reader = file.openSync();
  try {
    final header = reader.readSync(10);
    if (header.length < 10 ||
        latin1.decode(header.sublist(0, 3)) != 'ID3' ||
        ![3, 4].contains(header[3])) {
      return null;
    }
    int sync(List<int> bytes) =>
        bytes.fold(0, (int n, b) => (n << 7) | (b & 127));
    final size = sync(header.sublist(6, 10));
    if (size > 32 * 1024 * 1024 || size + 10 > reader.lengthSync()) return null;
    final bytes = reader.readSync(size);
    var offset = 0;
    if ((header[5] & 64) != 0 && bytes.length >= 4) {
      offset = header[3] == 4
          ? sync(bytes.sublist(0, 4))
          : ByteData.sublistView(bytes).getUint32(0) + 4;
    }
    while (offset + 10 <= bytes.length) {
      final name = latin1.decode(bytes.sublist(offset, offset + 4));
      final size = header[3] == 4
          ? sync(bytes.sublist(offset + 4, offset + 8))
          : ByteData.sublistView(bytes).getUint32(offset + 4);
      if (size <= 0 || offset + 10 + size > bytes.length) return null;
      if (name == 'POPM') {
        final end = offset + 10 + size;
        for (var i = offset + 10; i < end - 1; i++) {
          if (bytes[i] == 0) return bytes[i + 1];
        }
      }
      offset += 10 + size;
    }
    return null;
  } finally {
    reader.closeSync();
  }
}

/// Patch ID3 frames while preserving every unrelated frame and the original
/// audio bytes. The upstream writer prepends tags and omits POPM, so ratings
/// need this small container-level writer (audio is never decoded/re-encoded).
void writeId3Tags(
  String path, {
  Map<String, String> textFrames = const {},
  int? rating,
  List<int>? artwork,
  String mime = 'image/jpeg',
}) {
  final input = File(path).openSync();
  final output = File('$path.id3');
  RandomAccessFile? writer;
  try {
    final header = input.readSync(10);
    final hasTag =
        header.length == 10 && latin1.decode(header.sublist(0, 3)) == 'ID3';
    final version = hasTag ? header[3] : 4;
    if (version != 3 && version != 4) {
      throw UnsupportedError('Only ID3v2.3 and ID3v2.4 can be edited safely');
    }
    if (hasTag && (header[5] & 0x80) != 0) {
      throw UnsupportedError('Unsynchronized ID3 tags are read-only');
    }
    int syncSize(List<int> bytes) =>
        bytes.fold(0, (int size, byte) => (size << 7) | (byte & 127));
    List<int> sizeBytes(int length, {bool sync = false}) => sync
        ? [
            (length >> 21) & 127,
            (length >> 14) & 127,
            (length >> 7) & 127,
            length & 127,
          ]
        : [
            (length >> 24) & 255,
            (length >> 16) & 255,
            (length >> 8) & 255,
            length & 255,
          ];
    var audioOffset = 0;
    final kept = BytesBuilder();
    if (hasTag) {
      final length = syncSize(header.sublist(6, 10));
      if (length > 32 * 1024 * 1024 || length + 10 > input.lengthSync()) {
        throw const FormatException('Invalid ID3 tag length');
      }
      final body = input.readSync(length);
      audioOffset =
          10 + length + ((version == 4 && (header[5] & 16) != 0) ? 10 : 0);
      var offset = 0;
      if ((header[5] & 64) != 0 && body.length >= 4) {
        final length = version == 4
            ? syncSize(body.sublist(0, 4))
            : ByteData.sublistView(body).getUint32(0) + 4;
        offset = length;
      }
      final replaced = {
        ...textFrames.keys,
        if (rating != null) 'POPM',
        if (artwork != null) 'APIC',
      };
      while (offset + 10 <= body.length) {
        final name = latin1.decode(body.sublist(offset, offset + 4));
        if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(name)) break;
        final length = version == 4
            ? syncSize(body.sublist(offset + 4, offset + 8))
            : ByteData.sublistView(body).getUint32(offset + 4);
        if (length < 0 || offset + 10 + length > body.length) {
          throw const FormatException('Invalid ID3 frame length');
        }
        if (!replaced.contains(name)) {
          kept.add(body.sublist(offset, offset + 10 + length));
        }
        offset += 10 + length;
      }
      // Remove duplicate consecutive tags left by older Electrowave versions.
      while (audioOffset + 10 <= input.lengthSync()) {
        input.setPositionSync(audioOffset);
        final next = input.readSync(10);
        if (latin1.decode(next.sublist(0, 3)) != 'ID3') break;
        final length = syncSize(next.sublist(6, 10));
        if (audioOffset + 10 + length > input.lengthSync()) break;
        audioOffset +=
            10 + length + ((next[3] == 4 && (next[5] & 16) != 0) ? 10 : 0);
      }
    }
    void frame(String name, List<int> value) {
      kept.add(latin1.encode(name));
      kept.add(sizeBytes(value.length, sync: version == 4));
      kept.add([0, 0]);
      kept.add(value);
    }

    for (final entry in textFrames.entries) {
      if (entry.value.isEmpty) continue;
      if (version == 4) {
        frame(entry.key, [3, ...utf8.encode(entry.value)]);
      } else {
        final bytes = <int>[1, 255, 254];
        for (final unit in entry.value.codeUnits) {
          bytes.addAll([unit & 255, unit >> 8]);
        }
        frame(entry.key, bytes);
      }
    }
    if (rating != null) {
      frame('POPM', [
        ...ascii.encode('rating@electrowave'),
        0,
        [0, 1, 64, 128, 196, 255][rating.clamp(0, 5)],
        0,
        0,
        0,
        0,
      ]);
    }
    if (artwork != null) {
      frame('APIC', [0, ...ascii.encode(mime), 0, 3, 0, ...artwork]);
    }
    final body = kept.takeBytes();
    writer = output.openSync(mode: FileMode.write);
    writer.writeFromSync([
      73,
      68,
      51,
      version,
      0,
      0,
      ...sizeBytes(body.length, sync: true),
    ]);
    writer.writeFromSync(body);
    input.setPositionSync(audioOffset);
    while (input.positionSync() < input.lengthSync()) {
      writer.writeFromSync(input.readSync(65536));
    }
    writer.flushSync();
    writer.closeSync();
    writer = null;
    input.closeSync();
    output.renameSync(path);
  } finally {
    writer?.closeSync();
    try {
      input.closeSync();
    } catch (_) {
      /* Already closed before rename. */
    }
    if (output.existsSync()) output.deleteSync();
  }
}

/// The tag reader merges MP4's artist and album-artist atoms. Read just these
/// small metadata atoms, seeking past audio rather than loading the whole file.
Map<String, String> readMp4Identity(File file) {
  final result = <String, String>{};
  final reader = file.openSync();
  try {
    void walk(int start, int end, int depth) {
      if (depth > 8) return;
      var offset = start;
      while (offset + 8 <= end) {
        reader.setPositionSync(offset);
        final header = reader.readSync(8);
        if (header.length < 8) return;
        final data = ByteData.sublistView(header);
        var length = data.getUint32(0);
        var prefix = 8;
        final type = latin1.decode(header.sublist(4));
        if (length == 1) {
          final extra = reader.readSync(8);
          if (extra.length != 8) return;
          length = ByteData.sublistView(extra).getUint64(0);
          prefix = 16;
        } else if (length == 0) {
          length = end - offset;
        }
        if (length < prefix || offset + length > end) return;
        if (['moov', 'udta', 'ilst'].contains(type)) {
          walk(offset + prefix, offset + length, depth + 1);
        } else if (type == 'meta') {
          walk(offset + prefix + 4, offset + length, depth + 1);
        } else if (['aART', '©ART', 'cpil'].contains(type) && length <= 65536) {
          reader.setPositionSync(offset + prefix);
          final payload = reader.readSync(length - prefix);
          if (payload.length >= 16 &&
              latin1.decode(payload.sublist(4, 8)) == 'data') {
            result[type] = type == 'cpil'
                ? '${payload.last}'
                : utf8
                      .decode(payload.sublist(16), allowMalformed: true)
                      .replaceAll('\u0000', '');
          }
        }
        offset += length;
      }
    }

    walk(0, reader.lengthSync(), 0);
  } finally {
    reader.closeSync();
  }
  return result;
}
