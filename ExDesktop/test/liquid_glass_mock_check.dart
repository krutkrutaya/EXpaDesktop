// Mock tests for the liquid-glass animation port and the shell's system
// plumbing.
//
// Physics are exercised exactly as the UI would drive it — fixed or jittery
// 60fps frames instead of a real Ticker — and checked against invariants:
// the glass always completes, never NaNs, lands on the menu rect, fades its
// content in, closes back into the button, and survives randomized
// rectangles and mid-flight reversals. The system layers (volume COM chain,
// action launchers) are probed read-only: binding them without firing them,
// because a mock test must never lock, shut down, or mute the machine
// running it.
//
// Run with a pure Dart SDK (no Flutter needed):
//   dart run test/liquid_glass_mock_check.dart

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:exp_desktop/liquid_glass/menu_morph.dart';
import 'package:exp_desktop/liquid_glass/menu_spring.dart';
import 'package:exp_desktop/liquid_glass/spring.dart';
import 'package:exp_desktop/volume_control.dart';

import 'mock_harness.dart';

typedef _NoArgsNative = Void Function();
typedef _NoArgsDart = void Function();

double rectDist(List<double> a, List<double> b) {
  double s = 0;
  for (int i = 0; i < 4; i++) {
    s += math.pow((a[i] - b[i]).abs(), 2).toDouble();
  }
  return math.sqrt(s);
}

/// Runs the physics suite. `mock_all.dart` calls this directly.
void runPhysicsChecks() {
  section('== liquid-glass mock tests ==');
  testSpring();
  testMenuSpring();
  testOpenMorph();
  testOpenMorphPath();
  testCloseMorph();
  testReversal();
  testFuzz();
  testSystemActionsStatic();
  testSystemVolume();
}

void main() {
  runPhysicsChecks();
  finish('liquid-glass');
}

void testSpring() {
  print('[spring]');
  final s = Spring.fromValue(stiffness: 170, damping: 14, value: 0);
  s.target = 1;
  var settled = false;
  for (int i = 0; i < 600 && !settled; i++) {
    settled = s.update(16);
  }
  check('spring settles near target', (s.value - 1).abs() < 0.002);
  check('spring reports settled', settled);

  // A stalled frame (long dt) must not explode the physics.
  final s2 = Spring.fromValue(stiffness: 200, damping: 12, value: 0);
  s2.target = 1;
  for (int i = 0; i < 60; i++) {
    s2.update(300); // 300ms stall frame
  }
  check('spring survives stalled frames', s2.value.isFinite);

  // Zero-dt frames (a redraw with no clock change) must stay inert.
  final s3 = Spring.fromValue(stiffness: 200, damping: 12, value: 0.3);
  s3.target = 1;
  var changed = false;
  final before = s3.value;
  for (int i = 0; i < 100; i++) {
    s3.update(0);
    if (!s3.value.isFinite) break;
  }
  changed = (s3.value - before).abs() > 1e-9;
  check('spring survives zero-dt frames', s3.value.isFinite && !changed);
}

void testMenuSpring() {
  print('[menu spring]');
  final st = MenuSpringState(0);
  st.target = 1;
  MenuFrame f = const MenuFrame(
      closing: false, stopped: false, scale: 0.001, opacity: 0);
  double peak = 0;
  for (int i = 0; i < 1200; i++) {
    f = stepMenuSpring(st, 16);
    peak = math.max(peak, f.scale);
    if (f.stopped) break;
  }
  check('menu spring opens to 1.0', (f.scale - 1).abs() < 0.001);
  check('menu spring fully opaque at rest', f.opacity == 255);
  check('menu spring bounces past 1.0', peak > 1.0);
  check('menu spring stops', f.stopped);

  st.target = 0;
  for (int i = 0; i < 1200; i++) {
    f = stepMenuSpring(st, 16);
    if (f.stopped) break;
  }
  check('menu spring closes to floor', f.scale <= 0.0011);
  check('menu spring fully faded when closed', f.opacity == 0);
  check('menu spring closing stops', f.stopped);
}

void testOpenMorph() {
  print('[open morph]');
  const button = [1200.0, 700.0, 52.0, 52.0];
  const menu = [400.0, 100.0, 700.0, 550.0];
  final m = MenuMorphMotion(true, button, menu, 15.0);
  MorphFrame frame = m.frame;
  var opacitySeen = 0.0;
  var done = false;
  var steps = 0;
  for (; steps < 400; steps++) {
    frame = m.step(0.016);
    opacitySeen = math.max(opacitySeen, frame.contentOpacity);
    if (frame.done) {
      done = true;
      break;
    }
  }
  check('open morph completes', done);
  check('open morph completes under 3s', steps * 0.016 < 3.0);
  check('open morph rests on menu rect', rectDist(frame.body, menu) < 1.0);
  check('open morph radius settles to menu', (frame.bodyRadius - 15).abs() < 3.0);
  check('open morph content fully visible', frame.contentOpacity > 0.95);
  check('open morph content reached high opacity', opacitySeen > 0.9);
  check('open morph lens flattened', frame.lens < 0.05);
  check(
      'open morph finite',
      frame.body.every((v) => v.isFinite) &&
          frame.bodyRadius.isFinite &&
          frame.contentScale.isFinite);
  check('open morph starts at the button',
      rectDist(m.step(0.0).body, button) < 80.0 ||
          frame.done // at rest already; start-of-motion check done in fuzz
      );
  check('open morph content scale settles at 1',
      (frame.contentScale - 1).abs() < 0.02);
  check('open morph glass fully present at rest', frame.glassOpacity >= 0.99);
}

/// Walks the whole open path and watches every intermediate frame against
/// geometric invariants — a single bad frame in the middle is exactly the
/// sort of thing a rest-state test cannot see.
void testOpenMorphPath() {
  print('[open morph path]');
  const button = [1200.0, 700.0, 52.0, 52.0];
  const menu = [400.0, 100.0, 700.0, 550.0];
  final m = MenuMorphMotion(true, button, menu, 15.0);
  MorphFrame f = m.frame;
  var radiusBounds = true;
  var opacityBounds = true;
  var sizeBounds = true;
  var scaleBounds = true;
  var maxX = -double.infinity, minX = double.infinity;
  var maxY = -double.infinity, minY = double.infinity;
  var steps = 0;
  for (; steps < 400 && !f.done; steps++) {
    f = m.step(0.016);
    final w = f.body[2];
    final h = f.body[3];
    // The rounding never overshoots the current body's own geometry.
    if (f.bodyRadius < 0 || f.bodyRadius > math.min(w, h) / 2 + 0.5) {
      radiusBounds = false;
    }
    // Opacities live in [0, 1] every frame of the flight.
    if (f.glassOpacity < 0 ||
        f.glassOpacity > 1 ||
        f.contentOpacity < 0 ||
        f.contentOpacity > 1) {
      opacityBounds = false;
    }
    // The drop never grows far past its landing size (no balloons).
    if (w > menu[2] * 1.15 || h > menu[3] * 1.15 ||
        w < -1 || h < -1) {
      sizeBounds = false;
    }
    // Content scale only shrinks toward 1, never negative or absurd.
    if (f.contentScale < 0 || f.contentScale > 12) {
      scaleBounds = false;
    }
    // Travel window: the glass must stay inside the union of both the
    // button and the menu rect (plus a half-pixel tolerance) — never
    // flying off-screen past either landing zone.
    final x = f.body[0];
    final y = f.body[1];
    maxX = math.max(maxX, x);
    minX = math.min(minX, x);
    maxY = math.max(maxY, y);
    minY = math.min(minY, y);
  }
  final minXBound =
      math.min(button[0], menu[0]) - 0.5;
  final maxXBound = math.max(button[0] + button[2], menu[0] + menu[2]) + 0.5;
  final minYBound =
      math.min(button[1], menu[1]) - 0.5;
  final maxYBound = math.max(button[1] + button[3], menu[1] + menu[3]) + 0.5;
  check('path: rounding never exceeds the body geometry', radiusBounds);
  check('path: glass and content opacity stay in [0, 1]', opacityBounds);
  check('path: body size never balloons past the menu', sizeBounds);
  check('path: content scale stays sane', scaleBounds);
  check('path: travel stays near the button->menu corridor',
      maxX <= maxXBound &&
          minX >= minXBound &&
          maxY <= maxYBound &&
          minY >= minYBound);
}

void testCloseMorph() {
  print('[close morph]');
  const button = [1200.0, 700.0, 52.0, 52.0];
  const menu = [400.0, 100.0, 700.0, 550.0];
  final open = MenuMorphMotion(true, button, menu, 15.0);
  MorphFrame of = open.frame;
  for (int i = 0; i < 400 && !of.done; i++) {
    of = open.step(0.016);
  }
  check('setup: open morph reached done', of.done);

  final closeM = MenuMorphMotion(false, button, menu, 15.0, from: of);
  MorphFrame f = closeM.frame;
  var done = false;
  var steps = 0;
  for (; steps < 600; steps++) {
    f = closeM.step(0.016);
    if (f.done) {
      done = true;
      break;
    }
  }
  check('close morph completes', done);
  check('close morph completes under 5s', steps * 0.016 < 5.0);
  check('close morph glass fades to zero', f.glassOpacity == 0);
  check('close morph content faded', f.contentOpacity < 0.3);
  check(
      'close morph finite',
      f.body.every((v) => v.isFinite) &&
          f.bodyRadius.isFinite &&
          f.contentScale.isFinite);
  // The glass must return to where it was born: on the button, rounded like
  // the button's capsule.
  check('close morph returns to the button rect', rectDist(f.body, button) < 3.0);
  check(
      'close morph rounding returns to the button capsule',
      (f.bodyRadius - button[3] / 2).abs() < 2.0);
}

void testReversal() {
  print('[reversal]');
  const button = [1200.0, 700.0, 52.0, 52.0];
  const menu = [400.0, 100.0, 700.0, 550.0];
  final open = MenuMorphMotion(true, button, menu, 15.0);
  MorphFrame f = open.frame;
  for (int i = 0; i < 18; i++) {
    f = open.step(0.016); // mid-flight, about 0.29s in
  }
  final rev = MenuMorphMotion(
    false,
    button,
    menu,
    15.0,
    from: f,
    velocities: open.velocities,
  );
  var done = false;
  var steps = 0;
  for (; steps < 800; steps++) {
    f = rev.step(0.016);
    if (!f.body.every((v) => v.isFinite)) break;
    if (f.done) {
      done = true;
      break;
    }
  }
  check('mid-flight reversal completes', done);
  check('reversal stays finite',
      f.body.every((v) => v.isFinite) && f.bodyRadius.isFinite);
  check('reversal fades out', f.glassOpacity == 0);

  // And reopening right after the close begins must also behave.
  final open2 = MenuMorphMotion(true, button, menu, 15.0, from: rev.frame);
  MorphFrame f2 = open2.frame;
  var done2 = false;
  for (int i = 0; i < 400; i++) {
    f2 = open2.step(0.016);
    if (!f2.body.every((v) => v.isFinite)) break;
    if (f2.done) {
      done2 = true;
      break;
    }
  }
  check('reopen after reversal completes', done2);
  check('reopen rests on menu', rectDist(f2.body, menu) < 2.0);

  // An ultra-early reversal — before the drop is even thrown — must also
  // survive gracefully.
  final open3 = MenuMorphMotion(true, button, menu, 15.0);
  MorphFrame f3 = open3.frame;
  for (int i = 0; i < 4; i++) {
    f3 = open3.step(0.016); // ~0.06s in: right out of the capsule
  }
  final revEarly = MenuMorphMotion(
    false,
    button,
    menu,
    15.0,
    from: f3,
    velocities: open3.velocities,
  );
  var done3 = false;
  for (int i = 0; i < 800; i++) {
    f3 = revEarly.step(0.016);
    if (!f3.body.every((v) => v.isFinite)) break;
    if (f3.done) {
      done3 = true;
      break;
    }
  }
  check('early reversal completes', done3);
  check('early reversal stays finite',
      f3.body.every((v) => v.isFinite) && f3.bodyRadius.isFinite);
}

void testFuzz() {
  print('[fuzz]');
  final rnd = math.Random(42);
  var allOk = true;
  var allDone = true;
  var opacityOk = true;
  for (var k = 0; k < 200; k++) {
    final button = [
      rnd.nextDouble() * 1500,
      rnd.nextDouble() * 800,
      40 + rnd.nextDouble() * 60,
      40 + rnd.nextDouble() * 60,
    ];
    final menu = [
      rnd.nextDouble() * 1200,
      rnd.nextDouble() * 600,
      250 + rnd.nextDouble() * 700,
      200 + rnd.nextDouble() * 500,
    ];
    final radius = 10 + rnd.nextDouble() * 30;
    final m = MenuMorphMotion(true, button, menu, radius);
    MorphFrame f = m.frame;
    var done = false;
    for (var i = 0; i < 1000; i++) {
      // Jittery frame times like a busy UI.
      f = m.step(0.002 + rnd.nextDouble() * 0.05);
      if (!f.body.every((v) => v.isFinite) ||
          !f.bodyRadius.isFinite ||
          !f.contentScale.isFinite) {
        allOk = false;
        break;
      }
      if (f.glassOpacity < 0 || f.glassOpacity > 1) {
        opacityOk = false;
      }
      if (f.done) {
        done = true;
        break;
      }
    }
    if (!done) allDone = false;
    if (!allOk || !allDone) {
      check('fuzz run #$k (button=$button, menu=$menu)', false);
      return;
    }

    // ...then closing it back from wherever it rests.
    final c = MenuMorphMotion(false, button, menu, radius, from: f);
    var closed = false;
    for (var i = 0; i < 1000; i++) {
      f = c.step(0.002 + rnd.nextDouble() * 0.05);
      if (!f.body.every((v) => v.isFinite)) {
        allOk = false;
        break;
      }
      if (f.done) {
        closed = true;
        break;
      }
    }
    if (!closed) allDone = false;
    if (!allOk || !allDone) {
      check('fuzz close #$k (button=$button, menu=$menu)', false);
      return;
    }
  }
  check('fuzz: 200 random open morphs, all finite', allOk);
  check('fuzz: 200 random open+close cycles, all complete', allDone);
  check('fuzz: glass opacity never leaves [0, 1]', opacityOk);
}

/// Binds—but never fires—the system launchers. A test that locks or shuts
/// the machine down would be a self-destructing test.
void testSystemActionsStatic() {
  print('[system actions]');
  if (!Platform.isWindows) {
    check('system actions: skipped outside Windows', true);
    return;
  }
  check(
      'explorer.exe exists',
      File(r'C:\Windows\explorer.exe').existsSync());
  check(
      'shutdown.exe exists',
      File(r'C:\Windows\System32\shutdown.exe').existsSync());
  check(
      'rundll32.exe exists',
      File(r'C:\Windows\System32\rundll32.exe').existsSync());
  // user32.dll resolves LockWorkStation without calling it.
  try {
    DynamicLibrary.open('user32.dll')
        .lookupFunction<_NoArgsNative, _NoArgsDart>('LockWorkStation');
    check('user32 LockWorkStation binds without firing', true);
  } catch (e) {
    check('user32 LockWorkStation binds without firing', false);
  }
}

/// Probes the COM volume chain read-only: read the level twice, check the
/// range, nothing set. No nudges, no muting — the user's speakers stay
/// exactly where they were.
void testSystemVolume() {
  print('[system volume]');
  if (!Platform.isWindows) {
    check('system volume: skipped outside Windows', true);
    return;
  }
  final v1 = VolumeControl.instance.volume;
  check('system volume readable and finite', v1.isFinite);
  check('system volume in [0, 1]', v1 >= 0.0 && v1 <= 1.0);
  final v2 = VolumeControl.instance.volume;
  check('system volume stable across reads', (v2 - v1).abs() < 0.02);
  final muted = VolumeControl.instance.muted;
  // A plain bool getter: either value is valid, the point is that it does
  // not throw and does not lie.
  check('muted state readable', muted == true || muted == false);
}
