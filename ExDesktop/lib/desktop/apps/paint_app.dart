// The Paint window: a real canvas with a brush, an eraser, undo, and a PNG
// export that lands in Pictures.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../apps/browser_model.dart';
import '../../apps/paint_board.dart';
import '../../ui/glass.dart';

class PaintApp extends StatefulWidget {
  const PaintApp({super.key});

  @override
  State<PaintApp> createState() => _PaintAppState();
}

class _PaintAppState extends State<PaintApp> {
  final PaintBoard _board = PaintBoard();
  final GlobalKey _canvasKey = GlobalKey();
  int _color = 0xFFFFFFFF;
  double _width = 4;
  bool _eraser = false;
  String _status = 'Draw something';

  static const _palette = [
    0xFFFFFFFF,
    0xFF9AD0FF,
    0xFF9AFFD0,
    0xFFFFE49A,
    0xFFFF9AD0,
    0xFFFF9A9A,
    0xFFB49AFF,
    0xFF111111,
  ];

  void _begin(Offset point) {
    setState(() {
      _board.begin(
        point.dx,
        point.dy,
        color: _eraser ? 0x00000000 : _color,
        width: _width,
      );
    });
  }

  void _extend(Offset point) {
    setState(() => _board.extend(point.dx, point.dy));
  }

  void _end() {
    setState(() => _board.end());
  }

  Future<void> _save() async {
    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path =
          '${picturesDirectory()}${Platform.pathSeparator}paint-$stamp.png';
      await File(path).writeAsBytes(bytes.buffer.asUint8List());
      if (!mounted) return;
      setState(() => _status = 'Saved to Pictures');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not save the picture');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < _palette.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                _Swatch(
                  key: ValueKey('paint-color-$i'),
                  color: _palette[i],
                  selected: !_eraser && _color == _palette[i],
                  onTap: () => setState(() {
                    _color = _palette[i];
                    _eraser = false;
                  }),
                ),
              ],
              const SizedBox(width: 10),
              Container(width: 1, height: 20, color: Colors.white12),
              const SizedBox(width: 10),
              for (final size in const [2.0, 4.0, 8.0, 16.0]) ...[
                _SizeDot(
                  width: size,
                  selected: _width == size && !_eraser,
                  onTap: () => setState(() {
                    _width = size;
                    _eraser = false;
                  }),
                ),
                const SizedBox(width: 4),
              ],
              HoverIcon(
                key: const ValueKey('paint-eraser'),
                icon: Icons.auto_fix_normal_rounded,
                tooltip: 'Eraser',
                active: _eraser,
                activeColor: Colors.white,
                onTap: () => setState(() => _eraser = true),
              ),
              const Spacer(),
              HoverIcon(
                key: const ValueKey('paint-undo'),
                icon: Icons.undo_rounded,
                tooltip: 'Undo',
                onTap: _board.canUndo
                    ? () => setState(() => _board.undo())
                    : null,
              ),
              HoverIcon(
                key: const ValueKey('paint-clear'),
                icon: Icons.delete_outline_rounded,
                tooltip: 'Clear',
                onTap: () => setState(() => _board.clear()),
              ),
              const SizedBox(width: 4),
              PillButton(
                key: const ValueKey('paint-save'),
                label: 'Save PNG',
                icon: Icons.download_outlined,
                onTap: () => unawaited(_save()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GlassPanel(
              padding: const EdgeInsets.all(6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return MouseRegion(
                    cursor: SystemMouseCursors.precise,
                    child: GestureDetector(
                      key: const ValueKey('paint-canvas'),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) => _begin(details.localPosition),
                      onPanUpdate: (details) => _extend(details.localPosition),
                      onPanEnd: (_) => _end(),
                      onPanCancel: _end,
                      onTapDown: (details) => _begin(details.localPosition),
                      onTapUp: (_) => _end(),
                      child: RepaintBoundary(
                        key: _canvasKey,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ColoredBox(
                            color: const Color(0xFFFAFAFA),
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: _BoardPainter(board: _board),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Caption(_status),
              const Spacer(),
              Caption('${_board.strokeCount} strokes'),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final PaintBoard board;

  _BoardPainter({required this.board});

  @override
  void paint(Canvas canvas, Size size) {
    void draw(Stroke stroke) {
      if (stroke.points.isEmpty) return;
      final paint = Paint()
        ..color = Color(stroke.color)
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = stroke.color == 0x00000000
            ? BlendMode.clear
            : BlendMode.srcOver;
      if (stroke.points.length == 1) {
        final point = stroke.points.first;
        canvas.drawCircle(
          Offset(point.x, point.y),
          stroke.width / 2,
          paint..style = PaintingStyle.fill,
        );
        return;
      }
      final path = Path()
        ..moveTo(stroke.points.first.x, stroke.points.first.y);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
      canvas.drawPath(path, paint);
    }

    canvas.saveLayer(Offset.zero & size, Paint());
    for (final stroke in board.strokes) {
      draw(stroke);
    }
    final current = board.current;
    if (current != null) draw(current);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) => true;
}

class _Swatch extends StatelessWidget {
  final int color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Color(color),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeDot extends StatelessWidget {
  final double width;
  final bool selected;
  final VoidCallback onTap;

  const _SizeDot({
    required this.width,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? 0.16 : 0.04),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Container(
            width: width.clamp(3, 12),
            height: width.clamp(3, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(width),
            ),
          ),
        ),
      ),
    );
  }
}