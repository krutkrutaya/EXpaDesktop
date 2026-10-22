// EXWM: the window model, its server, and snapping. Pure Dart, so the window
// manager can be exercised without Flutter. EXPA's tests live in
// expa_check.dart.

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'package:exp_desktop/desktop/app_catalog.dart';
import 'package:exp_desktop/exwm/snap.dart';
import 'package:exp_desktop/exwm/window_manager.dart';
import 'package:exp_desktop/exwm/wm_server.dart';
import 'package:exp_desktop/exwm/workspaces.dart';

import 'mock_harness.dart';

void runExwmChecks() {
  _manager();
  _server();
  _snap();
}

void _manager() {
  section('[exwm manager]');
  const area = DesktopArea(1600, 900);
  final manager = WindowManager(area: area);

  final calc = manager.open(ShellApp.calculator);
  final notes = manager.open(ShellApp.notepad);
  checkEquals('two windows open', manager.count, 2);
  checkEquals('the newest is active', manager.activeId, notes.id);
  check('the newest is on top', manager.windows.last.id == notes.id);

  manager.focus(calc.id);
  checkEquals('focus raises', manager.activeId, calc.id);
  check('focus moves the window to the top', manager.windows.last.id == calc.id);

  manager.minimize(calc.id);
  check('minimize hides the window', manager.visible.length == 1);
  checkEquals('focus falls to the other window', manager.activeId, notes.id);
  check('a minimized window knows it', calc.minimized);

  manager.focus(calc.id);
  check('focus restores a minimized window', !calc.minimized);
  checkEquals('focus after restore', manager.activeId, calc.id);

  final cycled = manager.cycleFocus();
  check('cycle focus returns a window', cycled != null);
  check('cycle focus changes the active window', cycled!.id != calc.id);

  manager.close(notes.id);
  checkEquals('close removes a window', manager.count, 1);
  check('the active window survives', manager.activeId != null);
}

void _server() {
  section('[exwm server]');
  final workspaces = WorkspaceController(backgroundCount: 7);
  final server = WmServer(workspaces: workspaces, area: const DesktopArea(1600, 900));
  var notifications = 0;
  server.addListener(() => notifications++);

  final first = server.open(ShellApp.tasks);
  check('the server opens on the active workspace', server.activeManager.count == 1);
  checkEquals('one window across the server', server.windowCount, 1);

  workspaces.create(); // workspace 2
  check('a new workspace starts empty', server.activeManager.count == 0);
  final second = server.open(ShellApp.musics);
  checkEquals('two windows across the server', server.windowCount, 2);
  check('the managers differ', first.id >= 1 && second.id >= 1);

  workspaces.select(0);
  check('switching back finds the first window', server.activeManager.count == 1);
  final beforeFocus = notifications;
  server.focus(first.id);
  check('the server notifies on focus', notifications > beforeFocus);

  // Closing the active (second) workspace drops its manager.
  workspaces.select(1);
  workspaces.closeActive();
  check('closing a workspace prunes its windows',
      server.windowCount == 1 && server.managers.length == 1);
  server.dispose();
}

void _snap() {
  section('[exwm snap]');
  const area = DesktopArea(1600, 900);
  final max = area.maximizeRect;
  checkEquals('maximize left', max[0], 5.0);
  checkEquals('maximize top', max[1], 65.0);

  final left = snapRect(area, SnapZone.leftHalf, gap: 5);
  final right = snapRect(area, SnapZone.rightHalf, gap: 5);
  checkClose('left half width', left[2], 754, 0.01);
  checkClose('right half starts after the gap', right[0], 764, 0.01);
  checkClose('the two halves meet at the right edge', right[0] + right[2], 1518, 0.01);
  checkClose('the gap is real', right[0] - (left[0] + left[2]), 5, 0.01);

  final top = snapRect(area, SnapZone.topHalf, gap: 5);
  final bottom = snapRect(area, SnapZone.bottomHalf, gap: 5);
  checkClose('the top half height', top[3], 412.5, 0.01);
  checkClose('the bottom half starts after the gap', bottom[1], 482.5, 0.01);

  final tl = snapRect(area, SnapZone.topLeft, gap: 5);
  checkClose('a quarter is half wide', tl[2], 754, 0.01);
  checkClose('a quarter is half high', tl[3], 412.5, 0.01);
  check('maximize covers the full maximize rect',
      snapRect(area, SnapZone.maximize)[2] == max[2]);

  final manager = WindowManager(area: area);
  final window = manager.open(ShellApp.calculator);
  final before = List<double>.from(window.rect);
  check('snapActive snaps the focused window',
      manager.snapActive(SnapZone.leftHalf));
  checkClose('snapped to the left edge', window.rect[0], 5, 0.01);
  check('a snapped window can restore', window.maximized);
  manager.toggleMaximize(window.id);
  checkClose('restore returns the old rectangle', window.rect[0], before[0], 0.01);
  checkClose('restore width', window.rect[2], before[2], 0.01);

  // Edge snap on drag end: shove the window to the right edge and drop it.
  window.rect = [area.right - window.width + 10, 200, window.width, 400];
  check('dropping at the right edge snaps', manager.snapAfterDrag(window.id));
  checkClose('snapped right edge', window.rect[0] + window.rect[2], 1518, 0.01);

  manager.configure(snapEnabled: false);
  window.rect = [area.left - 30, 200, window.width, 400];
  check('snapping can be turned off', !manager.snapAfterDrag(window.id));

  manager.configure(snapEnabled: true, snapGap: 12);
  manager.snapTo(window.id, SnapZone.leftHalf);
  checkClose('the configured gap is used',
      snapRect(area, SnapZone.leftHalf, gap: 12)[2],
      window.rect[2],
      0.01);
}

void main() {
  runExwmChecks();
  finish('exwm');
}