// EXWM's snap zones: halves, quarters and maximize, expressed as rectangles
// inside the usable desktop. Pure Dart so the mock suite can check every zone
// on every screen size without a Flutter engine.

import 'window_manager.dart';

/// Where a window can be thrown.
enum SnapZone {
  leftHalf,
  rightHalf,
  topHalf,
  bottomHalf,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  maximize;

  /// `left half`, `top left`, ... for tooltips and the WM tests.
  String get label => switch (this) {
        SnapZone.leftHalf => 'left half',
        SnapZone.rightHalf => 'right half',
        SnapZone.topHalf => 'top half',
        SnapZone.bottomHalf => 'bottom half',
        SnapZone.topLeft => 'top left',
        SnapZone.topRight => 'top right',
        SnapZone.bottomLeft => 'bottom left',
        SnapZone.bottomRight => 'bottom right',
        SnapZone.maximize => 'maximize',
      };
}

/// The rectangle a zone occupies. [gap] is the space between two halves.
Rect4 snapRect(DesktopArea area, SnapZone zone, {double gap = 5}) {
  final full = area.maximizeRect;
  final left = full[0];
  final top = full[1];
  final width = full[2];
  final height = full[3];
  final right = left + width;
  final bottom = top + height;
  final halfWidth = ((width - gap) / 2).clamp(0.0, width).toDouble();
  final halfHeight = ((height - gap) / 2).clamp(0.0, height).toDouble();
  final rightHalfLeft = right - halfWidth;
  final bottomHalfTop = bottom - halfHeight;

  return switch (zone) {
    SnapZone.leftHalf => [left, top, halfWidth, height],
    SnapZone.rightHalf => [rightHalfLeft, top, halfWidth, height],
    SnapZone.topHalf => [left, top, width, halfHeight],
    SnapZone.bottomHalf => [left, bottomHalfTop, width, halfHeight],
    SnapZone.topLeft => [left, top, halfWidth, halfHeight],
    SnapZone.topRight => [rightHalfLeft, top, halfWidth, halfHeight],
    SnapZone.bottomLeft => [left, bottomHalfTop, halfWidth, halfHeight],
    SnapZone.bottomRight => [rightHalfLeft, bottomHalfTop, halfWidth, halfHeight],
    SnapZone.maximize => List<double>.from(full),
  };
}