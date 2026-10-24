// The real Start-menu of Windows, for the shell's "programs" panel.
//
// `Get-StartApps` lists every entry the Start saw once: Store apps by AUMID
// and classic shortcuts by the path to their .lnk. Launching both works the
// same way through explorer.exe, but with a different prefix, so the parsing
// is centralised here. The list is scanned once at startup; the panel then
// only filters it by the search text.

import 'dart:io';

import 'hidden_process.dart';

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
  /// Whether a Start-menu entry belongs in the Programs panel. Raw `.exe`
/// AppIDs are the junk the user complained about: they are not real Start
/// shortcuts, they can number in the hundreds and they make the panel lag.
/// Real entries are Store AUMIDs (`...!App`), Start-menu shortcuts (`.lnk`)
/// and shell-folder system entries (`{guid}\...`).
static bool isListable(String launchId) {
  final id = launchId.toLowerCase();
  if (id.endsWith('.exe')) return false;
  return id.contains('!') ||
      id.endsWith('.lnk') ||
      id.endsWith('.url') ||
      id.endsWith('.appref-ms') ||
      id.contains('{');
}

  /// Reads the Start menu. Returns the apps sorted by name so the search
  /// results look stable, and skips unlaunchable stubs entirely.
  static Future<List<WindowsAppEntry>> scan() async {
    if (_busy) return const [];
    _busy = true;
    try {
      // Get-StartApps is the authoritative Start-menu view. The extra
      // recursive pass over the two Programs folders catches installed apps
      // that the shell has not enumerated yet (Bloxstrap and friends) —
      // still only Start-menu shortcuts, never a walk over C:\.
      final result = await runPowerShell('''
\$rows = New-Object System.Collections.Generic.List[string]
Get-StartApps | ForEach-Object {
  \$rows.Add(("{0}|{1}" -f \$_.AppID, \$_.Name))
}
\$roots = @(
  (Join-Path \$env:APPDATA 'Microsoft\\Windows\\Start Menu\\Programs'),
  (Join-Path \$env:ProgramData 'Microsoft\\Windows\\Start Menu\\Programs')
)
foreach (\$root in \$roots) {
  if (-not (Test-Path -LiteralPath \$root)) { continue }
  Get-ChildItem -LiteralPath \$root -Recurse -File `
    -Include *.lnk,*.url,*.appref-ms -ErrorAction SilentlyContinue |
    ForEach-Object {
      \$rows.Add(("{0}|{1}" -f \$_.FullName, \$_.BaseName))
    }
}
\$rows | Sort-Object -Unique
''');
      if (result.exitCode != 0) {
        throw 'Start-menu scan failed with code ${result.exitCode}';
      }
      final found = <WindowsAppEntry>[];
      final seen = <String>{};
      for (final line in result.stdout.split('\n')) {
        final raw = line.trim();
        if (raw.isEmpty) continue;
        final cut = raw.indexOf('|');
        if (cut <= 0) continue;
        final launchId = raw.substring(0, cut).trim();
        var name = raw.substring(cut + 1).trim();
        if (!isListable(launchId)) continue;
        if (name.isEmpty) name = launchId;
        final key = '$name\u0000$launchId';
        if (!seen.add(key)) continue;
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
