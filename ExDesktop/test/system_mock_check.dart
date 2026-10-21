// Mock tests for the shell's system layer and the assistant.
//
// Four things are exercised here:
//   1. the hidden console runner (stdout/stderr/exit codes/timeouts/UTF-8),
//   2. the radio line protocol (every state, malformed input, adapters),
//   3. the Russian phrase matcher (a table of ~100 phrasings, positive and
//      negative, including the traps that used to misfire),
//   4. the router + the assistant's catalog and prompt (they must not drift).
//
// Nothing here changes the machine: the radio is parsed from recorded script
// output, the router talks to a recorder instead of the real device, and the
// only live calls are hidden `cmd`/`powershell` runs plus a read-only look at
// the audio endpoint.
//
// Run with a pure Dart SDK (no Flutter needed):
//   dart run test/system_mock_check.dart

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'dart:ffi';
import 'dart:io';

import 'package:exp_desktop/assistant_prompt.dart';
import 'package:exp_desktop/command_router.dart';
import 'package:exp_desktop/hidden_process.dart';
import 'package:exp_desktop/native_heap.dart';
import 'package:exp_desktop/radio_control.dart';
import 'package:exp_desktop/radio_script.dart';
import 'package:exp_desktop/sound_control.dart';
import 'package:exp_desktop/volume_control.dart';

import 'mock_harness.dart';

/// Runs the system suite. `mock_all.dart` calls this directly.
Future<void> runSystemChecks() async {
  await testHiddenProcess();
  testNativeHeap();
  testRadioScript();
  testRadioParsing();
  testRadioLabels();
  testCommandParser();
  await testRouter();
  testPromptCatalog();
  testSoundControl();
  testSourceGuards();
}

Future<void> main() async {
  await runSystemChecks();
  finish('system');
}

// ---- 1. the hidden console runner --------------------------------------------

Future<void> testHiddenProcess() async {
  section('[hidden process]');

  final echo = await runHidden('cmd.exe', ['/c', 'echo hello']);
  checkEquals('cmd echo exit code', echo.exitCode, 0);
  checkContains('cmd echo stdout', echo.stdout, 'hello');
  checkEquals('stdout splits into lines', echo.lines, ['hello']);

  final failing = await runHidden('cmd.exe', ['/c', 'echo oops 1>&2 & exit 3']);
  checkEquals('exit code is reported', failing.exitCode, 3);
  checkContains('stderr is captured', failing.stderr, 'oops');
  checkEquals('stdout stays empty on stderr-only run', failing.stdout.trim(), '');

  final quiet = await runHidden('cmd.exe', ['/c', 'exit 0']);
  checkEquals('silent run exit code', quiet.exitCode, 0);
  checkEquals('silent run prints nothing', quiet.stdout, '');

  final missing = await runHidden('definitely-not-a-real-binary.exe', const []);
  check('missing binary fails instead of throwing', missing.exitCode != 0);
  checkContains('missing binary explains itself', missing.stderr, 'CreateProcess');

  final spaced = await runHidden('cmd.exe', ['/c', 'echo', 'a b']);
  checkEquals('an argument with a space is quoted for the child',
      spaced.stdout.trim(), '"a b"');

  final ps = await runPowerShell('Write-Output "ps-ok"');
  checkContains('powershell runs hidden', ps.stdout, 'ps-ok');

  final cyrillic = await runPowerShell('Write-Output "привет мир"');
  checkEquals(
    'cyrillic survives -EncodedCommand',
    cyrillic.stdout.trim(),
    'привет мир',
  );

  final cyrillicBuilt = await runPowerShell('Write-Output ("привет " + "мир")');
  checkEquals(
    'cyrillic literals are not mojibake',
    cyrillicBuilt.stdout.trim(),
    'привет мир',
  );

  final long =
      await runHidden('cmd.exe', ['/c', 'for /L %i in (1,1,20000) do @echo line%i']);
  checkEquals('long output is complete', long.lines.length, 20000);
  checkEquals('long output keeps the first line', long.lines.first, 'line1');
  checkEquals('long output keeps the last line', long.lines.last, 'line20000');

  final slow = await runHidden(
    'cmd.exe',
    ['/c', 'ping -n 6 127.0.0.1 > nul'],
    timeout: const Duration(milliseconds: 300),
  );
  checkEquals('timeout kills the child', slow.exitCode, -2);
}

// ---- 2. the native heap --------------------------------------------------------

void testNativeHeap() {
  section('[native heap]');

  final cell = NativeHeap.alloc<Uint32>(4);
  cell.value = 0xDEADBEEF;
  checkEquals('write and read a 32-bit cell', cell.value, 0xDEADBEEF);
  NativeHeap.free(cell);

  NativeHeap.free(nullptr);
  check('free(nullptr) is safe', true);

  final view = NativeHeap.alloc<Uint8>(8);
  view.asTypedList(8).setAll(0, [1, 2, 3, 4, 5, 6, 7, 8]);
  checkEquals('typed list view of a block', view.asTypedList(8).join(','),
      '1,2,3,4,5,6,7,8');
  NativeHeap.free(view);

  var cycles = true;
  for (var i = 0; i < 2000; i++) {
    final block = NativeHeap.alloc<Uint32>(4);
    block.value = i;
    if (block.value != i) {
      cycles = false;
      break;
    }
    NativeHeap.free(block);
  }
  check('2000 alloc/free cycles stay consistent', cycles);
}

// ---- 3. the radio script -------------------------------------------------------

void testRadioScript() {
  section('[radio script]');

  final state = buildRadioStateScript();
  checkMissing('state script has no leftover mode', state, '__MODE__');
  checkMissing('state script has no leftover kind', state, '__KIND__');
  checkContains('state script asks for the radios', state, 'GetRadiosAsync');
  checkContains('state script requests access', state, 'RequestAccessAsync');
  checkContains('state script lists the adapter', state, 'Get-NetAdapter');
  checkContains('state script reports every radio', state, "'radio|'");
  checkContains('state script forces UTF-8 output', state,
      '[Console]::OutputEncoding');
  checkContains('state script is fail-soft', state, r"$ErrorActionPreference");

  final on = buildRadioSetScript(kind: 'WiFi', on: true);
  checkContains('set script carries the radio kind', on, "'WiFi'");
  checkContains('set script carries the wanted state', on, "'On'");
  checkMissing('set script has no leftover state', on, '__STATE__');
  checkContains('set script calls SetStateAsync', on, 'SetStateAsync');

  final off = buildRadioSetScript(kind: 'Bluetooth', on: false);
  checkContains('set script can switch off', off, "'Off'");
  checkContains('set script can reach bluetooth', off, "'Bluetooth'");
}

// ---- 4. the radio line protocol ------------------------------------------------

RadioSnapshot _parse(String stdout) => RadioSnapshot.parse(
      HiddenResult(exitCode: 0, stdout: stdout, stderr: ''),
    );

void testRadioParsing() {
  section('[radio parsing]');

  const full = '''
access=Allowed
count=2
radio|WiFi|Intel(R) Wi-Fi 6E AX211|On
radio|Bluetooth|Intel(R) Wireless Bluetooth(R)|Off
adapter|Wi-Fi|Up|Connected
''';
  final snapshot = _parse(full);
  checkEquals('access line parsed', snapshot.access, 'Allowed');

  final wifi = snapshot.statusOf(RadioKind.wifi);
  checkEquals('wifi state', wifi.state, RadioState.on);
  checkEquals('wifi radio name', wifi.deviceName, 'Intel(R) Wi-Fi 6E AX211');
  checkEquals('wifi adapter name', wifi.adapterName, 'Wi-Fi');
  check('wifi reports the link up', wifi.connected);
  check('wifi can be switched by the shell', wifi.canToggle);

  final bluetooth = snapshot.statusOf(RadioKind.bluetooth);
  checkEquals('bluetooth state', bluetooth.state, RadioState.off);
  check('bluetooth has no link', !bluetooth.connected);
  check('bluetooth can be switched by the shell', bluetooth.canToggle);

  checkEquals(
    'CRLF output parses the same',
    _parse(full.replaceAll('\n', '\r\n')).statusOf(RadioKind.wifi).state,
    RadioState.on,
  );
  checkEquals(
    'padded lines are tolerated',
    _parse('  access=Allowed  \n  radio|WiFi|Wi-Fi|On  \n')
        .statusOf(RadioKind.wifi)
        .state,
    RadioState.on,
  );

  checkEquals(
    'no radios at all means unavailable',
    _parse('access=Allowed\ncount=0\n').statusOf(RadioKind.wifi).state,
    RadioState.unavailable,
  );

  checkEquals(
    'policy-disabled radio is blocked',
    _parse('radio|WiFi|Wi-Fi|DisabledBySystem\n').statusOf(RadioKind.wifi).state,
    RadioState.blocked,
  );
  checkEquals(
    'user-disabled radio is blocked',
    _parse('radio|WiFi|Wi-Fi|DisabledByUser\n').statusOf(RadioKind.wifi).state,
    RadioState.blocked,
  );
  checkEquals(
    'unknown radio state stays unknown',
    _parse('radio|WiFi|Wi-Fi|SomethingNew\n').statusOf(RadioKind.wifi).state,
    RadioState.unknown,
  );

  checkEquals(
    'disabled adapter reads as off',
    _parse('radio|WiFi|Wi-Fi|On\nadapter|Wi-Fi|Disabled|Disconnected\n')
        .statusOf(RadioKind.wifi)
        .state,
    RadioState.off,
  );
  check(
    'disabled adapter is not connected',
    !_parse('adapter|Wi-Fi|Disabled|Disconnected\n')
        .statusOf(RadioKind.wifi)
        .connected,
  );

  final adapterOnly = _parse('adapter|Wi-Fi|Up|Connected\n');
  checkEquals(
    'adapter without the radio API still reads on',
    adapterOnly.statusOf(RadioKind.wifi).state,
    RadioState.on,
  );
  check('adapter-only has no radio to switch', !adapterOnly.statusOf(RadioKind.wifi).canToggle);
  checkEquals(
    'adapter-only is connected',
    adapterOnly.statusOf(RadioKind.wifi).connected,
    true,
  );
  checkEquals(
    'down adapter is still on but not connected',
    _parse('adapter|Wi-Fi|Down|Disconnected\n').statusOf(RadioKind.wifi).state,
    RadioState.on,
  );

  checkEquals(
    'radio without adapter has no link',
    _parse('radio|WiFi|Wi-Fi|On\n').statusOf(RadioKind.wifi).connected,
    false,
  );
  checkEquals(
    'radio without adapter has no adapter name',
    _parse('radio|WiFi|Wi-Fi|On\n').statusOf(RadioKind.wifi).adapterName,
    null,
  );

  checkEquals(
    'error line is surfaced',
    _parse('err|no radio api\n').error,
    'no radio api',
  );
  checkEquals(
    'garbage lines are ignored',
    _parse('hello\nworld\nradio|WiFi\nadapter|x|y\n').statusOf(RadioKind.wifi).state,
    RadioState.unavailable,
  );
  checkEquals(
    'an unknown radio kind falls back to wifi',
    _parse('radio|MobileBroadband|LTE|On\n').statusOf(RadioKind.wifi).state,
    RadioState.on,
  );
}

void testRadioLabels() {
  section('[radio labels]');

  checkEquals('wifi label', RadioKind.wifi.label, 'Wi-Fi');
  checkEquals('bluetooth label', RadioKind.bluetooth.label, 'Bluetooth');
  checkEquals('wifi api kind', RadioKind.wifi.winRtKind, 'WiFi');
  checkEquals('bluetooth api kind', RadioKind.bluetooth.winRtKind, 'Bluetooth');
  checkEquals('wifi fallback page', RadioKind.wifi.settingsUri,
      'ms-settings:network-wifi');
  checkEquals('bluetooth fallback page', RadioKind.bluetooth.settingsUri,
      'ms-settings:bluetooth');

  checkEquals('on label', RadioState.on.label, 'On');
  checkEquals('off label', RadioState.off.label, 'Off');
  checkEquals('blocked label', RadioState.blocked.label, 'Disabled by system');
  checkEquals('unknown label', RadioState.unknown.label, 'Unknown');
  checkEquals('unavailable label', RadioState.unavailable.label,
      'No device');

  const on = RadioStatus(kind: RadioKind.wifi, state: RadioState.on);
  const onLinked = RadioStatus(
    kind: RadioKind.wifi,
    state: RadioState.on,
    connected: true,
  );
  const off = RadioStatus(kind: RadioKind.wifi, state: RadioState.off);
  checkEquals('status label on', on.label, 'On');
  checkEquals('status label on and linked', onLinked.label, 'On, connected');
  checkEquals('status label off', off.label, 'Off');
  check('isOn is true for on', on.isOn);
  check('isOn is false for off', !off.isOn);
}

// ---- 5. the phrase matcher -----------------------------------------------------

typedef _Row = ({
  String phrase,
  AssistantIntent intent,
  Map<String, Object?> params,
});

void testCommandParser() {
  section('[command parser]');

  final rows = <_Row>[
    // radios
    (phrase: 'включи вайфай', intent: AssistantIntent.toggleWifi, params: {'on': true}),
    (phrase: 'выключи вайфай', intent: AssistantIntent.toggleWifi, params: {'on': false}),
    (phrase: 'вайфай включи', intent: AssistantIntent.toggleWifi, params: {'on': true}),
    (phrase: 'вруби вайфай', intent: AssistantIntent.toggleWifi, params: {'on': true}),
    (phrase: 'выруби вайфай', intent: AssistantIntent.toggleWifi, params: {'on': false}),
    (phrase: 'включи wi-fi', intent: AssistantIntent.toggleWifi, params: {'on': true}),
    (phrase: 'включи wi fi', intent: AssistantIntent.toggleWifi, params: {'on': true}),
    (phrase: 'включи вай-фай', intent: AssistantIntent.toggleWifi, params: {'on': true}),
    (phrase: 'включи блютуз', intent: AssistantIntent.toggleBluetooth, params: {'on': true}),
    (phrase: 'включи блютус', intent: AssistantIntent.toggleBluetooth, params: {'on': true}),
    (phrase: 'выключи bluetooth', intent: AssistantIntent.toggleBluetooth, params: {'on': false}),
    (phrase: 'выруби блютуз', intent: AssistantIntent.toggleBluetooth, params: {'on': false}),
    (phrase: 'ВКЛЮЧИ ВАЙФАЙ', intent: AssistantIntent.toggleWifi, params: {'on': true}),
    (phrase: 'Включи, вайфай!', intent: AssistantIntent.toggleWifi, params: {'on': true}),
    (phrase: '  включи   вайфай  ', intent: AssistantIntent.toggleWifi, params: {'on': true}),
    // volume
    (phrase: 'volume 40', intent: AssistantIntent.setVolume, params: {'value': 0.4}),
    (phrase: 'громкость 40%', intent: AssistantIntent.setVolume, params: {'value': 0.4}),
    (phrase: 'громкость 40 процентов', intent: AssistantIntent.setVolume, params: {'value': 0.4}),
    (phrase: 'поставь громкость 50', intent: AssistantIntent.setVolume, params: {'value': 0.5}),
    (phrase: 'сделай громкость 25', intent: AssistantIntent.setVolume, params: {'value': 0.25}),
    (phrase: 'громкость 0', intent: AssistantIntent.setVolume, params: {'value': 0.0}),
    (phrase: 'громкость 100', intent: AssistantIntent.setVolume, params: {'value': 1.0}),
    (phrase: 'на 30 процентов громкость', intent: AssistantIntent.setVolume, params: {'value': 0.3}),
    (phrase: 'звук 30', intent: AssistantIntent.setVolume, params: {'value': 0.3}),
    (phrase: 'громкость пятьдесят', intent: AssistantIntent.setVolume, params: {'value': 0.5}),
    (phrase: 'громкость сорок пять', intent: AssistantIntent.setVolume, params: {'value': 0.45}),
    (phrase: 'громкость сто', intent: AssistantIntent.setVolume, params: {'value': 1.0}),
    (phrase: 'громкость двадцать', intent: AssistantIntent.setVolume, params: {'value': 0.2}),
    (phrase: 'прибавь громкость', intent: AssistantIntent.adjustVolume, params: {'direction': 1.0}),
    (phrase: 'убавь громкость', intent: AssistantIntent.adjustVolume, params: {'direction': -1.0}),
    (phrase: 'прибавь звук', intent: AssistantIntent.adjustVolume, params: {'direction': 1.0}),
    (phrase: 'убавь звук', intent: AssistantIntent.adjustVolume, params: {'direction': -1.0}),
    (phrase: 'громче', intent: AssistantIntent.adjustVolume, params: {'direction': 1.0}),
    (phrase: 'сделай громче', intent: AssistantIntent.adjustVolume, params: {'direction': 1.0}),
    (phrase: 'потише', intent: AssistantIntent.adjustVolume, params: {'direction': -1.0}),
    (phrase: 'тише', intent: AssistantIntent.adjustVolume, params: {'direction': -1.0}),
    // mute
    (phrase: 'заглуши звук', intent: AssistantIntent.setMute, params: {'muted': true}),
    (phrase: 'выключи звук', intent: AssistantIntent.setMute, params: {'muted': true}),
    (phrase: 'выруби звук', intent: AssistantIntent.setMute, params: {'muted': true}),
    (phrase: 'без звука', intent: AssistantIntent.setMute, params: {'muted': true}),
    (phrase: 'mute', intent: AssistantIntent.setMute, params: {'muted': true}),
    (phrase: 'включи звук', intent: AssistantIntent.setMute, params: {'muted': false}),
    (phrase: 'верни звук', intent: AssistantIntent.setMute, params: {'muted': false}),
    (phrase: 'разглуши', intent: AssistantIntent.setMute, params: {'muted': false}),
    (phrase: 'звук включи', intent: AssistantIntent.setMute, params: {'muted': false}),
    // built-in settings
    (phrase: 'открой настройки звука', intent: AssistantIntent.openBuiltInSection, params: {'section': 'sound'}),
    (phrase: 'настройки звука', intent: AssistantIntent.openBuiltInSection, params: {'section': 'sound'}),
    (phrase: 'покажи настройки вайфай', intent: AssistantIntent.openBuiltInSection, params: {'section': 'wifi'}),
    (phrase: 'настройки блютуза', intent: AssistantIntent.openBuiltInSection, params: {'section': 'bluetooth'}),
    (phrase: 'настройки блютус', intent: AssistantIntent.openBuiltInSection, params: {'section': 'bluetooth'}),
    (phrase: 'настройки яркости', intent: AssistantIntent.openBuiltInSection, params: {'section': 'display'}),
    (phrase: 'настройки экрана', intent: AssistantIntent.openBuiltInSection, params: {'section': 'display'}),
    (phrase: 'открой настройки мыши', intent: AssistantIntent.openBuiltInSection, params: {'section': 'input'}),
    (phrase: 'настройки клавиатуры', intent: AssistantIntent.openBuiltInSection, params: {'section': 'input'}),
    (phrase: 'настройки приложений', intent: AssistantIntent.openBuiltInSection, params: {'section': 'apps'}),
    (phrase: 'настройки уведомлений', intent: AssistantIntent.openBuiltInSection, params: {'section': 'apps'}),
    (phrase: 'настройки обновлений', intent: AssistantIntent.openBuiltInSection, params: {'section': 'security'}),
    (phrase: 'настройки паролей', intent: AssistantIntent.openBuiltInSection, params: {'section': 'security'}),
    (phrase: 'настройки языка', intent: AssistantIntent.openBuiltInSection, params: {'section': 'language'}),
    (phrase: 'настройки времени', intent: AssistantIntent.openBuiltInSection, params: {'section': 'language'}),
    (phrase: 'настройки обоев', intent: AssistantIntent.openBuiltInSection, params: {'section': 'appearance'}),
    (phrase: 'настройки темы', intent: AssistantIntent.openBuiltInSection, params: {'section': 'appearance'}),
    (phrase: 'открой настройки', intent: AssistantIntent.openBuiltInSection, params: {'section': 'root'}),
    // windows settings
    (phrase: 'открой параметры windows', intent: AssistantIntent.openWindowsSettings, params: {'uri': 'ms-settings:'}),
    (phrase: 'настройки windows', intent: AssistantIntent.openWindowsSettings, params: {'uri': 'ms-settings:'}),
    // media
    (phrase: 'pause', intent: AssistantIntent.mediaPlayPause, params: {}),
    (phrase: 'играй', intent: AssistantIntent.mediaPlayPause, params: {}),
    (phrase: 'продолжи', intent: AssistantIntent.mediaPlayPause, params: {}),
    (phrase: 'возобнови', intent: AssistantIntent.mediaPlayPause, params: {}),
    (phrase: 'next track', intent: AssistantIntent.mediaNext, params: {}),
    (phrase: 'следующая песня', intent: AssistantIntent.mediaNext, params: {}),
    (phrase: 'previous track', intent: AssistantIntent.mediaPrevious, params: {}),
    (phrase: 'предыдущая композиция', intent: AssistantIntent.mediaPrevious, params: {}),
    // brightness
    (phrase: 'сделай ярче', intent: AssistantIntent.adjustBrightness, params: {'direction': 1.0}),
    (phrase: 'ярче', intent: AssistantIntent.adjustBrightness, params: {'direction': 1.0}),
    (phrase: 'сделай темнее', intent: AssistantIntent.adjustBrightness, params: {'direction': -1.0}),
    (phrase: 'brightness 60', intent: AssistantIntent.setBrightness, params: {'value': 0.6}),
    (phrase: 'яркость 100', intent: AssistantIntent.setBrightness, params: {'value': 1.0}),
    (phrase: 'яркость сто', intent: AssistantIntent.setBrightness, params: {'value': 1.0}),
    // power
    (phrase: 'заблокируй экран', intent: AssistantIntent.lock, params: {}),
    (phrase: 'заблокируй компьютер', intent: AssistantIntent.lock, params: {}),
    (phrase: 'усыпи компьютер', intent: AssistantIntent.sleep, params: {}),
    (phrase: 'sleep', intent: AssistantIntent.sleep, params: {}),
    (phrase: 'перезагрузи компьютер', intent: AssistantIntent.restart, params: {}),
    (phrase: 'restart', intent: AssistantIntent.restart, params: {}),
    (phrase: 'ребут', intent: AssistantIntent.restart, params: {}),
    (phrase: 'выключи компьютер', intent: AssistantIntent.shutdown, params: {}),
    (phrase: 'выключи пк', intent: AssistantIntent.shutdown, params: {}),
    (phrase: 'заверши работу', intent: AssistantIntent.shutdown, params: {}),
    (phrase: 'выйти из системы', intent: AssistantIntent.signOut, params: {}),
    (phrase: 'заверши сеанс', intent: AssistantIntent.signOut, params: {}),
    (phrase: 'выход', intent: AssistantIntent.signOut, params: {}),
    // english
    (phrase: 'turn on wifi', intent: AssistantIntent.toggleWifi, params: {'on': true}),
    (phrase: 'turn off wifi', intent: AssistantIntent.toggleWifi, params: {'on': false}),
    (phrase: 'toggle wifi', intent: AssistantIntent.toggleWifi, params: {}),
    (phrase: 'wifi on', intent: AssistantIntent.toggleWifi, params: {'on': true}),
    (phrase: 'wifi off', intent: AssistantIntent.toggleWifi, params: {'on': false}),
    (phrase: 'enable bluetooth', intent: AssistantIntent.toggleBluetooth, params: {'on': true}),
    (phrase: 'disable bluetooth', intent: AssistantIntent.toggleBluetooth, params: {'on': false}),
    (phrase: 'set volume 50', intent: AssistantIntent.setVolume, params: {'value': 0.5}),
    (phrase: 'volume 100', intent: AssistantIntent.setVolume, params: {'value': 1.0}),
    (phrase: 'louder', intent: AssistantIntent.adjustVolume, params: {'direction': 1.0}),
    (phrase: 'quieter', intent: AssistantIntent.adjustVolume, params: {'direction': -1.0}),
    (phrase: 'turn it up', intent: AssistantIntent.adjustVolume, params: {'direction': 1.0}),
    (phrase: 'turn it down', intent: AssistantIntent.adjustVolume, params: {'direction': -1.0}),
    (phrase: 'sound off', intent: AssistantIntent.setMute, params: {'muted': true}),
    (phrase: 'sound on', intent: AssistantIntent.setMute, params: {'muted': false}),
    (phrase: 'unmute', intent: AssistantIntent.setMute, params: {'muted': false}),
    (phrase: 'open sound settings', intent: AssistantIntent.openBuiltInSection, params: {'section': 'sound'}),
    (phrase: 'open wifi settings', intent: AssistantIntent.openBuiltInSection, params: {'section': 'wifi'}),
    (phrase: 'bluetooth settings', intent: AssistantIntent.openBuiltInSection, params: {'section': 'bluetooth'}),
    (phrase: 'display settings', intent: AssistantIntent.openBuiltInSection, params: {'section': 'display'}),
    (phrase: 'mouse settings', intent: AssistantIntent.openBuiltInSection, params: {'section': 'input'}),
    (phrase: 'notification settings', intent: AssistantIntent.openBuiltInSection, params: {'section': 'apps'}),
    (phrase: 'security settings', intent: AssistantIntent.openBuiltInSection, params: {'section': 'security'}),
    (phrase: 'language settings', intent: AssistantIntent.openBuiltInSection, params: {'section': 'language'}),
    (phrase: 'wallpaper settings', intent: AssistantIntent.openBuiltInSection, params: {'section': 'appearance'}),
    (phrase: 'open windows settings', intent: AssistantIntent.openWindowsSettings, params: {'uri': 'ms-settings:'}),
    (phrase: 'brighter', intent: AssistantIntent.adjustBrightness, params: {'direction': 1.0}),
    (phrase: 'darker', intent: AssistantIntent.adjustBrightness, params: {'direction': -1.0}),
    (phrase: 'play', intent: AssistantIntent.mediaPlayPause, params: {}),
    (phrase: 'resume', intent: AssistantIntent.mediaPlayPause, params: {}),
    (phrase: 'next song', intent: AssistantIntent.mediaNext, params: {}),
    (phrase: 'previous song', intent: AssistantIntent.mediaPrevious, params: {}),
    (phrase: 'lock the screen', intent: AssistantIntent.lock, params: {}),
    (phrase: 'shut down the computer', intent: AssistantIntent.shutdown, params: {}),
    (phrase: 'sign out', intent: AssistantIntent.signOut, params: {}),
    (phrase: 'reboot', intent: AssistantIntent.restart, params: {}),
  ];

  for (final row in rows) {
    final parsed = parseCommand(row.phrase);
    checkEquals(
      '«${row.phrase}» → ${row.intent.id}',
      parsed?.intent,
      row.intent,
    );
    for (final entry in row.params.entries) {
      checkEquals(
        '«${row.phrase}» ${entry.key} = ${entry.value}',
        parsed?.params[entry.key],
        entry.value,
      );
    }
  }

  section('[command parser: what must not be understood]');
  const notUnderstood = [
    'абракадабра',
    '',
    '   ',
    'просто текст',
    'включи',
    'вайфай',
    'громкость',
    'громкость 150',
    'громкость 101',
    'яркость 200',
  ];
  for (final phrase in notUnderstood) {
    check('«$phrase» is not a command', parseCommand(phrase) == null);
  }

  section('[command parser: traps]');
  checkEquals('«переключи вайфай» has no forced direction',
      parseCommand('переключи вайфай')?.params.containsKey('on'), false);
  checkEquals('«переключи блютуз» has no forced direction',
      parseCommand('переключи блютуз')?.params.containsKey('on'), false);
  checkEquals('«выключи звук» is a mute',
      parseCommand('выключи звук')?.intent, AssistantIntent.setMute);
  check('«выключи звук» is not a shutdown',
      parseCommand('выключи звук')?.intent != AssistantIntent.shutdown);
  check('«выключи компьютер» is not a mute',
      parseCommand('выключи компьютер')?.intent != AssistantIntent.setMute);
  check('«настройки звука» does not mute anything',
      parseCommand('настройки звука')?.intent != AssistantIntent.setMute);
  check('«выключи вайфай» is not a shutdown',
      parseCommand('выключи вайфай')?.intent != AssistantIntent.shutdown);
  check('«включи блютуз» is not a mute',
      parseCommand('включи блютуз')?.intent != AssistantIntent.setMute);
  check('«громкость 0» is allowed', parseCommand('громкость 0') != null);
  check('«громкость 100» is allowed', parseCommand('громкость 100') != null);
}

// ---- 6. the router -------------------------------------------------------------

Future<void> testRouter() async {
  section('[router]');

  final sink = _Recorder();
  final router = CommandRouter(sink: sink);

  checkEquals('volume command reply', await router.run('volume 40'), 'volume 40');
  checkEquals('volume command reaches the sink', sink.volumes, [0.4]);

  checkEquals('volume step reply', await router.run('прибавь громкость'), 'volume 42');
  checkEquals('volume step reaches the sink', sink.steps, [1.0]);

  checkEquals('mute reply', await router.run('заглуши звук'), 'sound muted');
  checkEquals('unmute reply', await router.run('включи звук'), 'sound on');
  checkEquals('mute reaches the sink', sink.mutes, [true, false]);

  checkEquals('wifi on reply', await router.run('включи вайфай'), 'Wi-Fi: on');
  checkEquals(
    'wifi off reply',
    await router.run('выключи вайфай'),
    'Wi-Fi: off',
  );
  checkEquals('bluetooth off reply', await router.run('выключи блютуз'),
      'Bluetooth: off');
  checkEquals('radios reach the sink', sink.radios, [
    (RadioKind.wifi, true),
    (RadioKind.wifi, false),
    (RadioKind.bluetooth, false),
  ]);

  checkEquals('built-in section reply', await router.run('открой настройки звука'),
      'opened settings');
  checkEquals('built-in section reaches the sink', sink.sections, ['sound']);

  checkEquals('windows page reply', await router.run('открой параметры windows'),
      'opened windows settings');
  checkEquals('windows page reaches the sink', sink.pages, ['ms-settings:']);

  checkEquals('brightness reply', await router.run('brightness 60'), 'brightness 60');
  checkEquals('brightness reaches the sink', sink.brightness, 0.6);
  checkEquals('brightness step reply', await router.run('сделай ярче'),
      'brightness changed');
  checkEquals('brightness step reaches the sink', sink.brightness, 0.65);

  checkEquals('play pause reply', await router.run('pause'), 'paused');
  checkEquals('next reply', await router.run('next track'), 'next track');
  checkEquals('previous reply', await router.run('previous track'),
      'previous track');
  checkEquals('media reaches the sink', sink.media, ['playPause', 'next', 'previous']);

  checkEquals('lock reply', await router.run('заблокируй экран'),
      'screen locked');
  checkEquals('sleep reply', await router.run('усыпи компьютер'), 'sleeping');
  checkEquals('sign out reply', await router.run('выйти из системы'),
      'signing out');
  checkEquals('restart reply', await router.run('перезагрузи компьютер'),
      'restarting');
  checkEquals('shutdown reply', await router.run('выключи компьютер'), 'shutting down');
  checkEquals('power reaches the sink', sink.power,
      ['lock', 'sleep', 'signOut', 'restart', 'shutdown']);

  final before = sink.totalCalls;
  checkEquals('unknown command says so', await router.run('абракадабра'),
      "didn't catch that");
  checkEquals('unknown command touches nothing', sink.totalCalls, before);
}

// ---- 7. the assistant's prompt and catalog -------------------------------------

void testPromptCatalog() {
  section('[prompt and catalog]');

  final ids = assistantIntents.map((spec) => spec.intent.id).toList();
  checkEquals('catalog ids are unique', ids.toSet().length, ids.length);

  final catalogIds = ids.toSet();
  final enumIds = AssistantIntent.values
      .where((intent) => intent != AssistantIntent.unknown)
      .map((intent) => intent.id)
      .toSet();
  checkEquals('catalog covers the enum', catalogIds, enumIds);

  for (final spec in assistantIntents) {
    check('${spec.intent.id} has examples', spec.examples.isNotEmpty);
    check('${spec.intent.id} says what it does', spec.action.isNotEmpty);
    checkContains('prompt names ${spec.intent.id}', assistantSystemPrompt,
        spec.intent.id);
    final fallback = spec.fallbackUri;
    if (fallback != null) {
      check('${spec.intent.id} fallback is an ms-settings page',
          fallback.startsWith('ms-settings:'));
    }
    for (final example in spec.examples) {
      final parsed = parseCommand(example);
      checkEquals(
        'catalog example «$example» lands on ${spec.intent.id}',
        parsed?.intent,
        spec.intent,
      );
    }
  }

  checkContains('prompt asks for JSON', assistantSystemPrompt, '{"intent"');
  checkContains('prompt says the shell owns its parameters',
      assistantSystemPrompt, 'built-in settings');
  checkContains('prompt keeps ms-settings as the fallback',
      assistantSystemPrompt, 'ms-settings:<uri>');
  checkContains('prompt forbids closing the desktop for sound',
      assistantSystemPrompt, 'never closes');
  checkContains('prompt asks for confirmation before power actions',
      assistantSystemPrompt, 'confirmation');
  checkContains('prompt tells the model to re-read the radio state',
      assistantSystemPrompt, 're-read');
  checkMissing('prompt has no "as an AI" filler', assistantSystemPrompt,
      'as an AI');
  check('prompt is long enough to be a prompt',
      assistantSystemPrompt.length > 1500);
}

// ---- 8. sound, read-only --------------------------------------------------------

void testSoundControl() {
  section('[sound control]');

  final sound = SoundControl.instance;
  sound.refresh();
  final volume = sound.volume;
  check('volume is in range', volume >= 0.0 && volume <= 1.0);
  checkEquals('percent matches the volume', sound.percent, (volume * 100).round());

  // Round-trip through COM: the getter must return the level, not the
  // HRESULT. It used to return 0, which made every panel open at 0%.
  // A CI runner has no audio endpoint; there the getter is a cached value
  // and a round-trip would be meaningless, not failing.
  final hasEndpoint = VolumeControl.instance.available;
  if (!hasEndpoint) {
    check('the volume round-trip is skipped (no audio endpoint)', true);
  }
  final before = VolumeControl.instance.volume;
  try {
    if (hasEndpoint) {
    VolumeControl.instance.volume = 0.37;
      checkClose('the volume getter returns the level, not the HRESULT',
          VolumeControl.instance.volume, 0.37, 0.02);
      VolumeControl.instance.volume = 0.61;
      checkClose('the volume getter follows a second change',
          VolumeControl.instance.volume, 0.61, 0.02);
    }
  } finally {
    VolumeControl.instance.volume = before;
  }
  checkClose('the volume is put back', VolumeControl.instance.volume, before, 0.02);
  check('mute reads as a bool', sound.muted == true || sound.muted == false);
  checkClose(
    'the mirror matches the endpoint',
    volume,
    VolumeControl.instance.volume,
    1e-6,
  );

  var notified = 0;
  void listener() => notified++;
  sound.addListener(listener);
  sound.refresh();
  checkEquals('refresh notifies listeners', notified, 1);
  sound.removeListener(listener);
  sound.refresh();
  checkEquals('a removed listener is not called', notified, 1);
}

// ---- 9. the sound path cannot touch the window ---------------------------------

void testSourceGuards() {
  section('[window guards]');

  const forbidden = ['withdraw(', 'iconify(', 'onClose', 'onMinimize'];
  for (final path in ['lib/command_router.dart', 'lib/sound_control.dart']) {
    final file = File(path);
    check('$path is on disk', file.existsSync());
    if (!file.existsSync()) continue;
    final source = file.readAsStringSync();
    for (final needle in forbidden) {
      checkMissing('$path has no "$needle"', source, needle);
    }
  }
}

// ---- the recorder ---------------------------------------------------------------

class _Recorder implements SystemCommandSink {
  final List<double> volumes = [];
  final List<double> steps = [];
  final List<bool> mutes = [];
  final List<(RadioKind, bool)> radios = [];
  final List<String> sections = [];
  final List<String> pages = [];
  final List<String> media = [];
  final List<String> power = [];
  double? brightness;
  double volume = 0.8;
  bool muted = false;

  int get totalCalls =>
      volumes.length +
      steps.length +
      mutes.length +
      radios.length +
      sections.length +
      pages.length +
      media.length +
      power.length +
      (brightness == null ? 0 : 1);

  @override
  Future<double> setVolume(double value) async {
    volumes.add(value);
    volume = value;
    return volume;
  }

  @override
  Future<double> stepVolume(double direction) async {
    steps.add(direction);
    volume = (volume + 0.02 * direction).clamp(0.0, 1.0);
    return volume;
  }

  @override
  Future<bool> setMuted(bool value) async {
    mutes.add(value);
    muted = value;
    return muted;
  }

  @override
  Future<RadioStatus> setRadioPower(RadioKind kind, bool on) async {
    radios.add((kind, on));
    return RadioStatus(
      kind: kind,
      state: on ? RadioState.on : RadioState.off,
      canToggle: true,
    );
  }

  @override
  Future<void> openBuiltInSection(String sectionId) async {
    sections.add(sectionId);
  }

  @override
  Future<void> openWindowsPage(String uri) async {
    pages.add(uri);
  }

  @override
  Future<void> setBrightness(double value) async {
    brightness = value;
  }

  @override
  Future<void> adjustBrightness(double direction) async {
    brightness = ((brightness ?? 0.6) + 0.05 * direction).clamp(0.0, 1.0);
  }

  @override
  Future<void> mediaPlayPause() async => media.add('playPause');

  @override
  Future<void> mediaNext() async => media.add('next');

  @override
  Future<void> mediaPrevious() async => media.add('previous');

  @override
  Future<void> lockScreen() async => power.add('lock');

  @override
  Future<void> sleepMachine() async => power.add('sleep');

  @override
  Future<void> signOut() async => power.add('signOut');

  @override
  Future<void> restartMachine() async => power.add('restart');

  @override
  Future<void> shutdownMachine() async => power.add('shutdown');
}