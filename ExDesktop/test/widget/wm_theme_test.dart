// A window drawn by EXWM must read EXPA's custom config: the radius and the
// active border accent come from ExpaTheme, not from hard-coded constants.

import 'package:exp_desktop/desktop/app_catalog.dart';
import 'package:exp_desktop/desktop/shell_window.dart';
import 'package:exp_desktop/desktop/window_manager.dart';
import 'package:exp_desktop/expa/de_config.dart';
import 'package:exp_desktop/expa/expa_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a ShellWindow uses the DE radius and accent', (tester) async {
    const config = DeConfig(
      accentIndex: 2,
      windowRadius: 24,
      animationsEnabled: false,
    );
    final manager = WindowManager(area: const DesktopArea(1200, 800));
    final window = manager.open(ShellApp.notepad);
    DeConfig? inside;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: ExpaTheme(
          config: config,
          child: SizedBox(
            width: 1200,
            height: 800,
            child: Stack(
              children: [
                ShellWindow(
                  window: window,
                  manager: manager,
                  active: true,
                  onChanged: () {},
                  onFocus: () {},
                  content: Builder(
                    builder: (context) {
                      inside = ExpaTheme.configOf(context);
                      return const Text('body');
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(inside, config);
    final decorations = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(ShellWindow),
          matching: find.byType(DecoratedBox),
        ))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>();
    expect(
      decorations.any(
          (box) => box.borderRadius == BorderRadius.circular(24)),
      isTrue,
    );

    final accent = const Color(0xFFB7E4C7).withValues(alpha: 0.55);
    final containers = tester.widgetList<Container>(find.descendant(
      of: find.byType(ShellWindow),
      matching: find.byType(Container),
    ));
    expect(
      containers.any((container) {
        final decoration = container.foregroundDecoration;
        return decoration is BoxDecoration &&
            decoration.border?.top.color == accent;
      }),
      isTrue,
    );
  });
}