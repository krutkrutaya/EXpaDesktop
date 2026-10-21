// The artwork rule, in one place: embedded cover, bundled image, or the
// shell's placeholder.
//
// The regression this locks down: the mini-player fell back to a hard-coded
// cover, so every track without art was shown with Монеточка's face.

import 'dart:typed_data';

import 'package:exp_desktop/track_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The canonical 1x1 transparent PNG, small enough to inline.
final Uint8List _tinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('a track without art gets the shell placeholder', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: TrackArt(size: 64))),
    ));

    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('empty cover bytes do not count as art', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: TrackArt(cover: Uint8List(0), size: 64)),
      ),
    ));

    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('an embedded cover is drawn instead of the placeholder',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: TrackArt(
            cover: _tinyPng,
            // Even with a bundled fallback around, the embedded cover wins.
            avatar: 'assets/music/ava-track-3.jpg',
            size: 64,
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsNothing);
  });

  testWidgets('the placeholder keeps the requested size', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: TrackArt(size: 38))),
    ));

    final size = tester.getSize(find.byType(TrackArt));
    expect(size.width, 38);
    expect(size.height, 38);
  });
}