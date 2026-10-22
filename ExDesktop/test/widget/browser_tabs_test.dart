// The in-shell Browser's tabs and bookmarks. WebView2 never starts under
// `flutter test`; the start page and the tab strip are the parts under test.

import 'package:exp_desktop/desktop/apps/browser_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tabs open, switch and close', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(width: 960, height: 640, child: BrowserApp()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('browser-new-tab')), findsOneWidget);
    expect(find.text('duckduckgo.com'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('browser-new-tab')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('browser-tab-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('browser-tab-close-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('browser-tab-1')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('browser-tab-close-1')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('browser-tab-1')), findsNothing);
    expect(find.byKey(const ValueKey('browser-tab-2')), findsOneWidget);
  });

  testWidgets('a page can be bookmarked and reopened', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(width: 960, height: 640, child: BrowserApp()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('browser-bookmark')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('browser-bookmark-https://duckduckgo.com')),
        findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsWidgets);

    await tester.tap(
        find.byKey(const ValueKey('browser-bookmark-https://duckduckgo.com')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}