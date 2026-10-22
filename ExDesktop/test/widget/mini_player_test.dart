// The mini player's artwork corners: a circle at rest, the glass radius on
// hover, and a tighter radius while pressed. The old implementation wrote the
// animated radius into a field that rebuilt an empty box, so hovering changed
// nothing — this test pins the behaviour.

import 'package:exp_desktop/playback/player_controller.dart';
import 'package:exp_desktop/playback/track.dart';
import 'package:exp_desktop/track_art.dart';
import 'package:exp_desktop/ui/mini_player.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hover and press animate the artwork rounding', (tester) async {
    final player = PlayerController(engine: _FakeAudio(), vsync: const TestVSync());
    player.setTracks(
      const [Track(title: 'One', artist: 'A', file: 'one.mp3')],
      const {},
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: MiniPlayer(player: player, onOpen: () {}),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    double radius() =>
        tester.widget<TrackArt>(find.byType(TrackArt)).borderRadius.topLeft.x;

    expect(radius(), 19.0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(TrackArt)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(radius(), lessThan(19.0));
    expect(radius(), greaterThan(7.0));

    await gesture.down(tester.getCenter(find.byType(TrackArt)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(radius(), lessThan(7.5));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    // Still hovered: back to the glass rounding, not the circle.
    expect(radius(), closeTo(10.0, 0.4));

    await gesture.moveTo(const Offset(2, 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(radius(), closeTo(19.0, 0.4));

    await gesture.removePointer();
    await tester.pump(const Duration(milliseconds: 300));
    player.dispose();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}

class _FakeAudio implements AudioEngine {
  @override
  Future<void> playAsset(String asset) async {}

  @override
  Future<void> playFile(String path) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<Duration?> position() async => Duration.zero;

  @override
  Stream<Duration> get onPosition => const Stream.empty();

  @override
  Stream<Duration> get onDuration => const Stream.empty();

  @override
  Stream<void> get onComplete => const Stream.empty();

  @override
  Future<void> dispose() async {}
}