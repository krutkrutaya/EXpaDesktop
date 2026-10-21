// The task list inside the Tasks app.
//
// The old Tasks tile started Task Manager — a Windows window outside the
// shell, and a tool nobody opens on a desktop launcher. This is a small,
// real list instead: add, tick off, delete, clear the finished ones. It is
// plain Dart, so the behaviour is checked by the mock suite.

class TaskItem {
  TaskItem({
    required this.id,
    required this.text,
    this.done = false,
  });

  final int id;
  String text;
  bool done;
}

class TaskBoard {
  TaskBoard();

  final List<TaskItem> _items = [];
  int _nextId = 1;

  List<TaskItem> get items => List<TaskItem>.unmodifiable(_items);
  int get count => _items.length;
  int get openCount => _items.where((task) => !task.done).length;
  int get doneCount => _items.where((task) => task.done).length;
  bool get isEmpty => _items.isEmpty;
  bool get allDone => _items.isNotEmpty && openCount == 0;

  /// Adds a task. Returns null for blank input (and never adds a wall of
  /// text: the row would break).
  TaskItem? add(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final clipped =
        trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
    final task = TaskItem(id: _nextId++, text: clipped);
    _items.insert(0, task);
    return task;
  }

  bool toggle(int id) {
    for (final task in _items) {
      if (task.id == id) {
        task.done = !task.done;
        return true;
      }
    }
    return false;
  }

  bool rename(int id, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    for (final task in _items) {
      if (task.id == id) {
        task.text = trimmed.length > 200
            ? '${trimmed.substring(0, 200)}…'
            : trimmed;
        return true;
      }
    }
    return false;
  }

  bool remove(int id) {
    final before = _items.length;
    _items.removeWhere((task) => task.id == id);
    return _items.length != before;
  }

  int clearDone() {
    final before = _items.length;
    _items.removeWhere((task) => task.done);
    return before - _items.length;
  }

  void clear() {
    _items.clear();
  }
}