// Widget tests for the settings window.
//
// They answer the question the mock suites cannot: does the window actually
// build at a real size, do the live panes show the state they are handed, and
// do the switches reach the backend? The backends are recorders, so no test
// touch the machine's radios or mutes the speakers of whoever runs it.
//
// Run with: flutter test

import 'package:exp_desktop/radio_control.dart';
import 'package:exp_desktop/settings_app.dart';
import 'package:exp_desktop/sound_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens on the sound pane with the live volume', (tester) async {
    final sound = _FakeSound(volume: 0.4);
    await _open(tester, section: 'sound', sound: sound);

    // The row in the list and the pane header both carry the title.
    expect(find.text('Sound settings'), findsNWidgets(2));
    expect(find.text('Уровень'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('Громкость 40%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sound switch mutes through the backend', (tester) async {
    final sound = _FakeSound(volume: 0.4);
    await _open(tester, section: 'sound', sound: sound);

    await tester.tap(find.byType(GlassToggle));
    await tester.pump();

    expect(sound.muted, isTrue);
    expect(find.text('Звук заглушён'), findsOneWidget);
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

    expect(find.text('Включено, подключено'), findsOneWidget);
    expect(find.text('Сеть подключена'), findsOneWidget);
    expect(find.text('Test Wi-Fi'), findsOneWidget);

    await tester.tap(find.byType(GlassToggle));
    await tester.pumpAndSettle();

    expect(radio.calls, [(RadioKind.wifi, false)]);
    expect(find.text('Выключено'), findsOneWidget);
    expect(find.text('Сеть не подключена'), findsOneWidget);
  });

  testWidgets('a machine without the radio says so', (tester) async {
    await _open(tester, section: 'bluetooth', radio: _FakeRadio());

    expect(find.text('Устройство не найдено'), findsOneWidget);
    expect(find.text('Устройство не найдено на этой машине.'), findsOneWidget);
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

    expect(find.text('Отключено системой'), findsOneWidget);
    expect(find.textContaining('Система не даёт переключить'), findsOneWidget);
  });

  testWidgets('rows the shell does not own keep their Windows link',
      (tester) async {
    await _open(tester, section: 'appearance');

    expect(find.text('Wallpaper'), findsWidgets);
    expect(find.text('Открыть в Параметрах Windows'), findsOneWidget);
    expect(find.textContaining('живёт в Параметрах Windows'), findsOneWidget);
  });

  testWidgets('nothing selected shows the hint', (tester) async {
    await _open(tester);
    expect(find.text('Select an item'), findsOneWidget);
  });

  testWidgets('the list carries every section title', (tester) async {
    await _open(tester);

    for (final title in [
      'Input & output',
      'Connected devices',
      'Network & connectivity',
    ]) {
      expect(find.text(title), findsOneWidget);
    }

    // The rest of the list is below the fold: scrolling must reach it.
    await tester.scrollUntilVisible(
      find.text('Security & privacy'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Security & privacy'), findsOneWidget);
  });

  testWidgets('the top bar can retarget the window to another section',
      (tester) async {
    final sound = _FakeSound(volume: 0.5);
    await _open(tester, section: 'sound', sound: sound);
    expect(find.text('Уровень'), findsOneWidget);

    await tester.pumpWidget(_host(_settings(
      section: 'wifi',
      radio: _FakeRadio(),
      sound: sound,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Уровень'), findsNothing);
    expect(find.text('Wi-Fi & internet'), findsNWidgets(2));
  });

  testWidgets('the window survives a small screen', (tester) async {
    await _open(tester, section: 'sound', sound: _FakeSound(), size: const Size(1024, 700));
    expect(tester.takeException(), isNull);
  });
}

// ---- helpers -------------------------------------------------------------------

Widget _settings({
  String? section,
  RadioSource? radio,
  SoundSource? sound,
}) {
  return SettingsApp(
    initialPosition: Offset.zero,
    onPositionChanged: (_) {},
    onClose: () {},
    onMinimize: () {},
    initialSection: section,
    radio: radio,
    sound: sound,
  );
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Stack(children: [child])),
    );

Future<void> _open(
  WidgetTester tester, {
  String? section,
  RadioSource? radio,
  SoundSource? sound,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(_settings(
    section: section,
    radio: radio,
    sound: sound,
  )));
  await _settleWindow(tester);
}

/// Pumps a fixed number of frames instead of `pumpAndSettle`: the sound pane
/// contains a WaveSlider whose ticker never stops, so "settle" would hang
/// forever. 90 frames is enough for the window's opening spring to rest.
Future<void> _settleWindow(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
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