// Mock tests for the shell's system layer: the hidden console runner, the
// radio reader, the phrase matcher and the assistant's catalog.
//
// Nothing here changes the machine: the radio is only read from a recorded
// script output, the command router talks to a recorder instead of the real
// device, and the only live calls are a hidden echo and a read-only look at
// the audio endpoint.
//
// Run with a pure Dart SDK (no Flutter needed):
//   dart run test/system_mock_check.dart

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'package:exp_desktop/assistant_prompt.dart';
import 'package:exp_desktop/command_router.dart';
import 'package:exp_desktop/hidden_process.dart';
import 'package:exp_desktop/radio_control.dart';
import 'package:exp_desktop/radio_script.dart';
import 'package:exp_desktop/sound_control.dart';

int _passed = 0;
int _failed = 0;
final List<String> _failures = [];

void check(String name, bool ok) {
  if (ok) {
    _passed++;
    print('  PASS  $name');
  } else {
    _failed++;
    _failures.add(name);
    print('  FAIL  $name');
  }
}

void checkEquals(String name, Object? actual, Object? expected) {
  final ok = actual.toString() == expected.toString();
  if (ok) {
    _passed++;
    print('  PASS  $name');
  } else {
    _failed++;
    _failures.add('$name (got $actual, want $expected)');
    print('  FAIL  $name — got $actual, want $expected');
  }
}

Future<void> main() async {
  print('== system mock tests ==');
  await testHiddenProcess();
  testRadioParsing();
  await testRadioScript();
  testCommandParser();
  await testRouter();
  testPromptCatalog();
  testSoundControl();
  print('');
  print('passed: $_passed   failed: $_failed');
  if (_failed > 0) {
    for (final f in _failures) {
      print('  !! $f');
    }
    throw StateError('MOCK TESTS FAILED');
  }
  print('ALL GREEN');
}

Future<void> testHiddenProcess() async {
  print('[hidden process]');
  final echo = await runHidden('cmd.exe', ['/c', 'echo hello']);
  check('echo exits cleanly', echo.exitCode == 0);
  check('stdout captured', echo.stdout.contains('hello'));
  check('stdout split into lines', echo.lines.contains('hello'));

  final failing = await runHidden('cmd.exe', ['/c', 'echo oops 1>&2 & exit 3']);
  checkEquals('exit code reported', failing.exitCode, 3);
  check('stderr captured', failing.stderr.contains('oops'));

  final missing = await runHidden('definitely-not-a-real-binary.exe', const []);
  check('missing binary does not throw', missing.exitCode != 0);

  final ps = await runPowerShell('Write-Output "ps-ok"');
  check('powershell runs hidden', ps.stdout.contains('ps-ok'));
}

void testRadioParsing() {
  print('[radio parsing]');
  const output = '''
access=Allowed
count=2
radio|WiFi|Intel(R) Wi-Fi 6E AX211|On
radio|Bluetooth|Intel(R) Wireless Bluetooth(R)|Off
adapter|Wi-Fi|Up|Connected
''';
  final snapshot = RadioSnapshot.parse(
    const HiddenResult(exitCode: 0, stdout: output, stderr: ''),
  );
  checkEquals('access parsed', snapshot.access, 'Allowed');

  final wifi = snapshot.statusOf(RadioKind.wifi);
  checkEquals('wifi state', wifi.state, RadioState.on);
  checkEquals('wifi name', wifi.deviceName, 'Intel(R) Wi-Fi 6E AX211');
  checkEquals('wifi adapter name', wifi.adapterName, 'Wi-Fi');
  check('wifi connected', wifi.connected);
  check('wifi can be toggled', wifi.canToggle);

  final bt = snapshot.statusOf(RadioKind.bluetooth);
  checkEquals('bluetooth state', bt.state, RadioState.off);
  check('bluetooth not connected', !bt.connected);

  const empty = 'access=Allowed\ncount=0\n';
  final blank = RadioSnapshot.parse(
    const HiddenResult(exitCode: 0, stdout: empty, stderr: ''),
  );
  checkEquals(
    'no radios means unavailable',
    blank.statusOf(RadioKind.wifi).state,
    RadioState.unavailable,
  );

  const disabled = 'access=Allowed\ncount=1\nradio|WiFi|Wi-Fi|On\nadapter|Wi-Fi|Disabled|Disconnected\n';
  final off = RadioSnapshot.parse(
    const HiddenResult(exitCode: 0, stdout: disabled, stderr: ''),
  );
  checkEquals(
    'disabled adapter reads as off',
    off.statusOf(RadioKind.wifi).state,
    RadioState.off,
  );

  const blocked =
      'access=Allowed\ncount=1\nradio|WiFi|Wi-Fi|DisabledBySystem\n';
  final blockedSnapshot = RadioSnapshot.parse(
    const HiddenResult(exitCode: 0, stdout: blocked, stderr: ''),
  );
  checkEquals(
    'policy-blocked radio',
    blockedSnapshot.statusOf(RadioKind.wifi).state,
    RadioState.blocked,
  );
}

Future<void> testRadioScript() async {
  print('[radio script]');
  final result = await runPowerShell(buildRadioStateScript());
  check('state script runs', result.exitCode == 0 || result.stdout.isNotEmpty);
  check(
    'state script reports access or an error',
    result.stdout.contains('access=') || result.stdout.contains('err|'),
  );
}

void testCommandParser() {
  print('[command parser]');

  ParsedCommand? parse(String text) => parseCommand(text);

  checkEquals('включи вайфай', parse('включи вайфай')?.intent,
      AssistantIntent.toggleWifi);
  checkEquals('включи вайфай -> on', parse('включи вайфай')?.params['on'], true);
  checkEquals('выключи вайфай -> off',
      parse('выключи вайфай')?.params['on'], false);
  checkEquals('переключи вайфай has no direction',
      parse('переключи вайфай')?.params.containsKey('on'), false);
  checkEquals('выключи блютуз', parse('выключи блютуз')?.intent,
      AssistantIntent.toggleBluetooth);
  checkEquals('wi-fi spelling', parse('включи wi-fi')?.intent,
      AssistantIntent.toggleWifi);

  checkEquals('громкость 40', parse('громкость 40')?.intent,
      AssistantIntent.setVolume);
  checkEquals('громкость 40 -> 0.4', parse('громкость 40')?.params['value'],
      0.4);
  checkEquals('поставь громкость 50 процентов',
      parse('поставь громкость 50 процентов')?.params['value'], 0.5);
  checkEquals('прибавь громкость', parse('прибавь громкость')?.intent,
      AssistantIntent.adjustVolume);
  checkEquals('прибавь громкость -> louder',
      parse('прибавь громкость')?.params['direction'], 1.0);
  checkEquals('убавь громкость -> quieter',
      parse('убавь громкость')?.params['direction'], -1.0);
  checkEquals('громче', parse('громче')?.params['direction'], 1.0);
  checkEquals('тише', parse('тише')?.params['direction'], -1.0);

  checkEquals('заглуши звук', parse('заглуши звук')?.intent,
      AssistantIntent.setMute);
  checkEquals('заглуши звук -> muted',
      parse('заглуши звук')?.params['muted'], true);
  checkEquals('выключи звук -> muted',
      parse('выключи звук')?.params['muted'], true);
  checkEquals('включи звук -> unmuted',
      parse('включи звук')?.params['muted'], false);

  checkEquals('открой настройки звука', parse('открой настройки звука')?.intent,
      AssistantIntent.openBuiltInSection);
  checkEquals('настройки звука -> sound',
      parse('открой настройки звука')?.params['section'], 'sound');
  checkEquals('настройки блютуза -> bluetooth',
      parse('настройки блютуза')?.params['section'], 'bluetooth');
  checkEquals('настройки вайфай -> wifi',
      parse('покажи настройки вайфай')?.params['section'], 'wifi');
  checkEquals('параметры windows', parse('открой параметры windows')?.intent,
      AssistantIntent.openWindowsSettings);

  checkEquals('пауза', parse('пауза')?.intent, AssistantIntent.mediaPlayPause);
  checkEquals('следующий трек', parse('следующий трек')?.intent,
      AssistantIntent.mediaNext);
  checkEquals('предыдущий трек', parse('предыдущий трек')?.intent,
      AssistantIntent.mediaPrevious);

  checkEquals('сделай ярче', parse('сделай ярче')?.intent,
      AssistantIntent.adjustBrightness);
  checkEquals('яркость 60', parse('яркость 60')?.params['value'], 0.6);

  checkEquals('заблокируй экран', parse('заблокируй экран')?.intent,
      AssistantIntent.lock);
  checkEquals('усыпи компьютер', parse('усыпи компьютер')?.intent,
      AssistantIntent.sleep);
  checkEquals('перезагрузи компьютер', parse('перезагрузи компьютер')?.intent,
      AssistantIntent.restart);
  checkEquals('выключи компьютер', parse('выключи компьютер')?.intent,
      AssistantIntent.shutdown);
  checkEquals('выйти из системы', parse('выйти из системы')?.intent,
      AssistantIntent.signOut);

  // The rule that broke before: a sound command is never a power command.
  checkEquals('выключи звук is not a shutdown',
      parse('выключи звук')?.intent == AssistantIntent.shutdown, false);
  checkEquals('выключи компьютер is not a mute',
      parse('выключи компьютер')?.intent == AssistantIntent.setMute, false);
  check('nonsense is not understood', parse('абракадабра') == null);
  check('empty is not understood', parse('') == null);
}

Future<void> testRouter() async {
  print('[router]');
  final sink = _RecordingSink();
  final router = CommandRouter(sink: sink);

  final reply = await router.run('прибавь громкость');
  checkEquals('volume step reached the sink', sink.volumeSteps, [1.0]);
  checkEquals('reply names the volume', reply, 'громкость 82');

  await router.run('выключи звук');
  checkEquals('mute reached the sink', sink.mutes, [true]);

  await router.run('включи вайфай');
  checkEquals('wifi reached the sink', sink.radios, [(RadioKind.wifi, true)]);

  await router.run('выключи блютуз');
  checkEquals('bluetooth reached the sink', sink.radios.last,
      (RadioKind.bluetooth, false));

  await router.run('открой настройки звука');
  checkEquals('built-in section reached the sink', sink.sections, ['sound']);

  await router.run('открой параметры windows');
  checkEquals('windows page reached the sink', sink.pages, ['ms-settings:']);

  checkEquals('unknown command says so', await router.run('абракадабра'),
      'не понял команду');
}

void testPromptCatalog() {
  print('[prompt]');
  final catalogIds = assistantIntents.map((s) => s.intent.id).toSet();
  for (final spec in assistantIntents) {
    check(
      'catalog entry ${spec.intent.id} has examples',
      spec.examples.isNotEmpty,
    );
    check(
      'catalog entry ${spec.intent.id} says what it does',
      spec.action.isNotEmpty,
    );
  }
  for (final intent in AssistantIntent.values) {
    if (intent == AssistantIntent.unknown) continue;
    check('catalog knows ${intent.id}', catalogIds.contains(intent.id));
    check(
      'prompt mentions ${intent.id}',
      assistantSystemPrompt.contains(intent.id),
    );
  }
  check(
    'prompt forbids closing the desktop for sound',
    assistantSystemPrompt.contains('никогда не закрывает'),
  );
  check(
    'prompt keeps the built-in settings first',
    assistantSystemPrompt.contains('встроенных настройках'),
  );
}

void testSoundControl() {
  print('[sound control]');
  final sound = SoundControl.instance;
  final volume = sound.volume;
  check('volume readable', volume >= 0.0 && volume <= 1.0);
  check('mute state readable', sound.muted == true || sound.muted == false);
  checkEquals('percent matches volume', sound.percent, (volume * 100).round());
}

// ---- the recorder -------------------------------------------------------------

class _RecordingSink implements SystemCommandSink {
  final List<double> volumeSteps = [];
  final List<bool> mutes = [];
  final List<(RadioKind, bool)> radios = [];
  final List<String> sections = [];
  final List<String> pages = [];
  double volume = 0.8;

  @override
  Future<double> setVolume(double value) async {
    volume = value;
    return value;
  }

  @override
  Future<double> stepVolume(double direction) async {
    volumeSteps.add(direction);
    volume = (volume + 0.02 * direction).clamp(0.0, 1.0);
    return volume;
  }

  @override
  Future<bool> setMuted(bool muted) async {
    mutes.add(muted);
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
  Future<void> setBrightness(double value) async {}

  @override
  Future<void> adjustBrightness(double direction) async {}

  @override
  Future<void> mediaPlayPause() async {}

  @override
  Future<void> mediaNext() async {}

  @override
  Future<void> mediaPrevious() async {}

  @override
  Future<void> lockScreen() async {}

  @override
  Future<void> sleepMachine() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> restartMachine() async {}

  @override
  Future<void> shutdownMachine() async {}
}
