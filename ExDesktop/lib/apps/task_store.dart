// The task list on disk: %APPDATA%\EXpaDesktop\tasks.json. Lists are tiny, so
// the app reads and writes synchronously instead of juggling async state.

import 'dart:convert';
import 'dart:io';

import 'task_board.dart';

class TaskStore {
  TaskStore({String? root}) : _root = root;

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

  String get path => '$rootDir${Platform.pathSeparator}tasks.json';

  static bool get _testing =>
      Platform.environment['FLUTTER_TEST'] == 'true';

  TaskBoard load() {
    if (_testing) return TaskBoard();
    try {
      final file = File(path);
      if (!file.existsSync()) return TaskBoard();
      return TaskBoard.fromJson(jsonDecode(file.readAsStringSync()));
    } catch (_) {
      return TaskBoard();
    }
  }

  void save(TaskBoard board) {
    if (_testing) return;
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final temp = File('${file.path}.tmp');
      temp.writeAsStringSync(jsonEncode(board.toJson()), flush: true);
      if (file.existsSync()) file.deleteSync();
      temp.renameSync(file.path);
    } catch (_) {
      // A read-only profile must not break the task list.
    }
  }
}