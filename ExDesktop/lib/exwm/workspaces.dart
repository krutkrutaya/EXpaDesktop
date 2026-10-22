// Workspaces *inside* the shell, not Windows virtual desktops.
//
// The nine dots used to fire Win+Ctrl shortcuts, which switched the real
// Windows desktops and left the shell behind. These workspaces live in the
// app: each one keeps its own wallpaper, switching is instant, and the dock
// shows exactly as many dots as there are workspaces with the current one
// lit.
//
// Plain Dart on purpose (no ChangeNotifier): the mock suite runs without
// Flutter, and the shell listens through a callback list the same way
// SoundControl does.

/// One in-app desktop: its own wallpaper, its own number in the dock.
class Workspace {
  Workspace(this.id, this.backgroundIndex);

  /// Stable id, so a future per-workspace state can key off it.
  final int id;

  /// Index into the shell's wallpaper list.
  int backgroundIndex;

  @override
  String toString() => 'Workspace($id, bg $backgroundIndex)';
}

class WorkspaceController {
  WorkspaceController({this.backgroundCount = 8})
      : assert(backgroundCount > 0);

  /// How many wallpapers the shell has.
  final int backgroundCount;

  /// The shell shows all of them as dots; beyond this the dock would be a
  /// dotted line, so the list simply refuses to grow.
  static const int maxWorkspaces = 9;

  final List<Workspace> _items = [Workspace(1, 0)];
  final List<void Function()> _listeners = [];

  int _active = 0;
  int _nextId = 2;

  int get count => _items.length;
  int get activeIndex => _active;
  Workspace get active => _items[_active];
  List<Workspace> get items => List.unmodifiable(_items);
  bool get canClose => _items.length > 1;
  bool get canCreate => _items.length < maxWorkspaces;

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Adds a desktop with a wallpaper the current one does not use, and
  /// switches to it. Returns false when the dock is already full.
  bool create() {
    if (!canCreate) return false;
    final used = _items.map((w) => w.backgroundIndex).toSet();
    var next = (active.backgroundIndex + 1) % backgroundCount;
    for (var step = 0; step < backgroundCount; step++) {
      final candidate = (next + step) % backgroundCount;
      if (!used.contains(candidate)) {
        next = candidate;
        break;
      }
    }
    _items.add(Workspace(_nextId++, next));
    _active = _items.length - 1;
    _notify();
    return true;
  }

  /// Removes the current desktop. The last one never goes away.
  bool closeActive() {
    if (!canClose) return false;
    _items.removeAt(_active);
    if (_active >= _items.length) _active = _items.length - 1;
    _notify();
    return true;
  }

  void select(int index) {
    if (index < 0 || index >= _items.length || index == _active) return;
    _active = index;
    _notify();
  }

  void next() => select((_active + 1) % _items.length);

  void previous() => select((_active - 1 + _items.length) % _items.length);

  /// Sets the wallpaper of the current desktop (the settings window).
  void setBackground(int index) {
    if (index < 0 || index >= backgroundCount) return;
    if (active.backgroundIndex == index) return;
    active.backgroundIndex = index;
    _notify();
  }

  /// Rotates the wallpaper of the current desktop, for the slideshow timer.
  void cycleBackground() {
    final index = (active.backgroundIndex + 1) % backgroundCount;
    active.backgroundIndex = index;
    _notify();
  }

  void _notify() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }
}