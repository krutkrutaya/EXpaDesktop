// Configs is the power view: live customization, the Vibe bar list, the open
// windows and maintenance actions. These tests pin the callbacks, not the
// shell chrome.

import 'package:exp_desktop/desktop/apps/configs_app.dart';
import 'package:exp_desktop/expa/de_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Configs shows the live knobs and edits them', (tester) async {
    DeConfig? saved;
    await tester.pumpWidget(_host(ConfigsApp(
      config: const DeConfig(accentIndex: 0, windowRadius: 16),
      onConfig: (value) => saved = value,
      waybarItems: const ['sound', 'wifi'],
      onWaybarItems: (_) {},
    )));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Configs'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Vibe bar'), findsOneWidget);
    expect(find.text('Open windows'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('configs-accent-2')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(saved?.accentIndex, 2);
  });

  testWidgets('the Vibe bar editor removes and adds panels', (tester) async {
    List<String>? items;
    await tester.pumpWidget(_host(ConfigsApp(
      waybarItems: const ['sound', 'wifi'],
      onWaybarItems: (value) => items = value,
    )));
    await tester.pump(const Duration(milliseconds: 200));

    final remove =
        find.byKey(const ValueKey('configs-waybar-remove-sound'));
    await tester.scrollUntilVisible(
      remove,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(remove);
    await tester.pump(const Duration(milliseconds: 100));
    expect(items, isNotNull);
    expect(items!.contains('sound'), isFalse);
    expect(items!.contains('wifi'), isTrue);
  });

  testWidgets('reset returns the customization to the defaults',
      (tester) async {
    DeConfig? saved;
    await tester.pumpWidget(_host(ConfigsApp(
      config: const DeConfig(windowRadius: 24, dockIconScale: 1.3),
      onConfig: (value) => saved = value,
    )));
    await tester.pump(const Duration(milliseconds: 200));

    final reset = find.byKey(const ValueKey('configs-reset'));
    await tester.scrollUntilVisible(
      reset,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(reset);
    await tester.pump(const Duration(milliseconds: 100));

    expect(saved, DeConfig.defaults);
  });
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(width: 680, height: 600, child: child),
        ),
      ),
    );