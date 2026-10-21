// Which floating surfaces may share the screen.
//
// The shell has six of them and they used to fight: the launcher (the nine
// dots) stayed open behind the settings window because opening one surface
// never told the others to leave. The rule is written down here once, as
// data, so the coordination can be tested without a screen.
//
// One surface at a time:
//   * the centred surfaces (launcher, power menu, settings window) all land
//     in the middle of the screen and are exclusive with each other;
//   * the flyouts (brightness, volume, player) hang off the top edge and are
//     exclusive with each other;
//   * opening a centred surface also closes the flyouts - a big panel starts
//     clean;
//   * a flyout may hover next to the settings window, so turning the volume
//     down does not kick the user out of the settings;
//   * the settings window is minimised into the dock rather than closed, so
//     its position and section survive.

/// A floating surface of the shell.
enum ShellPanel {
  menu,
  launcher,
  settings,
  brightness,
  volume,
  player,
  desktops;

  /// Surfaces that land in the middle of the screen.
  bool get isCentred =>
      this == ShellPanel.menu ||
      this == ShellPanel.launcher ||
      this == ShellPanel.settings;
}

/// What opening a panel must do to the others.
class PanelPlan {
  /// Panels that have to leave the screen.
  final List<ShellPanel> toClose;

  /// Whether the settings window should minimise instead of staying open.
  final bool minimizeSettings;

  const PanelPlan({required this.toClose, required this.minimizeSettings});

  @override
  String toString() =>
      'PanelPlan(close: ${toClose.map((p) => p.name).join(', ')}, '
      'minimizeSettings: $minimizeSettings)';
}

abstract final class PanelPolicy {
  static const List<ShellPanel> centred = [
    ShellPanel.menu,
    ShellPanel.launcher,
    ShellPanel.settings,
  ];

  static const List<ShellPanel> flyouts = [
    ShellPanel.brightness,
    ShellPanel.volume,
    ShellPanel.player,
    ShellPanel.desktops,
  ];

  /// The plan for opening [opening].
  static PanelPlan plan(ShellPanel opening) {
    final closing = <ShellPanel>[];

    // The flyouts are always exclusive: they share the top edge.
    for (final panel in flyouts) {
      if (panel != opening) closing.add(panel);
    }

    // A big surface never shares the screen with another big surface, and a
    // flyout never opens on top of the launcher or the power menu either.
    // The one exception is the settings window: it is a window, and turning
    // the volume down should not kick the user out of it.
    for (final panel in centred) {
      if (panel == opening) continue;
      if (panel == ShellPanel.settings && !opening.isCentred) continue;
      closing.add(panel);
    }

    return PanelPlan(
      toClose: closing,
      // Anything that needs the middle of the screen pushes the settings
      // window into the dock; a flyout leaves it alone.
      minimizeSettings: opening.isCentred && opening != ShellPanel.settings,
    );
  }
}