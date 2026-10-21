// The assistant's contract: the system prompt and the intent catalog it
// describes.
//
// The prompt is the thing a language model is given; the catalog is the
// machine-readable twin of the same list, so the buttons, the voice path and
// the prompt can never drift apart. A mock test checks that every intent in
// the catalog is named in the prompt and that every example parses to its own
// intent.

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

  /// The phrasings that mean this intent. English first, then the Russian
  /// ones the matcher also understands.
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
      'turn on wifi',
      'turn off wifi',
      'toggle wifi',
    ],
    action: 'switch the Wi-Fi radio through Windows.Devices.Radios, then '
        're-read the state and report it',
    fallbackUri: 'ms-settings:network-wifi',
  ),
  IntentSpec(
    intent: AssistantIntent.toggleBluetooth,
    examples: [
      'turn on bluetooth',
      'turn off bluetooth',
    ],
    action: 'switch the Bluetooth radio through Windows.Devices.Radios, then '
        're-read the state and report it',
    fallbackUri: 'ms-settings:bluetooth',
  ),
  IntentSpec(
    intent: AssistantIntent.setVolume,
    examples: [
      'volume 40',
      'set volume 50',
      'volume 30',
    ],
    action: 'set the master volume through IAudioEndpointVolume, never open '
        'a window',
  ),
  IntentSpec(
    intent: AssistantIntent.adjustVolume,
    examples: [
      'turn it up',
      'turn it down',
      'louder',
      'quieter',
    ],
    action: 'step the master volume by 2%, never open a window',
  ),
  IntentSpec(
    intent: AssistantIntent.setMute,
    examples: [
      'mute',
      'sound off',
      'sound on',
    ],
    action: 'mute or unmute the master volume, never open a window',
  ),
  IntentSpec(
    intent: AssistantIntent.openBuiltInSection,
    examples: [
      'open sound settings',
      'open wifi settings',
      'bluetooth settings',
    ],
    action: 'open that section of the shell\'s own settings, where the '
        'parameter is a real control',
  ),
  IntentSpec(
    intent: AssistantIntent.openWindowsSettings,
    examples: [
      'open windows settings',
    ],
    action: 'open a Windows Settings page through ms-settings:<uri>, only '
        'when the shell does not own the section',
  ),
  IntentSpec(
    intent: AssistantIntent.setBrightness,
    examples: [
      'brightness 60',
      'brightness 100',
    ],
    action: 'set the monitor brightness through DDC/CI (native DLL), no '
        'windows',
  ),
  IntentSpec(
    intent: AssistantIntent.adjustBrightness,
    examples: [
      'brighter',
      'darker',
    ],
    action: 'step the brightness through DDC/CI, no windows',
  ),
  IntentSpec(
    intent: AssistantIntent.mediaPlayPause,
    examples: ['pause', 'play', 'resume'],
    action: 'media key: play/pause',
  ),
  IntentSpec(
    intent: AssistantIntent.mediaNext,
    examples: ['next track', 'next song'],
    action: 'media key: next',
  ),
  IntentSpec(
    intent: AssistantIntent.mediaPrevious,
    examples: ['previous track', 'previous song'],
    action: 'media key: previous',
  ),
  IntentSpec(
    intent: AssistantIntent.lock,
    examples: ['lock the screen', 'lock computer'],
    action: 'LockWorkStation',
  ),
  IntentSpec(
    intent: AssistantIntent.sleep,
    examples: ['sleep', 'suspend the computer'],
    action: 'SetSuspendState',
  ),
  IntentSpec(
    intent: AssistantIntent.signOut,
    examples: ['sign out'],
    action: 'shutdown /l',
  ),
  IntentSpec(
    intent: AssistantIntent.restart,
    examples: ['restart the computer', 'reboot'],
    action: 'shutdown /r /t 0, after confirmation',
  ),
  IntentSpec(
    intent: AssistantIntent.shutdown,
    examples: ['shut down the computer', 'shutdown'],
    action: 'shutdown /s /t 0, after confirmation',
  ),
];

/// The system prompt the assistant runs on.
///
/// It is written for a model that returns one action per turn, and it keeps
/// the two rules that used to be broken: the shell owns the parameters it can
/// own, and a sound command never closes the desktop.
const String assistantSystemPrompt = r'''
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
''';