// The desktop environment's notification center: a small, pure model. The
// shell posts events here; the Notifications app and the waybar badge read it.
// No Flutter imports, so the ordering/unread logic is mock-tested.

class ShellNotification {
  final int id;
  final String title;
  final String body;
  final String category;
  final DateTime time;
  bool read;

  ShellNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.time,
    this.read = false,
  });

  @override
  String toString() =>
      'ShellNotification($id, $category, $title, ${read ? 'read' : 'new'})';
}

class NotificationCenter {
  NotificationCenter();

  static const int maxEntries = 100;

  final List<ShellNotification> _items = [];
  final List<void Function()> _listeners = [];
  int _nextId = 1;

  List<ShellNotification> get items => List.unmodifiable(_items);
  int get unread => _items.where((item) => !item.read).length;
  bool get isEmpty => _items.isEmpty;

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  ShellNotification post(
    String title,
    String body, {
    String category = 'system',
    DateTime? at,
  }) {
    final item = ShellNotification(
      id: _nextId++,
      title: title,
      body: body,
      category: category,
      time: at ?? DateTime.now(),
    );
    _items.insert(0, item);
    if (_items.length > maxEntries) _items.removeRange(maxEntries, _items.length);
    _notify();
    return item;
  }

  void markRead(ShellNotification item) {
    if (item.read) return;
    item.read = true;
    _notify();
  }

  void markAllRead() {
    var changed = false;
    for (final item in _items) {
      if (!item.read) {
        item.read = true;
        changed = true;
      }
    }
    if (changed) _notify();
  }

  void remove(int id) {
    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    if (_items.length != before) _notify();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    _notify();
  }

  void _notify() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }
}