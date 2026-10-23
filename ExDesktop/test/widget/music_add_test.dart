// The Add track path: Files in picker mode, and the Musics button that opens
// it. Files is fed a fake listing so the test never walks the real disk.

import 'package:exp_desktop/apps/audio_pick.dart';
import 'package:exp_desktop/apps/files_model.dart';
import 'package:exp_desktop/desktop/apps/files_app.dart';
import 'package:exp_desktop/desktop/apps/musics_app.dart';
import 'package:exp_desktop/playback/player_controller.dart';
import 'package:exp_desktop/playback/track.dart';
import 'package:exp_desktop/track_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Files shows a picker banner and a Use button on audio only',
      (tester) async {
    final picked = <String>[];
    final pick = ValueNotifier<AudioPickRequest?>(null);
    addTearDown(pick.dispose);

    await tester.pumpWidget(_host(
      FilesApp(
        startPath: r'C:\Music',
        lister: (path) async => const [
          FileEntry(
            name: 'Song.mp3',
            path: r'C:\Music\Song.mp3',
            isDirectory: false,
            size: 1024,
          ),
          FileEntry(
            name: 'notes.txt',
            path: r'C:\Music\notes.txt',
            isDirectory: false,
            size: 12,
          ),
        ],
        audioPick: pick,
      ),
    ));
    await _settle(tester);

    // No request: no banner, no Use buttons.
    expect(find.byKey(const ValueKey('audio-pick-banner')), findsNothing);
    expect(find.byKey(const ValueKey('files-pick-Song.mp3')), findsNothing);

    pick.value = AudioPickRequest(onPick: picked.add);
    await _settle(tester);

    expect(find.byKey(const ValueKey('audio-pick-banner')), findsOneWidget);
    expect(find.text('Choose an audio file to add to Musics'), findsOneWidget);
    expect(find.byKey(const ValueKey('files-pick-Song.mp3')), findsOneWidget);
    expect(find.byKey(const ValueKey('files-pick-notes.txt')), findsNothing);
    // The picker is a filter, not just a set of Use buttons: unsupported
    // files disappear while folders stay for navigation.
    expect(find.byKey(const ValueKey('files-entry-notes.txt')), findsNothing);
    expect(find.byKey(const ValueKey('files-entry-Song.mp3')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('files-pick-Song.mp3')));
    await tester.pump();
    expect(picked, [r'C:\Music\Song.mp3']);

    pick.value = null;
    await _settle(tester);
    expect(find.byKey(const ValueKey('audio-pick-banner')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancelling a pick clears the request', (tester) async {
    final pick = ValueNotifier<AudioPickRequest?>(null);
    addTearDown(pick.dispose);
    var cancelled = 0;

    await tester.pumpWidget(_host(
      FilesApp(
        startPath: r'C:\Music',
        lister: (path) async => const [],
        audioPick: pick,
      ),
    ));
    await _settle(tester);

    pick.value = AudioPickRequest(
      onPick: (_) {},
      onCancel: () {
        cancelled++;
        pick.value = null;
      },
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('audio-pick-cancel')));
    await _settle(tester);

    expect(cancelled, 1);
    expect(find.byKey(const ValueKey('audio-pick-banner')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double-clicking an audio file during a pick picks it',
      (tester) async {
    final picked = <String>[];
    final pick = ValueNotifier<AudioPickRequest?>(null);
    addTearDown(pick.dispose);

    await tester.pumpWidget(_host(
      FilesApp(
        startPath: r'C:\Music',
        lister: (path) async => const [
          FileEntry(
            name: 'Song.mp3',
            path: r'C:\Music\Song.mp3',
            isDirectory: false,
            size: 10,
          ),
        ],
        audioPick: pick,
      ),
    ));
    await _settle(tester);
    pick.value = AudioPickRequest(onPick: picked.add);
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('files-entry-Song.mp3')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(const ValueKey('files-entry-Song.mp3')));
    await _settle(tester);

    expect(picked, [r'C:\Music\Song.mp3']);
  });

  testWidgets('selecting a track stays paused until the play button',
      (tester) async {
    final engine = _FakeAudio();
    final player = PlayerController(engine: engine, vsync: const TestVSync());
    player.setTracks(const [
      Track(title: 'One', artist: 'A', file: 'one.mp3'),
      Track(title: 'Two', artist: 'B', file: 'two.mp3'),
    ], const {});

    await tester.pumpWidget(_host(MusicsApp(player: player)));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('musics-track-1')));
    await _settle(tester);

    expect(player.index, 1);
    expect(player.isPlaying, isFalse);
    expect(player.currentTime, '0:00');
    expect(engine.calls, isNot(contains('play')));

    await tester.tap(find.byKey(const ValueKey('musics-play')));
    await _settle(tester);
    expect(player.isPlaying, isTrue);
    expect(engine.calls, contains('play'));

    player.dispose();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the delete button hands the track to the shell',
      (tester) async {
    final engine = _FakeAudio();
    final player = PlayerController(engine: engine, vsync: const TestVSync());
    player.setTracks(const [
      Track(title: 'One', artist: 'A', file: 'one.mp3'),
    ], const {});
    Track? deleted;

    await tester.pumpWidget(_host(MusicsApp(
      player: player,
      onDeleteTrack: (track) => deleted = track,
    )));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('musics-delete-0')));
    await _settle(tester);

    expect(deleted?.title, 'One');
    expect(deleted?.file, 'one.mp3');
    player.dispose();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Musics has a working Add track button and shows the notice',
      (tester) async {
    final engine = _FakeAudio();
    final player = PlayerController(engine: engine, vsync: const TestVSync());
    final notice = ValueNotifier<String?>(null);
    addTearDown(notice.dispose);
    var added = 0;

    player.setTracks(const [
      Track(title: 'One', artist: 'A', file: 'one.mp3'),
      Track(title: 'Two', artist: 'B', file: 'two.mp3'),
    ], const {});

    await tester.pumpWidget(_host(
      MusicsApp(
        player: player,
        onAddTrack: () => added++,
        notice: notice,
      ),
    ));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('musics-add')));
    expect(added, 1);

    notice.value = 'Added: One';
    await _settle(tester);
    expect(find.text('Added: One'), findsOneWidget);

    // The list rows carry artwork now — the bug was that they did not.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('musics-track-0')),
        matching: find.byType(TrackArt),
      ),
      findsOneWidget,
    );
    expect(find.byType(TrackArt), findsAtLeastNWidgets(3));

    player.dispose();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 900, height: 620, child: child),
      ),
    );

Future<void> _settle(WidgetTester tester, {int frames = 40}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _FakeAudio implements AudioEngine {
  final List<String> calls = [];

  @override
  Future<void> playAsset(String asset) async => calls.add('play');

  @override
  Future<void> playFile(String path) async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> stop() async => calls.add('stop');

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