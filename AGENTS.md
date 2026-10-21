# AGENTS.md — EXpaDesktop

## What this is
`ExDesktop/` is a Windows Flutter desktop app: a liquid-glass panel overlay (dock-ish widgets: settings, music player) driven by hand-written dart physics. `lib/liquid_glass/` is a Dart port of the GNOME "liquid-glass" extension (TS reference lives in `liquid-glass-main/`).

## Critical context
- **`liquid-glass-main/` is gitignored and is REFERENCE ONLY.** It's a separate TypeScript project with its own CLAUDE.md (Japanese, GNOME extension rules). Do not treat its code/tests/rules as part of this repo; read it only to compare morph/phreysics behavior with our Dart port.
- The Dart port deliberately diverges from the reference: the random lateral push was removed, spring swing decays fully to 0, corner rounding is time-driven. These were user-approved tuning decisions — don't "restore" reference behavior without being asked.
- Slider droplet stretch params in `lib/liquid_glass/wave_slider.dart` (build/decay/painter amplitudes) are tuned and user-approved. Don't tweak amplitudes casually.

## Git workflow
- Two remotes, both must receive every push:
  ```powershell
  git push origin main; git push suptewme main
  ```
- Commit messages in English.
- PowerShell wraps `git push` progress into a fake `NativeCommandError` with exit code 1 even when the push succeeds. Judge success by the `main -> main` line in output, not the exit code.
- `Set-Location` explicitly in shell commands; the `workdir` param is unreliable in this environment.
- `git mv` fails on untracked files — use `Rename-Item` + `git add -A`.

## Running tests (Dart-only, no Flutter SDK needed)
The machine has no Flutter SDK. The only runnable verification is the pure-Dart physics mock:
```powershell
Set-Location "C:\Users\varenya\Documents\EXpaDesktop-main\EXpaDesktop-main\ExDesktop"
& "$env:TEMP\dartsdk\dart-sdk\bin\dart.exe" --enable-asserts "test\liquid_glass_mock_check.dart"
```
Expect `passed: 32, failed: 0 — ALL GREEN`.
- If the Dart SDK is missing, download `https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-windows-x64-release.zip` with `curl.exe -sL --ssl-no-revoke` and unzip to `%TEMP%\dartsdk`.
- The mock requires `ExDesktop/.dart_tool/package_config.json` (gitignored, handcrafted). Recreate it with an absolute `file:///` rootUri pointing at the ExDesktop dir and an explicit `"packageUri": "lib/"` — otherwise package imports in the mock won't resolve.
- **Run this test before every push when `liquid_glass/` or `core`-adjacent physics changed.**

## Asset traps
- `assets/icons/settings-app-ico.png` filename is hard-coded in `main.dart` + `pubspec.yaml` — never rename the file itself.
- `assets/music/` is bundled as a whole folder and scanned at runtime; filenames act as track IDs and feed auto-generated titles. Renaming a music file loses its association — prefer adding new files over renaming.
- `lib/settings_app.dart` is the snake_case name — don't "fix" it back to the file's old dash-named version.

## Code conventions
- UI strings are user-facing Russian; code identifiers, comments, commit messages are English.
- Package name in `pubspec.yaml` is `exp_desktop`.
- Pure-Dart physics code must stay Flutter-free (that's what makes the mock test possible). Don't import Flutter in `lib/liquid_glass/` base files (`morph_controller.dart`, `spring.dart`, `menu_morph.dart` core logic).
