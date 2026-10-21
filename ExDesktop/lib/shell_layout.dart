// Where every floating surface of the shell sits, for a given window size.
//
// It used to be six hand-written rects inside didChangeDependencies, and
// that is how the sound flyout ended up 42 px underneath the right dock:
// nothing checked the numbers. Here they are data, so the mock suite can
// assert that no panel leaves the screen, hits the dock, or is empty — on
// any window size, not just the one on this machine.

/// A rectangle in logical pixels: `[left, top, width, height]`.
typedef Rect4 = List<double>;

class ShellLayout {
  final double width;
  final double height;

  const ShellLayout(this.width, this.height);

  /// The right dock: [dockWidth] wide, [dockMargin] from the edges.
  static const double dockWidth = 72;
  static const double dockMargin = 5;

  /// Breathing room between a flyout and the dock.
  static const double dockGap = 8;

  /// Left edge of the dock.
  double get dockLeft => width - dockMargin - dockWidth;

  /// The dock itself.
  Rect4 get dockRect =>
      [dockLeft, dockMargin, dockWidth, height - dockMargin * 2];

  // ---- the power menu (the apps button in the dock) ------------------------
  Rect4 get menuButton => [width - 67, height - 72, 52, 52];
  Rect4 get menuRect => [width - 789, height - 570, 700, 550];

  // ---- brightness flyout (top left) ---------------------------------------
  Rect4 get brightnessButton => [width / 2 - 345, 10, 40, 40];
  Rect4 get brightnessRect => [width / 2 - 350, 60, 350, 180];

  // ---- player (top centre) ------------------------------------------------
  Rect4 get playerButton => [width / 2 - 95, 5, 190, 50];
  Rect4 get playerRect => [width / 2 - 300, 70, 600, 400];

  // ---- volume flyout (top right) ------------------------------------------
  /// The volume flyout ends before the dock starts: at its old position it ran
  /// 42 px underneath it, which is the overlap the screenshot showed.
  Rect4 get volumeRect => [dockLeft - dockGap - 320, 68, 320, 100];

  /// Where the flyout's drop goes when it closes: a little right and a little
  /// down from the icon, so it disappears *into* the right dock instead of
  /// hanging in the corner next to it.
  Rect4 get volumeButton => [width - 76, 22, 40, 40];

  // ---- virtual desktops (the four dots in the middle of the dock) ---------
  Rect4 get desktopsButton => [width - 76, height / 2 - 26, 52, 52];
  Rect4 get desktopsRect =>
      [dockLeft - dockGap - 320, height / 2 - 125, 320, 250];

  // ---- launcher (the nine dots at the bottom of the dock) ------------------
  Rect4 get launcherButton => [width - 76, height - 72, 52, 52];

  /// A compact landscape rectangle: three columns of icons, not a tall
  /// The app grid plus the action strip under it.
  Rect4 get launcherRect => [width / 2 - 160, height / 2 - 148, 320, 296];

  // ---- the settings window -------------------------------------------------
  Rect4 get settingsRect => [width / 2 - 425, height / 2 - 260, 850, 520];

  /// Every panel that floats over the desktop.
  Map<String, Rect4> get panels => {
        'menu': menuRect,
        'brightness': brightnessRect,
        'player': playerRect,
        'volume': volumeRect,
        'launcher': launcherRect,
        'desktops': desktopsRect,
        'settings': settingsRect,
      };

  /// True when two `[left, top, w, h]` rectangles share pixels.
  static bool overlaps(Rect4 a, Rect4 b) {
    final right = a[0] < b[0] + b[2] && b[0] < a[0] + a[2];
    final bottom = a[1] < b[1] + b[3] && b[1] < a[1] + a[3];
    return right && bottom;
  }

  /// True when the rectangle is fully on screen with [margin] to spare.
  bool fitsOnScreen(Rect4 rect, {double margin = 0}) =>
      rect[0] >= margin &&
      rect[1] >= margin &&
      rect[0] + rect[2] <= width - margin &&
      rect[1] + rect[3] <= height - margin;
}