// Real system actions behind every button of the shell: opening Windows
// Settings pages, launching programs, and the power menu operations.
//
// Settings pages and ms: URIs go through explorer.exe (a GUI process), so no
// console window flashes. Programs that are GUI apps run directly; console
// tools stay behind rundll32 or plain FFI.

import 'dart:ffi';
import 'dart:io';

typedef _LockWorkStationNative = Int32 Function();
typedef _LockWorkStationDart = int Function();

_LockWorkStationDart? _lockWorkStation;

/// Locks the workstation right away, straight through user32.dll.
void lockWorkstation() {
  try {
    _lockWorkStation ??= DynamicLibrary.open('user32.dll')
        .lookupFunction<_LockWorkStationNative, _LockWorkStationDart>(
            'LockWorkStation');
    _lockWorkStation!();
  } catch (_) {}
}

/// Opens a Windows Settings page, e.g. "ms-settings:sound". Unknown URIs open
/// the Settings home — a safe fallback for every link.
Future<void> openSettingsPage(String uri) async {
  try {
    await Process.start('explorer.exe', [uri], mode: ProcessStartMode.detached);
  } catch (_) {}
}

/// Opens any shell location explorer understands: "shell:...", "ms-settings:...",
/// "ms-screenclip:" and the like.
Future<void> openShellLocation(String location) =>
    openSettingsPage(location);

/// Launches a GUI executable by name, passing no arguments.
Future<void> launchExe(String exe) async {
  try {
    await Process.start(exe, [], mode: ProcessStartMode.detached);
  } catch (_) {}
}

/// Runs an executable with arguments — the power commands and rundll32.
Future<void> launchExeWithArgs(String exe, List<String> args) async {
  try {
    await Process.start(exe, args, mode: ProcessStartMode.detached);
  } catch (_) {}
}

/// Opens a UWP app via its AppsFolder alias, e.g. the calculator.
Future<void> launchAppFolder(String alias) => openShellLocation(
      'shell:AppsFolder\\$alias',
    );

/// Sleep: suspend the machine (hibernates instead if hibernation is on).
Future<void> sleepMachine() => launchExeWithArgs(
      'rundll32.exe',
      ['powrprof.dll,SetSuspendState 0,1,0'],
    );

/// Ends the interactive session of the current user.
Future<void> signOut() => launchExeWithArgs('shutdown.exe', ['/l']);

/// Restart with no timeout — the confirm dialog has already asked the user.
Future<void> restartMachine() => launchExeWithArgs('shutdown.exe', ['/r', '/t', '0']);

/// Full shutdown with no timeout.
Future<void> shutdownMachine() =>
    launchExeWithArgs('shutdown.exe', ['/s', '/t', '0']);
