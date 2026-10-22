// The small glass pieces every app window reuses.
//
// One hover style, one rounding, one tint: copied widgets are how a shell
// starts to look stitched together. The heavy lifting is still the liquid
// glass of the panels; these are the quiet controls inside a window.

import 'package:flutter/material.dart';

/// The dark glass a window's content sits on.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 14,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: child,
    );
  }
}

/// A hover-lit icon button: the shell's one button style.
class HoverIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color color;
  final Color? activeColor;
  final bool active;

  const HoverIcon({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 34,
    this.iconSize = 18,
    this.color = Colors.white,
    this.activeColor,
    this.active = false,
  });

  @override
  State<HoverIcon> createState() => _HoverIconState();
}

class _HoverIconState extends State<HoverIcon> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tint = widget.active
        ? (widget.activeColor ?? Colors.orange)
        : widget.color;
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
        onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(
              alpha: _pressed ? 0.22 : (_hovered ? 0.12 : 0.0),
            ),
            borderRadius: BorderRadius.circular(widget.size * 0.3),
          ),
          child: Icon(widget.icon, color: tint, size: widget.iconSize),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// A pill with a label and an optional icon: the app windows' main action.
class PillButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool active;
  final bool expand;

  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.active = false,
    this.expand = false,
  });

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final content = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(
              alpha: widget.active ? 0.20 : (_hovered && enabled ? 0.14 : 0.07),
            ),
            borderRadius: BorderRadius.circular(_hovered ? 10 : 14),
            border: Border.all(
              color: Colors.white.withValues(alpha: widget.active ? 0.24 : 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon,
                    size: 15,
                    color: enabled ? Colors.white : Colors.white38),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return widget.expand ? SizedBox(width: double.infinity, child: content) : content;
  }
}

/// A small grey caption.
class Caption extends StatelessWidget {
  final String text;
  final double size;

  /// 1 keeps a footer from pushing its row past the window; null wraps.
  final int? maxLines;

  const Caption(this.text, {super.key, this.size = 11, this.maxLines});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: size,
        height: 1.4,
      ),
    );
  }
}
/// A glass switch: a knob that slides inside a capsule.
class GlassToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const GlassToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 46,
          height: 26,
          padding: const EdgeInsets.all(3),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value
                ? Colors.white.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value ? Colors.black87 : Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}
