// Extra app-window tests: the Browser's start page (WebView2 is unavailable
// under `flutter test`, which is exactly the fallback path), and Notepad's
// autosave path with an in-memory store.
//
// The store's real file IO is covered by `dart run test/apps_check.dart`;
// inside a widget test the fake clock and real disk do not mix, so the UI is
// checked against a store that answers instantly.

import 'dart:io';

import 'package:exp_desktop/apps/notepad_store.dart';
import 'package:exp_desktop/desktop/apps/browser_app.dart';
import 'package:exp_desktop/desktop/apps/notepad_app.dart';
import 'package:exp_desktop/windows_app_icons.dart';
import 'package:exp_desktop/windows_apps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Start-menu icon extraction is disabled under flutter test', () async {
    expect(
      await WindowsAppIcons.load(const WindowsAppEntry(name: 'Test app')),
      isNull,
    );
  });
  testWidgets('the browser start page resolves what you type',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox(width: 960, height: 640, child: BrowserApp())),
    ));
    await tester.pump();

    // No runtime in a test: the fallback page, not a native view.
    expect(find.text('Browser'), findsOneWidget);
    expect(find.textContaining('Address: https://duckduckgo.com'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('browser-address')),
      'example.com',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.textContaining('Address: https://example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a word becomes a search in the address bar', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox(width: 960, height: 640, child: BrowserApp())),
    ));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('browser-address')),
      'glass desktop',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(
      find.textContaining('duckduckgo.com/?q=glass+desktop'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('notepad writes what is typed through its store', (tester) async {
    final store = _MemoryStore();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 560, height: 440, child: NotepadApp(store: store)),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('notepad-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'hello from the shell',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('notepad-save')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(store.text, 'hello from the shell');
    expect(find.textContaining('words'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notepad tabs keep their own text and Save As writes a file',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('expa_note_tabs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _MemoryStore();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 560,
          height: 440,
          child: NotepadApp(store: store),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await tester.enterText(
        find.byKey(const ValueKey('notepad-field')), 'first tab');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('notepad-new-tab')));
    await tester.pump();

    final field = find.byKey(const ValueKey('notepad-field'));
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.enterText(field, 'second tab');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('notepad-tab-0')));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'first tab');

    await tester.tap(find.byKey(const ValueKey('notepad-save-as')));
    await tester.pump();
    final path = '${dir.path}${Platform.pathSeparator}saved.txt';
    await tester.enterText(
        find.byKey(const ValueKey('notepad-save-path')), path);
    await tester.tap(find.byKey(const ValueKey('notepad-save-confirm')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(File(path).readAsStringSync(), 'first tab');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Notepad opens a file from the shell as a new tab',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('expa_note_open');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}opened.txt')
      ..writeAsStringSync('from Files');
    final open = ValueNotifier<String?>(null);
    addTearDown(open.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 560,
          height: 440,
          child: NotepadApp(store: _MemoryStore(), openPath: open),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    open.value = file.path;
    await tester.pump(const Duration(milliseconds: 100));

    final field = find.byKey(const ValueKey('notepad-field'));
    expect(tester.widget<TextField>(field).controller!.text, 'from Files');
    expect(find.text('opened.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notepad survives the smallest window', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 340,
          height: 240,
          child: NotepadApp(store: _MemoryStore()),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

/// A store with no disk behind it: the widget test only cares about the path
/// from the text field to `save`.
class _MemoryStore extends NotepadStore {
  _MemoryStore() : super(path: 'memory-note.txt');

  String text = '';

  @override
  Future<String> load() async => text;

  @override
  Future<bool> save(String value) async {
    text = value;
    return true;
  }

  @override
  Future<bool> exists() async => text.isNotEmpty;
}