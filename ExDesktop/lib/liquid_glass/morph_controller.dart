// Flutter glue for the liquid-glass morph: owns a MenuMorphMotion and steps
// it on every frame via a Ticker, exposing the current MorphFrame.

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

import 'menu_morph.dart';
import 'menu_spring.dart';

/// Drives a [MenuMorphMotion] from a [Ticker]. A null frame means hidden.
class MorphPanelController extends ChangeNotifier {
  MenuMorphMotion? _motion;
  MorphFrame? _frame;
  bool _isOpen = false;
  Ticker? _ticker;
  double _lastElapsed = 0;

  Rect4 _buttonRect;
  Rect4 _menuRect;
  double _menuRadius;
  TickerProvider? _vsync;

  MorphPanelController({
    required Rect4 buttonRect,
    required Rect4 menuRect,
    double menuRadius = 25.0,
  })  : _buttonRect = buttonRect,
        _menuRect = menuRect,
        _menuRadius = menuRadius;

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
    final frame = motion.step(dt);
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
  }

  void open() {
    final prev = _motion;
    _stop();
    _motion = MenuMorphMotion(
      true,
      _buttonRect,
      _menuRect,
      _menuRadius,
      from: _frame,
      velocities: prev != null && !prev.opening ? prev.velocities : null,
    );
    _isOpen = true;
    _start();
  }

  void close() {
    if (_frame == null && !_isOpen) return;
    final prev = _motion;
    _motion = MenuMorphMotion(
      false,
      _buttonRect,
      _menuRect,
      _menuRadius,
      from: _frame,
      velocities: prev != null && prev.opening ? prev.velocities : null,
    );
    _start();
  }

  void toggle() => (_isOpen || _frame != null) ? close() : open();

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

/// Drives the simpler [MenuFrame] scale spring (settings window).
class MenuSpringPanelController extends ChangeNotifier {
  MenuSpringState _state = MenuSpringState(0);
  MenuFrame _frame = const MenuFrame(
      closing: false, stopped: true, scale: 0.001, opacity: 0);
  Ticker? _ticker;
  double _lastElapsed = 0;

  MenuFrame get frame => _frame;
  bool get isOpen => _state.target == 1;

  void attach(TickerProvider vsync) {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTick);
  }

  void _onTick(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    var dt = seconds - _lastElapsed;
    _lastElapsed = seconds;
    if (dt < 0) dt = 0;
    if (dt <= 0) return;
    _frame = stepMenuSpring(_state, dt * 1000);
    if (_frame.stopped) {
      _ticker?.stop();
      _lastElapsed = 0;
    }
    notifyListeners();
  }

  void open() {
    _state.target = 1;
    _ensureRunning();
    notifyListeners();
  }

  void close() {
    _state.target = 0;
    _ensureRunning();
    notifyListeners();
  }

  void _ensureRunning() {
    if (_ticker?.isActive ?? false) return;
    _lastElapsed = 0;
    _ticker?.start();
  }

  void toggle() => isOpen ? close() : open();

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}
