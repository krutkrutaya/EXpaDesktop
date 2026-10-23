// The in-app window manager: every application opens *inside* the shell.
//
// It exists because the shell used to hand every tile to Windows: Calculator
// started calc.exe, Browser started the default browser, and the "desktops"
// were Windows virtual desktops. The user asked for the opposite: the apps
// live in EXpaDesktop, slide out of the right dock, and each in-app desktop
// keeps its own windows.
//
// Pure Dart: no Flutter imports, so the whole model is checked by
// `dart run test/desktop_check.dart` (z-order, focus, maximize, dragging,
// resizing, clamping, per-desktop isolation) without an engine.

import 'dart:math' as math;

import '../desktop/app_catalog.dart';
import 'snap.dart';

/// A rectangle in logical pixels: `[left, top, width, height]`.
typedef Rect4 = List<double>;

/// The usable desktop: the shell window minus the waybar at the top and the
/// dock on the right. Windows never open underneath either of them.
class DesktopArea {
  final double width;
  final double height;

  const DesktopArea(this.width, this.height);

  /// Breathing room from the shell's left edge.
  static const double insetLeft = 24;

  /// Below the waybar (60 px tall, floating at the top).
  static const double insetTop = 78;

  /// The dock: 72 px wide, 5 px from the edge, plus a 16 px gap.
  static const double insetRight = 93;

  /// Above the shell's bottom edge.
  static const double insetBottom = 20;

  /// How far a maximized window sits from the shell's own surfaces: a tight
  /// 5 px from the waybar above, the dock on the right, and the screen's
  /// left/bottom edges (nothing else lives there). This is "just a bigger
  /// window", not a screen-edge-hugging fullscreen.
  static const double maximizeInsetLeft = 5;
  static const double maximizeInsetTop = 65; // waybar 60 tall + 5 gap
  static const double maximizeInsetRight = 82; // dock 72 wide + 5 margin + 5 gap
  static const double maximizeInsetBottom = 5;

  /// The smallest window the manager allows.
  static const double minWidth = 340;
  static const double minHeight = 240;

  double get left => insetLeft;
  double get top => insetTop;

  double get right {
    const minRight = insetLeft + minWidth;
    if (top > height || minRight > width) return width;
    return (width - insetRight).clamp(minRight, width).toDouble();
  }

  double get bottom {
    const minBottom = insetTop + minHeight;
    if (minBottom > height) return height;
    return (height - insetBottom).clamp(minBottom, height).toDouble();
  }

  double get usableWidth => (right - left).clamp(0, width).toDouble();
  double get usableHeight => (bottom - top).clamp(0, height).toDouble();

  /// Where a maximized window goes: 5 px away from the waybar and the dock,
  /// and 5 px from the free screen edges (left and bottom).
  Rect4 get maximizeRect {
    // No minimum window size here: a maximized window is the screen, even on
    // a tiny or artificially small test surface. Clamping to minWidth first
    // would make clamp throw when the surface is narrower than 340 px.
    final w = (width - maximizeInsetLeft - maximizeInsetRight)
        .clamp(0.0, width)
        .toDouble();
    final h = (height - maximizeInsetTop - maximizeInsetBottom)
        .clamp(0.0, height)
        .toDouble();
    return [maximizeInsetLeft, maximizeInsetTop, w, h];
  }

  /// True when [rect] lies inside the usable desktop.
  bool contains(Rect4 rect) =>
      rect[0] >= left - 0.01 &&
      rect[1] >= top - 0.01 &&
      rect[0] + rect[2] <= right + 0.01 &&
      rect[1] + rect[3] <= bottom + 0.01;

  @override
  String toString() => 'DesktopArea($width x $height, '
      'usable $left,$top .. $right,$bottom)';
}

/// One open window. Mutable on purpose: dragging a window 60 times a second
/// must not allocate a new list of windows every frame.
class AppWindow {
  AppWindow({
    required this.id,
    required this.app,
    required Rect4 rect,
    this.minimized = false,
  }) : rect = List<double>.from(rect);

  /// Unique inside one desktop; the widget keys use it.
  final int id;

  /// Which application is inside.
  final ShellApp app;

  /// Position and size, `[left, top, width, height]`.
  Rect4 rect;

  bool minimized;

  /// Incremented every time a minimized window comes back. The window widget
  /// reads it on mount to choose the restore genie instead of a fresh-open
  /// pop; a brand-new window starts at zero.
  int restoreCount = 0;

  /// The size before the window was maximized, restored on toggle.
  Rect4? restoreRect;

  bool get maximized => restoreRect != null;

  String get appId => app.id;
  String get title => app.title;

  double get left => rect[0];
  double get top => rect[1];
  double get width => rect[2];
  double get height => rect[3];

  @override
  String toString() =>
      'AppWindow($id ${app.id} ${rect.map((v) => v.round()).toList()}'
      '${minimized ? ' minimized' : ''}${maximized ? ' maximized' : ''})';
}

/// Owns the windows of one in-app desktop.
///
/// The shell makes one manager per workspace, so switching desktops swaps
/// the whole set of windows; nothing leaks between them.
class WindowManager {
  WindowManager({required this.area});

  DesktopArea area;

  /// Opening order == z-order: the last entry is on top.
  final List<AppWindow> _windows = [];
  int? _activeId;
  int _nextId = 1;

  /// How many windows were opened in this desktop, for the cascade.
  int _opened = 0;

  /// Edge snapping (drag a window to a screen edge to tile it).
  bool snapEnabled = true;

  /// The space between two snapped halves, in logical pixels.
  double snapGap = 5;

  List<AppWindow> get windows => List<AppWindow>.unmodifiable(_windows);
  int get count => _windows.length;

  /// The window with focus, if any.
  AppWindow? get active => _byId(_activeId);

  int? get activeId => _activeId;

  AppWindow? _byId(int? id) {
    if (id == null) return null;
    for (final window in _windows) {
      if (window.id == id) return window;
    }
    return null;
  }

  /// The window running [appId], if it is open.
  AppWindow? forApp(String appId) {
    for (final window in _windows) {
      if (window.appId == appId) return window;
    }
    return null;
  }

  bool isOpen(String appId) => forApp(appId) != null;

  /// Windows that are not minimized, in z-order.
  List<AppWindow> get visible =>
      _windows.where((w) => !w.minimized).toList(growable: false);

  /// Opens [app] (or brings its window back) and focuses it.
  ///
  /// Apps are singletons: "open Musics" twice focuses the player instead of
  /// stacking two copies on top of each other.
  AppWindow open(ShellApp app, {Rect4? rect, bool focus = true}) {
    final existing = forApp(app.id);
    if (existing != null) {
      if (existing.minimized) {
        existing.minimized = false;
        existing.restoreCount++;
      }
      if (focus) _raise(existing);
      return existing;
    }

    final placed =
        rect != null && area.contains(rect) ? List<double>.from(rect) : _place(app);
    final window = AppWindow(
      id: _nextId++,
      app: app,
      rect: placed,
    );
    _windows.add(window);
    _opened++;
    if (focus) _activeId = window.id;
    return window;
  }

  /// A cascade from the middle of the desktop: each new window steps down and
  /// to the left, so the title bar of the one underneath stays reachable.
  Rect4 _place(ShellApp app) {
    final size = _fitSize(app.width, app.height);
    final step = _opened % 5;
    final left = area.left + (area.usableWidth - size[0]) / 2 - step * 26;
    final top = area.top + (area.usableHeight - size[1]) / 2 + step * 22;
    return _clampRect([left, top, size[0], size[1]]);
  }

  /// Clamps a desired size to the usable desktop.
  List<double> _fitSize(double width, double height) {
    final maxWidth = area.usableWidth;
    final maxHeight = area.usableHeight;
    return [
      width
          .clamp(math.min(DesktopArea.minWidth, maxWidth), maxWidth)
          .toDouble(),
      height
          .clamp(math.min(DesktopArea.minHeight, maxHeight), maxHeight)
          .toDouble(),
    ];
  }

  /// Keeps a window fully on the usable desktop.
  Rect4 _clampRect(Rect4 rect) {
    final size = _fitSize(rect[2], rect[3]);
    final maxLeft = math.max(area.left, area.right - size[0]);
    final maxTop = math.max(area.top, area.bottom - size[1]);
    final left = rect[0].clamp(area.left, maxLeft).toDouble();
    final top = rect[1].clamp(area.top, maxTop).toDouble();
    return [left, top, size[0], size[1]];
  }

  /// Focuses a window and raises it above the others.
  void focus(int id) {
    final window = _byId(id);
    if (window == null) return;
    if (window.minimized) {
      window.minimized = false;
      window.restoreCount++;
    }
    _raise(window);
  }

  void _raise(AppWindow window) {
    _windows.remove(window);
    _windows.add(window);
    _activeId = window.id;
  }

  /// Closes a window. Focus falls to the next one down the stack.
  void close(int id) {
    final window = _byId(id);
    if (window == null) return;
    final wasActive = _activeId == id;
    _windows.remove(window);
    if (wasActive) {
      _activeId = _windows.isEmpty ? null : _windows.last.id;
    }
  }

  /// Hides a window without closing it. Focus moves to the next one.
  void minimize(int id) {
    final window = _byId(id);
    if (window == null || window.minimized) return;
    window.minimized = true;
    if (_activeId == id) {
      _activeId = _topVisible()?.id;
    }
  }

  /// Brings a minimized window back and focuses it.
  void restore(int id) {
    final window = _byId(id);
    if (window == null) return;
    window.minimized = false;
    window.restoreCount++;
    _raise(window);
  }

  AppWindow? _topVisible() {
    for (final window in _windows.reversed) {
      if (!window.minimized) return window;
    }
    return null;
  }

  /// Hides the focused window (the window's own minimize button).
  /// Returns true when something was minimized.
  bool minimizeActive() {
    final window = active;
    if (window == null || window.minimized) return false;
    minimize(window.id);
    return true;
  }

  /// Maximize / restore. The restore rect survives moves, so a maximized
  /// window that is dragged comes back to a sensible place.
  void toggleMaximize(int id) {
    final window = _byId(id);
    if (window == null) return;
    final saved = window.restoreRect;
    if (saved != null) {
      window.restoreRect = null;
      window.rect = _clampRect(saved);
      _raise(window);
      return;
    }
    window.restoreRect = List<double>.from(window.rect);
    // Maximized is tight to the screen: 5 px from the sides, not the old
    // inset rectangle with its wide margins.
    window.rect = area.maximizeRect;
    _raise(window);
  }

  /// Throws a window into one of EXWM's snap zones. Snapping remembers the
  /// pre-snap rectangle, so dragging a snapped window restores it, exactly
  /// like maximizing.
  void snapTo(int id, SnapZone zone) {
    final window = _byId(id);
    if (window == null) return;
    if (!window.maximized) {
      window.restoreRect = List<double>.from(window.rect);
    }
    window.rect = snapRect(area, zone, gap: snapGap);
    _raise(window);
  }

  /// Snaps the focused window.
  bool snapActive(SnapZone zone) {
    final window = active;
    if (window == null || window.minimized) return false;
    snapTo(window.id, zone);
    return true;
  }

  /// Called when a title-bar drag ends. If the window was left against an
  /// edge, tile it; a top-edge drag maximizes.
  bool snapAfterDrag(int id) {
    if (!snapEnabled) return false;
    final window = _byId(id);
    if (window == null) return false;
    const threshold = 26.0;
    final nearLeft = window.left <= area.left + threshold;
    final nearRight = window.left + window.width >= area.right - threshold;
    final nearTop = window.top <= area.top + threshold;
    final nearBottom = window.top + window.height >= area.bottom - threshold;
    SnapZone? zone;
    if (nearTop && nearLeft) {
      zone = SnapZone.topLeft;
    } else if (nearTop && nearRight) {
      zone = SnapZone.topRight;
    } else if (nearBottom && nearLeft) {
      zone = SnapZone.bottomLeft;
    } else if (nearBottom && nearRight) {
      zone = SnapZone.bottomRight;
    } else if (nearTop) {
      zone = SnapZone.maximize;
    } else if (nearLeft) {
      zone = SnapZone.leftHalf;
    } else if (nearRight) {
      zone = SnapZone.rightHalf;
    } else if (nearBottom) {
      zone = SnapZone.bottomHalf;
    }
    if (zone == null) return false;
    snapTo(id, zone);
    return true;
  }

  /// Applies the desktop environment's behaviour settings.
  void configure({bool? snapEnabled, double? snapGap}) {
    if (snapEnabled != null) this.snapEnabled = snapEnabled;
    if (snapGap != null) {
      this.snapGap = snapGap.clamp(0.0, 32.0).toDouble();
    }
  }

  /// Moves a window by a delta, keeping its title bar reachable.
  ///
  /// A window may hang off the edge a little (that is how every desktop
  /// works), but never so far that it cannot be grabbed again.
  void moveBy(int id, double dx, double dy) {
    final window = _byId(id);
    if (window == null) return;
    if (window.maximized) {
      // Dragging a maximized window restores its saved size first, then the
      // drag moves the restored window — the way Windows behaves.
      final saved = window.restoreRect;
      window.restoreRect = null;
      if (saved != null) window.rect = _clampRect(saved);
    }
    const keep = 160.0;
    final minLeft = area.left - window.width + keep;
    final maxLeft = math.max(minLeft, area.right - keep);
    final maxTop = math.max(area.top, area.bottom - 52);
    final left = (window.left + dx).clamp(minLeft, maxLeft).toDouble();
    final top = (window.top + dy).clamp(area.top, maxTop).toDouble();
    window.rect = [left, top, window.width, window.height];
  }

  /// Resizes from the bottom-right corner.
  void resizeBy(int id, double dw, double dh) {
    final window = _byId(id);
    if (window == null) return;
    window.restoreRect = null;
    final maxWidth = math.max(0.0, area.right - window.left);
    final maxHeight = math.max(0.0, area.bottom - window.top);
    final width = (window.width + dw)
        .clamp(math.min(DesktopArea.minWidth, maxWidth), maxWidth)
        .toDouble();
    final height = (window.height + dh)
        .clamp(math.min(DesktopArea.minHeight, maxHeight), maxHeight)
        .toDouble();
    window.rect = [window.left, window.top, width, height];
  }

  /// Re-fits every window after the shell window changed size.
  void retarget(DesktopArea next) {
    area = next;
    for (final window in _windows) {
      final restore = window.restoreRect;
      if (restore != null) window.restoreRect = _clampRect(restore);
      // A maximized window always lands on the new area's maximize rect, so
      // it keeps hugging the screen after a resize.
      window.rect =
          window.maximized ? List<double>.from(area.maximizeRect) : _clampRect(window.rect);
    }
  }

  /// Brings the next visible window to the front (Alt+Tab).
  AppWindow? cycleFocus() {
    final candidates = _windows.reversed.toList();
    if (candidates.isEmpty) return null;
    final current = candidates.indexWhere((w) => w.id == _activeId);
    for (var step = 1; step <= candidates.length; step++) {
      final window = candidates[(current + step) % candidates.length];
      if (!window.minimized) {
        _raise(window);
        return window;
      }
    }
    return null;
  }

  /// Closes the focused window; returns it, for the shell's own bookkeeping.
  AppWindow? closeActive() {
    final window = active;
    if (window == null) return null;
    close(window.id);
    return window;
  }
}