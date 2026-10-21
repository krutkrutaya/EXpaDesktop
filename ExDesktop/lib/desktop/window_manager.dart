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

import 'app_catalog.dart';

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
  List<double> _fitSize(double width, double height) => [
        width.clamp(DesktopArea.minWidth, area.usableWidth).toDouble(),
        height.clamp(DesktopArea.minHeight, area.usableHeight).toDouble(),
      ];

  /// Keeps a window fully on the usable desktop.
  Rect4 _clampRect(Rect4 rect) {
    final size = _fitSize(rect[2], rect[3]);
    final left = rect[0].clamp(
      area.left,
      (area.right - size[0]).clamp(area.left, area.right),
    ).toDouble();
    final top = rect[1].clamp(
      area.top,
      (area.bottom - size[1]).clamp(area.top, area.bottom),
    ).toDouble();
    return [left, top, size[0], size[1]];
  }

  /// Focuses a window and raises it above the others.
  void focus(int id) {
    final window = _byId(id);
    if (window == null) return;
    if (window.minimized) window.minimized = false;
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
    window.rect = [area.left, area.top, area.usableWidth, area.usableHeight];
    _raise(window);
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
    final maxLeft = area.right - keep;
    final left = (window.left + dx).clamp(minLeft, maxLeft).toDouble();
    final top = (window.top + dy).clamp(
      area.top,
      area.bottom - 52,
    ).toDouble();
    window.rect = [left, top, window.width, window.height];
  }

  /// Resizes from the bottom-right corner.
  void resizeBy(int id, double dw, double dh) {
    final window = _byId(id);
    if (window == null) return;
    window.restoreRect = null;
    final maxWidth = area.right - window.left;
    final maxHeight = area.bottom - window.top;
    final width = (window.width + dw)
        .clamp(DesktopArea.minWidth.clamp(0, maxWidth), maxWidth)
        .toDouble();
    final height = (window.height + dh)
        .clamp(DesktopArea.minHeight.clamp(0, maxHeight), maxHeight)
        .toDouble();
    window.rect = [window.left, window.top, width, height];
  }

  /// Re-fits every window after the shell window changed size.
  void retarget(DesktopArea next) {
    area = next;
    for (final window in _windows) {
      final restore = window.restoreRect;
      if (restore != null) window.restoreRect = _clampRect(restore);
      window.rect = _clampRect(window.rect);
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