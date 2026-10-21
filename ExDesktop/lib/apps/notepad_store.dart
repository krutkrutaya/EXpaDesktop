// Notes that survive a restart.
//
// The Notepad window saves to the user's roaming profile, not next to the exe:
// an installed app usually lives in a folder it cannot write to. The path is
// injectable, so the mock suite writes into a temp folder instead of touching
// the real profile.

import 'dart:io';

class NotepadStore {
  NotepadStore({String? path}) : _path = path;

  final String? _path;

  /// Where the note lives. `%APPDATA%\EXpaDesktop\notes.txt` by default.
  String get path {
    final explicit = _path;
    if (explicit != null) return explicit;
    final appData = Platform.environment['APPDATA'];
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final base = (appData == null || appData.isEmpty) ? home : appData;
    return '$base${Platform.pathSeparator}EXpaDesktop'
        '${Platform.pathSeparator}notes.txt';
  }

  /// Reads the note; a missing file is an empty note, not an error.
  Future<String> load() async {
    try {
      final file = File(path);
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  /// Writes the note, creating the folder on first save.
  Future<bool> save(String text) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True when the file already exists.
  Future<bool> exists() => File(path).exists();
}