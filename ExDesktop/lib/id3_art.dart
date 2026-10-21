// The ID3v2 reader behind the track list: title, artist and the cover art
// embedded in the file.
//
// The player used to fall back to the file name and an empty square for every
// mp3 that was not in a hard-coded table. Most files carry their own tags, so
// the list can look right without a table at all.
//
// Pure Dart on purpose: the mock suite feeds it synthetic tags, no music files
// and no plugins needed.

import 'dart:convert';
import 'dart:typed_data';

/// What a track's ID3v2 tag says about itself.
class Id3Tags {
  final String? title;
  final String? artist;
  final Uint8List? cover;

  const Id3Tags({this.title, this.artist, this.cover});

  bool get isEmpty => title == null && artist == null && cover == null;
}

/// Reads ID3v2 tags from [bytes]. Returns null when there is no tag at all.
/// A malformed tag never throws: the player just falls back to the file name.
Id3Tags? parseId3(Uint8List? bytes) {
  if (bytes == null || bytes.length < 10) return null;
  if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) return null; // "ID3"

  final version = bytes[3];
  if (version < 2 || version > 4) return null;
  final flags = bytes[5];
  final tagSize = _syncSafe(bytes, 6);
  if (tagSize <= 0) return null;

  var offset = 10;
  final end = (10 + tagSize).clamp(0, bytes.length);

  // ID3v2.3/2.4 may carry an extended header before the frames.
  if ((flags & 0x40) != 0) {
    if (offset + 4 > end) return null;
    final extended = version == 4 ? _syncSafe(bytes, offset) : _be32(bytes, offset);
    offset += 4 + extended;
  }

  String? title;
  String? artist;
  Uint8List? cover;

  while (offset < end) {
    final frame = _readFrame(bytes, offset, end, version);
    if (frame == null) break;
    offset = frame.next;

    switch (frame.id) {
      case 'TIT2':
      case 'TT2':
        title ??= frame.text;
      case 'TPE1':
      case 'TP1':
        artist ??= frame.text;
      case 'APIC':
      case 'PIC':
        cover ??= frame.cover;
    }
    if (title != null && artist != null && cover != null) break;
  }

  final tags = Id3Tags(title: title, artist: artist, cover: cover);
  return tags.isEmpty ? null : tags;
}

class _Frame {
  final String id;
  final String? text;
  final Uint8List? cover;
  final int next;

  const _Frame({
    required this.id,
    required this.next,
    this.text,
    this.cover,
  });
}

_Frame? _readFrame(Uint8List b, int at, int end, int version) {
  final idLength = version == 2 ? 3 : 4;
  final headerLength = version == 2 ? 6 : 10;
  if (at + headerLength > end) return null;

  final id = String.fromCharCodes(b, at, at + idLength);
  if (id.codeUnits.every((c) => c == 0)) return null; // padding
  if (!RegExp(r'^[A-Z0-9]{3,4}$').hasMatch(id)) return null;

  final size = version == 2
      ? (b[at + 3] << 16) | (b[at + 4] << 8) | b[at + 5]
      : (version == 4 ? _syncSafe(b, at + 4) : _be32(b, at + 4));
  if (size <= 0) return null;

  final start = at + headerLength;
  final stop = start + size;
  if (stop > end || stop > b.length) return null;

  final body = Uint8List.sublistView(b, start, stop);
  final next = stop;

  if (id == 'APIC' || id == 'PIC') {
    return _Frame(id: id, next: next, cover: _picture(body, version));
  }
  if (id.startsWith('T')) {
    return _Frame(id: id, next: next, text: _text(body));
  }
  return _Frame(id: id, next: next);
}

/// The body of APIC/PIC: encoding, mime, picture type, description, data.
Uint8List? _picture(Uint8List body, int version) {
  if (body.isEmpty) return null;
  final encoding = body[0];
  var at = 1;

  if (version == 2) {
    // PIC stores a 3-byte image format ("JPG"/"PNG") instead of a mime type.
    at += 3;
  } else {
    while (at < body.length && body[at] != 0) {
      at++;
    }
    at++; // the null after the mime type
  }

  if (at >= body.length) return null;
  at++; // picture type

  // The description is encoded too: UTF-16 descriptions end on a double null.
  final wide = encoding == 1 || encoding == 2;
  if (wide) {
    while (at + 1 < body.length && !(body[at] == 0 && body[at + 1] == 0)) {
      at += 2;
    }
    at += 2;
  } else {
    while (at < body.length && body[at] != 0) {
      at++;
    }
    at++;
  }

  if (at >= body.length) return null;
  return Uint8List.sublistView(body, at);
}

/// The text of a T*** frame, honouring its first-byte encoding.
String? _text(Uint8List body) {
  if (body.length < 2) return null;
  final encoding = body[0];
  final data = Uint8List.sublistView(body, 1);
  try {
    final String value;
    switch (encoding) {
      case 0:
        value = latin1.decode(data);
      case 1:
        value = _utf16(data, littleEndian: true);
      case 2:
        value = _utf16(data, littleEndian: false);
      case 3:
        value = utf8.decode(data, allowMalformed: true);
      default:
        value = latin1.decode(data);
    }
    final trimmed = value.replaceAll('\u0000', '').trim();
    return trimmed.isEmpty ? null : trimmed;
  } catch (_) {
    return null;
  }
}

String _utf16(Uint8List data, {required bool littleEndian}) {
  var start = 0;
  var little = littleEndian;
  if (data.length >= 2) {
    if (data[0] == 0xFF && data[1] == 0xFE) {
      start = 2;
      little = true;
    } else if (data[0] == 0xFE && data[1] == 0xFF) {
      start = 2;
      little = false;
    }
  }
  final units = <int>[];
  for (var i = start; i + 1 < data.length; i += 2) {
    units.add(little
        ? data[i] | (data[i + 1] << 8)
        : (data[i] << 8) | data[i + 1]);
  }
  return String.fromCharCodes(units);
}

int _be32(Uint8List b, int at) =>
    (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

/// ID3 sizes are "syncsafe": 7 bits per byte, the high bit is always clear.
int _syncSafe(Uint8List b, int at) =>
    ((b[at] & 0x7F) << 21) |
    ((b[at + 1] & 0x7F) << 14) |
    ((b[at + 2] & 0x7F) << 7) |
    (b[at + 3] & 0x7F);