// The angle of the spinning artwork.
//
// The old shell used `AnimationController.repeat()` and `stop()`: pausing froze
// the cover at whatever angle the last frame happened to have, so it sat
// crooked. The fix is not a reset after the fact — a jump would be visible —
// but a spring: while paused, the angle is pulled to the nearest full turn and
// settles there with a soft overshoot, then stops.
//
// Pure Dart: checked by `dart run test/playback_check.dart`.

import 'dart:math' as math;

class SpinState {
  /// One full turn every four seconds — the speed the shell already had.
  static const double secondsPerTurn = 4.0;
  static const double twoPi = math.pi * 2;
  static const double speed = twoPi / secondsPerTurn;

  /// Stiffness of the settle spring; the damping ratio is just under 1, so it
  /// arrives quickly with a hint of bounce instead of snapping.
  static const double stiffness = 130.0;
  static const double dampingRatio = 0.82;

  double angle = 0;
  double velocity = 0;

  /// True when the artwork is upright and still.
  bool get settled {
    if (velocity.abs() > 0.02) return false;
    final target = _target;
    return (angle - target).abs() < 0.001;
  }

  double get _target => (angle / twoPi).round() * twoPi;

  /// Advances the physics by [dt] seconds.
  ///
  /// While [playing] the angle turns at a constant speed. While paused it is
  /// a damped spring towards the nearest upright angle. Returns true when the
  /// angle changed enough to need a repaint.
  bool advance(double dt, {required bool playing}) {
    if (dt <= 0) return false;
    // A long frame (window drag, GC) must not teleport the cover.
    final step = dt.clamp(0.0, 0.05);
    if (playing) {
      angle += speed * step;
      velocity = speed;
      return true;
    }

    final target = _target;
    final damping = 2 * math.sqrt(stiffness) * dampingRatio;
    final acceleration = stiffness * (target - angle) - damping * velocity;
    velocity += acceleration * step;
    angle += velocity * step;

    if ((target - angle).abs() < 0.0008 && velocity.abs() < 0.02) {
      angle = target % twoPi;
      velocity = 0;
      return true;
    }
    return true;
  }

  /// Whether the ticker is still needed: playing, or still settling.
  bool needsFrames(bool playing) => playing || !settled;

  void reset() {
    angle = 0;
    velocity = 0;
  }
}