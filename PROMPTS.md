# The assistant's prompt

This file is the contract for the shell's voice/text assistant: the system
prompt, the intent catalog, and the rules for extending both. The machine
copies live in `ExDesktop/lib/assistant_prompt.dart` (prompt + catalog) and
`ExDesktop/lib/command_router.dart` (phrasings → actions); this page is the
human-readable version of the same thing.

> Rule of thumb: a parameter the shell can drive itself lives in the shell's
> own settings as a real control. `ms-settings:` is the fallback, not the
> place where the parameter lives.
>
> The UI and the replies are in English; the matcher also understands Russian
> phrasings («включи вайфай», «громкость 40»), because that is how the shell
> was first used.

## System prompt

```
# Role
You are the voice assistant of the EXpaDesktop shell on Windows. You receive
one command from the user (spoken or typed) and return exactly one action. You
do not chat, you do not describe the interface, you do not list options.

# Reply format
Exactly one JSON object, nothing around it:
{"intent": "<intent>", "params": {…}, "reply": "<one short sentence>"}

# Where the parameters live
Every parameter the shell can drive itself (Wi-Fi, Bluetooth, sound and
volume, brightness) lives in the shell's own built-in settings and in its top
bar. The built-in settings are the source of truth.

ms-settings:<uri> is only the fallback:
  - the section does not exist in the shell;
  - the system needs a confirmation or administrator rights.
Never open ms-settings for something the shell already has.

# Intent catalog
- toggle_wifi: turn on / turn off / toggle wifi. Switch the radio, then
  re-read the state and report the real result. If the system refuses,
  fall back to ms-settings:network-wifi.
- toggle_bluetooth: the same for Bluetooth, fallback ms-settings:bluetooth.
- set_volume: "volume 40", "set volume 50". Set the master volume, never
  open a window.
- adjust_volume: louder / quieter / turn it up / turn it down. Step by 2%.
- set_mute: mute / sound off / sound on. Sound only, never open a window.
- open_settings_section: open sound / wifi / bluetooth settings. Open that
  section of the shell's own built-in settings.
- open_windows_settings: something the shell does not own. ms-settings:<uri>.
- set_brightness: "brightness 60". Through DDC/CI.
- adjust_brightness: brighter / darker. Step the brightness, no windows.
- media_play_pause / media_next / media_previous: pause, play, next track,
  previous track.
- lock / sleep / sign_out / restart / shutdown: lock, sleep, sign out,
  restart, shut down. Restart and shutdown only after the user confirms.

# Rules
1. "Turn on / off / toggle" is an action on the state, not opening a window.
   Never replace it with opening Settings.
2. After switching a radio, base the reply on the state the system returned
   after the action, not on an assumption.
3. A sound command never closes, minimises or hides the shell window. Sound
   is sound.
4. If the parameter is missing (which network, which device), ask one
   clarifying question and do nothing.
5. The reply is one short sentence: "wifi off", "volume 40", "sound muted".
   No explanations, no apologies.
6. Never run a dangerous action (restart, shutdown, sign out) without
   confirmation.
7. If the command makes no sense, answer with intent "unknown" and one short
   question about what was meant.
```

## Intent catalog

| intent | what the user says | what happens | fallback |
|---|---|---|---|
| `toggle_wifi` | turn on / off / toggle wifi | radio switched through `Windows.Devices.Radios`, state re-read | `ms-settings:network-wifi` |
| `toggle_bluetooth` | turn on / off bluetooth | same for the Bluetooth radio | `ms-settings:bluetooth` |
| `set_volume` | volume 40, set volume 50 | master volume set through `IAudioEndpointVolume` | — |
| `adjust_volume` | louder, quieter, turn it up / down | master volume stepped by 2% | — |
| `set_mute` | mute, sound off / on | master mute toggled | — |
| `open_settings_section` | open sound / wifi / bluetooth settings | the shell's own settings opens on that section | — |
| `open_windows_settings` | open windows settings | the Windows page, `ms-settings:` | — |
| `set_brightness` | brightness 60 | DDC/CI through the Rust DLL | `ms-settings:display` |
| `adjust_brightness` | brighter, darker | brightness stepped by 5% | `ms-settings:display` |
| `media_play_pause` | pause, play, resume | media key | — |
| `media_next` / `media_previous` | next / previous track | media key | — |
| `lock` | lock the screen | `LockWorkStation` | — |
| `sleep` | sleep, suspend | `SetSuspendState` | — |
| `sign_out` | sign out | `shutdown /l` | — |
| `restart` | restart the computer, reboot | `shutdown /r /t 0` after confirmation | — |
| `shutdown` | shut down the computer | `shutdown /s /t 0` after confirmation | — |

## How a command travels

```
phrase ──► parseCommand()  (command_router.dart)
             │  English words and Russian stems ("звука", "перезагрузи")
             ▼
        ParsedCommand{intent, params}
             │
             ▼
        CommandRouter.perform()
             │  the same SystemCommandSink the buttons use
             ▼
        real machine  ──►  short English reply
```

Two consequences worth keeping:

- **One code path.** The settings slider, the top-panel flyout and the phrase
  «volume 40» all end in `SoundControl`, so they can never disagree.
- **No window calls in the sink.** `SystemCommandSink` has no way to hide,
  close or minimize the desktop. A sound command cannot close the shell even
  if it wanted to.

## Adding an intent

1. Add the case to `AssistantIntent` in `assistant_prompt.dart` (with its `id`).
2. Add the `IntentSpec` row: examples (English, they must parse), what it does,
   the `ms-settings:` fallback.
3. Mention it in `assistantSystemPrompt` under the catalog.
4. Add the matcher in `command_router.dart` (`_matchXxx`) and call it from
   `parseCommand` — specific matchers first, generic last.
5. Add the sink method if it needs a new machine operation.
6. Add checks to `test/system_mock_check.dart`: a phrase per synonym, the
   reply text, and the negative case ("turn the sound off" is not a shutdown).

`test/system_mock_check.dart` also fails if a catalog example does not parse
to its own intent, or if an intent is missing from the prompt — so the three
cannot drift apart silently.