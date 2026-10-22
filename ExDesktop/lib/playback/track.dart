// One track, wherever it is shown: the waybar, the player flyout, Musics.
//
// A class instead of the `Map<String, String>` the shell used to pass around:
// a map made every typo a runtime null, and the duration had to be written
// back into it when the decoder reported the real length.

import 'dart:typed_data';

class Track {
  final String title;
  final String artist;

  /// The bundled file name, e.g. `morgenshtern-ice.mp3` (also the unique
  /// library key for imported files).
  final String file;

  /// Absolute path for a file imported from disk; empty for a bundled asset.
  final String path;

  /// The bundled cover from the track table; empty when there is none.
  final String avatar;

  /// `2:04` once known, empty before the track has been played.
  final String duration;

  const Track({
    required this.title,
    required this.artist,
    required this.file,
    this.path = '',
    this.avatar = '',
    this.duration = '',
  });

  /// True for a track that lives on disk outside the app bundle.
  bool get isFile => path.isNotEmpty;

  Track withDuration(String value) => Track(
        title: title,
        artist: artist,
        file: file,
        path: path,
        avatar: avatar,
        duration: value,
      );

  /// The cover embedded in the mp3, if the tag reader found one.
  Uint8List? coverIn(Map<String, Uint8List> covers) => covers[file];

  @override
  String toString() => 'Track($title - $artist)';
}