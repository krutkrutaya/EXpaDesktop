// The Browser app's model: what the address bar means, and where Back goes.
//
// The window itself embeds WebView2. The part worth testing is the part that
// decides what to load: `edge` is a search, `example.com` is a site,
// `localhost:8080` is a site, `hello world` is a search, and Back must not
// walk past the first page.

import 'dart:io';

/// What the address bar should do with [input].
class BrowserTarget {
  const BrowserTarget(this.uri, {required this.isSearch});

  final String uri;
  final bool isSearch;

  @override
  String toString() => uri;
}

abstract final class BrowserInput {
  /// The search engine used for anything that is not a URL.
  static const String searchBase = 'https://duckduckgo.com/?q=';

  /// Turns whatever the user typed into a URL to load.
  static BrowserTarget resolve(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      return const BrowserTarget('about:blank', isSearch: false);
    }

    // An explicit scheme is taken as-is.
    final scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').firstMatch(text);
    if (scheme != null) {
      return BrowserTarget(text, isSearch: false);
    }
    if (text.startsWith('about:') || text.startsWith('data:')) {
      return BrowserTarget(text, isSearch: false);
    }

    final looksLikeHost = RegExp(
      r'^(localhost|(\d{1,3}\.){3}\d{1,3})(:\d+)?(/.*)?$',
    ).hasMatch(text);
    final looksLikeDomain = RegExp(
      r'^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+(:\d+)?(/.*)?$',
    ).hasMatch(text);

    if (looksLikeHost || looksLikeDomain) {
      return BrowserTarget('https://$text', isSearch: false);
    }
    return BrowserTarget(
      '$searchBase${Uri.encodeQueryComponent(text)}',
      isSearch: true,
    );
  }

  /// What the address bar shows for a loaded URL (drops `https://` and a
  /// trailing slash, the way every browser does).
  static String display(String url) {
    var text = url;
    if (text.startsWith('https://')) text = text.substring(8);
    if (text.startsWith('http://')) text = text.substring(7);
    if (text.endsWith('/') && text.length > 1) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }
}

/// Back/forward across loaded pages.
class BrowserHistory {
  final List<String> _entries = [];
  int _index = -1;

  List<String> get entries => List<String>.unmodifiable(_entries);
  int get index => _index;
  String? get current =>
      _index >= 0 && _index < _entries.length ? _entries[_index] : null;
  bool get canBack => _index > 0;
  bool get canForward => _index >= 0 && _index < _entries.length - 1;

  /// Records a new page, dropping the forward branch.
  void push(String url) {
    if (url.isEmpty || url == 'about:blank') return;
    if (current == url) return;
    if (_index < _entries.length - 1) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    _entries.add(url);
    _index = _entries.length - 1;
  }

  String? back() {
    if (!canBack) return null;
    _index--;
    return current;
  }

  String? forward() {
    if (!canForward) return null;
    _index++;
    return current;
  }

  void clear() {
    _entries.clear();
    _index = -1;
  }
}

/// Where downloads and screenshots go: the user's Pictures folder when it
/// exists, the temp folder otherwise.
String picturesDirectory() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  final pictures = Directory('$home${Platform.pathSeparator}Pictures');
  if (pictures.existsSync()) return pictures.path;
  return Directory.systemTemp.path;
}
/// One browser tab. The window keeps one WebView and points it at the
/// selected tab's URL; the model remembers the pages and titles.
class BrowserTab {
  final int id;
  String url;
  String title;

  BrowserTab({required this.id, required this.url, this.title = ''});

  String get host {
    try {
      final uri = Uri.parse(url);
      return uri.host.isEmpty ? url : uri.host;
    } catch (_) {
      return url;
    }
  }

  Map<String, Object?> toJson() => {'id': id, 'url': url, 'title': title};

  static BrowserTab? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = '${json['url'] ?? ''}';
    if (url.isEmpty) return null;
    return BrowserTab(
      id: (json['id'] as num?)?.toInt() ?? 0,
      url: url,
      title: '${json['title'] ?? ''}',
    );
  }
}

class BrowserTabs {
  BrowserTabs({String home = 'https://duckduckgo.com'}) {
    add(url: home, select: true);
  }

  final List<BrowserTab> _tabs = [];
  final Set<String> bookmarks = {};
  int _active = 0;
  int _nextId = 1;

  List<BrowserTab> get tabs => List.unmodifiable(_tabs);
  BrowserTab get active => _tabs[_active.clamp(0, _tabs.length - 1)];
  int get count => _tabs.length;
  bool get canClose => _tabs.length > 1;

  BrowserTab add({String? url, String? title, bool select = true}) {
    final tab = BrowserTab(
      id: _nextId++,
      url: url ?? 'about:blank',
      title: title ?? '',
    );
    _tabs.add(tab);
    if (select) _active = _tabs.length - 1;
    return tab;
  }

  /// Closes a tab unless it is the last one. Returns true when the active tab
  /// changed (the window must load the new active URL).
  bool close(int id) {
    if (_tabs.length <= 1) return false;
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return false;
    final wasActive = index == _active;
    _tabs.removeAt(index);
    if (index < _active) _active--;
    if (_active >= _tabs.length) _active = _tabs.length - 1;
    return wasActive;
  }

  void select(int id) {
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index >= 0) _active = index;
  }

  void update({String? url, String? title}) {
    final tab = active;
    if (url != null && url.isNotEmpty) tab.url = url;
    if (title != null) tab.title = title;
  }

  bool isBookmarked(String url) => bookmarks.contains(url);

  bool toggleBookmark(String url) {
    if (url.isEmpty || url == 'about:blank') return false;
    if (!bookmarks.remove(url)) bookmarks.add(url);
    return bookmarks.contains(url);
  }

  Map<String, Object?> toJson() => {
        'tabs': [for (final tab in _tabs) tab.toJson()],
        'active': _active,
        'bookmarks': bookmarks.toList(),
      };

  static BrowserTabs fromJson(Object? json,
      {String home = 'https://duckduckgo.com'}) {
    final tabs = BrowserTabs(home: home);
    if (json is! Map) return tabs;
    tabs._tabs.clear();
    final raw = json['tabs'];
    if (raw is List) {
      for (final item in raw) {
        final tab = BrowserTab.fromJson(item);
        if (tab != null) tabs._tabs.add(tab);
      }
    }
    if (tabs._tabs.isEmpty) tabs.add(url: home);
    tabs._active =
        ((json['active'] as num?)?.toInt() ?? 0).clamp(0, tabs._tabs.length - 1);
    tabs._nextId =
        tabs._tabs.map((tab) => tab.id).fold(0, (a, b) => a > b ? a : b) + 1;
    final marks = json['bookmarks'];
    if (marks is List) {
      tabs.bookmarks.addAll(marks.map((mark) => '$mark'));
    }
    return tabs;
  }
}