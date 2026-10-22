// The chrome around every in-app window, and the way it arrives.
//
// Opening and restoring is a macOS genie: the window un-pinches out of the
// dock icon (and folds back into it when minimized). Closing keeps its own
// quick slide-and-fade. The manager owns the data; this widget owns the
// frames. When the minimize animation lands, it tells the manager, so a
// window is never hidden while it is still visible.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_catalog.dart';
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

  /// Ask the live window to fold into the dock. Called by the dock's running
  /// app button; the widget state plays the genie and then minimizes.
  static void minimizeAnimated(WindowManager manager, int id) =>
      _ShellWindowState.minimizeAnimated(manager, id);

  @override
  State<ShellWindow> createState() => _ShellWindowState();
}

class _ShellWindowState extends State<ShellWindow>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    // Fresh opens are a short pop, not a genie: a click should feel answered
    // in the first frame, not after a trip from the dock.
    duration: const Duration(milliseconds: 260),
  );

  /// Restoring a minimized window is the macOS genie: the pinched window
  /// unfolds out of its dock icon.
  late final AnimationController _restore = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  late final AnimationController _exit = AnimationController(
    vsync: this,
    // Long enough to read: the old 240 ms snapped the window away before the
    // eye could follow it.
    duration: const Duration(milliseconds: 320),
  );

  /// The minimize pinch: the genie folding the window into its dock icon.
  late final AnimationController _genie = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  bool _minimizing = false;
  bool _fromRestore = false;

  @override
  void initState() {
    super.initState();
    final rect = _rectOf(widget.window);
    _displayedRect = rect;
    _fromRect = rect;
    _toRect = rect;
    _states[widget.window.id] = this;
    _fromRestore = widget.window.restoreCount > 0;
    if (_fromRestore) {
      // Land the entrance at full size when the genie finishes; the builder
      // falls through to the entrance branch once _restore is idle.
      _restore.forward().whenComplete(() {
        if (mounted) _entrance.value = 1;
      });
    } else {
      _entrance.forward();
    }
  }

  /// Maximize / restore glides between the two rectangles instead of snapping.
  late final AnimationController _rectMove = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 230),
  );

  late Rect _displayedRect;
  late Rect _fromRect;
  late Rect _toRect;

  _ExitAction _exitAction = _ExitAction.none;
  bool _dragging = false;
  bool _resizing = false;

  static Rect _rectOf(AppWindow window) => Rect.fromLTWH(
        window.left,
        window.top,
        window.width,
        window.height,
      );

  bool get _animating =>
      _entrance.isAnimating ||
      _restore.isAnimating ||
      _exit.isAnimating ||
      _genie.isAnimating;

  /// Live states of every mounted window, keyed by the manager's id. The dock
  /// (or anything else) asks here first when it minimizes an app, so the
  /// squeeze into the dock plays through the widget that owns the window.
  static final Map<int, _ShellWindowState> _states = {};

  @override
  void dispose() {
    _entrance.dispose();
    _restore.dispose();
    _exit.dispose();
    _genie.dispose();
    _rectMove.dispose();
    // Leave the registry so a stale handle never points at a dead state.
    if (_states[widget.window.id] == this) _states.remove(widget.window.id);
    super.dispose();
  }

  /// Maximize or restore with a short glide. Called from the title bar (both
  /// the button and the double-click), so the manager's instant rect change
  /// is turned into an animation here.
  void _toggleMaximized() {
    _fromRect = _displayedRect;
    widget.manager.toggleMaximize(widget.window.id);
    _toRect = _rectOf(widget.window);
    _rectMove.forward(from: 0);
    setState(() {});
  }

  /// Asks the live window state to play the genie first. The title-bar button
  /// takes this path internally; the dock takes it through here. A window
  /// without a mounted state (should not happen) minimizes immediately.
  static void minimizeAnimated(WindowManager manager, int id) {
    final state = _states[id];
    if (state != null && state.mounted) {
      state._requestExit(_ExitAction.minimize);
    } else {
      manager.minimize(id);
    }
  }

  void _requestExit(_ExitAction action) {
    if (_exitAction != _ExitAction.none) return;
    _exitAction = action;
    if (action == _ExitAction.minimize) {
      // The macOS genie: fold into the dock icon, then tell the manager the
      // window is gone.
      _minimizing = true;
      _genie.forward().whenComplete(() {
        if (!mounted) return;
        widget.manager.minimize(widget.window.id);
        widget.onChanged();
      });
      return;
    }
    _exit.forward().whenComplete(() {
      if (!mounted) return;
      if (action == _ExitAction.close) {
        widget.manager.close(widget.window.id);
      }
      widget.onChanged();
    });
  }

  /// The dock anchor point the genie folds into: roughly the centre of the
  /// dock's icon column, in the shell's root coordinates.
  Offset _dockPoint() {
    final area = widget.manager.area;
    // Dead centre of the right rail, where the running-app icons live. The
    // old anchor was the dock's bottom corner, so windows folded into the
    // launcher instead of their own icon.
    return Offset(area.width - 46, area.height / 2);
  }

  double _clamp01(double v) => v.clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rectMove,
      builder: (context, child) {
        final rect = _rectMove.isAnimating
            ? Rect.lerp(
                _fromRect,
                _toRect,
                Curves.easeOutCubic.transform(_rectMove.value),
              )!
            : _rectOf(widget.window);
        _displayedRect = rect;
        return Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: child!,
        );
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!widget.active) widget.onFocus();
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_entrance, _restore, _exit, _genie]),
          builder: (context, child) {
            // Four motions share one builder:
            //  * minimize folds the window into its dock icon (macOS genie);
            //  * restore unfolds it back out of that icon;
            //  * close fades and lifts the window over 320 ms;
            //  * a fresh open is a short scale/fade, not a genie.
            Matrix4 matrix;
            double opacity = 1;
            final rect = _displayedRect;
            if (_minimizing && _genie.value > 0) {
              final p = Curves.easeInOutCubic.transform(_genie.value);
              final anchor = _dockPoint();
              final dx = (anchor.dx - rect.right) * p;
              final dy = (anchor.dy - rect.bottom) * p;
              final sx = 1.0 - 0.88 * p;
              final sy = 1.0 - 0.42 * p;
              opacity = 1.0 - _clamp01((p - 0.72) / 0.28);
              matrix = Matrix4.identity()
                ..translateByDouble(dx, dy, 0.0, 1.0)
                ..translateByDouble(rect.width, rect.height, 0.0, 1.0)
                ..scaleByDouble(sx, sy, 1.0, 1.0)
                ..translateByDouble(-rect.width, -rect.height, 0.0, 1.0);
            } else if (_restore.isAnimating) {
              final p = Curves.easeOutCubic.transform(_restore.value);
              final anchor = _dockPoint();
              final dx = (anchor.dx - rect.right) * (1 - p);
              final dy = (anchor.dy - rect.bottom) * (1 - p);
              final sx = 0.12 + 0.88 * p;
              final sy = 0.50 + 0.50 * p;
              opacity = _clamp01(_restore.value * 4);
              matrix = Matrix4.identity()
                ..translateByDouble(dx, dy, 0.0, 1.0)
                ..translateByDouble(rect.width, rect.height, 0.0, 1.0)
                ..scaleByDouble(sx, sy, 1.0, 1.0)
                ..translateByDouble(-rect.width, -rect.height, 0.0, 1.0);
            } else if (_exit.isAnimating) {
              final leave = Curves.easeInOutCubic.transform(_exit.value);
              // Hold the window visible for the first fifth; the old curve
              // was already mostly transparent halfway through the close,
              // which is why it read as "it disappears too early".
              final fade = _clamp01((leave - 0.22) / 0.78);
              opacity = 1.0 - fade;
              final scale = 1.0 - 0.045 * leave;
              matrix = Matrix4.identity()
                ..translateByDouble(0.0, -18.0 * leave, 0.0, 1.0)
                ..translateByDouble(
                    rect.width / 2, rect.height / 2, 0.0, 1.0)
                ..scaleByDouble(scale, scale, 1.0, 1.0)
                ..translateByDouble(
                    -rect.width / 2, -rect.height / 2, 0.0, 1.0);
            } else {
              final enter = Curves.easeOutCubic.transform(_entrance.value);
              final pop = Curves.easeOutBack
                  .transform(_entrance.value)
                  .clamp(0.0, 1.015);
              final scale = 0.94 + 0.06 * pop;
              opacity = _clamp01(enter);
              matrix = Matrix4.identity()
                ..translateByDouble(0.0, 12.0 * (1 - enter), 0.0, 1.0)
                ..translateByDouble(
                    rect.width / 2, rect.height / 2, 0.0, 1.0)
                ..scaleByDouble(scale, scale, 1.0, 1.0)
                ..translateByDouble(
                    -rect.width / 2, -rect.height / 2, 0.0, 1.0);
            }
            return Opacity(
              key: const ValueKey('window-opacity'),
              opacity: opacity,
              child: Transform(
                key: const ValueKey('window-entrance'),
                transform: matrix,
                child: child,
              ),
            );
          },
          child: WindowScope(
            active: widget.active,
            animating: _animating,
            contentSize: Size(widget.window.width, widget.window.height - 40),
            child: _chrome(context),
          ),
        ),
      ),
    );
  }

  Widget _chrome(BuildContext context) {
    final window = widget.window;
    final radius = window.maximized ? 10.0 : 16.0;
    // The window no longer carries a flat dark fill: the wallpaper shows
    // through a deep gaussian blur. Settings keeps the deepest blur.
    final blur = window.app == ShellApp.settings ? 50.0 : 30.0;
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
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: Colors.black.withValues(alpha: 0.30),
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
                        Positioned.fill(
                          child: RepaintBoundary(child: widget.content),
                        ),
                        if (!window.maximized) _resizeHandle(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleBar(BuildContext context) {
    final window = widget.window;
    // The drag/double-tap detector covers the icon and the title only. When
    // it wrapped the whole bar, its double-tap recogniser held the window
    // buttons in the gesture arena for ~300 ms: close and minimize felt
    // unresponsive and their animations looked late.
    return MouseRegion(
      cursor:
          _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.move,
      child: Container(
        height: 40,
        // Flush to the top corners: no padding above the buttons row and
        // no hairline under it, the glass underneath just shows through.
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {
                  _rectMove.stop();
                  setState(() => _dragging = true);
                },
                onPanUpdate: (details) {
                  widget.manager.moveBy(
                    window.id,
                    details.delta.dx,
                    details.delta.dy,
                  );
                  // Local repaint: dragging one window must not rebuild the
                  // whole desktop and every other app inside it.
                  setState(() {});
                },
                onPanEnd: (_) => setState(() => _dragging = false),
                onPanCancel: () => setState(() => _dragging = false),
                onDoubleTap: _toggleMaximized,
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
                          color:
                              widget.active ? Colors.white : Colors.white60,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
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
              onTap: _toggleMaximized,
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
          onPanStart: (_) {
        _rectMove.stop();
        setState(() => _resizing = true);
      },
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