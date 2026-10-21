// Damped spring physics, ported 1:1 from liquid-glass (src/animation/spring.ts).
// Semi-implicit Euler, sub-stepped so high stiffness stays stable.

/// The longest frame the physics follows in full (covers a 20fps cap).
const double kMaxStepS = 0.066;
const double _subStepS = 0.002;

class Spring {
  double _stiffness;
  double _damping;
  double _mass;

  double value;
  double velocity = 0;
  double target;

  Spring({required double stiffness, required double damping, double mass = 1.0})
      : _stiffness = stiffness,
        _damping = damping,
        _mass = mass,
        value = 0,
        target = 0;

  Spring.fromValue({
    required double stiffness,
    required double damping,
    double mass = 1.0,
    required this.value,
  })  : _stiffness = stiffness,
        _damping = damping,
        _mass = mass,
        target = value;

  void updateParams({required double stiffness, required double damping, double? mass}) {
    _stiffness = stiffness;
    _damping = damping;
    if (mass != null) _mass = mass;
  }

  /// Advances by [elapsedMs] milliseconds. Returns true when settled.
  bool update(double elapsedMs) {
    double dt = elapsedMs / 1000;
    if (dt > kMaxStepS) dt = kMaxStepS;

    final mass = _mass > 1e-3 ? _mass : 1e-3;
    double remaining = dt;
    while (remaining > 1e-6) {
      final h = math_min(remaining, _subStepS);
      final springForce = -_stiffness * (value - target);
      final dampingForce = -_damping * velocity;
      final acceleration = (springForce + dampingForce) / mass;

      velocity += acceleration * h;
      value += velocity * h;
      remaining -= h;
    }

    return velocity.abs() < 0.01 && (value - target).abs() < 0.001;
  }
}

double math_min(double a, double b) => a < b ? a : b;
