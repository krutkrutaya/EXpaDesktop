// Widget tests for the settings *content* (the window chrome is ShellWindow's
// job and is tested separately).
//
// They answer what the mock suites cannot: does every pane build at a real
// size, do the live controls show the state they are handed, and does a click
// reach the right callback? Radios, sound and sessions are recorders, so no
// test touches the machine's radios or mutes the speakers of whoever runs it.

import 'package:exp_desktop/audio_sessions.dart';
import 'package:exp_desktop/expa/de_config.dart';
import 'package:exp_desktop/expa/default_apps.dart';
import 'package:exp_desktop/expa/drives.dart';
import 'package:exp_desktop/expa/input_settings.dart';
import 'package:exp_desktop/expa/notifications.dart';
import 'package:exp_desktop/desktop/apps/settings_view.dart';
import 'package:exp_desktop/native/sysctl.dart';
import 'package:exp_desktop/radio_control.dart';
import 'package:exp_desktop/sound_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _zones = [
  TimezoneRow(
    id: 'Europe/Moscow',
    name: 'Moscow Standard Time',
    offsetMinutes: 180,
  ),
  TimezoneRow(
    id: 'Pacific Standard Time',
    name: 'Pacific Standard Time',
    offsetMinutes: -480,
  ),
];

const _displayState = DisplayState(
  current: DisplayModeRow(
    width: 1920,
    height: 1080,
    hz: 60,
    orientation: 0,
    bits: 32,
  ),
  resolutions: [
    (width: 1920, height: 1080),
    (width: 1280, height: 720),
  ],
  refreshRates: [60, 144],
);

const _soundDisplay = DisplaySettings(
  brightness: 0.7,
  contrast: 0.7,
  warmth: 0,
  onBrightness: _ignore,
  onContrast: _ignore,
  onWarmth: _ignore,
);

void _ignore(double _) {}

void main() {
  testWidgets('the sound pane leads with the master volume and the mute icon',
      (tester) async {
    final sound = _FakeSound(volume: 0.4);
    await _open(
      tester,
      section: 'sound',
      sound: sound,
      audioSessions: const [],
    );

    // The pane title and the nav row both read "Sound".
    expect(find.text('Sound'), findsNWidgets(2));
    expect(find.text('40%'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-master-volume')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-sound-mute')), findsOneWidget);
    // No old "Level" row and no full-width toggle.
    expect(find.text('Level'), findsNothing);
    expect(find.byType(GlassToggle), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-sound-mute')));
    await tester.pump();
    expect(sound.muted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sound pane lists every app session with its own slider',
      (tester) async {
    final sessions = [
      AudioAppSession(pid: 990001, exe: 'spotify', volume: 0.5, muted: false),
      AudioAppSession(pid: 990002, exe: 'chrome', volume: 0.9, muted: false),
    ];
    await _open(
      tester,
      section: 'sound',
      sound: _FakeSound(volume: 0.4),
      audioSessions: sessions,
    );

    expect(find.byKey(const ValueKey('settings-audio-990001')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-audio-990002')), findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);
    expect(find.text('Chrome'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-audio-mute-990001')));
    await tester.pump();
    expect(sessions.first.muted, isTrue);
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
    await _settle(tester);

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

  testWidgets('Default apps edits the desktop association table', (tester) async {
    FileAssociations? saved;
    await _open(
      tester,
      section: 'defaultapps',
      onAssociations: (value) => saved = value,
    );

    expect(find.text('.txt'), findsOneWidget);
    expect(find.text('notepad'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('settings-assoc-app-txt')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('paint').last);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.byExtension['txt'], 'paint');
  });

  testWidgets('the devices pane lists drives and cameras', (tester) async {
    String? opened;
    await _open(
      tester,
      section: 'drives',
      drives: const [
        DriveEntry(
          id: 'C:',
          label: 'System',
          totalBytes: 100000000000,
          freeBytes: 40000000000,
        ),
      ],
      cameras: const ['Integrated Camera'],
      onOpenPath: (path) => opened = path,
    );

    expect(find.byKey(const ValueKey('settings-drive-C:')), findsOneWidget);
    expect(find.textContaining('System'), findsOneWidget);
    expect(find.text('Integrated Camera'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-drive-open-C:')));
    await tester.pump();
    expect(opened, contains('C:'));
  });

  testWidgets('the pointer pane reports the speed and writes the swap',
      (tester) async {
    final source = _FakeInput(mouseSpeed: 7);
    await _open(tester, section: 'pointer', inputSource: source);

    expect(find.text('7'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('settings-mouse-swap')));
    await _settle(tester);

    expect(source.swapped, isTrue);
  });

  testWidgets('the lock pane saves a PIN and locks the desktop', (tester) async {
    DeConfig? saved;
    var locked = false;
    await _open(
      tester,
      section: 'lock',
      onConfig: (value) => saved = value,
      onLock: () => locked = true,
    );

    await tester.enterText(
        find.byKey(const ValueKey('settings-lock-pin')), '12ab34');
    await tester.tap(find.byKey(const ValueKey('settings-lock-save-pin')));
    await _settle(tester);
    expect(saved?.lockPin, '1234');

    await tester.tap(find.byKey(const ValueKey('settings-lock-now')));
    await _settle(tester);
    expect(locked, isTrue);
  });

  testWidgets('nothing selected shows the hint', (tester) async {
    await _open(tester);
    expect(find.text('Select a section on the left'), findsOneWidget);
  });

  testWidgets('the list carries the new sections, not the old rows',
      (tester) async {
    await _open(tester);

    for (final title in [
      'Input & output',
      'Connected devices',
      'Network & connectivity',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    // The section header and its single row both read "Appearance".
    expect(find.text('Appearance'), findsNWidgets(2));
    // The separate Desktop/Wallpaper row and the Windows Update security
    // row are gone by request.
    expect(find.byKey(const ValueKey('settings-row-wallpaper')), findsNothing);
    expect(find.byKey(const ValueKey('settings-row-update')), findsNothing);
    expect(find.text('Desktop'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-row-updates')),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('settings-nav')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.byKey(const ValueKey('settings-row-updates')), findsOneWidget);
    expect(find.text('Updates'), findsWidgets);
  });

  testWidgets('the navigator can retarget the pane', (tester) async {
    final sound = _FakeSound(volume: 0.5);
    final navigator = SettingsNavigator()..show('sound');
    await _open(tester, section: 'sound', sound: sound, navigator: navigator);
    expect(find.byKey(const ValueKey('settings-master-volume')), findsOneWidget);

    navigator.show('wifi');
    await _settle(tester);

    expect(find.byKey(const ValueKey('settings-master-volume')), findsNothing);
    expect(find.text('Wi-Fi & internet'), findsNWidgets(2));
  });

  testWidgets('the display pane reads the real modes and applies a choice',
      (tester) async {
    String? chosenRes;
    String? chosenOrient;
    String? chosenHz;
    await _open(
      tester,
      section: 'display',
      displayState: _displayState,
      onDisplayRes: (value) => chosenRes = value,
      onDisplayOrient: (value) => chosenOrient = value,
      onDisplayHz: (value) => chosenHz = value,
    );

    expect(find.textContaining('1920 × 1080'), findsWidgets);
    expect(find.byKey(const ValueKey('settings-display-res')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-display-orient')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-display-hz')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-display-res')));
    await _settle(tester);
    await tester.tap(find.text('1280 × 720').last);
    await _settle(tester);
    expect(chosenRes, '1280x720');

    await tester.tap(find.byKey(const ValueKey('settings-display-orient')));
    await _settle(tester);
    await tester.tap(find.text('Portrait').last);
    await _settle(tester);
    expect(chosenOrient, '1');

    await tester.tap(find.byKey(const ValueKey('settings-display-hz')));
    await _settle(tester);
    await tester.tap(find.text('144 Hz').last);
    await _settle(tester);
    expect(chosenHz, '144');
    expect(tester.takeException(), isNull);
  });

  testWidgets('appearance shows two large tiles and a back button per sheet',
      (tester) async {
    await _open(tester, section: 'appearance');

    final tile = find.byKey(const ValueKey('appearance-tile-wallpaper'));
    expect(tile, findsOneWidget);
    expect(find.byKey(const ValueKey('appearance-tile-vibe')), findsOneWidget);
    expect(tester.getSize(tile).width, greaterThan(250));
    expect(tester.getSize(tile).height, greaterThan(80));

    await tester.tap(tile);
    await _settle(tester);
    expect(find.byKey(const ValueKey('appearance-back')), findsOneWidget);
    expect(find.byKey(const ValueKey('slideshow-switch')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('appearance-back')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('appearance-tile-wallpaper')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wallpaper sheet applies a picture and the timer',
      (tester) async {
    final applied = <int>[];
    bool? slideshowOn;
    int? slideshowPeriod;
    await _open(
      tester,
      section: 'appearance',
      wallpapers: const [
        'assets/fons/fon1.jpg',
        'assets/fons/fon2.jpg',
      ],
      activeWallpaper: 0,
      onWallpaper: applied.add,
      slideshowOn: true,
      slideshowPeriod: 12,
      onSlideshow: (on, period) {
        slideshowOn = on;
        slideshowPeriod = period;
      },
    );
    await tester.tap(find.byKey(const ValueKey('appearance-tile-wallpaper')));
    await _settle(tester);

    expect(find.textContaining('Each desktop keeps its own wallpaper'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-wallpaper-1')));
    await tester.pump();
    expect(applied, [1]);

    await tester.enterText(
        find.byKey(const ValueKey('slideshow-period')), '30');
    await tester.tap(find.byKey(const ValueKey('slideshow-apply')));
    await tester.pump();
    expect(slideshowOn, isTrue);
    expect(slideshowPeriod, 30);

    await tester.tap(find.byKey(const ValueKey('slideshow-switch')));
    await tester.pump();
    expect(slideshowOn, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the vibe sheet removes and adds waybar panels', (tester) async {
    List<String>? items;
    await _open(
      tester,
      section: 'appearance',
      waybarItems: const ['sound', 'bluetooth', 'wifi', 'brightness'],
      onWaybarItems: (next) => items = next,
    );
    await tester.tap(find.byKey(const ValueKey('appearance-tile-vibe')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('waybar-item-sound')), findsOneWidget);
    expect(find.byKey(const ValueKey('waybar-item-brightness')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('waybar-remove-sound')));
    await tester.pump();
    expect(items, isNot(contains('sound')));
    expect(items, containsAll(['bluetooth', 'wifi', 'brightness']));

    await tester.tap(find.byKey(const ValueKey('waybar-add')));
    await _settle(tester);
    await tester.tap(find.text('Clipboard').last);
    await _settle(tester);
    expect(items, contains('clipboard'));

    await tester.tap(find.byKey(const ValueKey('appearance-back')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('appearance-tile-vibe')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the date pane picks a time zone, auto mode and a region',
      (tester) async {
    String? zone;
    bool? autoValue;
    String? region;
    await _open(
      tester,
      section: 'datetime',
      timezones: _zones,
      tzZone: 'Europe/Moscow',
      tzAuto: false,
      region: 'ru-RU',
      onTimezone: (value, {required bool auto}) {
        zone = value;
        autoValue = auto;
      },
      onRegion: (value) => region = value,
    );

    expect(find.text('Moscow Standard Time'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-tz-zone')));
    await _settle(tester);
    await tester.tap(find.text('Pacific Standard Time').last);
    await _settle(tester);
    expect(zone, 'Pacific Standard Time');
    expect(autoValue, isFalse);

    await tester.tap(find.byKey(const ValueKey('settings-tz-auto')));
    await tester.pump();
    expect(autoValue, isTrue);

    await tester.tap(find.byKey(const ValueKey('settings-region')));
    await _settle(tester);
    await tester.tap(find.text('United States — en-US').last);
    await _settle(tester);
    expect(region, 'en-US');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the updates pane opens the in-shell Updater', (tester) async {
    var opened = false;
    await _open(
      tester,
      section: 'updates',
      onOpenUpdater: () => opened = true,
    );

    expect(find.byKey(const ValueKey('updates-expa')), findsOneWidget);
    expect(find.byKey(const ValueKey('updates-windows')), findsNothing);

    await tester.tap(find.text('Open Updater'));
    await tester.pump();
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the content survives a small window', (tester) async {
    await _open(
      tester,
      section: 'sound',
      sound: _FakeSound(),
      audioSessions: const [],
      hostSize: const Size(760, 520),
    );
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
  bool slideshowOn = true,
  int slideshowPeriod = 12,
  void Function(bool, int)? onSlideshow,
  List<String> waybarItems = const ['sound', 'bluetooth', 'wifi', 'brightness'],
  ValueChanged<List<String>>? onWaybarItems,
  String tzZone = '',
  bool tzAuto = false,
  String region = 'ru-RU',
  void Function(String, {required bool auto})? onTimezone,
  ValueChanged<String>? onRegion,
  String displayRes = 'auto',
  String displayOrient = 'auto',
  String displayHz = 'auto',
  ValueChanged<String>? onDisplayRes,
  ValueChanged<String>? onDisplayOrient,
  ValueChanged<String>? onDisplayHz,
  VoidCallback? onOpenUpdater,
  DisplayState? displayState,
  List<TimezoneRow>? timezones,
  List<AudioAppSession>? audioSessions,
  DeConfig config = DeConfig.defaults,
  ValueChanged<DeConfig>? onConfig,
  FileAssociations associations = FileAssociations.standard,
  ValueChanged<FileAssociations>? onAssociations,
  NotificationCenter? notifications,
  VoidCallback? onLock,
  ValueChanged<String>? onOpenPath,
  InputSource? inputSource,
  List<DriveEntry>? drives,
  List<String>? cameras,
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
    display: display ?? _soundDisplay,
    slideshowOn: slideshowOn,
    slideshowPeriod: slideshowPeriod,
    onSlideshow: onSlideshow,
    waybarItems: waybarItems,
    onWaybarItems: onWaybarItems,
    tzZone: tzZone,
    tzAuto: tzAuto,
    region: region,
    onTimezone: onTimezone,
    onRegion: onRegion,
    displayRes: displayRes,
    displayOrient: displayOrient,
    displayHz: displayHz,
    onDisplayRes: onDisplayRes,
    onDisplayOrient: onDisplayOrient,
    onDisplayHz: onDisplayHz,
    onOpenUpdater: onOpenUpdater,
    displayState: displayState,
    timezones: timezones,
    audioSessions: audioSessions,
    config: config,
    onConfig: onConfig,
    associations: associations,
    onAssociations: onAssociations,
    notifications: notifications,
    onLock: onLock,
    onOpenPath: onOpenPath,
    inputSource: inputSource,
    drives: drives,
    cameras: cameras,
  );
}

Widget _host(Widget child, Size size) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
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
  bool slideshowOn = true,
  int slideshowPeriod = 12,
  void Function(bool, int)? onSlideshow,
  List<String> waybarItems = const ['sound', 'bluetooth', 'wifi', 'brightness'],
  ValueChanged<List<String>>? onWaybarItems,
  String tzZone = '',
  bool tzAuto = false,
  String region = 'ru-RU',
  void Function(String, {required bool auto})? onTimezone,
  ValueChanged<String>? onRegion,
  String displayRes = 'auto',
  String displayOrient = 'auto',
  String displayHz = 'auto',
  ValueChanged<String>? onDisplayRes,
  ValueChanged<String>? onDisplayOrient,
  ValueChanged<String>? onDisplayHz,
  VoidCallback? onOpenUpdater,
  DisplayState? displayState,
  List<TimezoneRow>? timezones,
  List<AudioAppSession>? audioSessions,
  DeConfig config = DeConfig.defaults,
  ValueChanged<DeConfig>? onConfig,
  FileAssociations associations = FileAssociations.standard,
  ValueChanged<FileAssociations>? onAssociations,
  NotificationCenter? notifications,
  VoidCallback? onLock,
  ValueChanged<String>? onOpenPath,
  InputSource? inputSource,
  List<DriveEntry>? drives,
  List<String>? cameras,
  Size hostSize = const Size(960, 640),
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(
    _settings(
      navigator: navigator,
      section: section,
      radio: radio,
      sound: sound,
      display: display,
      wallpapers: wallpapers,
      activeWallpaper: activeWallpaper,
      onWallpaper: onWallpaper,
      slideshowOn: slideshowOn,
      slideshowPeriod: slideshowPeriod,
      onSlideshow: onSlideshow,
      waybarItems: waybarItems,
      onWaybarItems: onWaybarItems,
      tzZone: tzZone,
      tzAuto: tzAuto,
      region: region,
      onTimezone: onTimezone,
      onRegion: onRegion,
      displayRes: displayRes,
      displayOrient: displayOrient,
      displayHz: displayHz,
      onDisplayRes: onDisplayRes,
      onDisplayOrient: onDisplayOrient,
      onDisplayHz: onDisplayHz,
      onOpenUpdater: onOpenUpdater,
      displayState: displayState,
      timezones: timezones,
      audioSessions: audioSessions,
      config: config,
      onConfig: onConfig,
      associations: associations,
      onAssociations: onAssociations,
      notifications: notifications,
      onLock: onLock,
      onOpenPath: onOpenPath,
      inputSource: inputSource,
      drives: drives,
    cameras: cameras,
    ),
    hostSize,
  ));
  await _settle(tester);
}

/// Fixed frames instead of `pumpAndSettle`: the shell's animations and the
/// wave sliders are better sampled deterministically.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
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
class _FakeInput implements InputSource {
  _FakeInput({this.mouseSpeed = 10});

  @override
  int? mouseSpeed;
  @override
  bool? mouseSwap = false;
  @override
  int? wheelLines = 3;
  @override
  int? keyDelay = 1;
  @override
  int? keySpeed = 31;

  bool swapped = false;

  @override
  void setMouseSpeed(int value) => mouseSpeed = value;
  @override
  void setMouseSwap(bool value) {
    mouseSwap = value;
    swapped = true;
  }
  @override
  void setWheelLines(int value) => wheelLines = value;
  @override
  void setKeyDelay(int value) => keyDelay = value;
  @override
  void setKeySpeed(int value) => keySpeed = value;
}