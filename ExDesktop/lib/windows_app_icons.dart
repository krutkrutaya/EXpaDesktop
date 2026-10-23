// Real Start-menu icons, extracted on demand.
//
// Get-StartApps only gives names and launch targets. For a shortcut the target
// is a .lnk, so PowerShell resolves it with WScript.Shell and pulls the icon
// with System.Drawing. Store apps expose a package logo instead. The result is
// a small PNG/JPEG cached under %APPDATA%\EXpaDesktop\app_icons.

import 'dart:io';
import 'dart:typed_data';

import 'windows_apps.dart';

abstract final class WindowsAppIcons {
  static final Map<String, Uint8List?> _memory = {};

  static bool get _testing =>
      Platform.environment['FLUTTER_TEST'] == 'true';

  static String get _root {
    final appData = Platform.environment['APPDATA'];
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final base = (appData == null || appData.isEmpty) ? home : appData;
    return '$base${Platform.pathSeparator}EXpaDesktop'
        '${Platform.pathSeparator}app_icons';
  }

  static String _key(WindowsAppEntry entry) {
    final target = entry.launchTarget ?? entry.name;
    final safe = entry.name
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${safe}_${_stableHash(target).toRadixString(16)}';
  }

  /// FNV-1a: stable across Dart runs, unlike String.hashCode on some VMs.
  static int _stableHash(String value) {
    var hash = 0x811C9DC5;
    for (final code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static String? _existing(String key) {
    for (final extension in const ['png', 'jpg', 'jpeg']) {
      final path = '$_root${Platform.pathSeparator}$key.$extension';
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Null means "use the app's fallback Material icon".
  static Future<Uint8List?> load(WindowsAppEntry entry) async {
    // Widget tests must not spawn PowerShell or touch the user's Start menu.
    if (_testing) return null;
    final key = _key(entry);
    if (_memory.containsKey(key)) return _memory[key];
    try {
      final cached = _existing(key);
      if (cached != null) {
        final bytes = File(cached).readAsBytesSync();
        _memory[key] = bytes;
        return bytes;
      }
      final target = entry.launchTarget;
      if (target == null || target.isEmpty) return null;
      final output = '$_root${Platform.pathSeparator}$key.png';
      Directory(_root).createSync(recursive: true);
      final script = _script(target, output);
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      );
      if (result.exitCode != 0 || !File(output).existsSync()) {
        _memory[key] = null;
        return null;
      }
      final bytes = File(output).readAsBytesSync();
      if (bytes.isEmpty) return null;
      _memory[key] = bytes;
      return bytes;
    } catch (_) {
      _memory[key] = null;
      return null;
    }
  }

  static String _quote(String value) => "'${value.replaceAll("'", "''")}'";

  static String _script(String target, String output) {
    final targetSql = _quote(target);
    final outputSql = _quote(output);
    if (target.contains('!')) {
      // AUMID: use the package's Logo. It may be a PNG/JPEG already.
      return '''
Add-Type -AssemblyName System.Drawing
\$aumid = $targetSql
\$family = \$aumid.Split('!')[0]
\$pkg = Get-AppxPackage | Where-Object { \$_.PackageFamilyName -eq \$family } | Select-Object -First 1
if (\$pkg) {
  \$logo = Join-Path \$pkg.InstallLocation \$pkg.Logo
  if (Test-Path \$logo) { Copy-Item -LiteralPath \$logo -Destination $outputSql -Force }
}
''';
    }
    return '''
Add-Type -AssemblyName System.Drawing
\$target = $targetSql
if (\$target.ToLower().EndsWith('.lnk')) {
  \$shell = New-Object -ComObject WScript.Shell
  \$target = \$shell.CreateShortcut(\$target).TargetPath
}
if (\$target -and (Test-Path -LiteralPath \$target)) {
  \$icon = [System.Drawing.Icon]::ExtractAssociatedIcon(\$target)
  if (\$icon) {
    \$icon.ToBitmap().Save($outputSql, [System.Drawing.Imaging.ImageFormat]::Png)
    \$icon.Dispose()
  }
}
''';
  }
}