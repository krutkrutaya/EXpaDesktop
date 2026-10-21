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
verified by mock tests: **32/32 PASS**, including 200 randomized fuzz
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

## 🧩 Structure

```
ExDesktop/
├── lib/
│   ├── main.dart                # shell: wallpapers, clock, panels, dock
│   ├── player.dart              # player: transport, slider, track list
│   ├── settings-app.dart        # spring-driven settings window
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
    └── liquid_glass_mock_check.dart  # 🧪 32 physics mock tests
```

## 🚀 Building

```bash
# 1. Flutter (https://docs.flutter.dev/get-started/install/windows)
cd ExDesktop
flutter pub get
flutter run -d windows
```

The Rust DLL is already built and lives at `lib/rust/brightness.dll`.
To rebuild it yourself:

```bash
cd lib/rust
cargo build --release
cp target/release/brightness.dll .
```

## 🧪 Physics Tests

```bash
cd ExDesktop
dart run test/liquid_glass_mock_check.dart
```

```
[spring]        ✓ settles, survives frame stalls
[menu spring]   ✓ bounces past 1.0, exponential close
[open morph]    ✓ lands exactly on the panel rect, < 3s
[close morph]   ✓ fades back into the button, < 5s
[reversal]      ✓ mid-flight reverse with velocity carry-over
[fuzz]          ✓ 200 random button/panel pairs, 0 NaNs
passed: 32   failed: 0 — ALL GREEN
```

## 📄 License

[MIT](LICENSE) © 2026 Suptemen

<div align="center">

**EXpaDesktop** — a desktop that flows 🌊

</div>
