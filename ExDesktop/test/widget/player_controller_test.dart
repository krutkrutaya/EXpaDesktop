// The player controller, driven without an audio device.
//
// The engine is a recorder and the ticker runs on the test scheduler, so this
// covers the parts a screenshot cannot: pause keeps the position, the artwork
// settles upright after a pause, completion advances the playlist, and a seek
// made before the track has loaded is applied when the duration arrives.

import 'dart:async';
import 'dart:math' as math;

import 'package:exp_desktop/playback/player_controller.dart';
import 'package:exp_desktop/playback/track.dart';
import 'package:flutter_test/flutter_test.dart';

const _tracks = [
  Track(title: 'One', artist: 'A', file: 'one.mp3', duration: '2:00'),
  Track(title: 'Two', artist: 'B', file: 'two.mp3', duration: '2:00'),
  Track(title: 'Three', artist: 'C', file: 'three.mp3', duration: '2:00'),
];

/// One test with a controller that is disposed before the test ends (an
/// active ticker at teardown counts as a leak).
void _playerTest(
  String name,
  Future<void> Function(WidgetTester tester, PlayerController player,
      _FakeAudio engine) body,
) {
  testWidgets(name, (tester) async {
    final engine = _FakeAudio();
    final player = PlayerController(engine: engine, vsync: const TestVSync());
    try {
      await body(tester, player, engine);
    } finally {
      player.dispose();
    }
  });
}

void main() {
  _playerTest('the library keeps the selected track when it is replaced',
      (tester, player, engine) async {

    player.setTracks(_tracks, const {});
    expect(player.tracks.length, 3);
    expect(player.track?.title, 'One');

    await player.select(1);
    expect(player.track?.title, 'Two');

    player.setTracks([
      const Track(title: 'Zero', artist: 'Z', file: 'zero.mp3'),
      ..._tracks,
    ], const {});
    expect(player.index, 2);
    expect(player.track?.title, 'Two');
  });

  _playerTest('play loads the asset and pause keeps the position',
      (tester, player, engine) async {
    player.setTracks(_tracks, const {});

    await player.play();
    await tester.pump(const Duration(milliseconds: 16));
    expect(player.isPlaying, isTrue);
    expect(engine.calls, contains('play'));
    expect(player.isLoaded, isTrue);

    engine.emitDuration(const Duration(seconds: 120));
    await tester.pump();
    engine.emitPosition(const Duration(seconds: 30));
    await tester.pump();
    expect(player.currentTime, '0:30');
    expect(player.progress.value, closeTo(0.25, 0.01));

    await player.pause();
    expect(player.isPlaying, isFalse);
    expect(engine.calls, contains('pause'));

    await player.play();
    // Resume, not a restart.
    expect(engine.calls.last, 'resume');
    expect(player.currentTime, '0:30');
    await tester.pump(const Duration(milliseconds: 400));
  });

  _playerTest('the artwork settles upright after a pause',
      (tester, player, engine) async {
    player.setTracks(_tracks, const {});

    await player.play();
    // Spin for ~700 ms so the angle is nowhere near a full turn.
    for (var i = 0; i < 44; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(player.debugAngle.abs(), greaterThan(0.4));

    await player.pause();
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final angle = player.debugAngle;
    expect(math.cos(angle), closeTo(1.0, 0.002));
    expect(math.sin(angle).abs(), lessThan(0.05));
    await tester.pump(const Duration(milliseconds: 400));
  });

  _playerTest('next and previous wrap the playlist',
      (tester, player, engine) async {
    player.setTracks(_tracks, const {});

    await player.next();
    expect(player.index, 1);
    await player.next();
    expect(player.index, 2);
    await player.next();
    expect(player.index, 0);
    await player.previous();
    expect(player.index, 2);
  });

  _playerTest('shuffle never repeats the current track',
      (tester, player, engine) async {
    player.setTracks(_tracks, const {});
    player.setShuffle(true);

    for (var i = 0; i < 40; i++) {
      final before = player.index;
      await player.next();
      expect(player.index, isNot(before));
      expect(player.index, inInclusiveRange(0, 2));
    }
  });

  _playerTest('completion advances to the next track',
      (tester, player, engine) async {
    player.setTracks(_tracks, const {});

    await player.play();
    await tester.pump(const Duration(milliseconds: 16));
    final playsBefore = engine.calls.where((c) => c == 'play').length;

    engine.complete();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(player.index, 1);
    expect(engine.calls.where((c) => c == 'play').length,
        greaterThan(playsBefore));
    expect(player.isPlaying, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
  });

  _playerTest('looping replays the same track',
      (tester, player, engine) async {
    player.setTracks(_tracks, const {});
    player.setLooping(true);

    await player.play();
    await tester.pump(const Duration(milliseconds: 16));
    engine.complete();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(player.index, 0);
    expect(player.isPlaying, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
  });

  _playerTest('a seek made before loading is applied at the duration',
      (tester, player, engine) async {
    player.setTracks(_tracks, const {});
    await player.select(1);

    await player.seekFraction(0.5);
    expect(player.currentTime, '1:00');
    expect(engine.calls.contains('seek'), isFalse);

    await player.play();
    await tester.pump(const Duration(milliseconds: 16));
    engine.emitDuration(const Duration(seconds: 120));
    await tester.pump();

    expect(engine.calls.contains('seek'), isTrue);
    expect(player.totalDuration, '2:00');
    await tester.pump(const Duration(milliseconds: 400));
  });

  _playerTest('seek while playing goes to the engine immediately',
      (tester, player, engine) async {
    player.setTracks(_tracks, const {});
    await player.play();
    await tester.pump(const Duration(milliseconds: 16));
    engine.emitDuration(const Duration(seconds: 100));
    await tester.pump();

    engine.calls.clear();
    await player.seekFraction(0.25);
    expect(engine.calls, contains('seek'));
    expect(player.currentTime, '0:25');
    await tester.pump(const Duration(milliseconds: 400));
  });

  _playerTest('the beat scale stays subtle and pauses flat',
      (tester, player, engine) async {

    expect(player.beatScaleAt(0), 1.0);
    player.setTracks(_tracks, const {});
    await player.play();
    await tester.pump(const Duration(milliseconds: 16));
    final beat = player.beatScaleAt(0);
    expect(beat, greaterThan(1.0));
    expect(beat, lessThan(1.06));
    await player.pause();
    expect(player.beatScaleAt(0), 1.0);
    await tester.pump(const Duration(milliseconds: 400));
  });
}

class _FakeAudio implements AudioEngine {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durations =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completions = StreamController<void>.broadcast();

  final List<String> calls = [];

  void emitPosition(Duration position) => _positions.add(position);
  void emitDuration(Duration duration) => _durations.add(duration);
  void complete() {
    _completions.add(null);
  }

  @override
  Future<void> playAsset(String asset) async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> seek(Duration position) async => calls.add('seek');

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<Duration?> position() async => Duration.zero;

  @override
  Stream<Duration> get onPosition => _positions.stream;

  @override
  Stream<Duration> get onDuration => _durations.stream;

  @override
  Stream<void> get onComplete => _completions.stream;

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _durations.close();
    await _completions.close();
  }
}