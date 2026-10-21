// The heartbeat of the Musics cover.
//
// The cover in the Musics app does not spin — it breathes. Without an audio
// analyser the beat is simulated at a fixed tempo: a sharp attack on the beat
// and an exponential decay, the shape a kick drum has. It is deliberately
// subtle (4.5%), because the point is that the app feels alive, not that the
// cover jumps around.
//
// Pure Dart: checked by `dart run test/playback_check.dart`.

import 'dart:math' as math;

abstract final class BeatPulse {
  /// 120 bpm: a beat every 500 ms.
  static const double bpm = 120.0;

  /// The largest extra scale, applied on the beat itself.
  static const double amount = 0.045;

  /// How fast the pulse dies down inside one beat.
  static const double decay = 7.0;

  /// The scale of the cover at [seconds] of playback.
  static double scaleAt(double seconds, {required bool playing}) {
    if (!playing) return 1.0;
    final beats = seconds * bpm / 60.0;
    final phase = beats - beats.floorToDouble();
    return 1.0 + amount * math.exp(-phase * decay);
  }

  /// The phase of the beat in 0..1, 0 being the hit.
  static double phaseAt(double seconds) {
    final beats = seconds * bpm / 60.0;
    return beats - beats.floorToDouble();
  }
}