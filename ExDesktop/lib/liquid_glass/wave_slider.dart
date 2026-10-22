// A Material-Design-style wavy slider.
//
// The active track is a gently flowing sine wave; while dragging it swells
// into a full wave that streams faster. The thumb grows on hover/press (one
// size for both) and stretches like a droplet against the drag direction:
// pull it left — its right side stretches, pull it right — its left.
//
// It moves smoothly, never in jumps: dragging anywhere shifts the value
// relative to where the thumb was (no snap under the finger), and every
// other change — a tap, an external set like a reset — glides there over a
// few frames. All sliders share this exact behavior and droplet stretch.

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
  bool _ticking = false;
  double _lastElapsed = 0;
  bool _hover = false;
  bool _drag = false;
  double _amp = 0.16;
  double _phase = 0;
  double _stretch = 0; // signed px, + = pulled right
  double _scale = 1;
  // The value on screen and the value we report. The report is direct; the
  // screen chases it, so nothing teleports.
  double _value = 0;
  double _target = 0;
  // Relative dragging: where the grab began, in px and in value.
  double _dragStartX = 0;
  double _dragStartValue = 0;

  @override
  void initState() {
    super.initState();
    _value = _target = widget.value.clamp(0.0, 1.0);
    _ticker = createTicker(_tick);
    // Deliberately not started: an idle slider must not repaint the whole
    // window 60 times a second. The wave only flows while it is hovered,
    // dragged, or chasing a new value.
  }

  @override
  void didUpdateWidget(covariant WaveSlider old) {
    super.didUpdateWidget(old);
    if (!_drag && widget.value != _target) {
      _target = widget.value.clamp(0.0, 1.0);
      _wake();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Starts the ticker if it is asleep. Safe to call on every interaction.
  void _wake() {
    if (_ticking) return;
    _ticking = true;
    _lastElapsed = 0;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    var dt = seconds - _lastElapsed;
    _lastElapsed = seconds;
    if (dt <= 0) return;
    // A long frame must not teleport the thumb or the wave.
    dt = dt.clamp(0.0, 0.05);

    // Chase the target (20/s: smooth but within arm's reach).
    _value += (_target - _value) * (1 - math.exp(-dt * 20));
    if ((_target - _value).abs() < 0.0004) _value = _target;

    final wantedAmp = _drag ? 1.0 : (_hover ? 0.45 : 0.16);
    _amp += (wantedAmp - _amp) * (1 - math.exp(-dt * 9));
    _phase += dt * (_drag ? 9.0 : 0.7);
    // While dragging the droplet holds its shape; the pull relaxes right
    // after the finger leaves it.
    _stretch *= math.exp(-dt * (_drag ? 6 : 13));
    if (_stretch.abs() < 0.05) _stretch = 0;
    final wantedScale = (_hover || _drag) ? 1.35 : 1.0;
    _scale += (wantedScale - _scale) * (1 - math.exp(-dt * 14));

    setState(() {});

    // Everything that needs frames is either an active interaction or a
    // value/amplitude/scale still in motion. When all of them have settled,
    // the ticker stops and the slider costs nothing until touched again.
    final settled = !_drag &&
        !_hover &&
        (_target - _value).abs() < 0.0005 &&
        (wantedAmp - _amp).abs() < 0.002 &&
        (wantedScale - _scale).abs() < 0.002 &&
        _stretch == 0;
    if (settled) {
      _ticking = false;
      _lastElapsed = 0;
      _ticker.stop();
    }
  }

  double _padFor(double radius) => radius * 1.35 + 2;

  double _posToValue(double dx, double width) {
    final pad = _padFor(widget.thumbRadius);
    final usable = math.max(width - pad * 2, 1.0);
    return ((dx - pad) / usable).clamp(0.0, 1.0);
  }

  void _apply(double v) {
    _target = v.clamp(0.0, 1.0);
    setState(() => _value = _target);
    _wake();
    widget.onChanged(_target);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hover = true);
        _wake();
      },
      onExit: (_) {
        setState(() => _hover = false);
        _wake();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _apply(_posToValue(d.localPosition.dx, width)),
            onHorizontalDragStart: (d) {
              // Relative from the very grab: the thumb stays where it is
              // until the finger moves, no snap under it.
              _dragStartX = d.localPosition.dx;
              _dragStartValue = _value;
              _target = _value;
              setState(() => _drag = true);
              _wake();
            },
            onHorizontalDragUpdate: (d) {
              final pad = _padFor(widget.thumbRadius);
              final span = math.max(width - pad * 2, 1.0);
              final from =
                  _dragStartValue + (d.localPosition.dx - _dragStartX) / span;
              // The pull tracks the finger speed: the faster the stroke,
              // the longer the droplet.
              _stretch = (_stretch * 0.45 + d.delta.dx * 1.0)
                  .clamp(-widget.thumbRadius * 2, widget.thumbRadius * 2);
              _apply(from);
            },
            onHorizontalDragEnd: (_) {
              setState(() => _drag = false);
              _wake();
              widget.onChangeEnd?.call(_value);
            },
            onHorizontalDragCancel: () {
              setState(() => _drag = false);
              _wake();
              widget.onChangeEnd?.call(_value);
            },
            child: SizedBox(
              height: widget.height,
              child: RepaintBoundary(
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

    // Thumb: a droplet that stretches against the drag direction — lead it
    // left and the right side stretches, lead it right and the left one
    // does; the faster the stroke the longer it pulls.
    final r = thumbRadius * thumbScale;
    final s = stretch.clamp(-r * 1.6, r * 1.6);
    final sa = s.abs();
    final rx = r + sa * 0.9;
    final ry = r * (1 - 0.3 * (sa / (sa + r)));
    final cx = thumbX - s * 0.7;
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
  bool shouldRepaint(covariant _WavePainter old) =>
      old.value != value ||
      old.amp != amp ||
      old.phase != phase ||
      old.stretch != stretch ||
      old.thumbScale != thumbScale ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.thumbColor != thumbColor ||
      old.thumbRadius != thumbRadius;
}
