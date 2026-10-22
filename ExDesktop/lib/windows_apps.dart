// The real Start-menu of Windows, for the shell's "programs" panel.
//
// `Get-StartApps` lists every entry the Start saw once: Store apps by AUMID
// and classic shortcuts by the path to their .lnk. Launching both works the
// same way through explorer.exe, but with a different prefix, so the parsing
// is centralised here. The list is scanned once at startup; the panel then
// only filters it by the search text.

import 'dart:convert';
import 'dart:io';

/// One installed Windows app: its Start-menu name and how to launch it.
class WindowsAppEntry {
  /// The name in Start, shown as the row's title.
  final String name;

  /// Store apps carry an AUMID (`Microsoft.Store...App`), classic apps carry
  /// the path to a .lnk. Null when the entry has no usable target.
  final String? launchTarget;

  const WindowsAppEntry({required this.name, this.launchTarget});

  /// The subtitle under the name, guessed from it: a category word, so the
  /// user sees what kind of thing the app is before clicking.
  String get description {
    final n = name.toLowerCase();
    if (_contains(n, const [
      'browser',
      'chrome',
      'firefox',
      'edge',
      'opera',
      'yandex',
      'vivaldi',
      'brave',
      'tor',
    ])) {
      return 'browser';
    }
    if (_contains(n, const [
      'steam',
      'epic',
      'gog ',
      'ea app',
      'eax',
      'ubisoft',
      'riot',
      'minecraft',
      'battle.net',
      'game',
      'origin',
      'playstation',
      'xbox',
    ])) {
      return 'game';
    }
    return 'app';
  }

  static bool _contains(String text, List<String> keys) {
    for (final key in keys) {
      if (text.contains(key)) return true;
    }
    return false;
  }

  @override
  String toString() => name;
}

/// Scanning and launching the machine's Start-menu.
abstract final class WindowsApps {
  static bool _busy = false;

  /// Whether [launchId] is something this shell can actually start. The
  /// Start-menu hands out three shapes of the AppID: Store apps carry a
  /// `!`-separated AUMID, shortcuts end with `.lnk`, and classic programs
  /// come as a `{guid}\path\program.exe` shell folder path. All three open
  /// through `shell:appsFolder`, so everything else (empty stubs like the
  /// bare system rows) is skipped.
  static bool _isLaunchable(String launchId) =>
      launchId.contains('!') ||
      launchId.toLowerCase().endsWith('.lnk') ||
      launchId.contains('{') ||
      launchId.toLowerCase().contains('.exe');

  /// Reads the Start menu. Returns the apps sorted by name so the search
  /// results look stable, and skips unlaunchable stubs entirely.
  static Future<List<WindowsAppEntry>> scan() async {
    if (_busy) return const [];
    _busy = true;
    try {
      final result = await Process.run(
        'powershell.exe',
        const [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          // `\$` keeps the Dart interpolation away from PowerShell's $_.
          'Get-StartApps | ForEach-Object { "{0}|{1}" -f \$_.AppID, \$_.Name }',
        ],
        stdoutEncoding: utf8,
      );
      if (result.exitCode != 0) {
        throw 'Get-StartApps failed with code ${result.exitCode}';
      }
      final found = <WindowsAppEntry>[];
      for (final line in result.stdout.toString().split('\n')) {
        final raw = line.trim();
        if (raw.isEmpty) continue;
        final cut = raw.indexOf('|');
        if (cut <= 0) continue;
        final launchId = raw.substring(0, cut).trim();
        var name = raw.substring(cut + 1).trim();
        if (!_isLaunchable(launchId)) continue;
        if (name.isEmpty) name = launchId;
        found.add(WindowsAppEntry(name: name, launchTarget: launchId));
      }
      found.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return found;
    } catch (_) {
      // No PowerShell or a failure: the panel stays empty instead of
      // crashing the shell.
      return const [];
    } finally {
      _busy = false;
    }
  }

  /// Launches [app]. Every AppID shape opens through the shell namespace:
  /// `explorer.exe shell:appsFolder\<AppID>` resolves Store AUMIDs, the
  /// `{guid}\...\program.exe` folder paths and raw .lnk paths alike — it is
  /// exactly how the real Start menu starts things. No console window
  /// flashes, and `detached` keeps the launched app alive if the shell quits.
  static Future<void> launch(WindowsAppEntry app) async {
    final target = app.launchTarget;
    if (target == null) return;
    await Process.start(
      'explorer.exe',
      ['shell:appsFolder\\$target'],
      mode: ProcessStartMode.detached,
    );
  }
}
