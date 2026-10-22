// The desktop environment's visual knobs, exposed to every widget.
//
// EXPA's shell wraps its Scaffold in this InheritedWidget. Widgets that draw
// chrome (windows, the dock, settings highlights) read the accent, the corner
// radius, the icon scale and the motion switch from here instead of passing a
// dozen parameters down the tree.

import 'package:flutter/material.dart';

import 'de_config.dart';

class ExpaTheme extends InheritedWidget {
  final DeConfig config;

  const ExpaTheme({
    super.key,
    required this.config,
    required super.child,
  });

  Color get accent => Color(config.accent);

  static ExpaTheme of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<ExpaTheme>();
    assert(theme != null, 'ExpaTheme.of called outside the desktop');
    return theme!;
  }

  /// A safe variant for widgets that can be tested in isolation.
  static DeConfig configOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ExpaTheme>()?.config ??
      DeConfig.defaults;

  @override
  bool updateShouldNotify(ExpaTheme oldWidget) =>
      oldWidget.config != config;
}