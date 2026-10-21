# The assistant's prompt

This file is the contract for the shell's voice/text assistant: the system
prompt, the intent catalog, and the rules for extending both. The machine
copies live in `ExDesktop/lib/assistant_prompt.dart` (prompt + catalog) and
`ExDesktop/lib/command_router.dart` (phrasings → actions); this page is the
human-readable version of the same thing.

> Rule of thumb: a parameter the shell can drive itself lives in the shell's
> own settings as a real control. `ms-settings:` is the fallback, not the
> place where the parameter lives.

## System prompt

```
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
```

## Intent catalog

| intent | what the user says | what happens | fallback |
|---|---|---|---|
| `toggle_wifi` | включи / выключи / переключи вайфай | radio switched through `Windows.Devices.Radios`, state re-read | `ms-settings:network-wifi` |
| `toggle_bluetooth` | включи / выключи блютуз | same for the Bluetooth radio | `ms-settings:bluetooth` |
| `set_volume` | громкость 40, поставь 50 процентов | master volume set through `IAudioEndpointVolume` | — |
| `adjust_volume` | прибавь / убавь громкость, громче, тише | master volume stepped by 2% | — |
| `set_mute` | заглуши, выключи / включи звук | master mute toggled | — |
| `open_settings_section` | открой настройки звука / вайфай / блютуза | the shell's own settings opens on that section | — |
| `open_windows_settings` | открой параметры windows | the Windows page, `ms-settings:` | — |
| `set_brightness` | яркость 60 | DDC/CI through the Rust DLL | `ms-settings:display` |
| `adjust_brightness` | ярче, темнее | brightness stepped by 5% | `ms-settings:display` |
| `media_play_pause` | пауза, играй | media key | — |
| `media_next` / `media_previous` | следующий / предыдущий трек | media key | — |
| `lock` | заблокируй экран | `LockWorkStation` | — |
| `sleep` | усыпи компьютер | `SetSuspendState` | — |
| `sign_out` | выйти из системы | `shutdown /l` | — |
| `restart` | перезагрузи компьютер | `shutdown /r /t 0` after confirmation | — |
| `shutdown` | выключи компьютер | `shutdown /s /t 0` after confirmation | — |

## How a command travels

```
phrase ──► parseCommand()  (command_router.dart)
             │  Russian stems: "звука", "перезагрузи", "следующий" all fold
             ▼
        ParsedCommand{intent, params}
             │
             ▼
        CommandRouter.perform()
             │  the same SystemCommandSink the buttons use
             ▼
        real machine  ──►  short Russian reply
```

Two consequences worth keeping:

- **One code path.** The settings slider, the top-panel flyout and the phrase
  «громкость 40» all end in `SoundControl`, so they can never disagree.
- **No window calls in the sink.** `SystemCommandSink` has no way to hide,
  close or minimize the desktop. A sound command cannot close the shell even
  if it wanted to.

## Adding an intent

1. Add the case to `AssistantIntent` in `assistant_prompt.dart` (with its `id`).
2. Add the `IntentSpec` row: examples, what it does, the `ms-settings:` fallback.
3. Mention it in `assistantSystemPrompt` under the catalog.
4. Add the matcher in `command_router.dart` (`_matchXxx`) and call it from
   `parseCommand` — specific matchers first, generic last.
5. Add the sink method if it needs a new machine operation.
6. Add checks to `test/system_mock_check.dart`: a phrase per synonym, the
   reply text, and the negative case ("выключи звук" must not be a shutdown).

`test/system_mock_check.dart` also fails if a catalog entry is missing from
the prompt or from the enum, so the three can't drift apart silently.