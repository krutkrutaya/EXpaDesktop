# ExDesktop (Flutter app)

The Windows desktop shell itself: wallpapers, clock, liquid-glass panels, an
in-app window manager (every app opens inside the shell), the player with the
Musics window, the shell's own settings with live Wi-Fi/Bluetooth/sound
controls, and the Ctrl+Alt+Space command line.

Everything about the project — what it is, how the liquid-glass physics work,
how the system layer talks to Windows, and what the tests cover — lives in the
[repository README](../README.md). This file is the short build sheet.

## Build

```powershell
flutter pub get
flutter analyze            # should print: No issues found!
flutter test               # 53 widget tests
dart run test/mock_all.dart   # 1185 mock checks (plain Dart, no Flutter needed)

flutter run -d windows     # debug, hot reload
flutter build windows --release
# -> build\windows\x64\runner\Release\exp_desktop.exe
```

Requirements for the Windows build:

- Flutter 3.x on PATH
- Visual Studio 2022/2026 with **Desktop development with C++**
  (MSVC, C++ CMake tools, Windows 10/11 SDK)
- **Developer Mode** on (Flutter symlinks plugin packages on Windows):
  `start ms-settings:developers`

> **`nuget.exe` on PATH.** The `audioplayers_windows` plugin pulls
> `nuget.exe` and the WIL package at configure time. CMake's downloader can
> fail on some networks (`schannel: server closed abruptly`); dropping
> `nuget.exe` somewhere on PATH (`C:\src\nuget`) makes the plugin skip its
> download and use yours.
>
> ```powershell
> New-Item -ItemType Directory -Force C:\src\nuget | Out-Null
> curl.exe -L -o C:\src\nuget\nuget.exe https://dist.nuget.org/win-x86-commandline/v6.5.0/nuget.exe
> $env:Path = "C:\src\nuget;$env:Path"
> ```

## Layout

| Path | What |
|---|---|
| `lib/main.dart` | shell: wallpapers, clock, panels, dock, command line |
| `lib/settings_app.dart` | settings window with the live parameter panes |
| `lib/sound_control.dart` | the single owner of volume/mute |
| `lib/radio_control.dart` | Wi-Fi/Bluetooth state and switching |
| `lib/radio_script.dart` | PowerShell bridge to `Windows.Devices.Radios` |
| `lib/hidden_process.dart` | console tools with no console window |
| `lib/assistant_prompt.dart` | the assistant's system prompt + catalog |
| `lib/command_router.dart` | Russian phrases → intents → machine actions |
| `lib/liquid_glass/` | the panel morph/physics |
| `lib/rust/` | brightness DLL (DDC/CI + gamma) |
| `windows/` | the Windows runner (CMake + C++ host) |
| `test/` | widget tests and the pure-Dart mock suites |