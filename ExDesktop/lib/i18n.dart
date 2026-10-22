// The shell's language: English by default, Russian optional.
//
// Every localized string goes through [Loc.t]: it takes both variants and
// returns the one for the current language. Widgets therefor pass a pair to
// t('Title', 'Заголовок') instead of holding two strings apiece.
//
// The choice is persisted to %APPDATA%\EXpaDesktop\language.cfg and read back
// on the next start; [notifier] lets any widget rebuild when it flips.

import 'dart:io';

import 'package:flutter/foundation.dart';

/// The languages the shell speaks.
enum AppLanguage {
  english,
  russian;

  /// How the language is named in dropdowns, always in its own tongue.
  String get display => this == AppLanguage.english ? 'English' : 'Русский';
}

class Loc {
  Loc._();

  static const String _fileName = 'language.cfg';

  /// The active language. English until the user (or the saved file) says ru.
  static AppLanguage language = AppLanguage.english;

  /// Everything that must rebuild when the language flips listens here.
  static final ValueNotifier<AppLanguage> notifier =
      ValueNotifier<AppLanguage>(AppLanguage.english);

  /// Picks the string for the current language.
  static String t(String english, String russian) =>
      language == AppLanguage.russian ? russian : english;

  /// %APPDATA%\EXpaDesktop\language.cfg (falls back to the profile dir).
  static File _file() {
    final appData = Platform.environment['APPDATA'];
    final base = (appData != null && appData.isNotEmpty)
        ? appData
        : (Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            Directory.current.path);
    return File(
        '$base${Platform.pathSeparator}EXpaDesktop'
        '${Platform.pathSeparator}$_fileName');
  }

  /// Reads the saved choice, if any; silently ignores a missing file.
  static Future<void> load() async {
    try {
      final value = (await _file().readAsString()).trim().toLowerCase();
      if (value == 'ru' || value == 'russian') {
        language = AppLanguage.russian;
        notifier.value = language;
      }
    } catch (_) {}
  }

  /// Applies a new language and saves it for the next start.
  static Future<void> set(AppLanguage lang) async {
    language = lang;
    notifier.value = lang;
    try {
      final file = _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(lang == AppLanguage.russian ? 'ru' : 'en');
    } catch (_) {}
  }
}
