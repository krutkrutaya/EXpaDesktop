// Which floating surfaces may share the screen.
//
// The settings window used to be one of these. It is a normal window now, so
// the rule got simpler:
//   * the centred surfaces (launcher, power menu) are exclusive;
//   * the flyouts (brightness, volume, player, desktops) are exclusive with
//     each other and never open on top of a centred surface;
//   * opening a centred surface closes every flyout.
//
// Windows are not part of this: they live under the panels and keep their
// place, which is exactly what a desktop does.

/// A floating surface of the shell.
enum ShellPanel {
  menu,
  launcher,
  brightness,
  volume,
  player,
  desktops;

  /// Surfaces that land in the middle of the screen.
  bool get isCentred => this == ShellPanel.menu || this == ShellPanel.launcher;
}

/// What opening a panel must do to the others.
class PanelPlan {
  final List<ShellPanel> toClose;

  const PanelPlan({required this.toClose});

  @override
  String toString() =>
      'PanelPlan(close: ${toClose.map((p) => p.name).join(', ')})';
}

abstract final class PanelPolicy {
  static const List<ShellPanel> centred = [
    ShellPanel.menu,
    ShellPanel.launcher,
  ];

  static const List<ShellPanel> flyouts = [
    ShellPanel.brightness,
    ShellPanel.volume,
    ShellPanel.player,
    ShellPanel.desktops,
  ];

  static PanelPlan plan(ShellPanel opening) {
    final closing = <ShellPanel>[];
    for (final panel in flyouts) {
      if (panel != opening) closing.add(panel);
    }
    for (final panel in centred) {
      if (panel != opening) closing.add(panel);
    }
    return PanelPlan(toClose: closing);
  }
}