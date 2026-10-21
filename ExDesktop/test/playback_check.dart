// The playback math: the spin that settles upright, the beat pulse and the
// playlist rules. No audio device, no engine — just the numbers.
//
//   dart run test/playback_check.dart

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:exp_desktop/playback/beat.dart';
import 'package:exp_desktop/playback/playlist.dart';
import 'package:exp_desktop/playback/spin.dart';
import 'package:exp_desktop/playback/track.dart';
import 'mock_harness.dart';

void runPlaybackChecks() {
  _spin();
  _beat();
  _playlist();
  _time();
  _track();
}

void _spin() {
  section('artwork spin');
  final spin = SpinState();
  check('starts upright', spin.angle == 0);
  check('starts settled', spin.settled);

  spin.advance(0.05, playing: true);
  checkClose('50 ms turns at the spin speed', spin.angle,
      SpinState.speed * 0.05, 1e-9);
  check('a spinning orbit always needs frames', spin.needsFrames(true));

  // A long frame must not teleport the artwork.
  final before = spin.angle;
  spin.advance(2.0, playing: true);
  checkClose('a long frame is capped at 50 ms', spin.angle - before,
      SpinState.speed * 0.05, 1e-9);

  // Pause at an awkward angle and let it settle.
  spin.angle = 1.1;
  spin.velocity = SpinState.speed;
  var frames = 0;
  while (!spin.settled && frames < 600) {
    spin.advance(1 / 60, playing: false);
    frames++;
  }
  check('the spin settles after a pause', spin.settled);
  check('settling takes less than a second', frames < 60);
  checkClose('it settles upright (cos)', math.cos(spin.angle), 1.0, 1e-3);
  checkClose('it settles upright (sin)', math.sin(spin.angle), 0.0, 1e-3);
  check('the velocity is gone', spin.velocity.abs() < 0.02);
  check('a settled, paused spin needs no frames', !spin.needsFrames(false));

  // Every angle settles, not just the convenient one.
  var settledEverywhere = true;
  for (var i = 0; i < 40; i++) {
    final probe = SpinState()
      ..angle = i * 0.71
      ..velocity = (i.isEven ? 1 : -1) * 3.0;
    var steps = 0;
    while (!probe.settled && steps < 600) {
      probe.advance(1 / 60, playing: false);
      steps++;
    }
    if (!probe.settled ||
        (math.cos(probe.angle) - 1).abs() > 1e-3 ||
        steps >= 600) {
      settledEverywhere = false;
    }
  }
  check('forty random angles all settle upright', settledEverywhere);

  final shifted = SpinState()..angle = SpinState.twoPi * 3;
  shifted.advance(1 / 60, playing: false);
  check('a full turn is already upright', shifted.settled);

  spin.reset();
  check('reset puts it back upright', spin.angle == 0 && spin.velocity == 0);
  check('a zero step changes nothing', !spin.advance(0, playing: true));
}

void _beat() {
  section('beat pulse');
  checkClose('paused: no pulse', BeatPulse.scaleAt(0.3, playing: false), 1.0);
  checkClose('the hit is the tallest point',
      BeatPulse.scaleAt(0.0, playing: true), 1.0 + BeatPulse.amount, 1e-9);
  checkClose('half a beat is quieter',
      BeatPulse.scaleAt(0.25, playing: true),
      1.0 + BeatPulse.amount * math.exp(-0.5 * BeatPulse.decay), 1e-9);
  check('the pulse decays', BeatPulse.scaleAt(0.4, playing: true) <
      BeatPulse.scaleAt(0.1, playing: true));
  checkClose('the next beat hits again',
      BeatPulse.scaleAt(0.5, playing: true), BeatPulse.scaleAt(0.0, playing: true), 1e-9);
  checkClose('the pulse is periodic over two beats',
      BeatPulse.scaleAt(1.0, playing: true), BeatPulse.scaleAt(0.0, playing: true), 1e-9);

  var inRange = true;
  for (var i = 0; i < 200; i++) {
    final value = BeatPulse.scaleAt(i * 0.013, playing: true);
    if (value < 1.0 - 1e-9 || value > 1.0 + BeatPulse.amount + 1e-9) {
      inRange = false;
    }
  }
  check('the pulse never exceeds its budget', inRange);

  var phases = true;
  for (var i = 0; i < 100; i++) {
    final phase = BeatPulse.phaseAt(i * 0.09);
    if (phase < 0 || phase >= 1) phases = false;
  }
  check('the phase stays in 0..1', phases);
  checkClose('120 bpm is one beat every 500 ms',
      BeatPulse.phaseAt(0.5001), 0.0002, 0.01);
}

void _playlist() {
  section('playlist');
  checkEquals('next wraps at the end', PlaylistPolicy.next(2, 3), 0);
  checkEquals('next steps forward', PlaylistPolicy.next(0, 3), 1);
  checkEquals('previous wraps at the start', PlaylistPolicy.previous(0, 3), 2);
  checkEquals('previous steps back', PlaylistPolicy.previous(2, 3), 1);
  checkEquals('one track: next stays', PlaylistPolicy.next(0, 1), 0);
  checkEquals('one track: previous stays', PlaylistPolicy.previous(0, 1), 0);
  checkEquals('empty: next is safe', PlaylistPolicy.next(0, 0), 0);
  checkEquals('empty: previous is safe', PlaylistPolicy.previous(0, 0), 0);

  final rnd = math.Random(7);
  var neverSame = true;
  var inRange = true;
  for (var i = 0; i < 500; i++) {
    final next = PlaylistPolicy.next(1, 4, shuffle: true, random: rnd);
    if (next == 1) neverSame = false;
    if (next < 0 || next >= 4) inRange = false;
  }
  check('shuffle never repeats the current track', neverSame);
  check('shuffle stays in the list', inRange);

  final a = List<int>.generate(
      40, (_) => PlaylistPolicy.next(0, 5, shuffle: true, random: math.Random(99)));
  final b = List<int>.generate(
      40, (_) => PlaylistPolicy.next(0, 5, shuffle: true, random: math.Random(99)));
  check('a seeded shuffle is reproducible', '$a' == '$b');

  final visited = <int>{};
  final walk = math.Random(3);
  var index = 0;
  for (var i = 0; i < 200; i++) {
    index = PlaylistPolicy.next(index, 6, shuffle: true, random: walk);
    visited.add(index);
  }
  check('a random walk reaches every track', visited.length == 6);
}

void _time() {
  section('time formatting');
  checkEquals('zero', formatPlaybackTime(Duration.zero), '0:00');
  checkEquals('seconds are padded', formatPlaybackTime(const Duration(seconds: 9)), '0:09');
  checkEquals('minutes', formatPlaybackTime(const Duration(seconds: 72)), '1:12');
  checkEquals('long', formatPlaybackTime(const Duration(minutes: 61, seconds: 5)), '61:05');
  checkEquals('negative clamps to zero',
      formatPlaybackTime(const Duration(seconds: -30)), '0:00');
  checkEquals('milliseconds are floored',
      formatPlaybackTime(const Duration(milliseconds: 1999)), '0:01');
  checkEquals('a clock string parses',
      parsePlaybackTime('2:07')?.inSeconds, 127);
  checkEquals('a short clock string parses',
      parsePlaybackTime('0:09')?.inSeconds, 9);
  check('junk does not parse', parsePlaybackTime('soon') == null);
  check('an impossible minute does not parse', parsePlaybackTime('1:99') == null);
  checkEquals('the round trip holds',
      formatPlaybackTime(parsePlaybackTime('61:05')!), '61:05');
}

void _track() {
  section('track model');
  const track = Track(
    title: 'ICE',
    artist: 'Morgenshtern',
    file: 'ice.mp3',
    avatar: 'assets/music/a.jpg',
    duration: '2:00',
  );
  checkEquals('title', track.title, 'ICE');
  checkEquals('file', track.file, 'ice.mp3');
  final updated = track.withDuration('2:07');
  checkEquals('duration is replaced', updated.duration, '2:07');
  checkEquals('the other fields survive', updated.artist, 'Morgenshtern');
  checkEquals('the cover key survives', updated.avatar, 'assets/music/a.jpg');
  final bytes = Uint8List.fromList([1, 2, 3]);
  check('cover lookup by file',
      identical(track.coverIn({'ice.mp3': bytes}), bytes));
  check('missing cover is null', track.coverIn({}) == null);
}

void main() {
  runPlaybackChecks();
  finish('playback');
}