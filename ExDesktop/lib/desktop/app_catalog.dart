// The applications the shell can open inside itself.
//
// This file stays pure Dart on purpose: the window manager and the catalog are
// checked by `dart run test/desktop_check.dart` without a Flutter engine, so
// the sizes and ids live here and the icons live in `app_icons.dart`.

/// One built-in application.
enum ShellApp {
  calculator('calculator', 'Calculator', 360, 500),
  notepad('notepad', 'Notepad', 560, 440),
  files('files', 'Files', 680, 500),
  paint('paint', 'Paint', 780, 560),
  snip('snip', 'Snip', 640, 500),
  tasks('tasks', 'Tasks', 440, 540),
  browser('browser', 'Browser', 960, 640),
  musics('musics', 'Musics', 820, 540),
  settings('settings', 'Settings', 920, 610),
  terminal('terminal', 'Terminal', 700, 440);

  const ShellApp(this.id, this.title, this.width, this.height);

  /// Stable id used by the window manager, the tests and the launcher.
  final String id;

  /// The title the window chrome shows.
  final String title;

  /// The size the window opens at, before it is clamped to the desktop.
  final double width;
  final double height;

  /// The app that owns [id], or null when the id is unknown.
  static ShellApp? byId(String id) {
    for (final app in values) {
      if (app.id == id) return app;
    }
    return null;
  }
}