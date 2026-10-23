// The Browser window: WebView2 composited *inside* the shell.
//
// `flutter_inappwebview` on Windows renders the page into a Flutter texture
// (not a child HWND), so the page is clipped by the window's rounded frame,
// moves with it and sits in the normal z-order — it is a real window in the
// shell, not a second OS window.
//
// The widget tests never start WebView2: `available` is false under
// `flutter test`, and the window then shows the start page with the resolved
// URL, which is what a person sees if the runtime is missing.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../apps/browser_model.dart';
import '../../apps/browser_store.dart';
import '../../ui/glass.dart';

/// True on a real Windows run with a WebView2 runtime, false in tests and
/// on machines where the runtime is missing (the window then shows its start
/// page instead of a broken native view).
final bool webViewAvailable = _detectWebView();

bool _detectWebView() {
  if (!Platform.isWindows) return false;
  if (Platform.environment['FLUTTER_TEST'] == 'true') return false;
  if (Platform.environment.containsKey('WEBVIEW2_BROWSER_EXECUTABLE_FOLDER')) {
    return true;
  }
  const roots = [
    r'C:\Program Files (x86)\Microsoft\EdgeWebView\Application',
    r'C:\Program Files\Microsoft\EdgeWebView\Application',
  ];
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    for (final entry in directory.listSync()) {
      if (entry is! Directory) continue;
      if (File('${entry.path}\\msedgewebview2.exe').existsSync()) return true;
    }
  }
  return false;
}

class BrowserApp extends StatefulWidget {
  final String homeUrl;

  /// A URL the shell wants this window to open (Files associations).
  final ValueNotifier<String?>? openUrl;

  /// Session store; injectable for tests.
  final BrowserSessionStore? store;

  const BrowserApp({
    super.key,
    this.homeUrl = 'https://duckduckgo.com',
    this.openUrl,
    this.store,
  });

  @override
  State<BrowserApp> createState() => _BrowserAppState();
}

class _BrowserAppState extends State<BrowserApp> {
  late final BrowserSessionStore _store =
      widget.store ?? BrowserSessionStore();
  late final BrowserTabs _tabs;
  final Map<int, BrowserHistory> _histories = {};
  Timer? _saveTimer;
  final TextEditingController _address = TextEditingController();
  final FocusNode _addressFocus = FocusNode(debugLabel: 'browser-address');

  InAppWebViewController? _controller;
  String _current = '';
  bool _loading = false;
  double _progress = 0;
  String? _error;
  bool _canGoBack = false;
  bool _canGoForward = false;

  bool get _available => webViewAvailable;

  /// Back/forward are per tab: switching tabs must not leak another page's
  /// history into this one.
  BrowserHistory get _history => _histories.putIfAbsent(
        _tabs.active.id,
        () {
          final history = BrowserHistory();
          final url = _tabs.active.url;
          if (url.isNotEmpty && url != 'about:blank') history.push(url);
          return history;
        },
      );

  @override
  void initState() {
    super.initState();
    _tabs = _store.load(home: widget.homeUrl);
    _current = _tabs.active.url;
    _history.push(_current);
    _address.text = BrowserInput.display(_current);
    widget.openUrl?.addListener(_onOpenUrl);
    _consumeOpenUrl();
  }

  /// Debounced: a page load can emit several navigation events, and writing
  /// the session JSON on each of them is wasted disk work. The dispose path
  /// flushes the last state.
  void _saveSession() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _store.save(_tabs);
    });
  }

  void _onOpenUrl() {
    if (mounted) _consumeOpenUrl();
  }

  void _consumeOpenUrl() {
    final url = widget.openUrl?.value;
    if (url == null || url.isEmpty) return;
    widget.openUrl?.value = null;
    unawaited(_open(url));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _store.save(_tabs);
    widget.openUrl?.removeListener(_onOpenUrl);
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _syncButtons() {
    setState(() {
      _canGoBack = _history.canBack;
      _canGoForward = _history.canForward;
    });
  }

  Future<void> _open(String input) async {
    final target = BrowserInput.resolve(input);
    _current = target.uri;
    _tabs.update(url: target.uri, title: BrowserInput.display(target.uri));
    _history.push(target.uri);
    _saveSession();
    _address.text = BrowserInput.display(target.uri);
    _addressFocus.unfocus();
    _error = null;
    setState(() {});
    _syncButtons();
    await _load(target.uri);
  }

  Future<void> _load(String url) async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _loading = true);
    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open this page');
    }
  }

  Future<void> _back() async {
    final url = _history.back();
    if (url == null) return;
    _current = url;
    _address.text = BrowserInput.display(url);
    setState(() {});
    _syncButtons();
    await _load(url);
  }

  Future<void> _forward() async {
    final url = _history.forward();
    if (url == null) return;
    _current = url;
    _address.text = BrowserInput.display(url);
    setState(() {});
    _syncButtons();
    await _load(url);
  }

  Future<void> _reload() async {
    if (_controller != null) {
      await _controller!.reload();
      return;
    }
    await _load(_current);
  }

  void _onNavigated(String? url) {
    if (url == null || url.isEmpty) return;
    _current = url;
    _tabs.update(url: url);
    _history.push(url);
    _address.text = BrowserInput.display(url);
    if (mounted) setState(() {});
    _syncButtons();
    _saveSession();
  }

  Future<void> _selectTab(int id) async {
    _tabs.select(id);
    _current = _tabs.active.url;
    _address.text = BrowserInput.display(_current);
    _history.push(_current);
    setState(() {});
    _syncButtons();
    _saveSession();
    await _load(_current);
  }

  Future<void> _newTab() async {
    _tabs.add(url: widget.homeUrl);
    _current = _tabs.active.url;
    _address.text = BrowserInput.display(_current);
    _history.push(_current);
    setState(() {});
    _syncButtons();
    _saveSession();
    await _load(_current);
  }

  Future<void> _closeTab(int id) async {
    final before = _tabs.count;
    final changed = _tabs.close(id);
    if (_tabs.count < before) _histories.remove(id);
    if (!mounted) return;
    if (changed) {
      _current = _tabs.active.url;
      _address.text = BrowserInput.display(_current);
      setState(() {});
      _syncButtons();
      await _load(_current);
    } else {
      setState(() {});
    }
    _saveSession();
  }

  void _toggleBookmark() {
    setState(() => _tabs.toggleBookmark(_current));
    _saveSession();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        children: [
          _tabStrip(),
          const SizedBox(height: 5),
          Row(
            children: [
              HoverIcon(
                key: const ValueKey('browser-back'),
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: _canGoBack ? () => _back() : null,
              ),
              HoverIcon(
                key: const ValueKey('browser-forward'),
                icon: Icons.arrow_forward_rounded,
                tooltip: 'Forward',
                onTap: _canGoForward ? () => _forward() : null,
              ),
              HoverIcon(
                key: const ValueKey('browser-reload'),
                icon: Icons.refresh_rounded,
                tooltip: 'Reload',
                onTap: _reload,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: GlassPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  radius: 11,
                  child: Row(
                    children: [
                      Icon(
                        _loading ? Icons.public : Icons.lock_outline,
                        size: 13,
                        color: Colors.white30,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('browser-address'),
                          controller: _address,
                          focusNode: _addressFocus,
                          onSubmitted: (value) => _open(value),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                          ),
                          cursorColor: Colors.white,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                            hintText: 'Search or enter an address',
                            hintStyle:
                                TextStyle(color: Colors.white24, fontSize: 12),
                          ),
                        ),
                      ),
                      HoverIcon(
                        key: const ValueKey('browser-go'),
                        icon: Icons.arrow_forward_rounded,
                        size: 28,
                        iconSize: 16,
                        tooltip: 'Go',
                        onTap: () => _open(_address.text),
                      ),
                      HoverIcon(
                        key: const ValueKey('browser-bookmark'),
                        icon: _tabs.isBookmarked(_current)
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        tooltip: _tabs.isBookmarked(_current)
                            ? 'Remove bookmark'
                            : 'Bookmark this page',
                        onTap: _toggleBookmark,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_tabs.bookmarks.isNotEmpty) ...[
            const SizedBox(height: 4),
            _bookmarkStrip(),
          ],
          const SizedBox(height: 6),
          // A hairline progress bar: the page is loading without a spinner
          // taking over the content.
          SizedBox(
            height: 2,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _loading ? 1 : 0,
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: const Color(0xFF9AB8FF),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _tabStrip() {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.count,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final tab = _tabs.tabs[index];
                final active = _tabs.active.id == tab.id;
                return GestureDetector(
                  key: ValueKey('browser-tab-${tab.id}'),
                  onTap: () => _selectTab(tab.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 154,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: Colors.white.withValues(
                            alpha: active ? 0.18 : 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _loading && active
                              ? Icons.public
                              : Icons.tab_rounded,
                          size: 12,
                          color: active ? Colors.white : Colors.white38,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tab.title.isEmpty ? tab.host : tab.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active ? Colors.white : Colors.white54,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                        if (_tabs.canClose)
                          GestureDetector(
                            key: ValueKey('browser-tab-close-${tab.id}'),
                            onTap: () => _closeTab(tab.id),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.close_rounded,
                                  size: 12, color: Colors.white38),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          HoverIcon(
            key: const ValueKey('browser-new-tab'),
            icon: Icons.add_rounded,
            tooltip: 'New tab',
            onTap: _newTab,
          ),
        ],
      ),
    );
  }

  Widget _bookmarkStrip() {
    return SizedBox(
      height: 23,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final url in _tabs.bookmarks)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: GestureDetector(
                key: ValueKey('browser-bookmark-$url'),
                onTap: () => _open(url),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 11, color: Color(0xFFFFD36E)),
                      const SizedBox(width: 4),
                      Text(
                        Uri.tryParse(url)?.host.isNotEmpty == true
                            ? Uri.parse(url).host
                            : url,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _content() {
    if (!_available) {
      return _StartPage(
        url: _current,
        onOpen: _open,
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_current)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                transparentBackground: true,
                supportZoom: true,
                isInspectable: false,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStart: (controller, url) {
                if (url == null) return;
                _onNavigated(url.toString());
                if (mounted) {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                }
              },
              onLoadStop: (controller, url) {
                if (url != null) _onNavigated(url.toString());
                if (mounted) setState(() => _loading = false);
                _controller?.getTitle().then((title) {
                  if (!mounted || title == null) return;
                  _tabs.update(title: title);
                  _saveSession();
                  setState(() {});
                });
                _controller?.canGoBack().then((value) {
                  if (!mounted) return;
                  setState(() => _canGoBack = value);
                });
                _controller?.canGoForward().then((value) {
                  if (!mounted) return;
                  setState(() => _canGoForward = value);
                });
              },
              onProgressChanged: (controller, progress) {
                if (mounted) setState(() => _progress = progress / 100);
              },
              onReceivedError: (controller, request, error) {
                if (mounted) {
                  setState(() {
                    _loading = false;
                    _error = request.isForMainFrame == true
                        ? 'Could not open this page'
                        : null;
                  });
                }
              },
            ),
          ),
        ),
        if (_error != null)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 34, color: Colors.white38),
                    const SizedBox(height: 8),
                    Caption(_error!),
                    const SizedBox(height: 10),
                    PillButton(
                      label: 'Try again',
                      icon: Icons.refresh,
                      onTap: _reload,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// What the window shows when WebView2 cannot host a page: a real start page
/// with shortcuts, not an empty rectangle.
class _StartPage extends StatelessWidget {
  final String url;
  final ValueChanged<String> onOpen;

  const _StartPage({required this.url, required this.onOpen});

  static const _shortcuts = [
    ('Flutter', 'https://flutter.dev'),
    ('GitHub', 'https://github.com'),
    ('Wikipedia', 'https://wikipedia.org'),
    ('YouTube', 'https://youtube.com'),
    ('Reddit', 'https://reddit.com'),
    ('Hacker News', 'https://news.ycombinator.com'),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.public_rounded, size: 22, color: Color(0xFF9AB8FF)),
              const SizedBox(width: 10),
              const Text(
                'Browser',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Caption(webViewAvailable
                  ? 'A page is on its way'
                  : 'WebView2 runtime is not available here'),
            ],
          ),
          const SizedBox(height: 6),
          Caption('Address: $url', size: 11),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final shortcut in _shortcuts)
                PillButton(
                  label: shortcut.$1,
                  icon: Icons.open_in_new_rounded,
                  onTap: () => onOpen(shortcut.$2),
                ),
            ],
          ),
          const Spacer(),
          const Caption(
            'The browser window lives inside EXpaDesktop: the address bar, '
            'the page and the frame are one window.',
          ),
        ],
      ),
    );
  }
}