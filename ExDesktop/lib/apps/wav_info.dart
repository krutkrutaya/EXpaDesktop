// How long a WAV file is, from its header.
//
// A WAV has no ID3 tag, so a dropped file would show "2:00" (the old shell's
// hard-coded fallback) until it finished playing. The RIFF chunks carry the
// byte rate and the data size, which is exactly the duration.

import 'dart:typed_data';

/// Reads the duration of a RIFF/WAVE file. [bytes] may be just the first few
/// kilobytes: both numbers live in the header chunks.
Duration? wavDuration(Uint8List bytes) {
  if (bytes.length < 44) return null;
  final data = ByteData.sublistView(bytes);

  bool tagAt(int offset, String tag) {
    if (offset + 4 > bytes.length) return false;
    for (var i = 0; i < 4; i++) {
      if (bytes[offset + i] != tag.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (!tagAt(0, 'RIFF') || !tagAt(8, 'WAVE')) return null;

  int? byteRate;
  int? dataSize;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final size = data.getUint32(offset + 4, Endian.little);
    if (tagAt(offset, 'fmt ')) {
      // audioFormat(2) channels(2) sampleRate(4) byteRate(4)
      if (offset + 16 > bytes.length) return null;
      byteRate = data.getUint32(offset + 16, Endian.little);
    } else if (tagAt(offset, 'data')) {
      dataSize = size;
      break;
    }
    // Chunks are word-aligned: an odd size has a pad byte.
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }

  if (byteRate == null || byteRate <= 0 || dataSize == null) return null;
  final seconds = dataSize / byteRate;
  if (seconds <= 0 || seconds > 60 * 60 * 24) return null;
  return Duration(milliseconds: (seconds * 1000).round());
}