// Flutter glue for the liquid-glass morph: owns a MenuMorphMotion and steps
// it on every frame via a Ticker, exposing the current MorphFrame.

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

import 'menu_morph.dart';

/// Drives a [MenuMorphMotion] from a [Ticker]. A null frame means hidden.
class MorphPanelController extends ChangeNotifier {
  MenuMorphMotion? _motion;
  MorphFrame? _frame;
  bool _isOpen = false;
  Ticker? _ticker;
  double _lastElapsed = 0;

  /// How fast the current motion is stepped. A dismissed menu can shrink
  /// away faster than it opened (see [close]); it is the same spring, played
  /// at a different speed.
  double _timeScale = 1.0;

  Rect4 _buttonRect;
  Rect4 _menuRect;
  double _menuRadius;
  TickerProvider? _vsync;

  MorphPanelController({
    required Rect4 buttonRect,
    required Rect4 menuRect,
    double menuRadius = 25.0,
    this.instantOpen = false,
  })  : _buttonRect = buttonRect,
        _menuRect = menuRect,
        _menuRadius = menuRadius;

  /// When true the panel skips the button flight entirely: the glass appears
  /// already full-size at the menu's rect and just fades in in place. The
  /// 9-dot launcher uses it, so the menu is never a drop that floats above
  /// its place and settles a second later.
  final bool instantOpen;

  MorphFrame? get frame => _frame;
  bool get isOpen => _isOpen;
  bool get animating => _ticker?.isActive ?? false;

  /// Visible in any form: opening, resting open, or closing.
  bool get active => _frame != null || _isOpen;

  void attach(TickerProvider vsync) {
    _vsync = vsync;
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTick);
  }

  void _onTick(Duration elapsed) {
    final motion = _motion;
    if (motion == null) return;
    final seconds = elapsed.inMicroseconds / 1e6;
    var dt = seconds - _lastElapsed;
    _lastElapsed = seconds;
    if (dt < 0) dt = 0;
    final frame = motion.step(dt * _timeScale);
    _frame = frame;
    if (frame.done) {
      if (motion.opening) {
        _isOpen = true;
      } else {
        _isOpen = false;
        _frame = null;
      }
      _stop();
    }
    notifyListeners();
  }

  void _stop() {
    // Keep the ticker around: Ticker.start() resumes with a fresh elapsed,
    // and stopping from inside the tick callback is safe — disposing is not.
    _ticker?.stop();
    _motion = null;
    _lastElapsed = 0;
    _timeScale = 1.0;
  }

  void open() {
    final prev = _motion;
    _stop();
    _motion = MenuMorphMotion(
      true,
      _buttonRect,
      _menuRect,
      _menuRadius,
      // A fresh instant panel starts as the finished glass in place (its
      // content then fades in), otherwise the flight hands its frame over.
      from: _startFrom(),
      // A motion that was already flying (opening or closing mid-air) hands
      // its velocity over, so the drop keeps sailing along its spring path
      // instead of restarting with a straight throw.
      velocities: prev?.velocities,
    );
    _isOpen = true;
    _start();
  }

  /// The frame the open motion starts from: the current mid-air frame after a
  /// reversal, the resting glass for a fresh open of an instant panel, or
  /// nothing (the button capsule) for a fresh flight.
  MorphFrame? _startFrom() {
    if (_frame != null) return _frame;
    if (!instantOpen) return null;
    return MorphFrame(
      body: List<double>.from(_menuRect),
      bodyRadius: _menuRadius,
      contentScale: 1,
      contentOpacity: 0,
      lens: 0,
      glassOpacity: 1,
      soften: 0,
      reveal: 0,
      done: false,
    );
  }

  /// Shrinks the panel back into its button.
  ///
  /// [speed] steps the same spring faster, for the case where a menu is
  /// dismissed because something else is opening: the window behind it should
  /// not have to wait through the full morph to be seen.
  void close({double speed = 1.0}) {
    if (_frame == null && !_isOpen) return;
    final prev = _motion;
    _timeScale = speed.clamp(1.0, 4.0);
    _motion = MenuMorphMotion(
      false,
      _buttonRect,
      _menuRect,
      _menuRadius,
      from: _frame,
      velocities: prev?.velocities,
    );
    _start();
  }

  void toggle() {
    final motion = _motion;
    if (motion != null) {
      // Spammable: a motion in flight reverses right where it is, following
      // the spring curve — you never have to wait for it to finish first.
      if (motion.opening) {
        close();
      } else {
        open();
      }
    } else if (_isOpen) {
      close();
    } else {
      open();
    }
  }

  void _start() {
    // Already ticking — the fresh motion gets picked up by the next tick.
    if (_ticker?.isActive ?? false) return;
    _lastElapsed = 0;
    if (_ticker == null && _vsync != null) {
      _ticker = _vsync!.createTicker(_onTick);
    }
    _ticker?.start();
  }

  /// Update where the button and menu are (they may move while it runs).
  void retarget(Rect4 button, Rect4 menu, double menuRadius) {
    _buttonRect = button;
    _menuRect = menu;
    _menuRadius = menuRadius;
    _motion?.retarget(button, menu, menuRadius);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}
