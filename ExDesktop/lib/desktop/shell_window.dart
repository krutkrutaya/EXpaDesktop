// The chrome around every in-app window, and the way it arrives.
//
// A window slides out of the right dock rather than appearing at its final
// place: the entrance is a 300 ms spring (scale + slide + fade), the close is
// a quick pull back towards the dock, and minimizing is the same motion with
// the window left hidden. The manager owns the data; this widget owns the
// frames. When the exit animation lands, it tells the manager, so a window is
// never removed while it is still visible.

import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'window_manager.dart';

/// What the exit animation should do when it lands.
enum _ExitAction { none, close, minimize }

/// Data a window's content may want: focus, size, and a way to close itself.
class WindowScope extends InheritedWidget {
  final bool active;
  final bool animating;
  final Size contentSize;

  const WindowScope({
    super.key,
    required this.active,
    required this.animating,
    required this.contentSize,
    required super.child,
  });

  static WindowScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WindowScope>();
    assert(scope != null, 'WindowScope.of called outside a window');
    return scope!;
  }

  @override
  bool updateShouldNotify(WindowScope oldWidget) =>
      active != oldWidget.active ||
      animating != oldWidget.animating ||
      contentSize != oldWidget.contentSize;
}

class ShellWindow extends StatefulWidget {
  final AppWindow window;
  final WindowManager manager;
  final bool active;
  final Widget content;
  final VoidCallback onChanged;
  final VoidCallback onFocus;

  const ShellWindow({
    super.key,
    required this.window,
    required this.manager,
    required this.active,
    required this.content,
    required this.onChanged,
    required this.onFocus,
  });

  @override
  State<ShellWindow> createState() => _ShellWindowState();
}

class _ShellWindowState extends State<ShellWindow>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();

  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
  );

  _ExitAction _exitAction = _ExitAction.none;
  bool _dragging = false;
  bool _resizing = false;

  @override
  void dispose() {
    _entrance.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _requestExit(_ExitAction action) {
    if (_exitAction != _ExitAction.none) return;
    _exitAction = action;
    _exit.forward().whenComplete(() {
      if (!mounted) return;
      if (action == _ExitAction.close) {
        widget.manager.close(widget.window.id);
      } else if (action == _ExitAction.minimize) {
        widget.manager.minimize(widget.window.id);
      }
      widget.onChanged();
    });
  }

  bool get _animating => _entrance.isAnimating || _exit.isAnimating;

  @override
  Widget build(BuildContext context) {
    final window = widget.window;
    return Positioned(
      left: window.left,
      top: window.top,
      width: window.width,
      height: window.height,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!widget.active) widget.onFocus();
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_entrance, _exit]),
          builder: (context, child) {
            final enter = Curves.easeOutCubic.transform(_entrance.value);
            final spring = Curves.easeOutBack.transform(_entrance.value * 0.8);
            final leave = Curves.easeInCubic.transform(_exit.value);
            final offset = 74.0 * (1 - enter) + 58.0 * leave;
            final scale = (0.94 + 0.06 * spring) * (1 - 0.05 * leave);
            final opacity = (enter * (1 - leave)).clamp(0.0, 1.0);
            return Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: Offset(offset, 0),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topRight,
                  child: child,
                ),
              ),
            );
          },
          child: WindowScope(
            active: widget.active,
            animating: _animating,
            contentSize: Size(window.width, window.height - 40),
            child: _chrome(context),
          ),
        ),
      ),
    );
  }

  Widget _chrome(BuildContext context) {
    final window = widget.window;
    final radius = window.maximized ? 10.0 : 16.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.active ? 0.55 : 0.35),
            blurRadius: widget.active ? 34 : 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xF21C1C1F), Color(0xF0121214)],
            ),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: widget.active ? 0.26 : 0.10),
            ),
          ),
          child: Column(
            children: [
              _titleBar(context),
              Expanded(
                child: ClipRect(
                  child: Stack(
                    children: [
                      Positioned.fill(child: widget.content),
                      if (!window.maximized) _resizeHandle(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _titleBar(BuildContext context) {
    final window = widget.window;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => setState(() => _dragging = true),
      onPanUpdate: (details) {
        widget.manager.moveBy(
          window.id,
          details.delta.dx,
          details.delta.dy,
        );
        // Local repaint: dragging one window must not rebuild the whole
        // desktop and every other app inside it.
        setState(() {});
      },
      onPanEnd: (_) => setState(() => _dragging = false),
      onPanCancel: () => setState(() => _dragging = false),
      onDoubleTap: () {
        widget.manager.toggleMaximize(window.id);
        setState(() {});
      },
      child: MouseRegion(
        cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.move,
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(
            color: widget.active
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                iconForApp(window.app),
                size: 16,
                color: accentForApp(window.app),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  window.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.active ? Colors.white : Colors.white60,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              _windowButton(
                key: const ValueKey('window-minimize'),
                icon: Icons.remove_rounded,
                tooltip: 'Minimize',
                onTap: () => _requestExit(_ExitAction.minimize),
              ),
              _windowButton(
                key: const ValueKey('window-maximize'),
                icon: window.maximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                tooltip: window.maximized ? 'Restore' : 'Maximize',
                onTap: () {
                  widget.manager.toggleMaximize(window.id);
                  setState(() {});
                },
              ),
              _windowButton(
                key: const ValueKey('window-close'),
                icon: Icons.close_rounded,
                tooltip: 'Close',
                danger: true,
                onTap: () => _requestExit(_ExitAction.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _windowButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return _TitleBarButton(
      key: key,
      icon: icon,
      tooltip: tooltip,
      danger: danger,
      onTap: onTap,
    );
  }

  Widget _resizeHandle() {
    return Positioned(
      right: 0,
      bottom: 0,
      width: 20,
      height: 20,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeDownRight,
        child: GestureDetector(
          key: const ValueKey('window-resize'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => setState(() => _resizing = true),
          onPanUpdate: (details) {
            widget.manager.resizeBy(
              widget.window.id,
              details.delta.dx,
              details.delta.dy,
            );
            setState(() {});
          },
          onPanEnd: (_) => setState(() => _resizing = false),
          onPanCancel: () => setState(() => _resizing = false),
          child: CustomPaint(
            painter: _GripPainter(
              color: Colors.white.withValues(alpha: _resizing ? 0.6 : 0.22),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  const _TitleBarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.danger
        ? const Color(0xFFC42B1C)
        : Colors.white.withValues(alpha: 0.14);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 30,
            height: 26,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: _hovered ? hoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: _hovered && widget.danger ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

/// Two diagonal hairlines in the corner, the way every resizable window hints
/// that it can be pulled.
class _GripPainter extends CustomPainter {
  final Color color;

  const _GripPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(w - 3, h - 9), Offset(w - 9, h - 3), paint);
    canvas.drawLine(Offset(w - 3, h - 15), Offset(w - 15, h - 3), paint);
  }

  @override
  bool shouldRepaint(_GripPainter oldDelegate) => oldDelegate.color != color;
}