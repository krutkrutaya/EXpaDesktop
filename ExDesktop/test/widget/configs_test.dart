// Configs: the Presets/Edit tabs, Lua apply, and .zip import through the
// injected picker. The real picker is the in-app Files window.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:exp_desktop/desktop/apps/configs_app.dart';
import 'package:exp_desktop/expa/de_config.dart';
import 'package:exp_desktop/expa/preset_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Presets is the first tab and applies a Lua look', (tester) async {
    DeConfig? saved;
    await tester.pumpWidget(_host(ConfigsApp(
      config: const DeConfig(accentIndex: 0, windowRadius: 16),
      onConfig: (value) => saved = value,
    )));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Configs'), findsOneWidget);
    expect(find.text('Midnight Glass'), findsOneWidget);
    expect(find.byKey(const ValueKey('configs-tab-presets')), findsOneWidget);
    expect(find.byKey(const ValueKey('configs-tab-edit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('configs-apply-midnight-glass')));
    await tester.pump(const Duration(milliseconds: 150));

    expect(saved, isNotNull);
    expect(saved!.accentIndex, 0);
    expect(saved!.windowRadius, 18);
    expect(saved!.wallpaperDim, closeTo(0.22, 0.001));

    await tester.tap(find.byKey(const ValueKey('configs-tab-edit')));
    await tester.pump(const Duration(milliseconds: 300));
    final editor =
        tester.widget<TextField>(find.byKey(const ValueKey('configs-lua')));
    expect(editor.controller!.text, contains('Midnight Glass'));
  });

  testWidgets('the Edit tab applies a hand-written Lua config', (tester) async {
    DeConfig? saved;
    await tester.pumpWidget(_host(ConfigsApp(
      onConfig: (value) => saved = value,
    )));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const ValueKey('configs-tab-edit')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byKey(const ValueKey('configs-lua')),
      'return { name = "Tiny", accent = "mint", radius = 12, animations = false }',
    );
    await tester.tap(find.byKey(const ValueKey('configs-lua-apply')));
    await tester.pump(const Duration(milliseconds: 150));

    expect(saved, isNotNull);
    expect(saved!.accentIndex, 2);
    expect(saved!.windowRadius, 12);
    expect(saved!.animationsEnabled, isFalse);
    expect(find.byKey(const ValueKey('configs-lua-error')), findsNothing);
  });

  testWidgets('the Edit tab reports broken Lua without changing the config',
      (tester) async {
    DeConfig? saved;
    await tester.pumpWidget(_host(ConfigsApp(
      onConfig: (value) => saved = value,
    )));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('configs-tab-edit')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
        find.byKey(const ValueKey('configs-lua')), 'return { radius = ');
    await tester.tap(find.byKey(const ValueKey('configs-lua-apply')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(saved, isNull);
    expect(find.byKey(const ValueKey('configs-lua-error')), findsOneWidget);
  });

  testWidgets('Add preset imports a Lua file from a .zip', (tester) async {
    final dir = Directory.systemTemp.createTempSync('expa_configs_zip');
    addTearDown(() => dir.deleteSync(recursive: true));
    final archive = Archive();
    final source = utf8.encode('''
return {
  name = "Glow",
  description = "From a pack",
  accent = "peach",
  radius = 16,
}
''');
    archive.addFile(ArchiveFile('packs/Glow.lua', source.length, source));
    final zip = File('${dir.path}${Platform.pathSeparator}glow.zip')
      ..writeAsBytesSync(ZipEncoder().encode(archive)!);

    DeConfig? saved;
    await tester.pumpWidget(_host(ConfigsApp(
      onConfig: (value) => saved = value,
      presetStore: PresetStore(root: dir.path),
      pickZip: () async => zip.path,
    )));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const ValueKey('configs-add-preset')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Glow'), findsOneWidget);
    expect(find.textContaining('From a pack'), findsOneWidget);
    expect(find.byKey(const ValueKey('configs-apply-glow')), findsOneWidget);
    expect(saved, isNull);

    await tester.tap(find.byKey(const ValueKey('configs-apply-glow')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(saved?.accentIndex, 3);
    expect(saved?.windowRadius, 16);
  });

  testWidgets('the live sliders are still in Edit', (tester) async {
    DeConfig? saved;
    await tester.pumpWidget(_host(ConfigsApp(
      config: const DeConfig(accentIndex: 0),
      onConfig: (value) => saved = value,
    )));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('configs-tab-edit')));
    await tester.pump(const Duration(milliseconds: 300));

    final accent = find.byKey(const ValueKey('configs-accent-2'));
    await tester.scrollUntilVisible(
      accent,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(accent);
    await tester.pump(const Duration(milliseconds: 100));
    expect(saved?.accentIndex, 2);
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