// The in-app window manager and the app catalog, checked without Flutter.
//
//   dart run test/desktop_check.dart
//
// Everything the window manager promises is a statement about data: the
// z-order, the focus, the clamp that keeps a title bar reachable, the
// per-desktop isolation. Those are the promises the UI relies on, so they are
// checked here instead of being eyeballed in a screenshot.

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'package:exp_desktop/desktop/app_catalog.dart';
import 'package:exp_desktop/desktop/window_manager.dart';
import 'mock_harness.dart';

void runDesktopChecks() {
  _catalog();
  _area();
  _opening();
  _focusAndClosing();
  _minimizeAndRestore();
  _maximize();
  _move();
  _resize();
  _retarget();
  _perDesktop();
}

void _catalog() {
  section('app catalog');
  checkEquals('ten built-in apps', ShellApp.values.length, 10);
  final ids = ShellApp.values.map((app) => app.id).toSet();
  checkEquals('ids are unique', ids.length, ShellApp.values.length);
  checkEquals('settings id', ShellApp.settings.id, 'settings');
  checkEquals('settings title', ShellApp.settings.title, 'Settings');
  checkEquals('musics title', ShellApp.musics.title, 'Musics');
  check('byId finds notepad', ShellApp.byId('notepad') == ShellApp.notepad);
  check('byId rejects junk', ShellApp.byId('does-not-exist') == null);
  for (final app in ShellApp.values) {
    check(
      '${app.id}: opens at least the minimum size',
      app.width >= DesktopArea.minWidth && app.height >= DesktopArea.minHeight,
    );
  }
}

void _area() {
  section('desktop area');
  const big = DesktopArea(1920, 1080);
  checkClose('left inset', big.left, 24);
  checkClose('top inset is below the waybar', big.top, 78);
  checkClose('right inset is left of the dock', big.right, 1827);
  checkClose('bottom inset', big.bottom, 1060);
  checkClose('usable width', big.usableWidth, 1803);
  checkClose('usable height', big.usableHeight, 982);
  check(
    'a window at the origin of the area is inside',
    big.contains([24, 78, 400, 300]),
  );
  check(
    'a window under the dock is outside',
    !big.contains([1500, 200, 400, 300]),
  );
  check(
    'a window above the waybar is outside',
    !big.contains([100, 10, 400, 300]),
  );

  const small = DesktopArea(800, 600);
  checkClose('small screen: right edge', small.right, 707);
  checkClose('small screen: bottom edge', small.bottom, 580);
  check('small screen still offers the minimum width',
      small.usableWidth >= DesktopArea.minWidth);
  check('small screen still offers the minimum height',
      small.usableHeight >= DesktopArea.minHeight);

  const tiny = DesktopArea(360, 300);
  check('tiny screen: right stays on screen', tiny.right <= 360);
  check('tiny screen: usable width is positive', tiny.usableWidth > 0);
  check('tiny screen: usable height is positive', tiny.usableHeight > 0);
}

void _opening() {
  section('opening windows');
  final wm = WindowManager(area: const DesktopArea(1920, 1080));

  checkEquals('starts empty', wm.count, 0);
  check('starts without focus', wm.active == null);

  final calc = wm.open(ShellApp.calculator);
  checkEquals('one window after open', wm.count, 1);
  checkEquals('the app is remembered', calc.app, ShellApp.calculator);
  checkEquals('id starts at 1', calc.id, 1);
  check('the first window gets focus', wm.active?.id == calc.id);
  check('isOpen knows it', wm.isOpen('calculator'));
  check('placed inside the desktop', wm.area.contains(calc.rect));
  checkClose('placed at the default width', calc.width, 360);
  checkClose('placed at the default height', calc.height, 500);

  final again = wm.open(ShellApp.calculator);
  checkEquals('singleton: still one window', wm.count, 1);
  check('singleton: same instance', identical(calc, again));

  final notes = wm.open(ShellApp.notepad);
  checkEquals('second window', wm.count, 2);
  check('the cascade moves the next one left', notes.left < calc.left);
  check('the cascade moves the next one down', notes.top > calc.top);
  check('the cascade stays inside', wm.area.contains(notes.rect));
  check('the newest window has focus', wm.active?.id == notes.id);

  // Five windows: the sixth wraps the cascade back to the first step.
  wm.open(ShellApp.files);
  wm.open(ShellApp.paint);
  wm.open(ShellApp.tasks);
  final sixth = wm.open(ShellApp.terminal);
  check('the sixth window is still inside', wm.area.contains(sixth.rect));
  checkEquals('six windows', wm.count, 6);

  final withRect = WindowManager(area: const DesktopArea(1920, 1080))
      .open(ShellApp.browser, rect: [100, 100, 800, 500]);
  checkClose('an explicit rect is honoured: left', withRect.left, 100);
  checkClose('an explicit rect is honoured: width', withRect.width, 800);
}

void _focusAndClosing() {
  section('focus and closing');
  final wm = WindowManager(area: const DesktopArea(1920, 1080));
  final a = wm.open(ShellApp.calculator);
  final b = wm.open(ShellApp.notepad);
  final c = wm.open(ShellApp.files);

  check('c is on top', wm.windows.last.id == c.id);
  wm.focus(a.id);
  check('focusing a raises it', wm.windows.last.id == a.id);
  check('focusing a activates it', wm.activeId == a.id);
  checkEquals('z-order keeps every window', wm.count, 3);
  check('windows are unique in the stack',
      wm.windows.map((w) => w.id).toSet().length == 3);

  wm.close(a.id);
  checkEquals('closing removes the window', wm.count, 2);
  check('focus falls to the top remaining', wm.activeId == wm.windows.last.id);
  check('closing a raised window keeps the others',
      wm.windows.any((w) => w.id == b.id) && wm.windows.any((w) => w.id == c.id));

  final closed = wm.closeActive();
  checkEquals('closeActive returns the window', closed?.app, ShellApp.files);
  checkEquals('closeActive removes it', wm.count, 1);
  wm.close(b.id);
  check('the last close leaves no focus', wm.activeId == null);
  check('closing an unknown id is harmless', () {
    wm.close(999);
    return wm.count == 0;
  }());
}

void _minimizeAndRestore() {
  section('minimize and restore');
  final wm = WindowManager(area: const DesktopArea(1920, 1080));
  final a = wm.open(ShellApp.calculator);
  final b = wm.open(ShellApp.notepad);

  wm.minimize(b.id);
  check('minimized window is hidden', !wm.visible.any((w) => w.id == b.id));
  check('minimizing the active window moves focus', wm.activeId == a.id);
  check('the minimized window is still open', wm.isOpen('notepad'));
  checkEquals('minimized windows are still counted', wm.count, 2);

  wm.open(ShellApp.notepad);
  check('opening a minimized app restores it', !wm.forApp('notepad')!.minimized);
  check('and focuses it', wm.activeId == b.id);

  wm.minimize(a.id);
  wm.focus(a.id);
  check('focusing a minimized window restores it', !a.minimized);
  check('restoring raises it', wm.windows.last.id == a.id);

  check('minimizeActive works', wm.minimizeActive());
  check('minimizeActive moved the focus away', wm.activeId != a.id);
  check('a second minimizeActive still has work', wm.minimizeActive());
  check('nothing visible is left', wm.visible.isEmpty);
  check('minimizeActive with nothing visible is false', !wm.minimizeActive());
}

void _maximize() {
  section('maximize');
  final wm = WindowManager(area: const DesktopArea(1920, 1080));
  final w = wm.open(ShellApp.files, rect: [200, 140, 600, 400]);

  wm.toggleMaximize(w.id);
  check('maximized', w.maximized);
  checkClose('maximized left', w.left, 24);
  checkClose('maximized top', w.top, 78);
  checkClose('maximized width', w.width, wm.area.usableWidth);
  checkClose('maximized height', w.height, wm.area.usableHeight);
  check('maximizing raises the window', wm.windows.last.id == w.id);

  wm.toggleMaximize(w.id);
  check('restored', !w.maximized);
  checkClose('restore left', w.left, 200);
  checkClose('restore top', w.top, 140);
  checkClose('restore width', w.width, 600);
  checkClose('restore height', w.height, 400);

  wm.toggleMaximize(w.id);
  wm.moveBy(w.id, 40, 40);
  check('dragging a maximized window restores it', !w.maximized);
  check('and the window moved', w.left > 24);
}

void _move() {
  section('moving');
  final wm = WindowManager(area: const DesktopArea(1920, 1080));
  final w = wm.open(ShellApp.calculator, rect: [400, 300, 360, 500]);

  wm.moveBy(w.id, 100, 50);
  checkClose('moved right', w.left, 500);
  checkClose('moved down', w.top, 350);

  wm.moveBy(w.id, 10000, 0);
  check('cannot be dragged past the right edge',
      w.left <= wm.area.right - 160 + 0.01);
  wm.moveBy(w.id, -10000, 0);
  check('the title bar stays reachable on the left',
      w.left >= wm.area.left - w.width + 160 - 0.01);
  wm.moveBy(w.id, 0, -10000);
  check('cannot be dragged above the waybar', w.top >= wm.area.top);
  wm.moveBy(w.id, 0, 10000);
  check('cannot be dragged below the desktop',
      w.top <= wm.area.bottom - 52 + 0.01);

  check('moving keeps the size', w.width == 360 && w.height == 500);
}

void _resize() {
  section('resizing');
  final wm = WindowManager(area: const DesktopArea(1920, 1080));
  final w = wm.open(ShellApp.calculator, rect: [300, 200, 400, 400]);

  wm.resizeBy(w.id, 120, 80);
  checkClose('grew right', w.width, 520);
  checkClose('grew down', w.height, 480);
  checkClose('resize keeps the origin', w.left, 300);

  wm.resizeBy(w.id, -5000, -5000);
  checkClose('clamped to the minimum width', w.width, DesktopArea.minWidth);
  checkClose('clamped to the minimum height', w.height, DesktopArea.minHeight);

  wm.resizeBy(w.id, 5000, 5000);
  check('cannot grow past the right edge',
      w.left + w.width <= wm.area.right + 0.01);
  check('cannot grow past the bottom edge',
      w.top + w.height <= wm.area.bottom + 0.01);

  wm.toggleMaximize(w.id);
  wm.resizeBy(w.id, 50, 50);
  check('resizing a maximized window leaves maximize mode', !w.maximized);
}

void _retarget() {
  section('retarget');
  final wm = WindowManager(area: const DesktopArea(1920, 1080));
  final a = wm.open(ShellApp.files, rect: [1000, 500, 700, 500]);
  final b = wm.open(ShellApp.paint);
  wm.toggleMaximize(b.id);

  wm.retarget(const DesktopArea(1280, 720));
  check('windows stay inside after a shrink', wm.area.contains(a.rect));
  check('a maximized window is re-fitted', wm.area.contains(b.rect));
  checkClose('the maximized window tracks the area',
      b.width, wm.area.usableWidth);

  wm.retarget(const DesktopArea(1920, 1080));
  wm.toggleMaximize(b.id);
  check('the restore rect was re-fitted too', wm.area.contains(b.rect));
}

void _perDesktop() {
  section('per-desktop isolation');
  const area = DesktopArea(1920, 1080);
  final one = WindowManager(area: area);
  final two = WindowManager(area: area);

  one.open(ShellApp.calculator);
  one.open(ShellApp.notepad);
  checkEquals('desktop one has two windows', one.count, 2);
  checkEquals('desktop two stays empty', two.count, 0);
  two.open(ShellApp.musics);
  checkEquals('desktop two has its own window', two.count, 1);
  check('desktop two does not see desktop one',
      !two.isOpen('calculator') && two.isOpen('musics'));
  check('desktop one does not see desktop two', !one.isOpen('musics'));

  final a = one.open(ShellApp.calculator);
  final b = one.open(ShellApp.notepad);
  final ra = a.rect.toList();
  one.close(a.id);
  check('closing on one desktop leaves the other untouched',
      two.count == 1 && b.width > 0 && ra.length == 4);
}

void main() {
  runDesktopChecks();
  finish('desktop');
}