// A Material-Design-style wavy slider.
//
// The active track is a gently flowing sine wave; while dragging it swells
// into a full wave that streams faster. The thumb grows on hover/press (one
// size for both) and stretches like a droplet against the drag direction:
// pull it left — its right side stretches, pull it right — its left.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class WaveSlider extends StatefulWidget {
  const WaveSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x2EFFFFFF),
    this.thumbColor = Colors.white,
    this.height = 30.0,
    this.thumbRadius = 8.5,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final double height;
  final double thumbRadius;

  @override
  State<WaveSlider> createState() => _WaveSliderState();
}

class _WaveSliderState extends State<WaveSlider>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  bool _hover = false;
  bool _drag = false;
  double _amp = 0.16;
  double _phase = 0;
  double _stretch = 0; // signed px, + = pulled right
  double _scale = 1;
  double _value = 0;

  @override
  void initState() {
    super.initState();
    _value = widget.value.clamp(0.0, 1.0);
    _ticker = createTicker(_tick);
    _ticker.start();
  }

  @override
  void didUpdateWidget(covariant WaveSlider old) {
    super.didUpdateWidget(old);
    if (!_drag) _value = widget.value.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final t = math.min(elapsed.inMicroseconds / 1e6, 0.05);
    if (t <= 0) return;
    final target = _drag ? 1.0 : (_hover ? 0.45 : 0.16);
    _amp += (target - _amp) * (1 - math.exp(-t * 9));
    _phase += t * (_drag ? 9.0 : 0.7);
    _stretch *= math.exp(-t * (_drag ? 9 : 13));
    if (_stretch.abs() < 0.05) _stretch = 0;
    final st = (_hover || _drag) ? 1.35 : 1.0;
    _scale += (st - _scale) * (1 - math.exp(-t * 14));
    setState(() {});
  }

  double _posToValue(double dx, double width) {
    final pad = widget.thumbRadius * 1.35 + 2;
    final usable = math.max(width - pad * 2, 1.0);
    return ((dx - pad) / usable).clamp(0.0, 1.0);
  }

  void _apply(double v) {
    setState(() => _value = v);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              // Jumping to a tap also bends the droplet toward the jump.
              final v = _posToValue(d.localPosition.dx, width);
              final span = math.max(width - (widget.thumbRadius * 1.35 + 2) * 2,
                  1.0);
              _stretch = ((v - _value) * span * 0.4)
                  .clamp(-widget.thumbRadius * 2.6, widget.thumbRadius * 2.6);
              _apply(v);
            },
            onHorizontalDragStart: (d) {
              setState(() => _drag = true);
              _apply(_posToValue(d.localPosition.dx, width));
            },
            onHorizontalDragUpdate: (d) {
              _stretch = (_stretch * 0.45 + d.delta.dx * 0.9)
                  .clamp(-widget.thumbRadius * 2.6, widget.thumbRadius * 2.6);
              _apply(_posToValue(d.localPosition.dx, width));
            },
            onHorizontalDragEnd: (_) {
              setState(() => _drag = false);
              widget.onChangeEnd?.call(_value);
            },
            onHorizontalDragCancel: () {
              setState(() => _drag = false);
              widget.onChangeEnd?.call(_value);
            },
            child: SizedBox(
              height: widget.height,
              child: CustomPaint(
                size: Size(width, widget.height),
                painter: _WavePainter(
                  value: _value,
                  amp: _amp,
                  phase: _phase,
                  stretch: _stretch,
                  thumbScale: _scale,
                  activeColor: widget.activeColor,
                  inactiveColor: widget.inactiveColor,
                  thumbColor: widget.thumbColor,
                  thumbRadius: widget.thumbRadius,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double value;
  final double amp;
  final double phase;
  final double stretch;
  final double thumbScale;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final double thumbRadius;

  const _WavePainter({
    required this.value,
    required this.amp,
    required this.phase,
    required this.stretch,
    required this.thumbScale,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.thumbRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height / 2;
    final pad = thumbRadius * 1.35 + 2;
    final usable = math.max(w - pad * 2, 1.0);
    final thumbX = pad + value.clamp(0.0, 1.0) * usable;

    // Inactive track: a thin straight line.
    if (thumbX < w - pad - 1) {
      final p = Paint()
        ..color = inactiveColor
        ..strokeWidth = math.max(2.6, 1.0)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(thumbX, cy), Offset(w - pad, cy), p);
    }

    // Active track: the wave.
    final len = thumbX - pad;
    if (len > 1) {
      final p = Paint()
        ..color = activeColor
        ..strokeWidth = 3.2 + 1.4 * amp
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      if (amp < 0.03 || len < 14) {
        canvas.drawLine(Offset(pad, cy), Offset(thumbX, cy), p);
      } else {
        final a = 3.8 * amp;
        const lambda = 26.0;
        final path = Path();
        for (double x = 0; x <= len; x += 1.5) {
          final env = (x / 12.0).clamp(0.0, 1.0);
          final y =
              cy + math.sin((x / lambda) * 2 * math.pi + phase) * a * env;
          if (x == 0) {
            path.moveTo(pad + x, y);
          } else {
            path.lineTo(pad + x, y);
          }
        }
        canvas.drawPath(path, p);
      }
    }

    // Thumb: a droplet that stretches against the drag direction.
    final r = thumbRadius * thumbScale;
    final s = stretch.clamp(-r * 1.3, r * 1.3);
    final sa = s.abs();
    final rx = r + sa * 0.85;
    final ry = r * (1 - 0.3 * (sa / (sa + r)));
    final cx = thumbX - s * 0.45;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: rx * 2,
        height: ry * 2,
      ),
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}
