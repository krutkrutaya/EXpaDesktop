// Widget tests for the shell itself: the surface coordination that used to
// break (the launcher staying open behind the settings window) and the
// "nothing overflows" pass at several window sizes.
//
// The radios and the sound run on recorders, so a test never spawns
// PowerShell, never moves the machine's volume and never mutes anything.
//
// Run with: flutter test

import 'package:exp_desktop/main.dart';
import 'package:exp_desktop/radio_control.dart';
import 'package:exp_desktop/sound_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the shell draws on startup', (tester) async {
    await _pumpShell(tester);

    // The nine-dot pill in the dock is always there.
    expect(find.byKey(const ValueKey('launcher-pill')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the settings window closes the nine-dot launcher',
      (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('launcher-pill')));
    await _settle(tester);
    expect(find.text('Калькулятор'), findsOneWidget);

    // The Wi-Fi button in the top bar opens the shell's own settings.
    await tester.tap(find.byKey(const ValueKey('topbar-wifi')));
    await _settle(tester);

    expect(find.text('Калькулятор'), findsNothing);
    expect(find.text('Wi-Fi & internet'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the launcher minimises the settings window',
      (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('topbar-wifi')));
    await _settle(tester);
    expect(find.text('Wi-Fi & internet'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('launcher-pill')));
    await _settle(tester);

    expect(find.text('Wi-Fi & internet'), findsNothing);
    expect(find.text('Калькулятор'), findsOneWidget);

    // The dock keeps a way back to the window.
    await tester.tap(find.byKey(const ValueKey('dock-settings')));
    await _settle(tester);
    // The window comes back on the section it was left on.
    expect(find.text('Wi-Fi & internet'), findsNWidgets(2));
  });

  testWidgets('the sound flyout leaves the settings window alone',
      (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('topbar-wifi')));
    await _settle(tester);
    expect(find.text('Wi-Fi & internet'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('topbar-volume')));
    await _settle(tester);

    // Volume is a flyout: the settings window must survive it.
    expect(find.text('Wi-Fi & internet'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the desktop closes the sound flyout', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('topbar-volume')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('volume-flyout')), findsOneWidget);

    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);

    expect(find.byKey(const ValueKey('volume-flyout')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the desktop closes the nine-dot launcher',
      (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('launcher-pill')));
    await _settle(tester);
    expect(find.text('Калькулятор'), findsOneWidget);

    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);

    expect(find.text('Калькулятор'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the desktop leaves the settings window open',
      (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('topbar-wifi')));
    await _settle(tester);

    await tester.tapAt(const Offset(240, 860));
    await _settle(tester);

    // A window, not a flyout: it keeps its title bar and its place.
    expect(find.text('Wi-Fi & internet'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the buildings fit a 1366x768 screen', (tester) async {
    await _pumpShell(tester, size: const Size(1366, 768));
    await tester.tap(find.byKey(const ValueKey('launcher-pill')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('topbar-volume')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the buildings fit a 1024x768 screen', (tester) async {
    await _pumpShell(tester, size: const Size(1024, 768));
    await tester.tap(find.byKey(const ValueKey('topbar-wifi')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1600, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: MyHomePage(radio: _FakeRadio(), sound: _FakeSound()),
  ));
  await _settle(tester);
}

/// The shell keeps a 1 s clock and a 12 s wallpaper timer running, so
/// `pumpAndSettle` would never return. 90 frames is enough for the springs.
Future<void> _settle(WidgetTester tester, {int frames = 90}) async {
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