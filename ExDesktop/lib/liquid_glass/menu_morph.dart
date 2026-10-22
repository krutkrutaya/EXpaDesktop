// The liquid-glass menu morph, ported 1:1 from liquid-glass
// (src/animation/menuMorph.ts, itself adapted from liquid-dom by @AndrewPrifer).
//
// Opening: the button's capsule draws itself into a round drop, the drop is
// thrown out to where the menu will be, swells to the menu's size and squares
// off, landing exactly on the menu's rect. Closing: the menu shrinks back
// into a drop that rises into the button, stretches into its capsule on the
// way, and fades there.

import 'dart:math' as math;

// [x, y, w, h]
typedef Rect4 = List<double>;

class MorphFrame {
  final Rect4 body;
  final double bodyRadius;
  final double contentScale;
  final double contentOpacity;
  final double lens;
  final double glassOpacity;
  final double soften;

  /// How visible the whole glass is for the fade: it rises fast at the very
  /// start of the open (the panel appears almost at once) and falls only at
  /// the very end of the close (the panel melts away last), unlike the item
  /// opacity which follows the size.
  final double reveal;
  final bool done;

  const MorphFrame({
    required this.body,
    required this.bodyRadius,
    required this.contentScale,
    required this.contentOpacity,
    required this.lens,
    required this.glassOpacity,
    required this.soften,
    this.reveal = 1,
    required this.done,
  });

  MorphFrame copyWith({
    Rect4? body,
    double? bodyRadius,
    double? contentScale,
    double? contentOpacity,
    double? lens,
    double? glassOpacity,
    double? soften,
    double? reveal,
    bool? done,
  }) {
    return MorphFrame(
      body: body ?? this.body,
      bodyRadius: bodyRadius ?? this.bodyRadius,
      contentScale: contentScale ?? this.contentScale,
      contentOpacity: contentOpacity ?? this.contentOpacity,
      lens: lens ?? this.lens,
      glassOpacity: glassOpacity ?? this.glassOpacity,
      soften: soften ?? this.soften,
      reveal: reveal ?? this.reveal,
      done: done ?? this.done,
    );
  }
}

const double _stepS = 0.002;
const double _maxFrameS = 0.05;

class _MorphSpring {
  double velocity = 0;
  double value;
  double target;
  final double _stiffness;
  final double _damping;

  _MorphSpring(this.value, this._stiffness, this._damping) : target = value;

  void step(double dt) {
    final acc = -_stiffness * (value - target) - _damping * velocity;
    velocity += acc * dt;
    value += velocity * dt;
  }

  bool settled(double within) =>
      (value - target).abs() < within && velocity.abs() < within * 10;
}

// [stiffness, damping], unit mass, as liquid-dom's demo has them.
const double _openMoveStiffness = 144, _openMoveDamping = 14;
const double _closeMoveStiffness = 130, _closeMoveDamping = 18;
const double _contentFadeStiffness = 137, _contentFadeDamping = 20;
// The drop is thrown out at this multiple of the distance, per second.
const double _throw = 16;
// The capsule draws into a drop this many times the button's height across.
const double _dropSizeFactor = 1.15;
const double _capsuleTimeS = 0.14;
const double _clockStart = 0.3;
const double _clockPower = 8;
const double _capsulePush = 2.2;
// Opening from a capsule a reversal left behind: it rounds into the drop this long.
const double _roundTimeS = 0.1;
// Glass opacity and softening come back to open values over this long.
const double _revealS = 0.12;
// The whole glass becomes visible this fast while opening, so a panel is
// really there from the first frames instead of fading in over half a second.
const double _glassShowS = 0.09;
// The springs swing the drop past the menu; all of the swing is taken out as
// it swells, so the grown glass sits exactly on the menu instead of drifting
// in around it at the end.
const double _settledSwing = 0;
const double _openSizeS = 0.3;
const double _closeSizeS = 0.25;
const double _contentScaleS = 0.3;
// The content starts twice its size.
const double _contentClosedScale = 2;
// The content is seen through the glass as if deep inside it when the menu
// opens, and comes up to the surface over this long.
const double _lensS = 0.3;
// Closing: the drop starts to turn into the capsule once it is this many
// button heights from where the capsule rests, or this long after closing
// began whatever; it fades over _fadeS from _fadeDelayS after it starts to.
const double _arriveHeights = 2;
const double _arriveMaxS = 0.6;
const double _closeCapsuleS = 0.16;
const double _fadeDelayS = 0.24;
const double _fadeS = 0.12;
// The refraction and blur are taken down as the drop comes back to the button.
const double _softenHeights = 1.5;
const double _softenS = 0.1;

double _cubicBezierAt(double t, double a, double b) =>
    3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t;

double _cubicBezierSlope(double t, double a, double b) =>
    3 * a * (1 - t) * (1 - t) +
    6 * (b - a) * t * (1 - t) +
    3 * (1 - b) * t * t;

double Function(double) _cubicBezier(double x1, double y1, double x2, double y2) {
  double eval(double x) {
    if (x <= 0 || x >= 1) return x.clamp(0.0, 1.0);
    double t = x;
    for (int i = 0; i < 8; i++) {
      final d = _cubicBezierSlope(t, x1, x2);
      if (d.abs() < 1e-6) break;
      t = (t - (_cubicBezierAt(t, x1, x2) - x) / d).clamp(0.0, 1.0);
    }
    return _cubicBezierAt(t, y1, y2);
  }

  return eval;
}

// Slow out of the drop, then quick to the menu's size.
final double Function(double) _openSize = _cubicBezier(0.8, 0.3, 0.5, 0.8);
double _easeOut(double t) => 1 - (1 - t) * (1 - t);
double _easeInOut(double t) =>
    t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;

double _clamp01(double t) => t.clamp(0.0, 1.0).toDouble();
double _lerp(double a, double b, double t) => a + (b - a) * t;

// Closing: the items are as faded as the opening had them at this many times
// the time it took to reach the size, so they stay longer.
const double _closeFadeHold = 1.0;

// How the items fade in as the glass opens, every _fadeStepS from its start.
const double _fadeStepS = 0.002;
final List<double> _openFade = _buildOpenFade();

List<double> _buildOpenFade() {
  final fade = _MorphSpring(0, _contentFadeStiffness, _contentFadeDamping);
  fade.target = 1;
  final values = <double>[];
  for (double t = 0; t < 1; t += _fadeStepS) {
    values.add(_clamp01(fade.value));
    fade.step(_fadeStepS);
  }
  return values;
}

List<double> _rectCenter(Rect4 r) => [r[0] + r[2] / 2, r[1] + r[3] / 2];

double _rectGap(Rect4 a, Rect4 b) {
  final dx = math.max(b[0] - (a[0] + a[2]), math.max(a[0] - (b[0] + b[2]), 0.0));
  final dy = math.max(b[1] - (a[1] + a[3]), math.max(a[1] - (b[1] + b[3]), 0.0));
  return math.sqrt(dx * dx + dy * dy);
}

class MenuMorphMotion {
  double _t = 0;
  _MorphSpring _x = _MorphSpring(0, 1, 1);
  _MorphSpring _y = _MorphSpring(0, 1, 1);
  _MorphSpring _opacity = _MorphSpring(0, 1, 1);
  final bool opening;
  Rect4 _buttonRect;
  Rect4 _menu;
  double _menuRadius;
  // Opening: how long the capsule takes to draw into a drop (0 when the
  // motion takes over from another). The rest of the motion starts after it.
  double _capsuleS = 0;
  List<double> _sizeFrom = [0, 0];
  // Opening, how round the corners start, as a fraction of the roundest they
  // can be; closing, the radius they start from.
  double _radiusFrom = 0;
  // Opening from a reversal: how long the capsule takes to round into a drop.
  double _roundS = 0;
  double _glassFrom = 1;
  double _softenFrom = 0;
  double _contentFrom = 1;
  double _lensFrom = 0;
  // Closing: when the drop came near the button, and its size then.
  double _arrivedAt = -1;
  List<double> _arrivedSize = [];
  // Closing: the furthest the body has been from the button, and how far the
  // refraction and blur are down; they never come back up.
  double _furthest = 0;
  double _soften = 0;
  // Closing: how much of the glass's opacity is left before the capsule fade
  // even begins — the drop melts while it is still travelling back.
  double _travelFade = 1;
  // Opening, the glass reveal starts here (0 for a fresh open, whatever a
  // reversal left behind); closing, it is the value to keep until the last
  // moment.
  double _glassRevealFrom = 0;
  MorphFrame _frame = const MorphFrame(
    body: [0, 0, 0, 0],
    bodyRadius: 0,
    contentScale: 2,
    contentOpacity: 0,
    lens: 1,
    glassOpacity: 0,
    soften: 0,
    done: true,
  );

  MenuMorphMotion(
    this.opening,
    this._buttonRect,
    this._menu,
    this._menuRadius, {
    MorphFrame? from,
    List<double>? velocities,
  }) {
    MorphFrame start = from ??
        (opening
            ? MorphFrame(
                body: List<double>.from(_buttonRect),
                bodyRadius: _buttonRect[3] / 2,
                contentScale: _contentClosedScale,
                contentOpacity: 0,
                lens: 1,
                glassOpacity: 1,
                soften: 0,
                reveal: 0,
                done: false,
              )
            : MorphFrame(
                body: List<double>.from(_menu),
                bodyRadius: _menuRadius,
                contentScale: 1,
                contentOpacity: 1,
                lens: 0,
                glassOpacity: 1,
                soften: 0,
                reveal: 1,
                done: false,
              ));
    _frame = start;
    _capsuleS = opening && from == null ? _capsuleTimeS : 0;

    final stiffness = opening ? _openMoveStiffness : _closeMoveStiffness;
    final damping = opening ? _openMoveDamping : _closeMoveDamping;
    // The drop is thrown from where it fell to.
    final c = _rectCenter(start.body);
    _x = _MorphSpring(c[0], stiffness, damping);
    _y = _MorphSpring(c[1], stiffness, damping);
    _opacity = _MorphSpring(start.contentOpacity, _contentFadeStiffness, _contentFadeDamping);
    if (velocities != null) {
      _x.velocity = velocities[0];
      _y.velocity = velocities[1];
    }
    final drop = _dropPx();
    _sizeFrom = _capsuleS > 0
        ? [drop, drop]
        : [start.body[2], start.body[3]];
    _radiusFrom = opening
        ? start.bodyRadius / math.max(math.min(start.body[2], start.body[3]) / 2, 1)
        : start.bodyRadius;
    if (opening && from != null) {
      final fw = start.body[2];
      final fh = start.body[3];
      if (math.min(fw, fh) <= drop * 1.01 && math.max(fw, fh) > drop * 1.05) {
        _roundS = _roundTimeS;
      }
    }
    _contentFrom = start.contentScale;
    _lensFrom = start.lens;
    _glassFrom = start.glassOpacity;
    _softenFrom = start.soften;
    _glassRevealFrom = start.reveal;
    // A close that took over from a partially faded frame keeps on fading
    // from there instead of jumping back to opaque.
    if (!opening) _travelFade = _clamp01(start.glassOpacity);
    _aim();
    if (opening && velocities == null) {
      // The drop is thrown out along the line to the menu; the reference's
      // random lateral push stayed in liquid-dom — against these large
      // panels it read as drift, then a snap into place at the end.
      final launch = _capsuleS > 0 ? _capsulePush : _throw * 0.5;
      _x.velocity = (_x.target - _x.value) * launch;
      _y.velocity = (_y.target - _y.value) * launch;
    }
  }

  double _dropPx() {
    final w = _buttonRect[2];
    final h = _buttonRect[3];
    return math.max(math.min(h * _dropSizeFactor, w), 1);
  }

  /// The body's velocity, for a motion that reverses this one.
  List<double> get velocities => [_x.velocity, _y.velocity];

  MorphFrame get frame => _frame;

  /// Where the button and the menu are now; they may move while it runs.
  void retarget(Rect4 button, Rect4? menu, double menuRadius) {
    _buttonRect = button;
    if (menu != null) _menu = menu;
    _menuRadius = menuRadius;
    _aim();
  }

  void _aim() {
    final c = _rectCenter(opening ? _menu : _buttonRect);
    _x.target = c[0];
    _y.target = c[1];
    _opacity.target = opening ? 1 : 0;
  }

  /// Advances by [elapsed] seconds.
  MorphFrame step(double elapsed, [double speed = 1]) {
    double dt = elapsed.clamp(0.0, _maxFrameS);
    dt *= speed;
    _t += dt;
    _frame = opening ? _open(dt) : _close(dt);
    return _frame;
  }

  void _stepSprings(double dt, [bool motionOnly = false]) {
    final springs =
        motionOnly ? [_x, _y] : <_MorphSpring>[_x, _y, _opacity];
    for (double t = 0; t < dt; t += _stepS) {
      final h = math.min(_stepS, dt - t);
      for (final s in springs) {
        s.step(h);
      }
    }
  }

  MorphFrame _open(double dt) {
    if (_capsuleS > 0) {
      // The springs run on a clock that is at full speed where the capsule
      // ends, so position, velocity and acceleration carry over without a step.
      final before = _t - dt;
      final span =
          math.min(_t, _capsuleS) - math.min(before, _capsuleS);
      if (span > 0) {
        final u = (before + span / 2) / _capsuleS;
        final ease = u * u * u * (u * (u * 6 - 15) + 10);
        _stepSprings(
            span * _lerp(_clockStart, 1, math.pow(ease, _clockPower).toDouble()),
            true);
      }
    }
    if (_t < _capsuleS) {
      final t = _t / _capsuleS;
      // It leaves the button as a capsule and rounds off on the way down.
      final k = _easeInOut(_clamp01((t - 0.3) / 0.7));
      final bw = _buttonRect[2];
      final bh = _buttonRect[3];
      final drop = _dropPx();
      final w = _lerp(bw, drop, k);
      final h = _lerp(bh, drop, k);
      final x = _x.value;
      final y = _y.value;

      _radiusFrom = 1;

      return MorphFrame(
        body: [x - w / 2, y - h / 2, w, h],
        bodyRadius: math.min(w, h) / 2,
        contentScale: _contentClosedScale,
        contentOpacity: 0,
        lens: 1,
        glassOpacity: 1,
        soften: 0,
        done: false,
      );
    }
    final t = _t - _capsuleS;
    _stepSprings(math.min(dt, t));
    final g = t - _roundS;
    double w, h, radius;
    if (g < 0) {
      // A capsule from a reversal goes through the round drop before it grows.
      final drop = _dropPx();
      final c = _easeInOut(_clamp01(t / _roundS));
      w = _lerp(_sizeFrom[0], drop, c);
      h = _lerp(_sizeFrom[1], drop, c);
      radius = math.min(w, h) / 2;
    } else {
      final from = _roundS > 0
          ? [_dropPx(), _dropPx()]
          : _sizeFrom;
      final k = _openSize(_clamp01(g / _openSizeS));
      w = _lerp(from[0], _menu[2], k);
      h = _lerp(from[1], _menu[3], k);
      // The corners square off as the glass grows, on the clock rather than
      // the slow-out size curve, and quickly: by mid-growth the rounding is
      // near the menu's, so the flying glass reads like the panel it will
      // land as instead of ballooning rounder and rounder for a second.
      final rounding = _clamp01(g / _openSizeS);
      final menuRound =
          _menuRadius / math.max(math.min(_menu[2], _menu[3]) / 2, 1);
      final roundFrom = _roundS > 0 ? 1.0 : _radiusFrom;
      // Never a corner sharper than the menu's while the drop is smaller.
      radius = math.max(
          _lerp(roundFrom, menuRound, math.sqrt(rounding)) *
              math.min(w, h) /
              2,
          math.min(_menuRadius, math.min(w / 2, h / 2)));
    }
    final k = _openSize(_clamp01(math.max(g, 0) / _openSizeS));
    final reveal = _clamp01(t / _revealS);
    final moving = !_x.settled(0.5) || !_y.settled(0.5);
    // Cubed, so the swing starts being taken out with no step in velocity.
    final swing = _lerp(1, _settledSwing, k * k * k);
    final x = _x.target + (_x.value - _x.target) * swing;
    final y = _y.target + (_y.value - _y.target) * swing;
    return MorphFrame(
      body: [x - w / 2, y - h / 2, w, h],
      bodyRadius: math.min(radius, math.min(w / 2, h / 2)),
      contentScale:
          _lerp(_contentFrom, 1, _easeOut(_clamp01(t / _contentScaleS))),
      contentOpacity: _clamp01(_opacity.value),
      lens: _lensFrom * (1 - _clamp01(t / _lensS) * _clamp01(t / _lensS)),
      glassOpacity: _lerp(_glassFrom, 1, reveal),
      soften: _lerp(_softenFrom, 0, reveal),
      // The glass shows up within the first ~0.1 s: the user reads the panel
      // almost immediately instead of waiting out the whole flight.
      reveal:
          _lerp(_glassRevealFrom, 1, _easeOut(_clamp01(t / _glassShowS))),
      done: !moving && g >= _openSizeS,
    );
  }

  // The items fade as they did when the glass opened to this size.
  double _closeOpacity(double w, double h) {
    final drop = _dropPx();
    final grown = math.min(
        (w - drop) / math.max(_menu[2] - drop, 1),
        (h - drop) / math.max(_menu[3] - drop, 1));
    final k = _clamp01(grown);
    double lo = 0, hi = 1;
    for (int i = 0; i < 16; i++) {
      final mid = (lo + hi) / 2;
      if (_openSize(mid) < k) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final idx = (lo * _openSizeS * _closeFadeHold / _fadeStepS)
        .round()
        .clamp(0, _openFade.length - 1);
    return _openFade[idx];
  }

  MorphFrame _close(double dt) {
    _stepSprings(dt);
    final t = _t;
    final drop = _dropPx();
    final targetW = math.min(_sizeFrom[0], drop);
    final targetH = math.min(_sizeFrom[1], drop);
    final k = _easeOut(_clamp01(t / _closeSizeS));
    double w = _lerp(_sizeFrom[0], targetW, k);
    double h = _lerp(_sizeFrom[1], targetH, k);
    // Rounding off into the drop as it shrinks, as the opening squares off.
    final radius = _lerp(_radiusFrom, math.min(w, h) / 2, k);
    var body = [_x.value - w / 2, _y.value - h / 2, w, h];
    var bodyRadius = math.min(radius, math.min(w / 2, h / 2));

    final hc = _rectCenter(_buttonRect);
    final near = math.sqrt(
            (_x.value - hc[0]) * (_x.value - hc[0]) +
                (_y.value - hc[1]) * (_y.value - hc[1])) <=
        _buttonRect[3] * _arriveHeights;
    if (_arrivedAt < 0 &&
        ((near && t >= _closeSizeS) ||
            t >= _arriveMaxS ||
            _sizeFrom[0] <= drop)) {
      _arrivedAt = t;
      _arrivedSize = [w, h];
    }
    var glassOpacity = 1.0;
    var since = -1.0;
    if (_arrivedAt >= 0) {
      // Into the capsule as it rises, ending on the button wherever the springs are.
      since = t - _arrivedAt;
      final c = _easeInOut(_clamp01(since / _closeCapsuleS));
      final aw = _arrivedSize[0];
      final ah = _arrivedSize[1];
      final bw = _buttonRect[2];
      final bh = _buttonRect[3];
      final cw = _lerp(aw, bw, c);
      final ch = _lerp(ah, bh, c);
      final cx = _lerp(_x.value, hc[0], c);
      final cy = _lerp(_y.value, hc[1], c);
      body = [cx - cw / 2, cy - ch / 2, cw, ch];
      bodyRadius = math.min(cw, ch) / 2;
      // The capsule fade rides on top of the travel fade that was built up.
      final capFade =
          1 - _easeInOut(_clamp01((since - _fadeDelayS) / _fadeS));
      glassOpacity = capFade * _travelFade;
    } else {
      // The drop starts going transparent while it is still on its way back,
      // but only slightly now: the panel must stay readable and melt at the
      // very end, not a third of the way home.
      _travelFade = math.min(
          _travelFade,
          1 - 0.25 * _easeInOut(_clamp01(t / _arriveMaxS)));
      glassOpacity = _travelFade;
    }
    // Measured from the furthest it got, so a menu that opened right below
    // the button does not start out half way down.
    final gap = _rectGap(body, _buttonRect);
    _furthest = math.max(_furthest, gap);
    final ramp = math.min(_buttonRect[3] * _softenHeights, _furthest);
    final closeness = ramp > 0 ? 1 - gap / ramp : 1.0;
    _soften = math.max(
        _soften,
        math.max(
            _clamp01(closeness),
            since >= 0 ? _clamp01(since / _softenS) : 0.0));
    final soften = _soften;
    // The whole glass holds until the capsule fade is nearly over, then melts
    // in the last ~0.1 s together with the travel fade. That is when the
    // panel actually disappears from the screen.
    final hideK = since >= 0
        ? _easeInOut(_clamp01((since - (_fadeDelayS + _fadeS - 0.02)) / 0.10))
        : 0.0;
    return MorphFrame(
      body: body,
      bodyRadius: bodyRadius,
      contentScale: _lerp(_contentFrom, _contentClosedScale,
          _easeOut(_clamp01(t / _contentScaleS))),
      contentOpacity: _closeOpacity(w, h),
      lens: _lerp(_lensFrom, 1, _easeOut(_clamp01(t / _lensS))),
      glassOpacity: glassOpacity,
      soften: soften,
      reveal: _glassRevealFrom * (1 - hideK),
      done: glassOpacity == 0,
    );
  }
}
