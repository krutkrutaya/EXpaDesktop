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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../apps/browser_model.dart';
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

  const BrowserApp({
    super.key,
    this.homeUrl = 'https://duckduckgo.com',
  });

  @override
  State<BrowserApp> createState() => _BrowserAppState();
}

class _BrowserAppState extends State<BrowserApp> {
  final BrowserHistory _history = BrowserHistory();
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

  @override
  void initState() {
    super.initState();
    _current = widget.homeUrl;
    _history.push(_current);
    _address.text = BrowserInput.display(_current);
  }

  @override
  void dispose() {
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
    _history.push(target.uri);
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
    _history.push(url);
    _address.text = BrowserInput.display(url);
    if (mounted) setState(() {});
    _syncButtons();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        children: [
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
                    ],
                  ),
                ),
              ),
            ],
          ),
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