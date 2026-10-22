// The Configs shelf is intentionally empty after the settings rework: its
// switches moved into the Settings window. An empty window is the spec, so a
// text/icon creeping back in is a regression.

import 'package:exp_desktop/desktop/apps/configs_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Configs is an empty shelf', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ConfigsApp()),
    ));

    expect(find.byType(Text), findsNothing);
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    expect(tester.takeException(), isNull);
  });
}