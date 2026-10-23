// The in-app file picker used by Configs "Add preset": Files stays a browser,
// but matching rows grow a Use button and the request is consumed.

import 'package:exp_desktop/apps/file_pick.dart';
import 'package:exp_desktop/apps/files_model.dart';
import 'package:exp_desktop/desktop/apps/files_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Files picks a requested .zip and clears the request',
      (tester) async {
    String? picked;
    final picker = ValueNotifier<FilePickRequest?>(FilePickRequest(
      title: 'Choose a .zip preset pack',
      accepts: (path) => path.toLowerCase().endsWith('.zip'),
      onPick: (path) => picked = path,
    ));
    addTearDown(picker.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(
          width: 680,
          height: 500,
          child: FilesApp(
            startPath: r'C:\packs',
            lister: (path) async => const [
              FileEntry(
                name: 'look.zip',
                path: r'C:\packs\look.zip',
                isDirectory: false,
                size: 12,
              ),
              FileEntry(
                name: 'notes.txt',
                path: r'C:\packs\notes.txt',
                isDirectory: false,
                size: 8,
              ),
            ],
            filePick: picker,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('file-pick-banner')), findsOneWidget);
    expect(find.text('Choose a .zip preset pack'), findsOneWidget);
    expect(find.byKey(const ValueKey('files-pick-look.zip')), findsOneWidget);
    expect(find.byKey(const ValueKey('files-pick-notes.txt')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('files-pick-look.zip')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 320));

    expect(picked, r'C:\packs\look.zip');
    expect(picker.value, isNull);
    expect(find.byKey(const ValueKey('file-pick-banner')), findsNothing);
  });

  testWidgets('Files routes Open with default app through the shell',
      (tester) async {
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(
          width: 680,
          height: 500,
          child: FilesApp(
            startPath: r'C:\notes',
            lister: (path) async => const [
              FileEntry(
                name: 'note.txt',
                path: r'C:\notes\note.txt',
                isDirectory: false,
                size: 8,
              ),
            ],
            onOpenDefault: (entry) {
              opened = entry.path;
              return true;
            },
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const ValueKey('files-entry-note.txt')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('files-open-default')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('files-open-default')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opened, r'C:\notes\note.txt');
  });
}