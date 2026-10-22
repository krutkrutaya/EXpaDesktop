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

  /// The waybar: 700 px wide for the default three right-side buttons, 60 px
  /// tall, centred at the top. The width grows when the vibe-bar pane adds
  /// placeholder buttons and shrinks a bit when they are trashed — it is a
  /// getter, not a const, and every geometry below derives from it.
  static List<String> waybarRightItems = [
    'bluetooth',
    'sound',
    'wifi',
    'brightness',
  ];

  /// The keys actually painted on the right side. Brightness lives on the
  /// left edge of the bar, but it is still a removable waybar item.
  static List<String> get visibleRightItems => [
        for (final key in waybarRightItems)
          if (key != 'brightness') key,
      ];

  /// Width of one right-side waybar button (40) plus its gap (4).
  static const double waybarItemPitch = 44;

  /// Never narrower than what the mini player plus the programs button need.
  /// 700 px fits the four base panels (brightness on the left, three on the
  /// right). Every extra panel widens the bar by one button pitch; removing
  /// base panels never shrinks it below the player's home.
  static double get waybarWidth => (700.0 +
          (waybarRightItems.length - 4).clamp(0, 99) * waybarItemPitch)
      .clamp(640.0, 1600.0)
      .toDouble();

  static const double waybarHeight = 60;

  Rect4 get waybarRect => [width / 2 - waybarWidth / 2, 0, waybarWidth, waybarHeight];

  /// A right-side waybar button's rect counting from the waybar's right edge:
  /// index 0 is the rightmost button. Read-only mirror of the widget Row that
  /// renders [waybarRightItems] from the same list.
  Rect4 rightButtonAt(int indexFromRight) {
    final rightEdge = width / 2 + waybarWidth / 2 - 5;
    return [rightEdge - 40 - indexFromRight * waybarItemPitch, 10, 40, 40];
  }

  /// Index (counting from the right) of a right-side button by its key;
  /// -1 when the vibe-bar pane removed it.
  int rightIndexOf(String key) {
    final visible = visibleRightItems;
    final i = visible.indexOf(key);
    return i < 0 ? -1 : visible.length - 1 - i;
  }

  int _rightIndexOfOr(String key, int fallback) {
    final i = rightIndexOf(key);
    return i < 0 ? fallback : i;
  }

  /// Left edge of the dock.
  double get dockLeft => width - dockMargin - dockWidth;

  /// The dock itself.
  Rect4 get dockRect =>
      [dockLeft, dockMargin, dockWidth, height - dockMargin * 2];

  // ---- power menu (a small dropdown above the launcher's power button) -----
  // The power button is the middle third of the launcher's action strip, and
  // the menu rises straight above it so it never covers the strip itself.
  Rect4 get powerButton => [width / 2 - 27, height / 2 + 88, 54, 40];
  Rect4 get powerRect => [width / 2 - 100, height / 2 - 107, 200, 180];

  // ---- brightness flyout (top left) ---------------------------------------
  // The button hangs 5 px inside the waybar's LEFT edge, so it keeps its
  // place when the waybar auto-widens.
  Rect4 get brightnessButton =>
      [width / 2 - waybarWidth / 2 + 5, 10, 40, 40];
  Rect4 get brightnessRect => [width / 2 - 350, 60, 350, 180];

  // ---- player (top centre) ------------------------------------------------
  Rect4 get playerButton => [width / 2 - 95, 5, 190, 50];
  Rect4 get playerRect => [width / 2 - 300, 70, 600, 400];

  // ---- volume flyout (under the waybar's sound button) ---------------------
  // Master row on top, a short divider, then the per-app volume rows: the
  // panel is several rows tall and its right edge stays flush with the
  // waybar's right edge.
  Rect4 get volumeButton =>
      rightButtonAt(_rightIndexOfOr('sound', 1));

  Rect4 get volumeRect {
    final rightEdge = width / 2 + waybarWidth / 2;
    return [rightEdge - 340, 68, 340, 300];
  }

  // ---- wi-fi flyout (under the waybar's wifi button) ------------------------
  // The network list drops from its own button like the sound flyout, pinned
  // to the waybar's right edge as well. The two flyouts never share the
  // screen (the panel policy), so identical anchors are fine.
  Rect4 get wifiButton => rightButtonAt(_rightIndexOfOr('wifi', 0));

  Rect4 get wifiRect {
    final rightEdge = width / 2 + waybarWidth / 2;
    return [rightEdge - 360, 68, 360, 430];
  }

  // ---- programs (the 4-squares button beside the mini player) --------------
  // A centred panel pressed by the 4-squares button: the button sits in the
  // waybar just left of the mini player, the panel opens in the middle of
  // the screen.
  Rect4 get appsButton => [width / 2 - 125, 10, 40, 40];

  Rect4 get appsRect => [width / 2 - 260, height / 2 - 240, 520, 480];

  // ---- desktops (the vertical dots in the middle of the dock) --------------
  Rect4 get desktopsButton => [width - 76, height / 2 - 26, 52, 52];
  Rect4 get desktopsRect =>
      [dockLeft - dockGap - 340, height / 2 - 135, 340, 270];

  // ---- launcher (the apps button at the bottom of the dock) ----------------
  Rect4 get launcherButton => [width - 76, height - 72, 52, 52];

  /// A compact landscape rectangle: three columns of icons, not a tall
  /// The app grid plus the action strip under it.
  Rect4 get launcherRect => [width / 2 - 160, height / 2 - 148, 320, 296];

  /// Every panel that floats over the desktop. The 'power' entry is the small
  /// dropdown above the launcher's power button; 'apps' is the installed
  /// programs panel opened from the waybar's 4-squares button; 'wifi' is the
  /// network list under the waybar's wifi button.
  Map<String, Rect4> get panels => {
        'power': powerRect,
        'brightness': brightnessRect,
        'player': playerRect,
        'volume': volumeRect,
        'wifi': wifiRect,
        'launcher': launcherRect,
        'desktops': desktopsRect,
        'apps': appsRect,
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