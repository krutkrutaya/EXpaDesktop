// The Paint app: a stroke list, not a bitmap.
//
// Keeping strokes (instead of pixels) makes undo trivial and lets the canvas
// be repainted at any window size. The painter lives in the widget; this file
// is the data, so the mock suite can check undo, clear and the brush bounds.

class PaintPoint {
  const PaintPoint(this.x, this.y);
  final double x;
  final double y;
}

class Stroke {
  Stroke({
    required this.color,
    required this.width,
    List<PaintPoint>? points,
  }) : points = points ?? <PaintPoint>[];

  /// ARGB, so the model stays independent of Flutter's Color class.
  final int color;
  final double width;
  final List<PaintPoint> points;

  bool get isEmpty => points.length < 2;
}

class PaintBoard {
  final List<Stroke> _strokes = [];
  Stroke? _current;

  List<Stroke> get strokes => List<Stroke>.unmodifiable(_strokes);
  Stroke? get current => _current;
  bool get canUndo => _strokes.isNotEmpty;
  bool get isDrawing => _current != null;
  int get strokeCount => _strokes.length;

  static const double minWidth = 1.0;
  static const double maxWidth = 40.0;

  void begin(double x, double y, {required int color, required double width}) {
    _current = Stroke(
      color: color,
      width: width.clamp(minWidth, maxWidth),
    )..points.add(PaintPoint(x, y));
  }

  /// Adds a point; points closer than a pixel are skipped, because a slow
  /// mouse otherwise produces thousands of duplicate points per stroke.
  void extend(double x, double y) {
    final stroke = _current;
    if (stroke == null) return;
    final last = stroke.points.last;
    final dx = x - last.x;
    final dy = y - last.y;
    if (dx * dx + dy * dy < 1.0) return;
    stroke.points.add(PaintPoint(x, y));
  }

  void end() {
    final stroke = _current;
    _current = null;
    if (stroke == null) return;
    // A single dot is a valid stroke; keep it.
    _strokes.add(stroke);
  }

  /// Undo removes the last finished stroke. Returns true when something went.
  bool undo() {
    if (_current != null) {
      _current = null;
      return true;
    }
    if (_strokes.isEmpty) return false;
    _strokes.removeLast();
    return true;
  }

  void clear() {
    _strokes.clear();
    _current = null;
  }
}