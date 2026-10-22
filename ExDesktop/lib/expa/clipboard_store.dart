// The clipboard history file: %APPDATA%\EXpaDesktop\clipboard.json.
// Flipboard history is small, so synchronous read/write is fine; the app
// calls it off the hot path.

import 'dart:convert';
import 'dart:io';

import 'clipboard_history.dart';

class ClipboardStore {
  ClipboardStore({String? root}) : _root = root;

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

  String get path =>
      '$rootDir${Platform.pathSeparator}clipboard.json';

  ClipboardHistory load() {
    try {
      final file = File(path);
      if (!file.existsSync()) return ClipboardHistory();
      return ClipboardHistory.fromJson(jsonDecode(file.readAsStringSync()));
    } catch (_) {
      return ClipboardHistory();
    }
  }

  Future<void> save(ClipboardHistory history) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(history.toJson()), flush: true);
      if (file.existsSync()) file.deleteSync();
      await temp.rename(file.path);
    } catch (_) {
      // A locked profile must not take the clipboard window down.
    }
  }
}