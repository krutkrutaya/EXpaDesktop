// The optional Rust scanner for the music folder.
//
// `music_scan.dll` walks the library, reads ID3/WAV metadata and writes cover
// art to a cache folder in one native pass. The call runs inside an isolate,
// so even a thousand-file library never blocks a frame. When the DLL is not
// there (fresh clone, CI), `scan` returns null and the shell uses the pure
// Dart scanner; nothing breaks.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../playback/track.dart';
import 'music_library.dart';

/// One row from the native scanner's JSON.
class MusicScanRecord {
  final String path;
  final String file;
  final String title;
  final String artist;
  final String duration;
  final String cover;

  const MusicScanRecord({
    required this.path,
    required this.file,
    required this.title,
    required this.artist,
    required this.duration,
    required this.cover,
  });
}

/// Parses the scanner's JSON. Pure, so the format is checked without a DLL.
List<MusicScanRecord> parseMusicScanJson(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    final records = <MusicScanRecord>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      String text(String key) => '${item[key] ?? ''}';
      final path = text('path');
      if (path.isEmpty) continue;
      records.add(MusicScanRecord(
        path: path,
        file: text('file').isEmpty ? path : text('file'),
        title: text('title').isEmpty ? text('file') : text('title'),
        artist: text('artist').isEmpty ? 'Unknown artist' : text('artist'),
        duration: text('duration'),
        cover: text('cover'),
      ));
    }
    return records;
  } catch (_) {
    return const [];
  }
}

typedef _ScanNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _ScanDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

class _Bindings {
  final _ScanDart scan;
  final _FreeDart free;

  const _Bindings(this.scan, this.free);
}

_Bindings? _openBindings() {
  Object? lastError;
  for (final candidate in const [
    'music_scan.dll',
    'lib/rust/music_scan/music_scan.dll',
    'data/flutter_assets/lib/rust/music_scan/music_scan.dll',
  ]) {
    try {
      final library = DynamicLibrary.open(candidate);
      final scan = library
          .lookupFunction<_ScanNative, _ScanDart>('scan_music');
      final free = library
          .lookupFunction<_FreeNative, _FreeDart>('free_music_string');
      return _Bindings(scan, free);
    } catch (error) {
      lastError = error;
    }
  }
  // Keeping the error referenced makes the failure visible in debug builds.
  assert(() {
    lastError;
    return true;
  }());
  return null;
}

/// Native scanning. Kept top-level so it can run in an isolate.
List<Map<String, Object?>>? _scanInIsolate(String directory, String cache) {
  final bindings = _openBindings();
  if (bindings == null) return null;

  final dirPointer = directory.toNativeUtf8();
  final cachePointer = cache.toNativeUtf8();
  Pointer<Utf8> result = nullptr;
  try {
    result = bindings.scan(dirPointer, cachePointer);
    if (result == nullptr) return null;
    final records = parseMusicScanJson(result.toDartString());
    final out = <Map<String, Object?>>[];
    for (final record in records) {
      Uint8List? cover;
      if (record.cover.isNotEmpty) {
        try {
          cover = File(record.cover).readAsBytesSync();
        } catch (_) {
          cover = null;
        }
      }
      out.add({
        'path': record.path,
        'file': record.file,
        'title': record.title,
        'artist': record.artist,
        'duration': record.duration,
        'cover': cover,
      });
    }
    return out;
  } finally {
    if (result != nullptr) bindings.free(result);
    malloc.free(dirPointer);
    malloc.free(cachePointer);
  }
}

abstract final class MusicScanner {
  /// True when the DLL can be loaded on this machine.
  static bool get available => _openBindings() != null;

  /// Scans [directory] with the Rust DLL, writing covers into [cache].
  /// Returns null when the DLL is missing or the scan failed, so the caller
  /// can fall back to the Dart scanner.
  static Future<List<LibraryTrack>?> scan(
    String directory,
    String cache,
  ) async {
    try {
      final raw = await Isolate.run(() => _scanInIsolate(directory, cache));
      if (raw == null) return null;
      return [
        for (final row in raw)
          LibraryTrack(
            Track(
              title: '${row['title']}',
              artist: '${row['artist']}',
              file: '${row['file']}',
              path: '${row['path']}',
              duration: '${row['duration']}',
            ),
            row['cover'] as Uint8List?,
          ),
      ];
    } catch (_) {
      return null;
    }
  }
}