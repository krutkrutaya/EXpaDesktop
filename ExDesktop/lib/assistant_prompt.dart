// The assistant's contract: the system prompt and the intent catalog it
// describes.
//
// The prompt is the thing a language model is given; the catalog is the
// machine-readable twin of the same list, so the buttons, the voice path and
// the prompt can never drift apart. A mock test checks that every intent in
// the catalog is named in the prompt.

/// What the assistant can be asked to do.
enum AssistantIntent {
  toggleWifi,
  toggleBluetooth,
  setVolume,
  adjustVolume,
  setMute,
  openBuiltInSection,
  openWindowsSettings,
  setBrightness,
  adjustBrightness,
  mediaPlayPause,
  mediaNext,
  mediaPrevious,
  lock,
  sleep,
  signOut,
  restart,
  shutdown,
  unknown;

  /// The id used in the prompt and in the JSON replies.
  String get id => switch (this) {
        AssistantIntent.toggleWifi => 'toggle_wifi',
        AssistantIntent.toggleBluetooth => 'toggle_bluetooth',
        AssistantIntent.setVolume => 'set_volume',
        AssistantIntent.adjustVolume => 'adjust_volume',
        AssistantIntent.setMute => 'set_mute',
        AssistantIntent.openBuiltInSection => 'open_settings_section',
        AssistantIntent.openWindowsSettings => 'open_windows_settings',
        AssistantIntent.setBrightness => 'set_brightness',
        AssistantIntent.adjustBrightness => 'adjust_brightness',
        AssistantIntent.mediaPlayPause => 'media_play_pause',
        AssistantIntent.mediaNext => 'media_next',
        AssistantIntent.mediaPrevious => 'media_previous',
        AssistantIntent.lock => 'lock',
        AssistantIntent.sleep => 'sleep',
        AssistantIntent.signOut => 'sign_out',
        AssistantIntent.restart => 'restart',
        AssistantIntent.shutdown => 'shutdown',
        AssistantIntent.unknown => 'unknown',
      };
}

/// One row of the catalog: what the user says, what happens, and where the
/// system keeps the same thing.
class IntentSpec {
  final AssistantIntent intent;

  /// The Russian phrases that mean this intent.
  final List<String> examples;

  /// What the shell actually does.
  final String action;

  /// The Windows page with the same setting, used when the shell cannot do
  /// it itself. Null when the shell owns the setting completely.
  final String? fallbackUri;

  const IntentSpec({
    required this.intent,
    required this.examples,
    required this.action,
    this.fallbackUri,
  });
}

/// The catalog, in the order the prompt lists it.
const List<IntentSpec> assistantIntents = [
  IntentSpec(
    intent: AssistantIntent.toggleWifi,
    examples: [
      'включи вайфай',
      'выключи вайфай',
      'переключи вайфай',
    ],
    action: 'переключить радио Wi-Fi через Windows.Devices.Radios, затем '
        'перечитать состояние и сказать результат',
    fallbackUri: 'ms-settings:network-wifi',
  ),
  IntentSpec(
    intent: AssistantIntent.toggleBluetooth,
    examples: [
      'включи блютуз',
      'выключи блютуз',
    ],
    action: 'переключить радио Bluetooth через Windows.Devices.Radios, затем '
        'перечитать состояние и сказать результат',
    fallbackUri: 'ms-settings:bluetooth',
  ),
  IntentSpec(
    intent: AssistantIntent.setVolume,
    examples: [
      'громкость 40',
      'поставь громкость 50 процентов',
      'сделай громкость тише',
    ],
    action: 'задать мастер-громкость через IAudioEndpointVolume, окна не '
        'открывать',
  ),
  IntentSpec(
    intent: AssistantIntent.adjustVolume,
    examples: [
      'прибавь громкость',
      'убавь громкость',
      'громче',
      'тише',
    ],
    action: 'сдвинуть мастер-громкость на шаг (2%), окна не открывать',
  ),
  IntentSpec(
    intent: AssistantIntent.setMute,
    examples: [
      'заглуши звук',
      'выключи звук',
      'включи звук',
    ],
    action: 'заглушить или включить мастер-звук, окна не открывать',
  ),
  IntentSpec(
    intent: AssistantIntent.openBuiltInSection,
    examples: [
      'открой настройки звука',
      'покажи настройки вайфай',
      'настройки блютуза',
    ],
    action: 'открыть раздел во встроенных настройках оболочки, где параметр '
        'живёт как настоящий контрол',
  ),
  IntentSpec(
    intent: AssistantIntent.openWindowsSettings,
    examples: [
      'открой параметры windows',
      'покажи настройки видеокарты',
    ],
    action: 'открыть страницу Параметров Windows через ms-settings:<uri>, '
        'только если раздела нет во встроенных настройках',
  ),
  IntentSpec(
    intent: AssistantIntent.setBrightness,
    examples: [
      'сделай ярче',
      'сделай темнее',
      'яркость 60',
    ],
    action: 'задать яркость через DDC/CI (native DLL), без окон',
  ),
  IntentSpec(
    intent: AssistantIntent.adjustBrightness,
    examples: [
      'сделай ярче',
      'сделай темнее',
    ],
    action: 'сдвинуть яркость на шаг через DDC/CI, без окон',
  ),
  IntentSpec(
    intent: AssistantIntent.mediaPlayPause,
    examples: ['пауза', 'играй', 'продолжи'],
    action: 'медиа-клавиша play/pause',
  ),
  IntentSpec(
    intent: AssistantIntent.mediaNext,
    examples: ['следующий трек', 'дальше'],
    action: 'медиа-клавиша next',
  ),
  IntentSpec(
    intent: AssistantIntent.mediaPrevious,
    examples: ['предыдущий трек', 'назад'],
    action: 'медиа-клавиша previous',
  ),
  IntentSpec(
    intent: AssistantIntent.lock,
    examples: ['заблокируй экран', 'замкни компьютер'],
    action: 'LockWorkStation',
  ),
  IntentSpec(
    intent: AssistantIntent.sleep,
    examples: ['усыпи компьютер', 'спящий режим'],
    action: 'SetSuspendState',
  ),
  IntentSpec(
    intent: AssistantIntent.signOut,
    examples: ['выйди из системы', 'заверши сеанс'],
    action: 'shutdown /l',
  ),
  IntentSpec(
    intent: AssistantIntent.restart,
    examples: ['перезагрузи компьютер', 'перезапусти'],
    action: 'shutdown /r /t 0, с подтверждением',
  ),
  IntentSpec(
    intent: AssistantIntent.shutdown,
    examples: ['выключи компьютер', 'заверши работу'],
    action: 'shutdown /s /t 0, с подтверждением',
  ),
];

/// The system prompt the assistant runs on.
///
/// It is written for a model that returns one action per turn, and it keeps
/// the two rules that used to be broken: the shell owns the parameters it
/// can own, and a sound command never closes the desktop.
const String assistantSystemPrompt = r'''
# Роль
Ты — голосовой ассистент оболочки EXpaDesktop на Windows. Ты получаешь команду
пользователя (голосом или текстом) и возвращаешь ровно одно действие. Диалог не
ведёшь, интерфейс не описываешь, списков не перечисляешь.

# Формат ответа — строго JSON, без текста вокруг
{"intent": "<intent>", "params": {…}, "reply": "<короткая фраза пользователю>"}

# Где живут параметры
Параметры, которыми оболочка умеет управлять сама (Wi-Fi, Bluetooth, звук и
громкость, яркость), живут во встроенных настройках оболочки и в её верхней
панели. Встроенные настройки — источник истины.

ms-settings:<uri> — только запасной вариант:
  — раздела нет во встроенных настройках;
  — системе нужно подтверждение или права администратора.
Никогда не открывай ms-settings для того, что уже есть в оболочке.

# Каталог намерений
- toggle_wifi: включи/выключи/переключи вайфай. Переключить радио, перечитать
  состояние, сказать фактический результат. Если система не дала —
  ms-settings:network-wifi.
- toggle_bluetooth: то же самое для Bluetooth. Если система не дала —
  ms-settings:bluetooth.
- set_volume: громкость N / потише / погромче. Задать мастер-громкость, окна не
  открывать.
- adjust_volume: прибавь/убавь громкость, громче, тише. Шаг 2%.
- set_mute: заглуши, выключи звук, включи звук. Только звук, окна не открывать.
- open_settings_section: открой настройки звука / вайфай / блютуза. Открыть
  раздел во встроенных настройках оболочки.
- open_windows_settings: то, чего во встроенных настройках нет. ms-settings:<uri>.
- set_brightness: яркость N. Через DDC/CI.
- adjust_brightness: ярче, темнее. Сдвинуть яркость на шаг, без окон.
- media_play_pause / media_next / media_previous: пауза, играй, следующий трек,
  предыдущий трек.
- lock / sleep / sign_out / restart / shutdown: блокировка, сон, выход,
  перезагрузка, выключение. Перезагрузка и выключение — только после
  подтверждения пользователя.

# Правила
1. «включи / выключи / переключи» — это действие над состоянием, а не
   открытие окна. Никогда не подменяй его открытием Параметров.
2. После переключения радио ответ должен опираться на состояние, которое
   система вернула после действия, а не на предположение.
3. Команда про звук никогда не закрывает, не сворачивает и не прячет окно
   оболочки. Звук — это звук.
4. Если параметр не назван (какую именно сеть, какое устройство) — задай один
   уточняющий вопрос и ничего не выполняй.
5. Reply — одна короткая фраза в нижнем регистре: «вайфай выключен»,
   «громкость 40», «звук заглушён». Без объяснений и без извинений.
6. Не выполняй опасные действия (перезагрузка, выключение, выход) без
   подтверждения.
7. Если команда непонятна — intent "unknown" и короткий вопрос, что именно
   имелось в виду.
''';
