// One request from Musics to the Files window: "let me pick an audio file".
//
// The Files window listens to the request, shows a banner and a Use button on
// audio rows, then hands the chosen path back. The request object is short
// lived: the shell clears it as soon as the import starts, which also hides
// the banner.

import 'music_library.dart';

class AudioPickRequest {
  final void Function(String path) onPick;
  final void Function()? onCancel;

  const AudioPickRequest({required this.onPick, this.onCancel});

  /// Whether this file can be handed to the player.
  bool accepts(String path) => isAudioPath(path);
}