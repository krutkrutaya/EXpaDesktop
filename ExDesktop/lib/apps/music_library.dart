// The user's own music folder, inside the shell.
//
// Bundled tracks live in the app's assets; tracks the user adds with the
// in-app file picker are copied into `%APPDATA%\EXpaDesktop\Music`, so moving
// or deleting the original never breaks the library. The folder is the
// library: scanning it on startup is enough, no index file to fall out of
// sync.
//
// Pure Dart (dart:io + the ID3 reader): the mock suite scans a temp folder
// with synthetic files, no audio device involved.

import 'dart:io';
import 'dart:typed_data';

import '../id3_art.dart';
import '../playback/track.dart';
import 'wav_info.dart';

/// Every extension the player accepts. `audioplayers` on Windows goes through
/// Media Foundation, which handles all of these.
const Set<String> audioExtensions = {
  'mp3',
  'wav',
  'flac',
  'ogg',
  'oga',
  'm4a',
  'aac',
  'wma',
  'opus',
  'aiff',
  'aif',
};

/// True when [path] looks like an audio file we can play.
bool isAudioPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return false;
  return audioExtensions.contains(path.substring(dot + 1).toLowerCase());
}

/// One scanned file: the track and the cover bytes found in its tags.
class LibraryTrack {
  final Track track;
  final Uint8List? cover;

  const LibraryTrack(this.track, this.cover);
}

/// `my_cool-song.mp3` -> `My Cool Song`.
String titleFromFileName(String path) {
  final name = path
      .replaceAll('/', Platform.pathSeparator)
      .replaceAll('\\', Platform.pathSeparator)
      .split(Platform.pathSeparator)
      .last;
  final stem = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
  final words = stem
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase());
  final title = words.join(' ');
  return title.isEmpty ? name : title;
}

/// The music library on disk.
class MusicLibrary {
  MusicLibrary({String? root}) : _root = root;

  final String? _root;

  /// `%APPDATA%\EXpaDesktop` by default.
  String get rootDir {
    final explicit = _root;
    if (explicit != null) return explicit;
    final appData = Platform.environment['APPDATA'];
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final base = (appData == null || appData.isEmpty) ? home : appData;
    return '$base${Platform.pathSeparator}EXpaDesktop';
  }

  String get musicDir => '$rootDir${Platform.pathSeparator}Music';
  String get coverCacheDir => '$rootDir${Platform.pathSeparator}cover-cache';

  /// Copies [sourcePath] into the library. Returns the destination, or null
  /// when the file is not audio or cannot be read.
  Future<String?> import(String sourcePath) async {
    if (!isAudioPath(sourcePath)) return null;
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return null;
      await Directory(musicDir).create(recursive: true);
      final destination = uniqueDestination(sourcePath);
      await source.copy(destination);
      return destination;
    } catch (_) {
      return null;
    }
  }

  /// `Song.mp3` -> `Song (2).mp3` when the name is taken.
  String uniqueDestination(String sourcePath) {
    final name = sourcePath
        .replaceAll('\\', Platform.pathSeparator)
        .split(Platform.pathSeparator)
        .last;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    var candidate = '$musicDir${Platform.pathSeparator}$name';
    var counter = 2;
    while (File(candidate).existsSync()) {
      candidate =
          '$musicDir${Platform.pathSeparator}$stem ($counter)$extension';
      counter++;
    }
    return candidate;
  }

  /// Whether the library folder holds anything.
  bool get hasFolder => Directory(musicDir).existsSync();

  /// Deletes a file from the library. Returns false when the file was not
  /// there or could not be removed.
  bool delete(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      file.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Scans [musicDir] synchronously. Used by the fallback path and by the
  /// tests; the app runs it in an isolate so the UI never blocks.
  List<LibraryTrack> scanSync() => scanMusicDirectory(musicDir);
}

/// Scans a folder for audio files. Top-level so it can run inside an isolate.
List<LibraryTrack> scanMusicDirectory(String directory) {
  final folder = Directory(directory);
  if (!folder.existsSync()) return const [];

  final tracks = <LibraryTrack>[];
  final files = <File>[];
  try {
    for (final entity in folder.listSync(recursive: true, followLinks: false)) {
      if (entity is File && isAudioPath(entity.path)) files.add(entity);
    }
  } catch (_) {
    return const [];
  }
  files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

  for (final file in files) {
    try {
      tracks.add(readLibraryTrack(file, directory));
    } catch (_) {
      // One unreadable file must not take the folder down.
    }
  }
  return tracks;
}

/// Reads one file into a [LibraryTrack]. The relative path is the stable key.
LibraryTrack readLibraryTrack(File file, String root) {
  final relative = file.path
      .replaceAll('\\', '/')
      .replaceFirst(
        '${root.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '')}/',
        '',
      );

  var title = titleFromFileName(file.path);
  var artist = 'Unknown artist';
  String? duration;
  Uint8List? cover;

  final extension = relative.contains('.')
      ? relative.substring(relative.lastIndexOf('.') + 1).toLowerCase()
      : '';

  if (extension == 'mp3') {
    final tagBytes = readId3Prefix(file);
    if (tagBytes != null) {
      final tags = parseId3(tagBytes);
      if (tags != null) {
        if (tags.title != null) title = tags.title!;
        if (tags.artist != null) artist = tags.artist!;
        if (tags.cover != null) cover = tags.cover;
      }
    }
  } else if (extension == 'wav') {
    try {
      final handle = file.openSync();
      final header = handle.readSync(64 * 1024);
      handle.closeSync();
      final parsed = wavDuration(header);
      if (parsed != null) duration = _format(parsed);
    } catch (_) {
      // A broken WAV still gets listed; the player will report the truth.
    }
  }

  return LibraryTrack(
    Track(
      title: title,
      artist: artist,
      file: relative,
      path: file.path,
      duration: duration ?? '',
    ),
    cover,
  );
}

/// The ID3 tag at the start of an mp3, without reading a whole album track.
Uint8List? readId3Prefix(File file, {int maxBytes = 8 * 1024 * 1024}) {
  RandomAccessFile? handle;
  try {
    handle = file.openSync();
    final header = handle.readSync(10);
    if (header.length < 10 || header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
      return null;
    }
    // Syncsafe integer: 7 bits per byte.
    final size = (header[6] & 0x7F) << 21 |
        (header[7] & 0x7F) << 14 |
        (header[8] & 0x7F) << 7 |
        (header[9] & 0x7F);
    final total = (10 + size).clamp(10, maxBytes);
    handle.setPositionSync(0);
    return handle.readSync(total);
  } catch (_) {
    return null;
  } finally {
    handle?.closeSync();
  }
}

String _format(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}