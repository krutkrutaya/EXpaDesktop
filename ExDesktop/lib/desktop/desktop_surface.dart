// The desktop layer: every open window, in z-order.
//
// It is a thin Stack over the window manager. The shell owns the manager (one
// per in-app desktop), the surface only renders it and forwards the two things
// a window cannot do itself: raise on focus and ask for a repaint after a drag
// or a resize.

import 'package:flutter/material.dart';

import 'shell_window.dart';
import 'window_manager.dart';

class DesktopSurface extends StatelessWidget {
  final WindowManager manager;
  final Widget Function(AppWindow window) builder;
  final VoidCallback onChanged;

  const DesktopSurface({
    super.key,
    required this.manager,
    required this.builder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final windows = manager.windows.where((w) => !w.minimized).toList();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final window in windows)
          ShellWindow(
            key: ValueKey('window-${window.id}'),
            window: window,
            manager: manager,
            active: manager.activeId == window.id,
            content: builder(window),
            onChanged: onChanged,
            onFocus: () {
              manager.focus(window.id);
              onChanged();
            },
          ),
      ],
    );
  }
}