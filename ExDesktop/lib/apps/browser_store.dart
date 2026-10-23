// Tabs and bookmarks on disk: %APPDATA%\EXpaDesktop\browser.json.
//
// The session is small, so it is read synchronously on the first frame and
// written after tab/bookmark/navigation changes. Tests keep it in memory.

import 'dart:convert';
import 'dart:io';

import 'browser_model.dart';

class BrowserSessionStore {
  BrowserSessionStore({String? root}) : _root = root;

  final String? _root;

  String get rootDir {
    final explicit = _root;
    if (explicit != null) return explicit;
    final appData = Platform.environment['APPDATA'];
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final base = (appData == null || appData.isEmpty) ? home : appData;
    return '$base${Platform.pathSeparator}EXpaDesktop';
  }

  String get path => '$rootDir${Platform.pathSeparator}browser.json';

  static bool get _testing =>
      Platform.environment['FLUTTER_TEST'] == 'true';

  BrowserTabs load({String home = 'https://duckduckgo.com'}) {
    if (_testing) return BrowserTabs(home: home);
    try {
      final file = File(path);
      if (!file.existsSync()) return BrowserTabs(home: home);
      return BrowserTabs.fromJson(
        jsonDecode(file.readAsStringSync()),
        home: home,
      );
    } catch (_) {
      return BrowserTabs(home: home);
    }
  }

  void save(BrowserTabs tabs) {
    if (_testing) return;
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final temp = File('${file.path}.tmp');
      temp.writeAsStringSync(jsonEncode(tabs.toJson()), flush: true);
      if (file.existsSync()) file.deleteSync();
      temp.renameSync(file.path);
    } catch (_) {
      // A read-only profile leaves the session in memory only.
    }
  }
}