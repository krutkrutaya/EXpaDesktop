// The voice/text path: a command becomes an intent, an intent becomes an
// action, an action becomes a short sentence.
//
// The router is the only place that knows how a phrase maps to a machine
// operation, and the buttons call the very same sink, so "turn the volume
// down" and the slider in the settings window can never disagree. Nothing in
// here can close the desktop: the sink has no way to touch the window.
//
// Both English and Russian phrasings are understood; the replies follow the
// UI language, which is English.

import 'assistant_prompt.dart';
import 'radio_control.dart';

/// A command that was understood.
class ParsedCommand {
  final AssistantIntent intent;
  final Map<String, Object?> params;

  const ParsedCommand(this.intent, [this.params = const {}]);

  @override
  String toString() => 'ParsedCommand(${intent.id}, $params)';
}

/// Everything the shell can do when a command is understood.
///
/// The shell implements this against the real machine; the tests implement it
/// with a recorder.
abstract class SystemCommandSink {
  /// Sets the master volume (0..1) and returns what the device ended up at.
  Future<double> setVolume(double value);

  /// Moves the master volume by one step and returns the new value.
  Future<double> stepVolume(double direction);

  /// Mutes or unmutes and returns the state the device ended up in.
  Future<bool> setMuted(bool muted);

  /// Switches a radio and returns the state the system reports afterwards.
  Future<RadioStatus> setRadioPower(RadioKind kind, bool on);

  /// Opens a section of the shell's own settings.
  Future<void> openBuiltInSection(String sectionId);

  /// Opens a Windows Settings page (ms-settings:...).
  Future<void> openWindowsPage(String uri);

  /// Sets the monitor brightness (0..1).
  Future<void> setBrightness(double value);

  /// Moves the brightness by one step (-1 darker, +1 brighter).
  Future<void> adjustBrightness(double direction);

  Future<void> mediaPlayPause();
  Future<void> mediaNext();
  Future<void> mediaPrevious();
  Future<void> lockScreen();
  Future<void> sleepMachine();
  Future<void> signOut();
  Future<void> restartMachine();
  Future<void> shutdownMachine();
}

/// Turns phrases into commands and commands into actions.
class CommandRouter {
  final SystemCommandSink sink;
  final RadioControl radio;

  CommandRouter({required this.sink, RadioControl? radio})
      : radio = radio ?? RadioControl.instance;

  /// Understands [utterance] and performs it. Returns the reply sentence.
  Future<String> run(String utterance) async {
    final command = parseCommand(utterance);
    if (command == null) return "didn't catch that";
    return perform(command);
  }

  /// Performs an already understood command.
  Future<String> perform(ParsedCommand command) async {
    switch (command.intent) {
      case AssistantIntent.setVolume:
        final value = await sink.setVolume(command.params['value']! as double);
        return 'volume ${(value * 100).round()}';
      case AssistantIntent.adjustVolume:
        final value =
            await sink.stepVolume(command.params['direction']! as double);
        return 'volume ${(value * 100).round()}';
      case AssistantIntent.setMute:
        final muted = await sink.setMuted(command.params['muted']! as bool);
        return muted ? 'sound muted' : 'sound on';
      case AssistantIntent.toggleWifi:
        return _toggleRadio(RadioKind.wifi, command.params['on'] as bool?);
      case AssistantIntent.toggleBluetooth:
        return _toggleRadio(RadioKind.bluetooth, command.params['on'] as bool?);
      case AssistantIntent.openBuiltInSection:
        await sink.openBuiltInSection(command.params['section']! as String);
        return 'opened settings';
      case AssistantIntent.openWindowsSettings:
        await sink.openWindowsPage(command.params['uri']! as String);
        return 'opened windows settings';
      case AssistantIntent.setBrightness:
        final value = command.params['value']! as double;
        await sink.setBrightness(value);
        return 'brightness ${(value * 100).round()}';
      case AssistantIntent.adjustBrightness:
        await sink.adjustBrightness(command.params['direction']! as double);
        return 'brightness changed';
      case AssistantIntent.mediaPlayPause:
        await sink.mediaPlayPause();
        return 'paused';
      case AssistantIntent.mediaNext:
        await sink.mediaNext();
        return 'next track';
      case AssistantIntent.mediaPrevious:
        await sink.mediaPrevious();
        return 'previous track';
      case AssistantIntent.lock:
        await sink.lockScreen();
        return 'screen locked';
      case AssistantIntent.sleep:
        await sink.sleepMachine();
        return 'sleeping';
      case AssistantIntent.signOut:
        await sink.signOut();
        return 'signing out';
      case AssistantIntent.restart:
        await sink.restartMachine();
        return 'restarting';
      case AssistantIntent.shutdown:
        await sink.shutdownMachine();
        return 'shutting down';
      case AssistantIntent.unknown:
        return "didn't catch that";
    }
  }

  Future<String> _toggleRadio(RadioKind kind, bool? on) async {
    final wanted = on ?? !(await radio.status(kind)).isOn;
    final result = await sink.setRadioPower(kind, wanted);
    return '${kind.label}: ${result.state.label.toLowerCase()}';
  }
}

// ---- the phrase matcher ------------------------------------------------------

/// Reads an English or Russian command and returns what it means.
ParsedCommand? parseCommand(String utterance) {
  final words = _words(utterance);
  if (words.isEmpty) return null;

  // Sound first: "turn the sound off" must never be read as anything else.
  final mute = _matchMute(words);
  if (mute != null) return mute;

  final volume = _matchVolume(words);
  if (volume != null) return volume;

  final brightness = _matchBrightness(words);
  if (brightness != null) return brightness;

  final media = _matchMedia(words);
  if (media != null) return media;

  final power = _matchPower(words);
  if (power != null) return power;

  final settings = _matchSettings(words);
  if (settings != null) return settings;

  final radio = _matchRadio(words);
  if (radio != null) return radio;

  return null;
}

List<String> _words(String utterance) => utterance
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9 ]'), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// An exact word.
bool _has(List<String> words, String needle) => words.contains(needle);

/// Two adjacent words, for English phrasal verbs: "turn on", "shut down".
bool _hasPhrase(List<String> words, String first, String second) {
  for (var i = 0; i + 1 < words.length; i++) {
    if (words[i] == first && words[i + 1] == second) return true;
  }
  return false;
}

/// A word that starts with the stem: Russian inflects, and a command says
/// "звука", "перезагрузи", "следующий" - the stem is what stays the same.
bool _stem(List<String> words, String stem) =>
    words.any((w) => w == stem || w.startsWith(stem));

bool _hasAnyPrefix(List<String> words, List<String> prefixes) =>
    words.any((w) => prefixes.any((p) => w.startsWith(p)));

/// Numbers the way people say them out loud (Russian "сорок пять", "сто").
const Map<String, int> _numeralWords = {
  'ноль': 0,
  'один': 1,
  'одну': 1,
  'одна': 1,
  'два': 2,
  'две': 2,
  'три': 3,
  'четыре': 4,
  'пять': 5,
  'шесть': 6,
  'семь': 7,
  'восемь': 8,
  'девять': 9,
  'десять': 10,
  'одиннадцать': 11,
  'двенадцать': 12,
  'тринадцать': 13,
  'четырнадцать': 14,
  'пятнадцать': 15,
  'шестнадцать': 16,
  'семнадцать': 17,
  'восемнадцать': 18,
  'девятнадцать': 19,
  'двадцать': 20,
  'тридцать': 30,
  'сорок': 40,
  'пятьдесят': 50,
  'шестьдесят': 60,
  'семьдесят': 70,
  'восемьдесят': 80,
  'девяносто': 90,
  'сто': 100,
};

/// The first number in the phrase, digits or words: "40", "40%",
/// "сорок", "двадцать пять", "сто".
int? _number(List<String> words) {
  var total = 0;
  var seen = false;
  for (final word in words) {
    final digit = int.tryParse(word);
    if (digit != null) {
      total += digit;
      seen = true;
      continue;
    }
    final value = _numeralWords[word];
    if (value != null) {
      total += value;
      seen = true;
      continue;
    }
    if (seen) break;
  }
  return seen ? total : null;
}

bool _mentionsSound(List<String> words) =>
    _stem(words, 'звук') ||
    _stem(words, 'динамик') ||
    _stem(words, 'шум') ||
    _has(words, 'sound') ||
    _has(words, 'audio');

bool _mentionsVolume(List<String> words) =>
    _stem(words, 'громкост') || _has(words, 'volume');

bool _mentionsWifi(List<String> words) =>
    _stem(words, 'вайфай') ||
    _has(words, 'wifi') ||
    _has(words, 'wireless') ||
    (_stem(words, 'вай') && _stem(words, 'фай')) ||
    (_has(words, 'wi') && _has(words, 'fi'));

bool _mentionsBluetooth(List<String> words) =>
    _stem(words, 'блютуз') ||
    _stem(words, 'блютус') ||
    _has(words, 'bluetooth');

bool _mentionsSettings(List<String> words) =>
    _stem(words, 'настройк') ||
    _stem(words, 'параметр') ||
    _has(words, 'settings') ||
    _has(words, 'setting');

ParsedCommand? _matchMute(List<String> words) {
  if (_has(words, 'mute') ||
      _has(words, 'unmute') ||
      _hasPhrase(words, 'sound', 'off') ||
      _hasPhrase(words, 'sound', 'on') ||
      _hasAnyPrefix(words, ['заглуш', 'приглуш'])) {
    // "unmute" and "sound on" mean the opposite of the rest.
    final unmute = _has(words, 'unmute') || _hasPhrase(words, 'sound', 'on');
    return ParsedCommand(AssistantIntent.setMute, {'muted': !unmute});
  }
  // "разглуши" carries no object of its own: the word is the whole command.
  if (_stem(words, 'разглуш')) {
    return const ParsedCommand(AssistantIntent.setMute, {'muted': false});
  }
  if (_mentionsSound(words)) {
    if (_hasAnyPrefix(words, ['выключ', 'выруб']) ||
        _hasPhrase(words, 'turn', 'off')) {
      return const ParsedCommand(AssistantIntent.setMute, {'muted': true});
    }
    if (_hasAnyPrefix(words, ['включ', 'вруб', 'верн']) ||
        _stem(words, 'разглуш') ||
        _hasPhrase(words, 'turn', 'on')) {
      return const ParsedCommand(AssistantIntent.setMute, {'muted': false});
    }
    if (_stem(words, 'без')) {
      return const ParsedCommand(AssistantIntent.setMute, {'muted': true});
    }
  }
  return null;
}

ParsedCommand? _matchVolume(List<String> words) {
  final mentions = _mentionsVolume(words) || _mentionsSound(words);
  final louder = _stem(words, 'громче') ||
      _stem(words, 'погромче') ||
      _has(words, 'louder') ||
      _hasPhrase(words, 'turn', 'up') ||
      _hasPhrase(words, 'turn', 'it') && _has(words, 'up') ||
      (mentions && _hasAnyPrefix(words, ['прибав', 'увелич', 'добав']));
  final quieter = _stem(words, 'тише') ||
      _stem(words, 'потише') ||
      _has(words, 'quieter') ||
      _hasPhrase(words, 'turn', 'down') ||
      _hasPhrase(words, 'turn', 'it') && _has(words, 'down') ||
      (mentions && _hasAnyPrefix(words, ['убав', 'уменьш']));

  if (louder && !quieter) {
    return const ParsedCommand(AssistantIntent.adjustVolume, {'direction': 1.0});
  }
  if (quieter && !louder) {
    return const ParsedCommand(AssistantIntent.adjustVolume, {'direction': -1.0});
  }

  final percent = _number(words);
  if (mentions && percent != null && percent >= 0 && percent <= 100) {
    return ParsedCommand(AssistantIntent.setVolume, {
      'value': (percent / 100).clamp(0.0, 1.0),
    });
  }
  return null;
}

ParsedCommand? _matchBrightness(List<String> words) {
  final mentions = _stem(words, 'яркост') || _has(words, 'brightness');
  final percent = _number(words);
  if (mentions && percent != null && percent >= 0 && percent <= 100) {
    return ParsedCommand(AssistantIntent.setBrightness, {
      'value': (percent / 100).clamp(0.0, 1.0),
    });
  }
  if (_stem(words, 'ярче') || _has(words, 'brighter')) {
    return const ParsedCommand(
      AssistantIntent.adjustBrightness,
      {'direction': 1.0},
    );
  }
  if (_stem(words, 'темнее') ||
      _stem(words, 'потускнее') ||
      _has(words, 'darker') ||
      _has(words, 'dimmer')) {
    return const ParsedCommand(
      AssistantIntent.adjustBrightness,
      {'direction': -1.0},
    );
  }
  return null;
}

ParsedCommand? _matchMedia(List<String> words) {
  if (_stem(words, 'пауз') ||
      _stem(words, 'играй') ||
      _stem(words, 'продолжи') ||
      _stem(words, 'возобнови') ||
      _has(words, 'pause') ||
      _has(words, 'play') ||
      _has(words, 'resume')) {
    return const ParsedCommand(AssistantIntent.mediaPlayPause);
  }
  final music = _stem(words, 'трек') ||
      _stem(words, 'песня') ||
      _stem(words, 'музык') ||
      _stem(words, 'композиц') ||
      _has(words, 'track') ||
      _has(words, 'song') ||
      _has(words, 'music');
  if (music &&
      (_stem(words, 'следующ') ||
          _stem(words, 'дальше') ||
          _has(words, 'next'))) {
    return const ParsedCommand(AssistantIntent.mediaNext);
  }
  if (music &&
      (_stem(words, 'предыдущ') ||
          _stem(words, 'назад') ||
          _has(words, 'previous'))) {
    return const ParsedCommand(AssistantIntent.mediaPrevious);
  }
  return null;
}

ParsedCommand? _matchPower(List<String> words) {
  if (_hasAnyPrefix(words, ['заблокир', 'замкн']) ||
      _has(words, 'lock') ||
      _hasPhrase(words, 'lock', 'screen')) {
    return const ParsedCommand(AssistantIntent.lock);
  }
  if (_stem(words, 'усып') ||
      _stem(words, 'спящ') ||
      _has(words, 'сон') ||
      _has(words, 'sleep') ||
      _has(words, 'suspend')) {
    return const ParsedCommand(AssistantIntent.sleep);
  }
  if (_stem(words, 'перезагруз') ||
      _stem(words, 'перезапуст') ||
      _stem(words, 'ребут') ||
      _has(words, 'restart') ||
      _has(words, 'reboot')) {
    return const ParsedCommand(AssistantIntent.restart);
  }
  if (_stem(words, 'заверши') && _stem(words, 'работ')) {
    return const ParsedCommand(AssistantIntent.shutdown);
  }
  if (_hasPhrase(words, 'shut', 'down') ||
      _has(words, 'shutdown') ||
      _has(words, 'poweroff')) {
    return const ParsedCommand(AssistantIntent.shutdown);
  }
  final machine = _stem(words, 'комп') ||
      _stem(words, 'ноут') ||
      _stem(words, 'пк') ||
      _stem(words, 'машина') ||
      _has(words, 'computer') ||
      _has(words, 'pc');
  if (machine &&
      (_hasAnyPrefix(words, ['выключ', 'выруб']) || _hasPhrase(words, 'turn', 'off'))) {
    return const ParsedCommand(AssistantIntent.shutdown);
  }
  if (_stem(words, 'выйти') ||
      _stem(words, 'выйд') ||
      _stem(words, 'выход') ||
      _hasPhrase(words, 'sign', 'out') ||
      _hasPhrase(words, 'log', 'out')) {
    return const ParsedCommand(AssistantIntent.signOut);
  }
  if (_stem(words, 'заверши') && _stem(words, 'сеанс')) {
    return const ParsedCommand(AssistantIntent.signOut);
  }
  return null;
}

ParsedCommand? _matchSettings(List<String> words) {
  if (!_mentionsSettings(words)) return null;

  if (_has(words, 'windows') || _stem(words, 'виндовс')) {
    return const ParsedCommand(AssistantIntent.openWindowsSettings, {
      'uri': 'ms-settings:',
    });
  }
  if (_mentionsSound(words)) {
    return const ParsedCommand(AssistantIntent.openBuiltInSection, {
      'section': 'sound',
    });
  }
  if (_mentionsWifi(words)) {
    return const ParsedCommand(AssistantIntent.openBuiltInSection, {
      'section': 'wifi',
    });
  }
  if (_mentionsBluetooth(words)) {
    return const ParsedCommand(AssistantIntent.openBuiltInSection, {
      'section': 'bluetooth',
    });
  }
  if (_stem(words, 'яркост') ||
      _stem(words, 'экран') ||
      _stem(words, 'дисплей') ||
      _has(words, 'display') ||
      _has(words, 'screen') ||
      _has(words, 'brightness')) {
    return const ParsedCommand(AssistantIntent.openBuiltInSection, {
      'section': 'display',
    });
  }
  if (_stem(words, 'мыш') ||
      _stem(words, 'клавиатур') ||
      _stem(words, 'ввод') ||
      _has(words, 'mouse') ||
      _has(words, 'keyboard') ||
      _has(words, 'input')) {
    return const ParsedCommand(AssistantIntent.openBuiltInSection, {
      'section': 'input',
    });
  }
  if (_stem(words, 'приложен') ||
      _stem(words, 'окн') ||
      _stem(words, 'уведомлен') ||
      _has(words, 'apps') ||
      _has(words, 'windows') ||
      _has(words, 'notification') ||
      _has(words, 'notifications')) {
    return const ParsedCommand(AssistantIntent.openBuiltInSection, {
      'section': 'apps',
    });
  }
  if (_stem(words, 'обновлен') ||
      _stem(words, 'безопасн') ||
      _stem(words, 'парол') ||
      _has(words, 'update') ||
      _has(words, 'security') ||
      _has(words, 'password')) {
    return const ParsedCommand(AssistantIntent.openBuiltInSection, {
      'section': 'security',
    });
  }
  if (_stem(words, 'язык') ||
      _stem(words, 'врем') ||
      _stem(words, 'регион') ||
      _has(words, 'language') ||
      _has(words, 'time') ||
      _has(words, 'region')) {
    return const ParsedCommand(AssistantIntent.openBuiltInSection, {
      'section': 'language',
    });
  }
  if (_stem(words, 'обо') ||
      _stem(words, 'цвет') ||
      _stem(words, 'тем') ||
      _stem(words, 'шрифт') ||
      _stem(words, 'оформлен') ||
      _has(words, 'wallpaper') ||
      _has(words, 'colors') ||
      _has(words, 'theme') ||
      _has(words, 'fonts')) {
    return const ParsedCommand(AssistantIntent.openBuiltInSection, {
      'section': 'appearance',
    });
  }
  return const ParsedCommand(AssistantIntent.openBuiltInSection, {
    'section': 'root',
  });
}

ParsedCommand? _matchRadio(List<String> words) {
  final isWifi = _mentionsWifi(words);
  final isBluetooth = _mentionsBluetooth(words);
  if (!isWifi && !isBluetooth) return null;

  final on = _hasAnyPrefix(words, ['включ', 'подключ', 'вруб']) ||
      _hasPhrase(words, 'turn', 'on') ||
      _hasPhrase(words, 'switch', 'on') ||
      _has(words, 'enable') ||
      _has(words, 'on');
  final off = _hasAnyPrefix(words, ['выключ', 'отключ', 'выруб']) ||
      _hasPhrase(words, 'turn', 'off') ||
      _hasPhrase(words, 'switch', 'off') ||
      _has(words, 'disable') ||
      _has(words, 'off');
  final toggle = _hasAnyPrefix(words, ['переключ', 'перевкл']) ||
      _has(words, 'toggle') ||
      _has(words, 'switch');
  if (!on && !off && !toggle) return null;

  final intent =
      isWifi ? AssistantIntent.toggleWifi : AssistantIntent.toggleBluetooth;
  if (off) return ParsedCommand(intent, {'on': false});
  if (on) return ParsedCommand(intent, {'on': true});
  return ParsedCommand(intent);
}