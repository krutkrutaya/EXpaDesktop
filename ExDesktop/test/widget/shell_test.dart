// Widget tests for the shell: the in-app windows, the launcher, the waybar,
// the workspaces, the panels and the player path.
//
// The radios, the sound and the audio engine run on recorders, so a test never
// spawns PowerShell, mutes the speakers or plays a track. The workspace and
// window managers are the real ones — they live entirely inside the app.
//
// Run with: flutter test

import 'dart:async';
import 'dart:io';

import 'package:exp_desktop/main.dart';
import 'package:exp_desktop/playback/player_controller.dart';
import 'package:exp_desktop/radio_control.dart';
import 'package:exp_desktop/shell_prefs.dart';
import 'package:exp_desktop/sound_control.dart';
import 'package:exp_desktop/wifi_control.dart';
import 'package:exp_desktop/windows_apps.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the shell draws on startup', (tester) async {
    await _pumpShell(tester);

    expect(find.byKey(const ValueKey('waybar')), findsOneWidget);
    expect(find.byKey(const ValueKey('apps-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-dots')), findsOneWidget);
    expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the programs button sits beside the mini player and opens apps',
      (tester) async {
    await _pumpShell(tester);

    final programs = find.byKey(const ValueKey('topbar-programs'));
    final player = find.byKey(const ValueKey('mini-player'));
    expect(programs, findsOneWidget);
    expect(player, findsOneWidget);

    // The four-squares button is to the left of the mini player, on the same
    // centre line — the layout that had hidden it behind the player.
    final programsCentre = tester.getCenter(programs);
    final playerCentre = tester.getCenter(player);
    expect(programsCentre.dx, lessThan(playerCentre.dx));
    expect((programsCentre.dy - playerCentre.dy).abs(), lessThan(1.5));

    await tester.tap(programs);
    await _settle(tester);
    expect(find.byKey(const ValueKey('apps-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a launcher tile opens an in-app window and closes the launcher',
      (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('launcher-app-calculator')), findsOneWidget);
    expect(find.text('Calculator'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('launcher-app-calculator')));
    await _settle(tester);

    // The launcher is gone, the calculator window is on the desktop.
    expect(find.byKey(const ValueKey('launcher-app-calculator')), findsNothing);
    expect(find.byKey(const ValueKey('calc-display')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-app-calculator')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the window arrives with an animation, not instantly',
      (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('launcher-app-calculator')));

    // The launcher shrinks away at 2.6x while the window starts its own pop in
    // the same frame: no artificial 150 ms pause before anything appears.
    // A few frames in, the window is still translucent.
    await tester.pump(const Duration(milliseconds: 32));
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('window-1')),
        matching: find.byType(Opacity),
      ).first,
    );
    expect(opacity.opacity, lessThan(1.0));

    await _settle(tester);
    final settled = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('window-1')),
        matching: find.byType(Opacity),
      ).first,
    );
    expect(settled.opacity, 1.0);
  });

  testWidgets('the dock icon joins with the window, it does not pop in',
      (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('launcher-app-calculator')));

    // Right after the window starts, its dock icon is still fading in.
    await tester.pump(const Duration(milliseconds: 160));
    final fade = tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byKey(const ValueKey('dock-app-calculator')),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, lessThan(1.0));

    await _settle(tester);
    final settled = tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byKey(const ValueKey('dock-app-calculator')),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(settled.opacity.value, 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the calculator buttons really calculate', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'calculator');

    await tester.tap(find.text('7'));
    await tester.tap(find.text('＋'));
    await tester.tap(find.text('5'));
    await tester.tap(find.text('='));
    await tester.pump();

    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the close button removes the window after its exit animation',
      (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'calculator');

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('window-1')),
      matching: find.byKey(const ValueKey('window-close')),
    ));
    await _settle(tester);

    expect(find.byKey(const ValueKey('calc-display')), findsNothing);
    expect(find.byKey(const ValueKey('dock-app-calculator')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimize hides the window and the dock brings it back',
      (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'tasks');

    await tester.tap(find.byKey(const ValueKey('window-minimize')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tasks-input')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('dock-app-tasks')));
    // The restored window un-pinches out of the dock: one frame in, the
    // genie is still near the icon, not at full size.
    await tester.pump();
    final restoredTransform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byKey(const ValueKey('window-1')),
            matching: find.byKey(const ValueKey('window-entrance')),
          )
          .first,
    );
    // The x basis is the genie's horizontal squeeze; getMaxScaleOnAxis also
    // counts the untouched z axis (1.0), so read the actual column.
    expect(restoredTransform.transform.storage[0], lessThan(0.9));

    await _settle(tester);
    expect(find.byKey(const ValueKey('tasks-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window can be dragged by its title bar', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'calculator');

    final before = tester.getTopLeft(find.byKey(const ValueKey('window-1')));
    await tester.drag(find.text('Calculator'), const Offset(120, 70));
    // Let the double-tap recogniser's timer expire before the test ends.
    await tester.pump(const Duration(milliseconds: 400));

    final after = tester.getTopLeft(find.byKey(const ValueKey('window-1')));
    // The pan recogniser eats ~20 px of slop before it starts moving.
    expect(after.dx, greaterThan(before.dx + 80));
    expect(after.dy, greaterThan(before.dy + 30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window can be resized from the corner', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'tasks');

    final before = tester.getSize(find.byKey(const ValueKey('window-1')));
    await tester.drag(
      find.byKey(const ValueKey('window-resize')),
      const Offset(90, 50),
    );
    await tester.pump();

    final after = tester.getSize(find.byKey(const ValueKey('window-1')));
    expect(after.width, greaterThan(before.width + 70));
    expect(after.height, greaterThan(before.height + 30));
  });

  testWidgets('double-clicking the title bar maximizes and restores',
      (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'tasks');

    final before = tester.getSize(find.byKey(const ValueKey('window-1')));
    await tester.tap(find.text('Tasks'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Tasks'));
    await _settle(tester, frames: 60);

    final maximized = tester.getSize(find.byKey(const ValueKey('window-1')));
    expect(maximized.width, greaterThan(before.width + 200));
    // 5 px from the free edges, 5 px below the waybar, 5 px from the dock:
    // 1600 - 5 (left) - 82 (dock 72 + 5 margin + 5 gap) = 1513.
    expect(maximized.width, 1513);
    final rect = tester.getRect(find.byKey(const ValueKey('window-1')));
    expect(rect.left, 5);
    expect(rect.top, 65);
    expect(rect.right, closeTo(1600 - 82, 0.01));
    expect(rect.bottom, closeTo(900 - 5, 0.01));

    await tester.tap(find.text('Tasks'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Tasks'));
    await _settle(tester, frames: 60);

    final restored = tester.getSize(find.byKey(const ValueKey('window-1')));
    expect(restored.width, before.width);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the desktop does not close an app window', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'calculator');

    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);

    expect(find.byKey(const ValueKey('calc-display')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the settings window opens inside the shell', (tester) async {
    await _pumpShell(tester);

    // The Bluetooth waybar button still opens Settings at that pane; the
    // Wi-Fi button now opens its own flyout instead (see below).
    await tester.tap(find.byKey(const ValueKey('topbar-bluetooth')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('settings-row-bluetooth')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-settings')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sound flyout stays open next to a window', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'tasks');

    await tester.tap(find.byKey(const ValueKey('topbar-volume')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('volume-flyout')), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks-input')), findsOneWidget);
  });

  testWidgets('tapping the desktop closes the sound flyout', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('topbar-volume')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('volume-flyout')), findsOneWidget);

    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);
    expect(find.byKey(const ValueKey('volume-flyout')), findsNothing);
  });

  testWidgets('the workspace panel stays open while desktops are added',
      (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('desktop-dots')));
    await _settle(tester);
    expect(find.text('Desktop 1 of 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workspace-new')));
    await _settle(tester, frames: 60);
    await tester.tap(find.byKey(const ValueKey('workspace-new')));
    await _settle(tester, frames: 60);

    // The panel did not close; the chips grew.
    expect(find.byKey(const ValueKey('workspace-new')), findsOneWidget);
    expect(find.text('Desktop 3 of 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-chip-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-dot-2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workspace-close')));
    await _settle(tester, frames: 60);
    expect(find.text('Desktop 2 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chip switches desktops and the windows follow', (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'calculator');

    await tester.tap(find.byKey(const ValueKey('desktop-dots')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('workspace-new')));
    await _settle(tester, frames: 60);
    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);

    // Desktop 2 has no windows of its own.
    expect(find.byKey(const ValueKey('calc-display')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('desktop-dots')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('workspace-chip-0')));
    await _settle(tester);
    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);

    expect(find.byKey(const ValueKey('calc-display')), findsOneWidget);
  });

  testWidgets('the mouse wheel over the dots scrolls desktops', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('desktop-dots')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('workspace-new')));
    await _settle(tester, frames: 60);
    await tester.tapAt(const Offset(240, 700));
    await _settle(tester);

    // The new desktop is active: dot 1 is the tall one.
    expect(
      tester.getSize(find.byKey(const ValueKey('workspace-dot-1'))).height,
      greaterThan(
        tester.getSize(find.byKey(const ValueKey('workspace-dot-0'))).height,
      ),
    );

    final centre = tester.getCenter(find.byKey(const ValueKey('desktop-dots')));
    await tester.sendEventToBinding(PointerScrollEvent(
      position: centre,
      scrollDelta: const Offset(0, 20),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester.getSize(find.byKey(const ValueKey('workspace-dot-0'))).height,
      greaterThan(
        tester.getSize(find.byKey(const ValueKey('workspace-dot-1'))).height,
      ),
    );
  });

  testWidgets('Tracks opens the Musics window', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('mini-player')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('player-tracks')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-tracks')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('player-tracks')), findsNothing);
    expect(find.byKey(const ValueKey('musics-track-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('musics-play')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Musics transport drives the player', (tester) async {
    final audio = _FakeAudio();
    await _pumpShell(tester, audio: audio);
    await _openApp(tester, 'musics');

    await tester.tap(find.byKey(const ValueKey('musics-play')));
    await _settle(tester, frames: 40);
    expect(find.byIcon(Icons.pause_rounded), findsWidgets);
    expect(audio.calls, contains('play'));

    await tester.tap(find.byKey(const ValueKey('musics-next')));
    await _settle(tester, frames: 40);
    expect(audio.calls.where((call) => call == 'play').length, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the workspace panel and the launcher are different surfaces',
      (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('launcher-app-files')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop-dots')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('launcher-app-files')), findsNothing);
    expect(find.text('Desktop 1 of 1'), findsOneWidget);
  });

  testWidgets('the shell fits a 1366x768 screen', (tester) async {
    await _pumpShell(tester, size: const Size(1366, 768));
    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('launcher-app-musics')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shell fits a 1024x768 screen', (tester) async {
    await _pumpShell(tester, size: const Size(1024, 768));
    await tester.tap(find.byKey(const ValueKey('topbar-wifi')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the desktops button is vertically centred in the dock',
      (tester) async {
    await _pumpShell(tester);
    final dots = tester.getCenter(find.byKey(const ValueKey('desktop-dots')));
    final dock = tester.getRect(find.byKey(const ValueKey('dock')));
    expect((dots.dy - dock.center.dy).abs(), lessThan(1.0));
    expect((dots.dx - dock.center.dx).abs(), lessThan(1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the programs panel shows real-looking rows, not exe junk',
      (tester) async {
    await _pumpShell(
      tester,
      windowsApps: const [
        WindowsAppEntry(name: 'Real App', launchTarget: 'C:/apps/real.lnk'),
        WindowsAppEntry(name: 'Junk', launchTarget: 'C:/junk/junk.exe'),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('topbar-programs')));
    await _settle(tester);

    expect(find.text('Real App'), findsOneWidget);
    expect(find.text('Junk'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('windows-app-Real App')),
        matching: find.text('R'),
      ),
      findsOneWidget,
    );
    // The old fallback was the generic 9-square icon; the tile now uses a
    // colored letter while the real icon is loading or unavailable.
    expect(find.byIcon(Icons.apps_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wifi waybar button opens its own network flyout',
      (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('topbar-wifi')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('wifi-flyout')), findsOneWidget);
    expect(find.text('Networks'), findsOneWidget);

    final search = find.descendant(
      of: find.byKey(const ValueKey('wifi-flyout')),
      matching: find.byIcon(Icons.search_rounded),
    );
    await tester.tap(search);
    await _settle(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('wifi-flyout')),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a close keeps the window visible for most of its exit',
      (tester) async {
    await _pumpShell(tester);
    await _openApp(tester, 'calculator');

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('window-1')),
      matching: find.byKey(const ValueKey('window-close')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    // 180 ms into a 320 ms exit: still on screen.
    expect(find.byKey(const ValueKey('calc-display')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 220));
    // The completion schedules the manager's removal for the next frame.
    await tester.pump();
    expect(find.byKey(const ValueKey('calc-display')), findsNothing);
    // Let the dock icon's own 210 ms exit timer finish before teardown.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a launcher app gets a dock task and animates away',
      (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);

    final tile = find.byKey(const ValueKey('launcher-app-configs'));
    expect(tile, findsOneWidget);

    await tester.tap(tile);
    await _settle(tester);
    expect(find.byKey(const ValueKey('configs-tab-presets')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-app-configs')), findsOneWidget);

    // Clicking the active dock task folds the window into the dock.
    await tester.tap(find.byKey(const ValueKey('dock-app-configs')));
    await _settle(tester, frames: 80);
    expect(find.byKey(const ValueKey('configs-tab-presets')), findsNothing);

    // Clicking it again restores the same window.
    await tester.tap(find.byKey(const ValueKey('dock-app-configs')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('configs-tab-presets')), findsOneWidget);

    // Closing the window removes the dock task after its fade.
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('window-1')),
      matching: find.byKey(const ValueKey('window-close')),
    ));
    await _settle(tester, frames: 100);
    expect(find.byKey(const ValueKey('dock-app-configs')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the launcher keeps the original nine apps', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);

    for (final id in [
      'calculator',
      'notepad',
      'files',
      'paint',
      'snip',
      'tasks',
      'browser',
      'musics',
      'configs',
    ]) {
      expect(find.byKey(ValueKey('launcher-app-$id')), findsOneWidget,
          reason: 'launcher tile for $id');
    }
    expect(find.byKey(const ValueKey('launcher-app-calendar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the player banner blurs its artwork', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('mini-player')));
    await _settle(tester);

    expect(find.byKey(const ValueKey('player-flyout')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('player-flyout')),
        matching: find.byType(ImageFiltered),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('launcher tiles do not paint a dark hover wash', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('apps-button')));
    await _settle(tester);

    final tile = find.byKey(const ValueKey('launcher-app-calculator'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(tile));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.descendant(of: tile, matching: find.byType(AnimatedContainer)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await gesture.removePointer();
  });

  testWidgets('the wifi flyout expands the connect card for each network',
      (tester) async {
    await _pumpShell(
      tester,
      wifiNetworks: [
        WifiNetwork(
          ssid: 'Home',
          signal: 80,
          secure: true,
          known: true,
          connected: false,
          auto: true,
        ),
        WifiNetwork(
          ssid: 'Cafe',
          signal: 30,
          secure: false,
          known: false,
          connected: false,
          auto: false,
        ),
        WifiNetwork(
          ssid: 'Phone',
          signal: 60,
          secure: true,
          known: true,
          connected: true,
          auto: true,
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('topbar-wifi')));
    await _settle(tester);

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Cafe'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    // Locked Home and Phone, open Cafe.
    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('wifi-row-Home')));
    await tester.tap(find.byKey(const ValueKey('wifi-row-Home')));
    await _settle(tester);
    expect(find.text('Enter password'), findsOneWidget);
    expect(find.text('Connect automatically'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('wifi-row-Cafe')));
    await tester.tap(find.byKey(const ValueKey('wifi-row-Cafe')));
    await _settle(tester);
    expect(find.text('Enter password'), findsNothing);
    expect(find.text('Connect'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('wifi-row-Phone')));
    await tester.tap(find.byKey(const ValueKey('wifi-row-Phone')));
    await _settle(tester);
    expect(find.text('Connected, pinned'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// ---- helpers -------------------------------------------------------------------

Future<void> _openApp(WidgetTester tester, String appId) async {
  await tester.tap(find.byKey(const ValueKey('apps-button')));
  await _settle(tester);
  await tester.tap(find.byKey(ValueKey('launcher-app-$appId')));
  await _settle(tester);
}

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1600, 900),
  AudioEngine? audio,
  List<WifiNetwork>? wifiNetworks,
  List<WindowsAppEntry>? windowsApps,
}) async {
  // Hermetic prefs: the waybar list, slideshow and display choices of the
  // machine running the tests must never leak into a shell test.
  final prefsDir = Directory.systemTemp.createTempSync('expa_shell_');
  ShellPrefs.setDirectory(prefsDir.path);
  addTearDown(() {
    ShellPrefs.setDirectory(null);
    try {
      prefsDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: MyHomePage(
      radio: _FakeRadio(),
      sound: _FakeSound(),
      audio: audio ?? _FakeAudio(),
      wifiNetworks: wifiNetworks,
      windowsApps: windowsApps,
    ),
  ));
  await _settle(tester);
}

/// The shell keeps a 1 s clock, a 12 s wallpaper timer and a spinning artwork
/// ticker, so `pumpAndSettle` would never return. Fixed frames are enough for
/// every spring.
Future<void> _settle(WidgetTester tester, {int frames = 220}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _FakeSound implements SoundSource {
  double _volume = 0.5;
  bool _muted = false;

  @override
  double get volume => _volume;

  @override
  set volume(double value) => _volume = value.clamp(0.0, 1.0);

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) => _muted = value;

  @override
  int get percent => (_volume * 100).round();

  @override
  void stepVolume(double direction) =>
      _volume = (_volume + 0.02 * direction).clamp(0.0, 1.0);

  @override
  void refresh() {}
}

class _FakeRadio implements RadioSource {
  final Map<RadioKind, RadioStatus> _states = {
    RadioKind.wifi: const RadioStatus(
      kind: RadioKind.wifi,
      state: RadioState.on,
      canToggle: true,
    ),
    RadioKind.bluetooth: const RadioStatus(
      kind: RadioKind.bluetooth,
      state: RadioState.off,
      canToggle: true,
    ),
  };

  @override
  Future<RadioStatus> status(RadioKind kind, {bool force = false}) async =>
      _states[kind]!;

  @override
  Future<RadioActionResult> setPower(RadioKind kind, bool on) async {
    final next = RadioStatus(
      kind: kind,
      state: on ? RadioState.on : RadioState.off,
      canToggle: true,
    );
    _states[kind] = next;
    return RadioActionResult(ok: true, status: next, message: 'ok');
  }
}

/// The audio backend without audio: records what the player asked for.
class _FakeAudio implements AudioEngine {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durations =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completions = StreamController<void>.broadcast();

  final List<String> calls = [];

  @override
  Future<void> playAsset(String asset) async {
    calls.add('play');
    _durations.add(const Duration(seconds: 120));
  }

  @override
  Future<void> playFile(String path) async => calls.add('playFile');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> seek(Duration position) async => calls.add('seek');

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<Duration?> position() async => Duration.zero;

  @override
  Stream<Duration> get onPosition => _positions.stream;

  @override
  Stream<Duration> get onDuration => _durations.stream;

  @override
  Stream<void> get onComplete => _completions.stream;

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _durations.close();
    await _completions.close();
  }
}