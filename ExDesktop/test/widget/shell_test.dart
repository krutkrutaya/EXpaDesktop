// Widget tests for the shell: the in-app windows, the launcher, the waybar,
// the workspaces, the panels and the player path.
//
// The radios, the sound and the audio engine run on recorders, so a test never
// spawns PowerShell, mutes the speakers or plays a track. The workspace and
// window managers are the real ones — they live entirely inside the app.
//
// Run with: flutter test

import 'dart:async';

import 'package:exp_desktop/main.dart';
import 'package:exp_desktop/playback/player_controller.dart';
import 'package:exp_desktop/radio_control.dart';
import 'package:exp_desktop/sound_control.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the shell draws on startup', (tester) async {
    await _pumpShell(tester);

    expect(find.byKey(const ValueKey('waybar')), findsOneWidget);
    expect(find.byKey(const ValueKey('apps-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-dots')), findsOneWidget);
    expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the waybar has no dead four-squares button', (tester) async {
    await _pumpShell(tester);
    expect(find.byIcon(Icons.widgets_outlined), findsNothing);
  });

  testWidgets('a launcher tile opens an in-app window and closes the launcher',
      (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('launcher-app-calculator')), findsOneWidget);
    expect(find.text('Calculator'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('launcher-app-calculator')));
    await _settle(tester);

    // The launcher is gone, the calculator window is on the desktop.
    expect(find.byKey(const ValueKey('launcher-app-calculator')), findsNothing);
    expect(find.byKey(const ValueKey('calc-display')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-app-calculator')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the window arrives with an animation, not instantly',
      (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('launcher-app-calculator')));

    // The launcher shrinks away first (it plays its close at 2.6x); the window
    // starts its own entrance ~150 ms later, so it is not hidden behind the
    // menu. A few frames into that entrance it is still transparent.
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pump(const Duration(milliseconds: 32));
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('window-1')),
        matching: find.byType(Opacity),
      ).first,
    );
    expect(opacity.opacity, lessThan(1.0));

    await _settle(tester);
    final settled = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('window-1')),
        matching: find.byType(Opacity),
      ).first,
    );
    expect(settled.opacity, 1.0);
  });

  testWidgets('the dock icon joins with the window, it does not pop in',
      (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('launcher-app-calculator')));

    // Right after the window starts, its dock icon is still fading in.
    await tester.pump(const Duration(milliseconds: 160));
    final fade = tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byKey(const ValueKey('dock-app-calculator')),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, lessThan(1.0));

    await _settle(tester);
    final settled = tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byKey(const ValueKey('dock-app-calculator')),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(settled.opacity.value, 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the calculator buttons really calculate', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'calculator');

    await tester.tap(find.text('7'));
    await tester.tap(find.text('＋'));
    await tester.tap(find.text('5'));
    await tester.tap(find.text('='));
    await tester.pump();

    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the close button removes the window after its exit animation',
      (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'calculator');

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('window-1')),
      matching: find.byKey(const ValueKey('window-close')),
    ));
    await _settle(tester);

    expect(find.byKey(const ValueKey('calc-display')), findsNothing);
    expect(find.byKey(const ValueKey('dock-app-calculator')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimize hides the window and the dock brings it back',
      (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'tasks');

    await tester.tap(find.byKey(const ValueKey('window-minimize')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tasks-input')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('dock-app-tasks')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tasks-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window can be dragged by its title bar', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'calculator');

    final before = tester.getTopLeft(find.byKey(const ValueKey('window-1')));
    await tester.drag(find.text('Calculator'), const Offset(120, 70));
    // Let the double-tap recogniser's timer expire before the test ends.
    await tester.pump(const Duration(milliseconds: 400));

    final after = tester.getTopLeft(find.byKey(const ValueKey('window-1')));
    // The pan recogniser eats ~20 px of slop before it starts moving.
    expect(after.dx, greaterThan(before.dx + 80));
    expect(after.dy, greaterThan(before.dy + 30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window can be resized from the corner', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'tasks');

    final before = tester.getSize(find.byKey(const ValueKey('window-1')));
    await tester.drag(
      find.byKey(const ValueKey('window-resize')),
      const Offset(90, 50),
    );
    await tester.pump();

    final after = tester.getSize(find.byKey(const ValueKey('window-1')));
    expect(after.width, greaterThan(before.width + 70));
    expect(after.height, greaterThan(before.height + 30));
  });

  testWidgets('double-clicking the title bar maximizes and restores',
      (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'tasks');

    final before = tester.getSize(find.byKey(const ValueKey('window-1')));
    await tester.tap(find.text('Tasks'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Tasks'));
    await _settle(tester, frames: 60);

    final maximized = tester.getSize(find.byKey(const ValueKey('window-1')));
    expect(maximized.width, greaterThan(before.width + 200));
    expect(maximized.width, 1483);

    await tester.tap(find.text('Tasks'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Tasks'));
    await _settle(tester, frames: 60);

    final restored = tester.getSize(find.byKey(const ValueKey('window-1')));
    expect(restored.width, before.width);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the desktop does not close an app window', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'calculator');

    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);

    expect(find.byKey(const ValueKey('calc-display')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the settings window opens inside the shell', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('topbar-wifi')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('settings-row-wifi')), findsOneWidget);
    expect(find.text('Wi-Fi & internet'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('dock-settings')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sound flyout stays open next to a window', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'tasks');

    await tester.tap(find.byKey(const ValueKey('topbar-volume')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('volume-flyout')), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks-input')), findsOneWidget);
  });

  testWidgets('tapping the desktop closes the sound flyout', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('topbar-volume')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('volume-flyout')), findsOneWidget);

    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);
    expect(find.byKey(const ValueKey('volume-flyout')), findsNothing);
  });

  testWidgets('the workspace panel stays open while desktops are added',
      (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('desktop-dots')));
    await _settle(tester);
    expect(find.text('Desktop 1 of 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workspace-new')));
    await _settle(tester, frames: 60);
    await tester.tap(find.byKey(const ValueKey('workspace-new')));
    await _settle(tester, frames: 60);

    // The panel did not close; the chips grew.
    expect(find.byKey(const ValueKey('workspace-new')), findsOneWidget);
    expect(find.text('Desktop 3 of 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-chip-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-dot-2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workspace-close')));
    await _settle(tester, frames: 60);
    expect(find.text('Desktop 2 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chip switches desktops and the windows follow', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'calculator');

    await tester.tap(find.byKey(const ValueKey('desktop-dots')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('workspace-new')));
    await _settle(tester, frames: 60);
    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);

    // Desktop 2 has no windows of its own.
    expect(find.byKey(const ValueKey('calc-display')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('desktop-dots')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('workspace-chip-0')));
    await _settle(tester);
    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);

    expect(find.byKey(const ValueKey('calc-display')), findsOneWidget);
  });

  testWidgets('the mouse wheel over the dots scrolls desktops', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('desktop-dots')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('workspace-new')));
    await _settle(tester, frames: 60);
    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);

    // The new desktop is active: dot 1 is the tall one.
    expect(
      tester.getSize(find.byKey(const ValueKey('workspace-dot-1'))).height,
      greaterThan(
        tester.getSize(find.byKey(const ValueKey('workspace-dot-0'))).height,
      ),
    );

    final centre = tester.getCenter(find.byKey(const ValueKey('desktop-dots')));
    await tester.sendEventToBinding(PointerScrollEvent(
      position: centre,
      scrollDelta: const Offset(0, 20),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester.getSize(find.byKey(const ValueKey('workspace-dot-0'))).height,
      greaterThan(
        tester.getSize(find.byKey(const ValueKey('workspace-dot-1'))).height,
      ),
    );
  });

  testWidgets('Tracks opens the Musics window', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('mini-player')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('player-tracks')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-tracks')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('player-tracks')), findsNothing);
    expect(find.byKey(const ValueKey('musics-track-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('musics-play')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Musics transport drives the player', (tester) async {
    final audio = _FakeAudio();
    await _pumpShell(tester, audio: audio);
    await _openApp(tester, 'musics');

    await tester.tap(find.byKey(const ValueKey('musics-play')));
    await _settle(tester, frames: 40);
    expect(find.byIcon(Icons.pause_rounded), findsWidgets);
    expect(audio.calls, contains('play'));

    await tester.tap(find.byKey(const ValueKey('musics-next')));
    await _settle(tester, frames: 40);
    expect(audio.calls.where((call) => call == 'play').length, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the workspace panel and the launcher are different surfaces',
      (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('launcher-app-files')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop-dots')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('launcher-app-files')), findsNothing);
    expect(find.text('Desktop 1 of 1'), findsOneWidget);
  });

  testWidgets('the shell fits a 1366x768 screen', (tester) async {
    await _pumpShell(tester, size: const Size(1366, 768));
    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('launcher-app-musics')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shell fits a 1024x768 screen', (tester) async {
    await _pumpShell(tester, size: const Size(1024, 768));
    await tester.tap(find.byKey(const ValueKey('topbar-wifi')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}

// ---- helpers -------------------------------------------------------------------

Future<void> _openApp(WidgetTester tester, String appId) async {
  await tester.tap(find.byKey(const ValueKey('apps-button')));
  await _settle(tester);
  await tester.tap(find.byKey(ValueKey('launcher-app-$appId')));
  await _settle(tester);
}

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1600, 900),
  AudioEngine? audio,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: MyHomePage(
      radio: _FakeRadio(),
      sound: _FakeSound(),
      audio: audio ?? _FakeAudio(),
    ),
  ));
  await _settle(tester);
}

/// The shell keeps a 1 s clock, a 12 s wallpaper timer and a spinning artwork
/// ticker, so `pumpAndSettle` would never return. Fixed frames are enough for
/// every spring.
Future<void> _settle(WidgetTester tester, {int frames = 220}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _FakeSound implements SoundSource {
  double _volume = 0.5;
  bool _muted = false;

  @override
  double get volume => _volume;

  @override
  set volume(double value) => _volume = value.clamp(0.0, 1.0);

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) => _muted = value;

  @override
  int get percent => (_volume * 100).round();

  @override
  void stepVolume(double direction) =>
      _volume = (_volume + 0.02 * direction).clamp(0.0, 1.0);

  @override
  void refresh() {}
}

class _FakeRadio implements RadioSource {
  final Map<RadioKind, RadioStatus> _states = {
    RadioKind.wifi: const RadioStatus(
      kind: RadioKind.wifi,
      state: RadioState.on,
      canToggle: true,
    ),
    RadioKind.bluetooth: const RadioStatus(
      kind: RadioKind.bluetooth,
      state: RadioState.off,
      canToggle: true,
    ),
  };

  @override
  Future<RadioStatus> status(RadioKind kind, {bool force = false}) async =>
      _states[kind]!;

  @override
  Future<RadioActionResult> setPower(RadioKind kind, bool on) async {
    final next = RadioStatus(
      kind: kind,
      state: on ? RadioState.on : RadioState.off,
      canToggle: true,
    );
    _states[kind] = next;
    return RadioActionResult(ok: true, status: next, message: 'ok');
  }
}

/// The audio backend without audio: records what the player asked for.
class _FakeAudio implements AudioEngine {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durations =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completions = StreamController<void>.broadcast();

  final List<String> calls = [];

  @override
  Future<void> playAsset(String asset) async {
    calls.add('play');
    _durations.add(const Duration(seconds: 120));
  }

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