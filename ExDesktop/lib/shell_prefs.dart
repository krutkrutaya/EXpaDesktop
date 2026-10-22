// The shell's small preference store: one key=value file under
// %APPDATA%\EXpaDesktop\prefs.cfg, read once, written on each change.
//
// Things that live here: the wallpaper slideshow switch and its period, the
// desktop clock's time zone + region, the display pane's chosen resolution /
// orientation / rate, and the vibe-bar's waybar button list. Language keeps
// its own cfg through Loc; this store is everything else.
//
// Deliberately synchronous and tiny: the values are a handful of short
// lines, and every caller changes one value while the user watches.

import 'dart:io';
import 'dart:convert';

class ShellPrefs {
  ShellPrefs._();

  static Map<String, String>? _cache;
  static bool _loaded = false;

  /// Overridable for tests that do not want to touch the real machine.
  static String? _directory;

  /// The effective prefs file path (the Configs app shows it).
  static String get path => _path;

  static String get _path {
    final dir =
        _directory ?? Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    return '$dir\\EXpaDesktop\\prefs.cfg';
  }

  static void _load() {
    if (_loaded) return;
    _loaded = true;
    // The cache must exist even when there is no file yet: get() reads it
    // synchronously and a missing prefs.cfg is the normal first launch.
    _cache ??= {};
    try {
      final file = File(_path);
      if (!file.existsSync()) return;
      for (final raw in const LineSplitter().convert(file.readAsStringSync())) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        _cache![line.substring(0, eq)] = line.substring(eq + 1);
      }
    } catch (_) {
      // A broken file must never stop the shell; values fall to defaults.
      _cache = {};
    }
  }

  static String get(String key, [String fallback = '']) {
    _load();
    return _cache![key] ?? fallback;
  }

  static int getInt(String key, int fallback) =>
      int.tryParse(get(key)) ?? fallback;

  static bool getBool(String key, bool fallback) {
    final v = get(key);
    if (v.isEmpty) return fallback;
    return v == '1' || v.toLowerCase() == 'true';
  }

  static void set(String key, String value) {
    _load();
    _cache![key] = value;
    try {
      final file = File(_path);
      file.parent.createSync(recursive: true);
      final buffer = StringBuffer(
        '// EXpaDesktop shell preferences (key=value).\n',
      );
      final keys = _cache!.keys.toList()..sort();
      for (final k in keys) {
        buffer.writeln('$k=${_cache![k]}');
      }
      file.writeAsStringSync(buffer.toString(), flush: true);
    } catch (_) {
      // No permission / odd APPDATA: keep the in-memory value alive anyway.
    }
  }

  /// Clears the override (tests use it) and the in-memory cache, so the next
/// read comes from the new directory instead of the previous test's file.
  static void setDirectory(String? dir) {
    _directory = dir;
    _loaded = false;
    _cache = null;
  }
}
