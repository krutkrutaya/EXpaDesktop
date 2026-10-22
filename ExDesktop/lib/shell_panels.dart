// Which floating surfaces may share the screen.
//
// The rule after the redesign:
//   * the launcher is the only centred surface;
//   * the power menu is a small dropdown above its own button, so opening it
//     closes nothing — the launcher stays visible underneath;
//   * the flyouts (brightness, volume, player, desktops) are exclusive with
//     each other and never open on top of the launcher;
//   * opening anything but power closes the power menu too.
//
// Windows are not part of this: they live under the panels and keep their
// place, which is exactly what a desktop does.

/// A floating surface of the shell.
enum ShellPanel {
  power,// the small dropdown above the launcher's power button
  launcher,// the 9-dot app menu in the middle of the screen
  apps,// the installed-programs panel (waybar's 4-squares button)
  brightness,// the light flyout under the waybar's left buttons
  volume,// the sound + per-app mixer flyout under the waybar's sound button
  wifi,// the network list under the waybar's wifi button
  player,// the mini player flyout under the waybar art
  desktops;// the workspaces flyout

  /// Surfaces that land in the middle of the screen.
  bool get isCentred => this == ShellPanel.launcher || this == ShellPanel.apps;

  /// Drops from a waybar button (or the mini player) and is exclusive with
  /// the other flyouts.
  bool get isFlyout =>
      this == ShellPanel.brightness ||
      this == ShellPanel.volume ||
      this == ShellPanel.wifi ||
      this == ShellPanel.player ||
      this == ShellPanel.desktops;
}

/// What opening a panel must do to the others.
class PanelPlan {
  final List<ShellPanel> toClose;

  const PanelPlan({required this.toClose});

  @override
  String toString() =>
      'PanelPlan(close: ${toClose.map((p) => p.name).join(', ')})';
}

/// Encodes the "only one surface at a time" rules as data, so the mock suite
/// can prove no panel opens buried under another one.
abstract final class PanelPolicy {
  /// Panels that cover the middle of the screen.
  static const List<ShellPanel> centred = [
    ShellPanel.launcher,
    ShellPanel.apps,
  ];

  /// Panels that drop from a waybar button.
  static const List<ShellPanel> flyouts = [
    ShellPanel.brightness,
    ShellPanel.volume,
    ShellPanel.wifi,
    ShellPanel.player,
    ShellPanel.desktops,
  ];

  /// The close-plan for [opening]: everything that must shut when it opens.
  static PanelPlan plan(ShellPanel opening) {
    // The power dropdown lives over the launcher's own power button, so it
    // may not close anything — the launcher must stay open underneath it.
    if (opening == ShellPanel.power) {
      return const PanelPlan(toClose: []);
    }
    final closing = <ShellPanel>[];
    for (final panel in flyouts) {
      if (panel != opening) closing.add(panel);
    }
    // Centred panels close too, but the opening one must never close itself.
    for (final panel in centred) {
      if (panel != opening) closing.add(panel);
    }
    closing.add(ShellPanel.power);
    return PanelPlan(toClose: closing);
  }
}
