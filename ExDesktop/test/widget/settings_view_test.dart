// Widget tests for the settings *content* (the window chrome is ShellWindow's
// job and is tested separately).
//
// They answer what the mock suites cannot: does the pane build at a real size,
// do the live controls show the state they are handed, and does a click reach
// the backend? The backends are recorders, so no test touches the machine's
// radios or mutes the speakers of whoever runs it.
//
// Run with: flutter test

import 'package:exp_desktop/desktop/apps/settings_view.dart';
import 'package:exp_desktop/radio_control.dart';
import 'package:exp_desktop/sound_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens on the sound pane with the live volume', (tester) async {
    final sound = _FakeSound(volume: 0.4);
    await _open(tester, section: 'sound', sound: sound);

    expect(find.text('Sound settings'), findsNWidgets(2));
    expect(find.text('Level'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('Volume 40%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sound switch mutes through the backend', (tester) async {
    final sound = _FakeSound(volume: 0.4);
    await _open(tester, section: 'sound', sound: sound);

    await tester.tap(find.byType(GlassToggle));
    await tester.pump();

    expect(sound.muted, isTrue);
    expect(find.text('Sound muted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wifi pane shows the radio state and switches it',
      (tester) async {
    final radio = _FakeRadio(
      wifi: const RadioStatus(
        kind: RadioKind.wifi,
        state: RadioState.on,
        deviceName: 'Test Wi-Fi',
        connected: true,
        canToggle: true,
      ),
    );
    await _open(tester, section: 'wifi', radio: radio);

    expect(find.text('On, connected'), findsOneWidget);
    expect(find.text('Network connected'), findsOneWidget);
    expect(find.text('Test Wi-Fi'), findsOneWidget);

    await tester.tap(find.byType(GlassToggle));
    await tester.pumpAndSettle();

    expect(radio.calls, [(RadioKind.wifi, false)]);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('a machine without the radio says so', (tester) async {
    await _open(tester, section: 'bluetooth', radio: _FakeRadio());

    expect(find.text('No device'), findsOneWidget);
    expect(find.text('No such device on this machine.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a blocked radio explains itself', (tester) async {
    final radio = _FakeRadio(
      bluetooth: const RadioStatus(
        kind: RadioKind.bluetooth,
        state: RadioState.blocked,
      ),
    );
    await _open(tester, section: 'bluetooth', radio: radio);

    expect(find.text('Disabled by system'), findsOneWidget);
    expect(
      find.textContaining('The system will not switch the radio'),
      findsOneWidget,
    );
  });

  testWidgets('rows the shell does not own keep their Windows link',
      (tester) async {
    await _open(tester, section: 'appearance');

    expect(find.text('Open in Windows Settings'), findsOneWidget);
    expect(find.textContaining('lives in Windows Settings'), findsOneWidget);
  });

  testWidgets('nothing selected shows the hint', (tester) async {
    await _open(tester);
    expect(find.text('Select a section on the left'), findsOneWidget);
  });

  testWidgets('the list carries every section title', (tester) async {
    await _open(tester);

    for (final title in [
      'Input & output',
      'Desktop',
      'Connected devices',
      'Network & connectivity',
    ]) {
      expect(find.text(title), findsOneWidget);
    }

    await tester.scrollUntilVisible(
      find.text('Security & privacy'),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('settings-nav')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Security & privacy'), findsOneWidget);
  });

  testWidgets('the navigator can retarget the pane', (tester) async {
    final sound = _FakeSound(volume: 0.5);
    final navigator = SettingsNavigator()..show('sound');
    await _open(tester, section: 'sound', sound: sound, navigator: navigator);
    expect(find.text('Level'), findsOneWidget);

    navigator.show('wifi');
    await tester.pumpAndSettle();

    expect(find.text('Level'), findsNothing);
    expect(find.text('Wi-Fi & internet'), findsNWidgets(2));
  });

  testWidgets('tapping a row opens that pane', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('settings-row-display')));
    await _settle(tester);

    expect(find.text('Brightness'), findsOneWidget);
  });

  testWidgets('the content survives a small window', (tester) async {
    await _open(
      tester,
      section: 'sound',
      sound: _FakeSound(),
      size: const Size(1024, 700),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the display pane shows the real values, not made-up defaults',
      (tester) async {
    final applied = <String, double>{};
    final display = DisplaySettings(
      brightness: 0.42,
      contrast: 0.6,
      warmth: 0.0,
      onBrightness: (v) => applied['brightness'] = v,
      onContrast: (v) => applied['contrast'] = v,
      onWarmth: (v) => applied['warmth'] = v,
    );

    await _open(tester, section: 'display', display: display);

    expect(find.text('Brightness'), findsOneWidget);
    expect(find.text('Contrast'), findsOneWidget);
    expect(find.text('Warmth'), findsOneWidget);

    // The numbers have to be the live ones: warmth 0 is a neutral screen,
    // and showing 50% there was the bug.
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(applied, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wallpaper pane lists the wallpapers and applies one',
      (tester) async {
    final applied = <int>[];
    await _open(
      tester,
      section: 'wallpaper',
      wallpapers: const [
        'assets/fons/fon1.jpg',
        'assets/fons/fon2.jpg',
        'assets/fons/fon3.jpg',
      ],
      activeWallpaper: 1,
      onWallpaper: applied.add,
    );

    expect(find.textContaining('Each desktop keeps its own wallpaper'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-wallpaper-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-wallpaper-2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-wallpaper-2')));
    await tester.pump();
    expect(applied, [2]);
    expect(tester.takeException(), isNull);
  });
}

// ---- helpers -------------------------------------------------------------------

Widget _settings({
  SettingsNavigator? navigator,
  String? section,
  RadioSource? radio,
  SoundSource? sound,
  DisplaySettings? display,
  List<String> wallpapers = const [],
  int activeWallpaper = 0,
  ValueChanged<int>? onWallpaper,
}) {
  final nav = navigator ?? SettingsNavigator();
  if (navigator == null) nav.show(section);
  return SettingsView(
    navigator: nav,
    radio: radio,
    sound: sound,
    wallpapers: wallpapers,
    activeWallpaper: activeWallpaper,
    onWallpaper: onWallpaper,
    display: display ??
        DisplaySettings(
          brightness: 0.7,
          contrast: 0.7,
          warmth: 0,
          onBrightness: (_) {},
          onContrast: (_) {},
          onWarmth: (_) {},
        ),
  );
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 920, height: 610, child: child),
        ),
      ),
    );

Future<void> _open(
  WidgetTester tester, {
  SettingsNavigator? navigator,
  String? section,
  RadioSource? radio,
  SoundSource? sound,
  DisplaySettings? display,
  List<String> wallpapers = const [],
  int activeWallpaper = 0,
  ValueChanged<int>? onWallpaper,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(_settings(
    navigator: navigator,
    section: section,
    radio: radio,
    sound: sound,
    display: display,
    wallpapers: wallpapers,
    activeWallpaper: activeWallpaper,
    onWallpaper: onWallpaper,
  )));
  await _settle(tester);
}

/// Fixed frames instead of `pumpAndSettle`: the WaveSlider's ticker never
/// stops, so settling would hang.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _FakeSound implements SoundSource {
  _FakeSound({double volume = 0.5, bool muted = false})
      : _volume = volume,
        _muted = muted;

  double _volume;
  bool _muted;

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
  _FakeRadio({RadioStatus? wifi, RadioStatus? bluetooth})
      : states = {
          RadioKind.wifi: wifi ??
              const RadioStatus(
                kind: RadioKind.wifi,
                state: RadioState.unavailable,
              ),
          RadioKind.bluetooth: bluetooth ??
              const RadioStatus(
                kind: RadioKind.bluetooth,
                state: RadioState.unavailable,
              ),
        };

  final Map<RadioKind, RadioStatus> states;
  final List<(RadioKind, bool)> calls = [];

  @override
  Future<RadioStatus> status(RadioKind kind, {bool force = false}) async =>
      states[kind]!;

  @override
  Future<RadioActionResult> setPower(RadioKind kind, bool on) async {
    calls.add((kind, on));
    final next = RadioStatus(
      kind: kind,
      state: on ? RadioState.on : RadioState.off,
      canToggle: true,
    );
    states[kind] = next;
    return RadioActionResult(ok: true, status: next, message: 'ok');
  }
}