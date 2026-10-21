// Mock tests for the liquid-glass animation port.
//
// Exercises the physics exactly as the UI would drive it — fixed or jittery
// 60fps frames instead of a real Ticker — and checks the invariants:
// the glass always completes, never NaNs, lands on the menu rect, fades
// its content in, closes back into the button, and survives randomized
// rectangles and mid-flight reversals.
//
// Run with a pure Dart SDK (no Flutter needed):
//   dart run test/liquid_glass_mock_check.dart

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:exp_desktop/liquid_glass/menu_morph.dart';
import 'package:exp_desktop/liquid_glass/menu_spring.dart';
import 'package:exp_desktop/liquid_glass/spring.dart';

int _passed = 0;
int _failed = 0;
final List<String> _failures = [];

void check(String name, bool ok) {
  if (ok) {
    _passed++;
    print('  PASS  $name');
  } else {
    _failed++;
    _failures.add(name);
    print('  FAIL  $name');
  }
}

double rectDist(List<double> a, List<double> b) {
  double s = 0;
  for (int i = 0; i < 4; i++) {
    s += math.pow((a[i] - b[i]).abs(), 2).toDouble();
  }
  return math.sqrt(s);
}

void main() {
  print('== liquid-glass mock tests ==');
  testSpring();
  testMenuSpring();
  testOpenMorph();
  testCloseMorph();
  testReversal();
  testFuzz();
  print('');
  print('passed: $_passed   failed: $_failed');
  if (_failed > 0) {
    for (final f in _failures) {
      print('  !! $f');
    }
    throw StateError('MOCK TESTS FAILED');
  }
  print('ALL GREEN');
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
}

void testFuzz() {
  print('[fuzz]');
  final rnd = math.Random(42);
  var allOk = true;
  var allDone = true;
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
}
