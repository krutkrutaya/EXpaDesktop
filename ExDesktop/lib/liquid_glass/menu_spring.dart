// Menu open/close scale spring, ported from liquid-glass
// (src/animation/menuSpring.ts).
//
// Opening: a damped spring that swings just past 1.0 and settles — the
// liquid bounce. Closing: exponential decay, never bounces, opacity fades
// out ahead of the shrink.

import 'dart:math' as math;

import 'spring.dart';

const double _closeSpeed = 15.0;
const double _closedBelow = 0.005;
const double _openSnapDistance = 0.002;
const double _openSnapVelocity = 0.03;

const double _openStiffness = 170.0;
const double _openDamping = 14.0;

class MenuSpringState {
  double value;
  double velocity = 0;
  double target;

  MenuSpringState(this.value) : target = value;
}

class MenuFrame {
  final bool closing;
  final bool stopped;
  final double scale;
  final double opacity;

  const MenuFrame({
    required this.closing,
    required this.stopped,
    required this.scale,
    required this.opacity,
  });
}

double _clampOpacity(double v) => v.clamp(0.0, 255.0);

({double s, bool stopped}) _stepClosing(MenuSpringState scale, double elapsedMs) {
  final dt = (elapsedMs / 1000).clamp(0.0, kMaxStepS);
  final k = 1.0 - math.exp(-_closeSpeed * dt);
  scale.value += (0 - scale.value) * k;
  if (scale.value < _closedBelow) return (s: 0, stopped: true);
  return (s: scale.value, stopped: false);
}

({double s, bool stopped}) _stepOpening(MenuSpringState scale, double elapsedMs) {
  final spring = Spring.fromValue(
    stiffness: _openStiffness,
    damping: _openDamping,
    value: scale.value,
  );
  spring.velocity = scale.velocity;
  spring.target = 1.0;
  final settled = spring.update(elapsedMs);
  scale.value = spring.value;
  scale.velocity = spring.velocity;
  final s = scale.value;
  // Snap to 1.0 once the bounce has almost settled.
  if ((1.0 - s).abs() < _openSnapDistance &&
      scale.velocity.abs() < _openSnapVelocity) {
    return (s: 1.0, stopped: true);
  }
  return (s: s, stopped: settled);
}

MenuFrame stepMenuSpring(MenuSpringState scale, double elapsedMs) {
  final closing = scale.target == 0;
  final r =
      closing ? _stepClosing(scale, elapsedMs) : _stepOpening(scale, elapsedMs);
  // Scale 0 can upset renderers, hence the 0.001 floor. Opacity fades out
  // between scale 1.0 and 0.3, ahead of the shrink.
  if (closing) {
    return MenuFrame(
      closing: closing,
      stopped: r.stopped,
      scale: math.max(0.001, r.s),
      opacity: _clampOpacity((r.s - 0.3) / 0.7 * 255),
    );
  }
  return MenuFrame(
    closing: closing,
    stopped: r.stopped,
    scale: 0.2 + r.s * 0.8,
    opacity: _clampOpacity((r.s / 0.3) * 255),
  );
}
