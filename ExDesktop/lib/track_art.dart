// One track's artwork, wherever it is shown.
//
// Three sources, in order: the cover embedded in the mp3's ID3 tag, the
// image the track table points at, and a placeholder drawn in the shell's own
// style. The mini-player used to fall back to a hard-coded cover, so every
// track without art was shown with Монеточка's face.

import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Rounded artwork for a track: embedded cover, bundled image, or a
/// music-note tile that matches the glass panels.
class TrackArt extends StatelessWidget {
  /// The picture from the ID3 tag, if the file has one.
  final Uint8List? cover;

  /// The bundled asset path from the track table, if any.
  final String? avatar;

  final double size;
  final BorderRadius borderRadius;

  const TrackArt({
    super.key,
    this.cover,
    this.avatar,
    this.size = 40,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: _art(),
      ),
    );
  }

  Widget _art() {
    final bytes = cover;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => _placeholder(),
      );
    }

    final path = avatar;
    if (path != null && path.isNotEmpty) {
      return Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => _placeholder(),
      );
    }

    return _placeholder();
  }

  /// The default: a translucent glass tile with a note on it, so a track
  /// without art still looks like part of the shell.
  Widget _placeholder() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.20),
            Colors.white.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * 0.5,
          color: Colors.white.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}