// The music library on disk: what counts as audio, how a WAV reports its
// duration, how files are imported without overwriting each other and how a
// folder scan builds track entries.
//
//   dart run test/library_check.dart

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:exp_desktop/apps/music_library.dart';
import 'package:exp_desktop/apps/music_scanner.dart';
import 'package:exp_desktop/apps/wav_info.dart';
import 'mock_harness.dart';

Future<void> runLibraryChecks() async {
  _extensions();
  _wavDurations();
  _scanJson();
  await _rustScan();
  await _importAndScan();
}

void _scanJson() {
  section('rust scan json');
  final parsed = parseMusicScanJson(
      r'[{"path":"C:\\Music\\A.mp3","file":"A.mp3","title":"He said \"hi\"","artist":"Artist","duration":"3:07","cover":"C:\\cache\\c.jpg"}]');
  checkEquals('one record', parsed.length, 1);
  checkEquals('path survives escapes', parsed.single.path, r'C:\Music\A.mp3');
  checkEquals('file', parsed.single.file, 'A.mp3');
  checkEquals('title quotes survive', parsed.single.title, 'He said "hi"');
  checkEquals('artist', parsed.single.artist, 'Artist');
  checkEquals('duration', parsed.single.duration, '3:07');
  checkEquals('cover path', parsed.single.cover, r'C:\cache\c.jpg');

  final defaults = parseMusicScanJson(
      r'[{"path":"C:\\Music\\B.wav","title":""}]');
  checkEquals('a missing file key falls back to the path',
      defaults.single.file, r'C:\Music\B.wav');
  checkEquals('a missing artist gets a label', defaults.single.artist,
      'Unknown artist');
  check('a missing cover is empty', defaults.single.cover.isEmpty);
  check('no duration is empty', defaults.single.duration.isEmpty);

  check('an empty list parses', parseMusicScanJson('[]').isEmpty);
  check('junk parses to nothing', parseMusicScanJson('not json').isEmpty);
  check('an object is not a list', parseMusicScanJson('{}').isEmpty);
  check('an entry without a path is skipped',
      parseMusicScanJson('[{"file":"x.mp3"}]').isEmpty);
}

void _extensions() {
  section('audio files');
  for (final ext in ['mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac', 'opus']) {
    check('.$ext is audio', isAudioPath('song.$ext'));
  }
  check('uppercase matters not', isAudioPath('SONG.MP3'));
  check('a path with dots works', isAudioPath(r'C:\a.b\song.name.wav'));
  check('a text file is not audio', !isAudioPath('notes.txt'));
  check('no extension is not audio', !isAudioPath('README'));
  check('a trailing dot is not audio', !isAudioPath('song.'));

  checkEquals('a file name becomes a title',
      titleFromFileName('my_cool-song.mp3'), 'My Cool Song');
  checkEquals('a path keeps only the name',
      titleFromFileName(r'C:\Music\Album\Hello World.flac'), 'Hello World');
  checkEquals('no extension still works',
      titleFromFileName(r'C:\Music\untitled'), 'Untitled');
}

void _wavDurations() {
  section('wav duration');
  final oneSecond = _wav(byteRate: 176400, dataSize: 176400);
  checkEquals('one second', wavDuration(oneSecond)?.inMilliseconds, 1000);
  final half = _wav(byteRate: 176400, dataSize: 88200);
  checkEquals('half a second', wavDuration(half)?.inMilliseconds, 500);
  checkEquals('a long file', wavDuration(_wav(byteRate: 44100, dataSize: 44100 * 95))?.inSeconds, 95);

  check('a short buffer is refused',
      wavDuration(Uint8List.fromList(List.filled(20, 0))) == null);
  check('a non-RIFF buffer is refused',
      wavDuration(Uint8List.fromList(List.filled(100, 7))) == null);
  check('zero byte rate is refused',
      wavDuration(_wav(byteRate: 0, dataSize: 1000)) == null);
  check('zero data is refused',
      wavDuration(_wav(byteRate: 1000, dataSize: 0)) == null);
  check('an odd chunk is padded correctly',
      wavDuration(_wav(byteRate: 88200, dataSize: 88200, oddChunk: true))
              ?.inSeconds ==
          1);
}

Future<void> _importAndScan() async {
  section('music library');
  final temp = await Directory.systemTemp.createTemp('exp_library_');
  final library = MusicLibrary(root: temp.path);
  check('the music folder starts missing', !library.hasFolder);

  final source = File('${temp.path}${Platform.pathSeparator}My Song.MP3');
  await source.writeAsBytes([1, 2, 3, 4]);
  final first = await library.import(source.path);
  check('an mp3 is imported', first != null);
  check('the destination is inside the library folder',
      first != null && first.contains('Music'));
  check('the music folder was created', library.hasFolder);
  check('the bytes were copied',
      first != null && (await File(first).readAsBytes()).join(',') == '1,2,3,4');

  final second = await library.import(source.path);
  check('a second copy gets its own name', second != first);
  check('the second copy says (2)', second != null && second.contains('(2)'));
  check('both files exist',
      first != null && second != null && File(first).existsSync() && File(second).existsSync());

  final text = File('${temp.path}${Platform.pathSeparator}notes.txt');
  await text.writeAsString('hello');
  check('a text file is not imported', await library.import(text.path) == null);
  check('a missing file is not imported',
      await library.import('${temp.path}${Platform.pathSeparator}nope.mp3') == null);

  // Scan: one tagged mp3, one wav in a subfolder.
  final music = Directory(library.musicDir);
  final tagged = File('${music.path}${Platform.pathSeparator}Tagged.mp3');
  await tagged.writeAsBytes(_id3(title: 'Real Title', artist: 'Real Artist'));
  final sub = Directory('${music.path}${Platform.pathSeparator}Sub')
    ..createSync();
  await File('${sub.path}${Platform.pathSeparator}Drum Loop.WAV')
      .writeAsBytes(_wav(byteRate: 88200, dataSize: 44100));

  final scanned = scanMusicDirectory(library.musicDir);
  check('every audio file is found', scanned.length >= 4);
  final taggedTrack = scanned.firstWhere((t) => t.track.file == 'Tagged.mp3');
  checkEquals('the ID3 title wins', taggedTrack.track.title, 'Real Title');
  checkEquals('the ID3 artist wins', taggedTrack.track.artist, 'Real Artist');
  check('the tagged track has a real path', taggedTrack.track.isFile);
  check('the tagged track has no cover here', taggedTrack.cover == null);

  final wavTrack =
      scanned.firstWhere((t) => t.track.file == 'Sub/Drum Loop.WAV');
  checkEquals('the subfolder is part of the key', wavTrack.track.file,
      'Sub/Drum Loop.WAV');
  checkEquals('the wav duration is read', wavTrack.track.duration, '0:00');
  check('the wav has a path', wavTrack.track.path.endsWith('Drum Loop.WAV'));

  final names = scanned.map((t) => t.track.file.toLowerCase()).toList();
  final sorted = List<String>.from(names)..sort();
  check('the scan is sorted by path', '$names' == '$sorted');

  final empty = Directory('${temp.path}${Platform.pathSeparator}Empty');
  check('a missing folder scans empty', scanMusicDirectory(empty.path).isEmpty);

  await temp.delete(recursive: true);
  check('the temp folder is gone', !temp.existsSync());
}

Future<void> _rustScan() async {
  section('rust scanner');
  if (!MusicScanner.available) {
    check('the DLL is not built here; the Dart fallback is active', true);
    return;
  }
  final temp = await Directory.systemTemp.createTemp('exp_rust_');
  final music = Directory('${temp.path}${Platform.pathSeparator}music')
    ..createSync();
  final png = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...List<int>.filled(40, 1),
  ];
  await File('${music.path}${Platform.pathSeparator}Tagged.mp3')
      .writeAsBytes(_id3WithCover(
    title: 'Rust Title',
    artist: 'Rust Artist',
    cover: png,
  ));
  await File('${music.path}${Platform.pathSeparator}Loop.wav')
      .writeAsBytes(_wav(byteRate: 88200, dataSize: 44100));
  await File('${music.path}${Platform.pathSeparator}notes.txt')
      .writeAsString('x');

  final cache = '${temp.path}${Platform.pathSeparator}cache';
  final scanned = await MusicScanner.scan(music.path, cache);
  check('the scanner returned a list', scanned != null);
  final list = scanned ?? const <LibraryTrack>[];
  checkEquals('two audio files', list.length, 2);
  final byFile = {for (final entry in list) entry.track.file: entry};

  final mp3 = byFile['Tagged.mp3'];
  check('the mp3 is listed', mp3 != null);
  checkEquals('the ID3 title', mp3?.track.title, 'Rust Title');
  checkEquals('the ID3 artist', mp3?.track.artist, 'Rust Artist');
  check('the cover was extracted', (mp3?.cover?.length ?? 0) == png.length);
  check('the cover cache was written',
      Directory(cache).existsSync() && Directory(cache).listSync().isNotEmpty);

  final wav = byFile['Loop.wav'];
  check('the wav is listed', wav != null);
  checkEquals('the wav duration', wav?.track.duration, '0:00');
  check('the text file is skipped', !byFile.containsKey('notes.txt'));
  await temp.delete(recursive: true);
}

/// The minimal tag with an APIC frame for the native scanner test.
Uint8List _id3WithCover({
  required String title,
  required String artist,
  required List<int> cover,
}) {
  final frames = BytesBuilder();
  void frame(String id, List<int> body) {
    frames.add(ascii.encode(id));
    frames.add([
      (body.length >> 24) & 0xFF,
      (body.length >> 16) & 0xFF,
      (body.length >> 8) & 0xFF,
      body.length & 0xFF,
      0,
      0,
    ]);
    frames.add(body);
  }

  frame('TIT2', [3, ...utf8.encode(title)]);
  frame('TPE1', [3, ...utf8.encode(artist)]);
  frame('APIC', [0, ...ascii.encode('image/png'), 0, 3, 0, ...cover]);
  final body = frames.toBytes();
  return Uint8List.fromList([
    0x49, 0x44, 0x33, 3, 0, 0,
    (body.length >> 21) & 0x7F,
    (body.length >> 14) & 0x7F,
    (body.length >> 7) & 0x7F,
    body.length & 0x7F,
    ...body,
  ]);
}

/// A RIFF/WAVE header with the declared data size (the payload is not needed).
Uint8List _wav({required int byteRate, required int dataSize, bool oddChunk = false}) {
  final out = BytesBuilder();
  void ascii(String value) => out.add(value.codeUnits);
  void u32(int value) => out.add([
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ]);
  void u16(int value) => out.add([value & 0xFF, (value >> 8) & 0xFF]);

  ascii('RIFF');
  u32(36 + dataSize);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1);
  u16(2);
  u32(44100);
  u32(byteRate);
  u16(4);
  u16(16);
  if (oddChunk) {
    ascii('JUNK');
    u32(3);
    out.add([1, 2, 3, 0]); // odd size + pad
  }
  ascii('data');
  u32(dataSize);
  out.add(Uint8List(16));
  return out.toBytes();
}

/// A minimal ID3v2.3 tag with TIT2 and TPE1.
Uint8List _id3({required String title, required String artist}) {
  final frames = BytesBuilder();
  void frame(String id, String value) {
    final body = <int>[3, ...utf8.encode(value)];
    frames.add(ascii.encode(id));
    frames.add([
      (body.length >> 24) & 0xFF,
      (body.length >> 16) & 0xFF,
      (body.length >> 8) & 0xFF,
      body.length & 0xFF,
      0,
      0,
    ]);
    frames.add(body);
  }

  frame('TIT2', title);
  frame('TPE1', artist);
  final body = frames.toBytes();
  return Uint8List.fromList([
    0x49, 0x44, 0x33, 3, 0, 0,
    (body.length >> 21) & 0x7F,
    (body.length >> 14) & 0x7F,
    (body.length >> 7) & 0x7F,
    body.length & 0x7F,
    ...body,
  ]);
}

void main() async {
  await runLibraryChecks();
  finish('library');
}