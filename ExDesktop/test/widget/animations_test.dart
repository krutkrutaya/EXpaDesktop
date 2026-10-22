// Animation-cost regression tests: the wave sliders must sleep when nothing
// is happening. They used to run a Ticker forever — every settings slider,
// the volume flyout, the player — which kept the shell repainting at 60 fps
// for no reason and was a large part of the "animations lag" report.

import 'package:exp_desktop/liquid_glass/wave_slider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an idle wave slider has no running ticker', (tester) async {
    var value = 0.4;
    await tester.pumpWidget(_host(value, (next) => value = next));
    await tester.pump(const Duration(milliseconds: 500));

    // Nothing is hovered, dragged or chasing a value: zero frame callbacks.
    expect(tester.binding.transientCallbackCount, 0);

    // A new value wakes it, and it goes back to sleep once it arrives.
    value = 0.9;
    await tester.pumpWidget(_host(value, (next) => value = next));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('hovering wakes the slider and leaving puts it to sleep',
      (tester) async {
    var value = 0.5;
    await tester.pumpWidget(_host(value, (next) => value = next));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.transientCallbackCount, 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(4, 4));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(WaveSlider)));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await gesture.moveTo(const Offset(4, 4));
    await tester.pump();
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.binding.transientCallbackCount, 0);
    await gesture.removePointer();
  });

  testWidgets('the slider repaints only while it moves', (tester) async {
    var value = 0.5;
    await tester.pumpWidget(_host(value, (next) => value = next));
    await tester.pump(const Duration(milliseconds: 500));
    final before = tester.binding.transientCallbackCount;

    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.transientCallbackCount, before);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(double value, ValueChanged<double> onChanged) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(120),
        child: Column(
          children: [
            SizedBox(
              width: 320,
              child: WaveSlider(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    ),
  );
}