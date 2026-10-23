<div align="center">

# 🪟 EXpaDesktop

**A custom desktop launcher for Windows — glassy, alive, with liquid animations**

Flutter · Rust · Glassmorphism · Liquid Glass

![Platform](https://img.shields.io/badge/platform-Windows-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Rust](https://img.shields.io/badge/Rust-2021-DEA584?logo=rust&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)
![Made with love](https://img.shields.io/badge/made%20with-%E2%9D%A4-red)

</div>

---

## ✨ What is this

EXpaDesktop replaces the standard desktop with its own shell: giant
clock, wallpaper slideshow, floating glass panels and **an in-app window
manager** — every application opens *inside* EXpaDesktop, slides out of the
right dock and lands as a glass window you can drag, resize, maximize,
minimize and close. Nothing launches a second Windows window.

![EXpaDesktop](docs/screenshot.jpg)

## 🪟 In-app windows

| | |
|---|---|
| Calculator | a real four-function calculator with keyboard input |
| Notepad | autosaves to `%APPDATA%\EXpaDesktop\notes.txt`; opens text files from Files and saves edits back to them |
| Files | a directory browser with text and image preview; double-click follows the desktop's file associations |
| Paint | a stroke canvas with colours, eraser, undo and PNG export to Pictures |
| Snip | captures the shell itself, previews and saves the shot |
| Tasks | a real to-do list, persisted to `%APPDATA%\EXpaDesktop\tasks.json` |
| Browser | WebView2 composited into the window: tabs, bookmarks, address bar, back/forward, start page |
| Musics | the player as a window: every track, transport, seek bar, beat cover |
| Terminal | runs `cmd` lines in the window and prints the output |
| Configs | Presets/Edit tabs: Lua looks, .zip pack import through in-app Files, a Lua editor, and live controls |
| Settings | every pane works in-app: pointer/keyboard, drives, associations, notifications, multitasking, lock screen |
| Clipboard | watches the Windows clipboard, keeps a searchable history, pins and copies entries back |
| Notifications | the in-shell notification center, with unread state and a waybar badge |
| Calendar | a real Monday-first month grid with previous/next/today |
| Emoji | a searchable picker that copies through the system clipboard |
| Updater | compares the build with GitHub, shows release/commit changelogs and rebuilds/restarts |

- **Entrance**: a 300 ms spring — the window scales up, fades in and slides
  out of the right dock; closing pulls it back the same way. Minimizing leaves
  it on the dock's running-window strip.
- **EXWM** (`lib/exwm/`) owns the windows: one manager per workspace, focus
  stack, snapping to halves/quarters/maximize, drag-edge snapping and
  `Ctrl+Alt+arrows`/`Ctrl+Alt+1..4`. **EXPA** (`lib/expa/`) owns the desktop
  environment: `DeConfig`, the theme, notifications, clipboard history, file
  associations, versioning and the updater bridge. Both have their own mock
  suites (`test/exwm_check.dart`, `test/expa_check.dart`).
- **Per-desktop windows**: every in-app desktop keeps its own set of windows,
  so switching desktops really switches the work, not just the wallpaper.
- **Drag** by the title bar, **resize** from the corner, **double-click** the
  title to maximize/restore. Dragging repaints only that window.
- The dock shows one icon per open window: click to focus, click the focused
  one to minimize.

## 🌊 Liquid Glass Animations

Panel animations are a Dart port of
[liquid-dom](https://github.com/AndrewPrifer/liquid-dom) / liquid-glass,
with all the physics:

| Stage | What happens |
|-------|--------------|
| 🟢 Opening | The button's capsule draws itself into a round drop → the drop is **thrown** toward where the panel will be, pushed by a spring and a random nudge (no two openings are alike) → it swells to the panel's size as its corners square off |
| 🔵 Content | The content is seen as if **deep inside the glass** and rises to the surface while the drop grows |
| 🔴 Closing | The panel shrinks back into a drop → the drop rises into the button, stretching into its capsule on the way → and fades there |
| ⚡ Reversal | Close right in the middle of an opening — the velocity carries over and the drop turns around without a blink |

The physics is damped springs (semi-implicit Euler, sub-stepped),
verified by mock tests: **53/53 PASS**, including 200 randomized fuzz
runs and 300 ms stress frames.

## 🎵 Music Player

- A track fades in over ~250 ms instead of slamming the room at full level; **pause keeps the position**, play resumes exactly there
- **The spinning artwork settles upright**: pausing no longer freezes the cover at a random angle — a damped spring turns it to the nearest full turn and stops there, smoothly
- Covers come from the mp3 itself: the player reads the ID3v2 APIC frame, so a dropped file shows its own artwork with no config
- **Wavy slider** in the Material Design style — the active track lives as a sine wave, surging while you drag
- The thumb grows on hover and **stretches like a droplet** against the drag direction
- 🟠 Loop the current track, repeat the playlist, shuffle order
- **Musics** (the Tracks pill) opens a full player window: the list of tracks and artists, previous / play / next, a timecode seek bar, and a cover that **breathes with the beat** instead of spinning
- **Every row in Musics shows its cover**, not just the big artwork on the left
- **Add track** opens the in-app Files window as a picker; it accepts mp3, wav, flac, ogg, m4a, aac, wma, opus and aiff, copies the file into `%APPDATA%\EXpaDesktop\Music` and refreshes the library. Files on disk that match are picked up on the next start too
- Covers for the list come from the mp3 tags (or the shell's glass placeholder), and the **Rust scanner** extracts them for the whole folder in one native pass

## ⚡ Smooth by construction

The animations are not just pretty, they are budgeted:

- **Idle sliders do not tick.** The wave slider used to run a ticker forever;
  now it sleeps when it is not hovered, dragged or chasing a value, so a
  settings window with four sliders costs zero frames at rest.
- **Every animation that changes one thing rebuilds one thing.** The 12 s
  wallpaper slideshow repaints the wallpaper, the 45 s radio refresh repaints
  the waybar, music playback repaints the player, and dragging a window
  repaints that window — never the other apps.
- **Window movement is composited, not repainted**: app content sits in a
  `RepaintBoundary`, and maximize/restore glides between rectangles over
  230 ms. A maximized window stops **5 px** from the dock, the waybar and the
  free screen edges — "just a bigger window", not edge-to-edge fullscreen.
- **Opening and closing have a readable rhythm.** A fresh window pops in over
  260 ms; closing holds it fully visible for the first fifth and fades/lifts
  it over 320 ms; minimizing and restoring play the macOS genie out of the
  dock. The title-bar buttons sit outside the drag/double-tap detector, so
  their taps are not held for the double-click timeout.
- **The mini player's artwork answers the pointer**: its corner radius eases
  from a circle (19) to the glass rounding (10) on hover and tighter (7) while
  pressed, then back.
- Everything is animated: settings panes crossfade, the appearance sheets
  slide under a Back button, the Vibe bar's buttons save as they change, the
  Wi-Fi cards expand in place, the file picker's banner slides down, dock
  icons scale in and out, the Musics cover crossfades between tracks, and the
  snip preview fades in.

## ☀️ Display Control

Through a native Rust DLL (`FFI`) — real hardware, not overlays:

| Function | How |
|----------|-----|
| Brightness | DDC/CI `SetMonitorBrightness` + a software gamma-ramp boost above the maximum |
| Contrast | DDC/CI `SetMonitorContrast` |
| Warmth | Gamma ramp `SetDeviceGammaRamp` (cuts the blue-red channels) |

All three sliders use the same wavy WaveSlider as the player.

## 🖥️ The Shell

- A 145 px clock, wallpapers rotating every 12 seconds with a crossfade
- **Waybar** (the top panel): brightness on the left, the mini player in the
  middle (with the spinning cover and play/pause), Bluetooth / sound / Wi-Fi on
  the right. The old four-squares decoration next to the player is gone.
- Right dock: one icon per running window, **a vertical column of desktop dots**
  (as many as there are desktops, the current one lit), and the apps button
- **Scroll the mouse wheel over the dots** to flip through desktops; the dots
  adapt their size so even nine desktops fit the pill
- Power menu behind the apps button (lock / sign out / restart / sleep /
  shutdown / settings)
- The workspace panel keeps itself open while you add, close or switch
  desktops — the buttons have real disabled states at the nine/one limit, so a
  click never silently disappears

## 🎛️ Settings that actually switch things

The shell's own settings window is a real app inside the shell; every control
changes something here — no row sends you to Windows Settings.

| Surface | What it does |
|---------|--------------|
| Sound | master slider with the small mute icon on the right, a short divider, then **every app that is making noise** with its own slider and mute |
| Wallpaper & theme | the Appearance tile: every wallpaper for the active desktop, the **timer switch** and a seconds field, autosaved |
| Vibe bar | the Appearance tile: add/remove waybar panels; every panel opens its in-shell app |
| Display & monitor | the **real** resolutions, orientations and refresh rates Windows reports, then brightness/contrast/warmth |
| Mouse & keyboard | pointer speed, button swap, wheel lines and keyboard repeat delay/rate through `SystemParametersInfo` |
| Accessibility | reduce motion and text scale for the whole shell |
| Drives & cameras | logical disks (with free space and Open-in-Files) and PnP cameras |
| Default apps | the desktop's own file associations, used by Files on double-click |
| Notifications | the notification center history plus the toast switch |
| Multitasking | snapping, the tile gap and window animations — the same EXWM knobs Configs edits |
| Date & time | the Windows time-zone table, an "automatic" switch and a region dropdown; the desktop clock follows the zone |
| Wi-Fi / Bluetooth | their own flyouts; Wi-Fi has search, signal, lock, password, auto-join and disconnect |
| Lock screen | an optional PIN, auto-lock and an in-desktop lock overlay |
| Updates | opens the in-shell Updater (GitHub release or main commit, changelog, rebuild/restart) |

The native backend is **`sysctl.dll`** (Rust): WASAPI master volume and
per-app sessions, the WLAN API, GDI monitor modes, the DST-aware time-zone
table, the Windows clipboard and the `SystemParametersInfo` input settings.
Radios go through `Windows.Devices.Radios`.

## 🎨 Configs: Lua presets

Configs has two tabs. **Presets** applies a Lua look to the window manager and
desktop; **Edit** is a Lua editor with Apply / Save / Reset and the live
sliders underneath. The built-in looks are Lua sources parsed by the same
safe subset as imported packs. **Add preset** opens the in-app Files window,
you pick a `.zip`, and every `.lua` file inside becomes a preset. Nothing is
extracted to disk and nothing is executed: the parser understands comments,
`local`, tables, strings, numbers, booleans and `return`, and rejects anything
else with a line/column error. Imported/saved presets live in
`%APPDATA%\EXpaDesktop\presets.json`.

### Command line

`Ctrl+Alt+Space` opens a one-line command field. Type `turn on wifi`,
`volume 40`, `sound off`, `open bluetooth settings` — the phrase goes through
the same sink as the buttons and the reply appears under the field. Russian
phrasings («включи вайфай», «громкость 40») still work: the matcher is
bilingual on purpose. The phrase matcher and the assistant's system prompt
live in [`PROMPTS.md`](PROMPTS.md).

`Ctrl+Tab` cycles the open windows; `Esc` closes the command field.

## 🧩 Structure

```
ExDesktop/
├── lib/
│   ├── main.dart                # shell: wallpaper, waybar, panels, dock
│   ├── player.dart              # player flyout (Tracks → Musics)
│   ├── playback/                # 🎧 the player, as data
│   │   ├── player_controller.dart#  audio, playlist, progress, the spin
│   │   ├── spin.dart            #   artwork angle: spins, springs upright
│   │   ├── beat.dart            #   the Musics cover's heartbeat
│   │   ├── playlist.dart        #   next/previous/shuffle + time formatting
│   │   └── track.dart           #   one track
│   ├── desktop/                 # 🪟 in-app windows
│   │   ├── app_catalog.dart     #   the eleven apps, their ids and sizes
│   │   ├── window_manager.dart  #   z-order, focus, minimize, drag, resize
│   │   ├── shell_window.dart    #   chrome, entrance, genie, 5 px maximize
│   │   ├── desktop_surface.dart #   the Stack of windows
│   │   ├── app_icons.dart
│   │   └── apps/                #   the windows themselves
│   │       ├── calculator_app.dart
│   │       ├── notepad_app.dart
│   │       ├── files_app.dart
│   │       ├── paint_app.dart
│   │       ├── snip_app.dart
│   │       ├── tasks_app.dart
│   │       ├── browser_app.dart #   WebView2 in a Flutter texture
│   │       ├── musics_app.dart
│   │       ├── configs_app.dart #   intentionally empty shelf
│   │       ├── settings_view.dart #  sound, display, appearance, time, updates
│   │       └── terminal_app.dart
│   ├── apps/                    # pure models (no widgets), mock-tested
│   │   ├── calculator_engine.dart
│   │   ├── task_board.dart
│   │   ├── notepad_store.dart
│   │   ├── files_model.dart
│   │   ├── paint_board.dart
│   │   ├── terminal_session.dart
│   │   ├── browser_model.dart
│   │   ├── audio_pick.dart      #  Musics → Files picker request
│   │   ├── music_library.dart   #  the user's Music folder: import + scan
│   │   ├── music_scanner.dart   #  the Rust scanner's FFI + JSON
│   │   └── wav_info.dart        #  WAV duration from the header
│   ├── ui/                      # glass controls + the waybar's mini player
│   ├── native/
│   │   └── sysctl.dart          # FFI + JSON parsers for sysctl.dll
│   ├── audio_sessions.dart      # per-app sessions (Rust WASAPI)
│   ├── sound_control.dart       # one owner of the master volume and mute
│   ├── volume_control.dart      # the master endpoint through sysctl.dll
│   ├── wifi_control.dart        # WLAN API wrapper: scan / join / leave
│   ├── radio_control.dart       # Wi-Fi / Bluetooth state and switching
│   ├── radio_script.dart        # the PowerShell bridge to Windows' radio API
│   ├── hidden_process.dart      # console tools with no console window
│   ├── native_heap.dart         # malloc/free for the old FFI modules
│   ├── i18n.dart                # English/Russian shell strings
│   ├── shell_prefs.dart         # prefs.cfg: slideshow, waybar, zone, display
│   ├── assistant_prompt.dart    # the assistant's system prompt + catalog
│   ├── command_router.dart      # phrases → intents → machine actions
│   ├── shell_layout.dart        # where every panel sits, as testable numbers
│   ├── shell_panels.dart        # which surface may share the screen with which
│   ├── workspaces.dart          # in-app desktops: wallpaper per desktop
│   ├── id3_art.dart             # title / artist / cover from the mp3 tags
│   ├── track_art.dart           # one artwork rule: cover, asset, placeholder
│   ├── liquid_glass/            # 🔬 physics & widgets
│   └── rust/
│       ├── src/lib.rs           #   DDC/CI + gamma ramps
│       ├── music_scan/          #   fast folder scan + ID3/covers
│       └── sysctl/              #   audio, Wi-Fi, display modes, time zones
├── assets/                      # fons, music, icons
└── test/
    ├── mock_harness.dart             # 🧪 shared check/report harness
    ├── mock_all.dart                 # 🧪 everything, one total
    ├── desktop_check.dart            # 🧪 118 window manager + catalog checks
    ├── apps_check.dart               # 🧪 150 app-model checks
    ├── playback_check.dart           # 🧪 54 spin/beat/playlist checks
    ├── library_check.dart            # 🧪 69 import/WAV/Rust-JSON checks
    ├── native_check.dart             # 🧪 39 audio/Wi-Fi/display/zone parsers
    ├── shell_check.dart              # 🧪 414 layout/waybar/policy/ID3 checks
    ├── system_mock_check.dart        # 🧪 476 system + assistant checks
    ├── liquid_glass_mock_check.dart  # 🧪 53 physics checks
    └── widget/
        ├── shell_test.dart           # 🧪 29 shell widget tests
        ├── settings_view_test.dart   # 🧪 16 settings panes
        ├── player_controller_test.dart # 🧪 10 player tests
        ├── apps_extra_test.dart      # 🧪 4 browser/notepad tests
        ├── music_add_test.dart       # 🧪 4 picker + Musics tests
        ├── animations_test.dart      # 🧪 3 idle-ticker regression tests
        ├── mini_player_test.dart     # 🧪 1 hover/press rounding test\n        ├── configs_test.dart        # 🧪 1 empty-Configs test
        └── track_art_test.dart       # 🧪 4 artwork tests
```

`windows/` holds the generated runner (CMake + C++ window host).

## 🚀 Getting it running

**The repo ships sources, not binaries** — `build/` and every artefact stay on
your machine. Build it once, here is the whole path from a clean Windows.

### 1. Flutter

```powershell
# any folder without spaces or Cyrillic; C:\src is the usual choice
New-Item -ItemType Directory -Force C:\src | Out-Null
curl.exe -L -o C:\src\flutter.zip https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.7-stable.zip
tar.exe -xf C:\src\flutter.zip -C C:\src
Remove-Item C:\src\flutter.zip
[Environment]::SetEnvironmentVariable("Path", "C:\src\flutter\bin;" + [Environment]::GetEnvironmentVariable("Path", "User"), "User")
```

Open a new terminal and check `flutter --version`.

### 2. The C++ toolchain (needed to build a Windows app)

Visual Studio Installer → **Modify** → tick **Desktop development with C++**
(MSVC, C++ CMake tools, Windows 10/11 SDK). `flutter doctor` turns green when
it sees them.

### 3. Developer Mode

Flutter symlinks plugin packages on Windows, which needs symlink support:

```powershell
start ms-settings:developers
```

→ turn **Developer Mode** on.

### 4. `nuget.exe` on PATH

`audioplayers_windows` asks CMake to download `nuget.exe` while configuring,
and that downloader is flaky (`schannel: server closed abruptly`). A local copy
makes the plugin skip the download:

```powershell
New-Item -ItemType Directory -Force C:\src\nuget | Out-Null
curl.exe -L -o C:\src\nuget\nuget.exe https://dist.nuget.org/win-x86-commandline/v6.5.0/nuget.exe
$env:Path = "C:\src\nuget;$env:Path"
```

### 5. Run it

```powershell
cd ExDesktop
flutter pub get
flutter run -d windows            # debug, with hot reload
flutter build windows --release   # -> build\windows\x64\runner\Release\exp_desktop.exe
```

The release folder is self-contained: `exp_desktop.exe`, `flutter_windows.dll`,
`audioplayers_windows_plugin.dll`, `flutter_inappwebview_windows_plugin.dll`,
`WebView2Loader.dll`, `brightness.dll`, `music_scan.dll`, `sysctl.dll` (when
built), `updater.exe` (when built) and `data\flutter_assets\`. The Windows
runner lives in `ExDesktop/windows/` (generated with `flutter create
--platforms=windows .` and committed, so a fresh clone builds).

The Browser window needs the **Microsoft Edge WebView2 runtime**, which ships
with Windows 10/11 and with Edge; if it is missing the window shows its start
page and says so instead of breaking.

`windows/CMakeLists.txt` defines
`_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` for the plugin
subdirectories: C++/WinRT still includes `<experimental/coroutine>`, and MSVC
14.51 turned that into a hard error. It is Microsoft's documented escape hatch.

**Nothing binary is committed.** There are four optional Rust binaries/libraries;
all are built once with a Rust toolchain:

```bash
cd ExDesktop/lib/rust
cargo build --release
cp target/release/brightness.dll .        # local only, gitignored

cd music_scan
cargo build --release
cp target/release/music_scan.dll .

cd ../sysctl
cargo build --release
cp target/release/sysctl.dll .
cargo test                                # 9 pure unit tests

cd ../updater
cargo build --release
cp target/release/updater.exe .
cargo test                                # 5 version/plan unit tests
```

- **updater.exe** — the release-the-app helper: `git fetch`, check out the
  chosen release tag or pull `main`, refuse a dirty tree, run
  `flutter build windows --release`, relaunch the app, and relaunch the old
  build if the update fails. `--plan` prints the exact commands. The in-shell
  Updater passes the repo path, mode and target; the GitHub check/changelog is
  Dart (`lib/expa/update_service.dart`).

- **brightness.dll** — DDC/CI + gamma ramps. Without it the brightness sliders
  do nothing: `lib/main.dart` tries several paths and fails soft.
- **music_scan.dll** — walks `%APPDATA%\EXpaDesktop\Music`, reads ID3
  title/artist/TLEN/APIC and WAV durations in one native pass and caches the
  covers. Without it the shell falls back to the pure-Dart scanner (correct,
  just slower on a big library).
- **sysctl.dll** — master volume + per-app WASAPI sessions, Wi-Fi scan/join
  through the WLAN API, the monitor's real modes, the DST-aware time-zone
  table, the Windows clipboard (read/write/sequence) and the pointer/keyboard
  `SystemParametersInfo` settings. Every call fails soft; without it the
  settings panes stay readable but cannot touch the machine, and
  `native_check.dart` still validates the JSON.

`flutter build windows` copies each DLL next to the exe when it is present and
prints a status line when it is not.

## 🏷️ Versioning & updates

The build version lives in a file named **`version_x.y.z.txt`**
(`x` = release, `y` = large change, `z` = patch/minor). The file name is the
source of truth; the body carries the commit the build came from:

```
version=1.2.1
commit=cd86fd7
```

`lib/expa/version.dart` parses it, `UpdateService` compares it with
`GET /repos/krutkrutaya/EXpaDesktop/releases/latest` and `/commits/main`, and
the Updater window shows both changelogs. “Update to release” passes the real
tag (e.g. `v1.1.0`); “Update to main” pulls the latest commit. The Rust
`updater.exe` double-checks the version file, refuses a downgrade or a dirty
tree, builds and relaunches. To bump the version, rename the file and update
`versionAsset`/`appVersion` together.

## 🧪 Tests

Widget tests run under `flutter test`; the window manager, app models, player
math, library, native parsers and system suites are plain Dart scripts (no
Flutter needed). `mock_all.dart` runs all of them and prints a single total —
**1627 checks** with the optional Rust DLLs built, plus **91 widget tests**,
**9 sysctl Rust tests** and **6 updater Rust tests**.

```bash
cd ExDesktop
flutter test                                 # 91 widget tests
flutter analyze                              # No issues found
dart run test/mock_all.dart                  # 1627 mock checks
dart run test/exwm_check.dart                # window manager + snap: 51 checks
dart run test/expa_check.dart                # config, notifications, version: 108 checks
dart run test/lua_preset_check.dart          # Lua subset, built-ins, zip: 60 checks
dart run test/desktop_check.dart             # windows: 118 checks
dart run test/apps_check.dart                # app models: 180 checks
dart run test/playback_check.dart            # spin/beat/playlist: 54 checks
dart run test/library_check.dart             # import, WAV, Rust JSON: 69 checks
dart run test/native_check.dart              # audio/Wi-Fi/display/zone parsers: 39 checks
dart run test/liquid_glass_mock_check.dart   # physics only: 53 checks
dart run test/system_mock_check.dart         # system + assistant: 476 checks
dart run test/shell_check.dart               # layout, waybar, panels, ID3: 414 checks
```

```
[liquid glass]    ✓ springs, morphs, reversal, 200 fuzz runs, COM volume probe
[hidden process]  ✓ stdout/stderr/exit codes, 20k-line output, timeout kill,
                    UTF-16LE -EncodedCommand, Cyrillic round-trip
[native heap]     ✓ write/read, 2000 alloc/free cycles, free(nullptr)
[radio script]    ✓ no leftover placeholders, UTF-8 output, SetStateAsync
[radio parsing]   ✓ every state, disabled adapter, adapter-only, CRLF,
                    malformed lines, unknown radio kinds
[radio labels]    ✓ Russian state strings for both radios
[command parser]  ✓ 100+ phrasings: radios, volume (digits, %, Russian
                    numerals), mute, settings sections, media, brightness,
                    power — plus the traps that used to misfire
[router]          ✓ every intent reaches the sink and answers in one line
[prompt]          ✓ every catalog intent is in the prompt, every catalog
                    example parses to its own intent
[sound]           ✓ read-only endpoint checks, listeners fire and detach
[window guards]   ✓ the sound path contains no window-visibility calls
passed: 682   failed: 0 — ALL GREEN
```

## 📄 License

[MIT](LICENSE) © 2026 Suptemen

<div align="center">

**EXpaDesktop** — a desktop that flows 🌊

</div>
