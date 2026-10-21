// Where playback goes next, and how long a track has been playing.
//
// Pure Dart: the rules that decide "next" and "previous" are checked without
// a Flutter engine, because they are the part that is easy to get wrong
// (shuffle replaying the same track, previous on an empty list, a negative
// duration printing as `-1:-3`).

import 'dart:math' as math;

abstract final class PlaylistPolicy {
  /// The index after [current]. Shuffle never picks the current track when
  /// there is another one, and never leaves the list.
  static int next(int current, int length,
      {bool shuffle = false, math.Random? random}) {
    if (length <= 1) return 0;
    if (shuffle) {
      final rnd = random ?? math.Random();
      var candidate = current;
      // The loop is bounded: a bad source of randomness cannot hang the app.
      for (var attempt = 0; attempt < 32 && candidate == current; attempt++) {
        candidate = rnd.nextInt(length);
      }
      if (candidate == current) candidate = (current + 1) % length;
      return candidate;
    }
    return (current + 1) % length;
  }

  /// The index before [current]; wraps to the end.
  static int previous(int current, int length) {
    if (length <= 0) return 0;
    return (current - 1 + length) % length;
  }
}

/// Reads `2:07` back into a duration, or null when the text is not a time.
/// The track table carries a duration before anything is decoded, so a seek
/// on a freshly selected track can land somewhere sensible.
Duration? parsePlaybackTime(String text) {
  final match = RegExp(r'^\s*(\d+):([0-5]?\d)\s*$').firstMatch(text);
  if (match == null) return null;
  return Duration(
    minutes: int.parse(match.group(1)!),
    seconds: int.parse(match.group(2)!),
  );
}

/// Turns `72` seconds into `1:12` and never prints a negative time.
String formatPlaybackTime(Duration duration) {
  final total = duration.isNegative ? Duration.zero : duration;
  final minutes = total.inMinutes;
  final seconds = total.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}