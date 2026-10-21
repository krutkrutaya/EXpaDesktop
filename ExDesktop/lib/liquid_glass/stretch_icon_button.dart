// An icon button that squashes into an oval while held (the Google-Gemini
// press stretch) and snaps back elastically on release. `active` lights it
// up with a tinted halo and a small bounce when it turns on.
//
// Paint hygiene: the transforming subtree sits behind its own RepaintBoundary
// so pressing one button never re-rasterizes the blurred panels behind it,
// and the release uses a short snappy over-shoot instead of a long wobble.

import 'package:flutter/material.dart';

class StretchIconButton extends StatefulWidget {
  const StretchIconButton({
    super.key,
    required this.child,
    this.onTap,
    this.active = false,
    this.activeColor = Colors.orange,
    this.size = 48.0,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool active;
  final Color activeColor;
  final double size;

  @override
  State<StretchIconButton> createState() => _StretchIconButtonState();
}

class _StretchIconButtonState extends State<StretchIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _press,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutBack,
  );
  bool _hovered = false;

  @override
  void didUpdateWidget(covariant StretchIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A little bounce when it turns on (loop engaged).
    if (widget.active && !oldWidget.active) {
      _press.value = 1;
      _press.reverse();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _press.dispose();
    super.dispose();
  }

  void _down() => _press.forward();

  void _up() {
    _press.reverse();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _down(),
          onTapUp: (_) => _up(),
          onTapCancel: _press.reverse,
          child: AnimatedBuilder(
            animation: _curve,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: widget.size,
              height: widget.size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.active
                    ? widget.activeColor.withValues(alpha: 0.16)
                    : _hovered
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.transparent,
                border: widget.active
                    ? Border.all(
                        color: widget.activeColor.withValues(alpha: 0.5))
                    : null,
              ),
              child: widget.child,
            ),
            builder: (context, child) {
              final p = _curve.value;
              return Transform.scale(
                scaleX: 1.0 + 0.22 * p,
                scaleY: 1.0 - 0.13 * p,
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }
}
