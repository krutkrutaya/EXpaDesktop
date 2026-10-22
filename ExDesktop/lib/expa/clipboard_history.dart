// Clipboard history: the data the Clipboard widget keeps while it scans the
// Windows clipboard. Pure Dart; the file store is separate.

class ClipboardEntry {
  final String text;
  DateTime time;
  bool pinned;

  ClipboardEntry({
    required this.text,
    required this.time,
    this.pinned = false,
  });

  Map<String, Object?> toJson() => {
        'text': text,
        'time': time.millisecondsSinceEpoch,
        'pinned': pinned,
      };

  static ClipboardEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = '${json['text'] ?? ''}';
    if (text.isEmpty) return null;
    final millis = (json['time'] as num?)?.toInt() ?? 0;
    return ClipboardEntry(
      text: text,
      time: DateTime.fromMillisecondsSinceEpoch(millis),
      pinned: json['pinned'] == true,
    );
  }
}

class ClipboardHistory {
  ClipboardHistory({List<ClipboardEntry>? entries})
      : _entries = entries ?? <ClipboardEntry>[];

  static const int maxEntries = 40;

  final List<ClipboardEntry> _entries;

  List<ClipboardEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;

  /// Adds a new clipboard value. Repeated values move to the top instead of
  /// filling the history with copies; the pinned flag survives the move.
  ClipboardEntry add(String text, {DateTime? at}) {
    final value = text.replaceAll('\u0000', '');
    final existing = _entries.where((entry) => entry.text == value).toList();
    if (existing.isNotEmpty) {
      final entry = existing.first;
      _entries.remove(entry);
      entry.time = at ?? DateTime.now();
      _entries.insert(0, entry);
      return entry;
    }
    final entry = ClipboardEntry(text: value, time: at ?? DateTime.now());
    _entries.insert(0, entry);
    // Pinned entries stay; trim the oldest unpinned first.
    while (_entries.length > maxEntries) {
      final index = _entries.lastIndexWhere((item) => !item.pinned);
      if (index < 0) break;
      _entries.removeAt(index);
    }
    return entry;
  }

  void togglePin(ClipboardEntry entry) {
    entry.pinned = !entry.pinned;
  }

  void remove(ClipboardEntry entry) {
    _entries.remove(entry);
  }

  void clear() => _entries.clear();

  List<Object?> toJson() =>
      [for (final entry in _entries) entry.toJson()];

  static ClipboardHistory fromJson(Object? json) {
    final history = ClipboardHistory();
    if (json is List) {
      for (final item in json) {
        final entry = ClipboardEntry.fromJson(item);
        if (entry != null) history._entries.add(entry);
      }
    }
    if (history._entries.length > maxEntries) {
      history._entries.removeRange(maxEntries, history._entries.length);
    }
    return history;
  }
}