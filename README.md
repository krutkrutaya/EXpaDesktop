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
| Notepad | autosaves to `%APPDATA%\EXpaDesktop\notes.txt` |
| Files | a directory browser with text and image preview inside the window |
| Paint | a stroke canvas with colours, eraser, undo and PNG export to Pictures |
| Snip | captures the shell itself, previews and saves the shot |
| Tasks | a real to-do list, not Task Manager |
| Browser | WebView2 composited into the window: address bar, back/forward, start page |
| Musics | the player as a window: every track, transport, seek bar, beat cover |
| Terminal | runs `cmd` lines in the window and prints the output |
| Settings | the shell's own settings, now a window like every other app |

- **Entrance**: a 300 ms spring — the window scales up, fades in and slides
  out of the right dock; closing pulls it back the same way. Minimizing leaves
  it on the dock's running-window strip.
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

The parameters the shell can drive itself live **in the shell**, not behind a
link to Windows:

| Parameter | Read from | Switched by |
|-----------|-----------|-------------|
| Volume / mute | `IAudioEndpointVolume` (COM) | the same endpoint, no windows opened |
| Wi-Fi | `Windows.Devices.Radios` + `Get-NetAdapter` | `Radio.SetStateAsync` — the API behind the taskbar's quick settings, no UAC |
| Bluetooth | `Windows.Devices.Radios` | `Radio.SetStateAsync` |
| Brightness | the Rust DDC/CI DLL | the same DLL |

`ms-settings:` is the fallback: the rows the shell does not own ("Default
apps", "Windows Update", …) still open the matching Windows page, but every
row the shell owns shows its real state and a switch that works.

Opening a radio goes through a hidden PowerShell bridge (`CreateProcessW`
with `CREATE_NO_WINDOW`, so no console flashes) and a worker isolate, so the
UI never waits on a process. Windows' own radio API answers something real —
the shell shows what the machine reports, including "device not found" and
"blocked by the system".

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
│   │   ├── app_catalog.dart     #   the ten apps, their ids and sizes
│   │   ├── window_manager.dart  #   z-order, focus, minimize, drag, resize
│   │   ├── shell_window.dart    #   the chrome + the entrance spring
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
│   │       ├── settings_view.dart
│   │       └── terminal_app.dart
│   ├── apps/                    # pure models (no widgets), mock-tested
│   │   ├── calculator_engine.dart
│   │   ├── task_board.dart
│   │   ├── notepad_store.dart
│   │   ├── files_model.dart
│   │   ├── paint_board.dart
│   │   ├── terminal_session.dart
│   │   └── browser_model.dart
│   ├── ui/                      # glass controls + the waybar's mini player
│   ├── sound_control.dart       # one owner of the master volume and mute
│   ├── radio_control.dart       # Wi-Fi / Bluetooth state and switching
│   ├── radio_script.dart        # the PowerShell bridge to Windows' radio API
│   ├── hidden_process.dart      # console tools with no console window
│   ├── native_heap.dart         # malloc/free for the FFI modules
│   ├── assistant_prompt.dart    # the assistant's system prompt + catalog
│   ├── command_router.dart      # phrases → intents → machine actions
│   ├── shell_layout.dart        # where every panel sits, as testable numbers
│   ├── shell_panels.dart        # which surface may share the screen with which
│   ├── workspaces.dart          # in-app desktops: wallpaper per desktop
│   ├── id3_art.dart             # title / artist / cover from the mp3 tags
│   ├── track_art.dart           # one artwork rule: cover, asset, placeholder
│   ├── liquid_glass/            # 🔬 physics & widgets
│   └── rust/                    # DDC/CI + gamma ramps (Rust)
├── assets/                      # fons, music, icons
└── test/
    ├── mock_harness.dart             # 🧪 shared check/report harness
    ├── mock_all.dart                 # 🧪 everything, one total
    ├── desktop_check.dart            # 🧪 117 window manager + catalog checks
    ├── apps_check.dart               # 🧪 150 app-model checks
    ├── playback_check.dart           # 🧪 54 spin/beat/playlist checks
    ├── shell_check.dart              # 🧪 335 layout/policy/ID3/workspace checks
    ├── system_mock_check.dart        # 🧪 476 system + assistant checks
    ├── liquid_glass_mock_check.dart  # 🧪 53 physics checks
    └── widget/
        ├── shell_test.dart           # 🧪 23 shell widget tests
        ├── settings_view_test.dart   # 🧪 13 settings widget tests
        ├── player_controller_test.dart # 🧪 10 player tests
        ├── apps_extra_test.dart      # 🧪 4 browser/notepad tests
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
`WebView2Loader.dll` and `data\flutter_assets\`.
The Windows runner lives in `ExDesktop/windows/` (generated with
`flutter create --platforms=windows .` and committed, so a fresh clone builds).

The Browser window needs the **Microsoft Edge WebView2 runtime**, which ships
with Windows 10/11 and with Edge; if it is missing the window shows its start
page and says so instead of breaking.

`windows/CMakeLists.txt` defines
`_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` for the plugin
subdirectories: C++/WinRT still includes `<experimental/coroutine>`, and MSVC
14.51 turned that into a hard error. It is Microsoft's documented escape hatch.

**Nothing binary is committed.** The DDC/CI brightness controller is a Rust
library you build once (needs a Rust toolchain):

```bash
cd ExDesktop/lib/rust
cargo build --release
cp target/release/brightness.dll .   # local only, gitignored
```

Without it the app still runs — the brightness sliders simply do nothing:
`lib/main.dart` tries several paths and fails soft. `flutter build windows`
copies the DLL next to the exe when it is there, and skips it otherwise.

## 🧪 Tests

Widget tests run under `flutter test`; the window manager, app models, player
math, system layer and physics suites are plain Dart scripts (no Flutter
needed). `mock_all.dart` runs all of them and prints a single total —
**1185 checks**, plus **54 widget tests**.

```bash
cd ExDesktop
flutter test                                 # 54 widget tests
flutter analyze                              # No issues found
dart run test/mock_all.dart                  # 1185 mock checks
dart run test/desktop_check.dart             # windows: 117 checks
dart run test/apps_check.dart                # app models: 150 checks
dart run test/playback_check.dart            # spin/beat/playlist: 54 checks
dart run test/liquid_glass_mock_check.dart   # physics only: 53 checks
dart run test/system_mock_check.dart         # system + assistant: 476 checks
dart run test/shell_check.dart               # layout, panels, ID3, workspaces: 335 checks
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
