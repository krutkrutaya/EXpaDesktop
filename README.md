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
clock, wallpaper slideshow, floating glass panels and a built-in music
player — everything opens and closes **as a drop of liquid glass**
that grows out of a button and dissolves back into it.

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

- **Wavy slider** in the Material Design style — the active track lives as a sine wave, surging while you drag
- The thumb grows on hover and **stretches like a droplet** against the drag direction
- 🟠 Loop the current track, repeat the playlist, shuffle order (the `•••` menu)
- Buttons spring like Google Gemini ones: pressing stretches them into an oval, releasing snaps them back elastically
- Track list — dark glass cards with smooth edge fade while scrolling

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
- Top panel with "glass" (BackdropFilter): apps, mini-player, bluetooth / volume / wi-fi
- Right dock with an indicator and a power menu (sleep / restart / settings)
- Settings window: 7 sections, draggable by its title bar, minimizes into the dock, opens on a bouncy spring

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

`Ctrl+Alt+Space` opens a one-line command field. Type «включи вайфай»,
«громкость 40», «заглуши звук», «открой настройки блютуза» — the phrase goes
through the same sink as the buttons and the reply appears under the field.
The phrase matcher and the assistant's system prompt live in
[`PROMPTS.md`](PROMPTS.md).

## 🧩 Structure

```
ExDesktop/
├── lib/
│   ├── main.dart                # shell: wallpapers, clock, panels, dock
│   ├── player.dart              # player: transport, slider, track list
│   ├── settings_app.dart        # spring-driven settings + live parameter panes
│   ├── sound_control.dart       # one owner of the master volume and mute
│   ├── radio_control.dart       # Wi-Fi / Bluetooth state and switching
│   ├── radio_script.dart        # the PowerShell bridge to Windows' radio API
│   ├── hidden_process.dart      # console tools with no console window
│   ├── native_heap.dart         # malloc/free for the FFI modules
│   ├── assistant_prompt.dart    # the assistant's system prompt + catalog
│   ├── command_router.dart      # phrases → intents → machine actions
│   ├── liquid_glass/            # 🔬 physics & widgets
│   │   ├── menu_morph.dart      #   capsule→drop→panel morph
│   │   ├── menu_spring.dart     #   bouncy scale (settings)
│   │   ├── spring.dart          #   damped spring
│   │   ├── morph_controller.dart#   tickers, open/close/reverse
│   │   ├── morph_glass.dart     #   rendering: lens, glass, blur
│   │   ├── wave_slider.dart     #   wavy Material slider
│   │   └── stretch_icon_button.dart  # Gemini-style buttons
│   └── rust/
│       ├── src/lib.rs           # DDC/CI + gamma ramps (Rust)
│       └── brightness.dll       # prebuilt native library
├── assets/
│   ├── fons/                    # 8 wallpapers
│   ├── music/                   # tracks and cover art
│   └── icons/
└── test/
    ├── mock_harness.dart             # 🧪 shared check/report harness
    ├── mock_all.dart                 # 🧪 everything, one total
    ├── liquid_glass_mock_check.dart  # 🧪 53 physics mock tests
    ├── system_mock_check.dart        # 🧪 412 system + assistant mock tests
    └── widget/
        └── settings_app_test.dart    # 🧪 10 widget tests
```

`windows/` holds the generated runner (CMake + C++ window host).

## 🚀 Building

Requirements: **Flutter 3.x**, **Visual Studio 2022/2026 with the "Desktop
development with C++" workload** (MSVC + CMake + Windows 10/11 SDK), and
**Developer Mode** turned on (Flutter symlinks plugins on Windows).

```bash
cd ExDesktop
flutter pub get
flutter run -d windows          # or: flutter build windows --release
```

The Windows runner lives in `ExDesktop/windows/` (generated with
`flutter create --platforms=windows .` and committed, so a fresh clone
builds). The Rust DLL is already built and lives at `lib/rust/brightness.dll`.
To rebuild it yourself:

```bash
cd lib/rust
cargo build --release
cp target/release/brightness.dll .
```

## 🧪 Tests

Widget tests run under `flutter test`; the system/physics suites are plain
Dart scripts (no Flutter needed). `mock_all.dart` runs both mock suites and
prints a single total — **465 checks**, plus **10 widget tests**.

```bash
cd ExDesktop
flutter test                                 # 10 widget tests
flutter analyze                              # No issues found
dart run test/mock_all.dart                  # 465 mock checks
dart run test/liquid_glass_mock_check.dart   # physics only, 53 checks
dart run test/system_mock_check.dart         # system + assistant, 412 checks
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
passed: 465   failed: 0 — ALL GREEN
```

## 📄 License

[MIT](LICENSE) © 2026 Suptemen

<div align="center">

**EXpaDesktop** — a desktop that flows 🌊

</div>
