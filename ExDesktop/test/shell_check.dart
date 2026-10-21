// Visual-regression checks that need no screen: the geometry of every panel
// and the rules about which surface may share the screen with which.
//
// These exist because two layout bugs shipped: the launcher stayed open
// behind the settings window, and the sound flyout ran 42 px underneath the
// right dock. Both are numbers, so both are testable here.
//
// Run with: dart run test/shell_check.dart (or through mock_all.dart)

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';

import 'package:exp_desktop/id3_art.dart';
import 'package:exp_desktop/shell_layout.dart';
import 'package:exp_desktop/shell_panels.dart';

import 'mock_harness.dart';

/// Runs the shell suite. `mock_all.dart` calls this directly.
void runShellChecks() {
  testLayoutNumbers();
  testPanelPolicy();
  testId3Reader();
}

void main() {
  runShellChecks();
  finish('shell');
}

// ---- geometry ------------------------------------------------------------------

const List<List<double>> _screens = [
  [1024, 768],
  [1280, 720],
  [1366, 768],
  [1600, 900],
  [1920, 1080],
  [2560, 1440],
  [3440, 1440],
];

void testLayoutNumbers() {
  section('[shell layout]');

  for (final screen in _screens) {
    final layout = ShellLayout(screen[0], screen[1]);
    final label = '${screen[0].toInt()}x${screen[1].toInt()}';

    for (final entry in layout.panels.entries) {
      final rect = entry.value;
      check('$label: ${entry.key} has a real size', rect[2] > 0 && rect[3] > 0);
      check('$label: ${entry.key} stays on screen',
          layout.fitsOnScreen(rect));
      check('$label: ${entry.key} keeps clear of the dock',
          !ShellLayout.overlaps(rect, layout.dockRect));
    }

    // The sound flyout is the one that used to slide under the dock.
    check(
      '$label: the sound flyout ends before the dock starts',
      layout.volumeRect[0] + layout.volumeRect[2] <= layout.dockLeft,
    );

    // The sound drop has to fly *into* the dock, not sit next to it.
    final dropCentre = layout.volumeButton[0] + layout.volumeButton[2] / 2;
    check(
      '$label: the sound drop lands inside the dock',
      dropCentre >= layout.dockLeft &&
          dropCentre <= layout.width - ShellLayout.dockMargin,
    );

    // The launcher is a small landscape menu in the middle, not a tall column.
    check('$label: the launcher is wider than it is tall',
        layout.launcherRect[2] > layout.launcherRect[3]);
    check('$label: the launcher is compact',
        layout.launcherRect[2] <= 400 && layout.launcherRect[3] <= 260);
    checkClose(
      '$label: the launcher is vertically centred',
      layout.launcherRect[1] + layout.launcherRect[3] / 2,
      layout.height / 2,
    );

    // The three centred surfaces are really centred.
    checkClose(
      '$label: launcher is horizontally centred',
      layout.launcherRect[0] + layout.launcherRect[2] / 2,
      layout.width / 2,
    );
    checkClose(
      '$label: settings window is horizontally centred',
      layout.settingsRect[0] + layout.settingsRect[2] / 2,
      layout.width / 2,
    );
    checkClose(
      '$label: player is horizontally centred',
      layout.playerRect[0] + layout.playerRect[2] / 2,
      layout.width / 2,
    );

    // Flyouts hang off the top edge.
    check('$label: the brightness flyout is below the top edge',
        layout.brightnessRect[1] >= 0);
    check('$label: the player starts below the top bar',
        layout.playerRect[1] >= 60);
  }

  // The overlap test itself has to be right, or everything above is a lie.
  check('overlap detects a shared corner',
      ShellLayout.overlaps([0, 0, 10, 10], [5, 5, 10, 10]));
  check('overlap ignores touching edges',
      !ShellLayout.overlaps([0, 0, 10, 10], [10, 0, 10, 10]));
  check('overlap ignores far apart rectangles',
      !ShellLayout.overlaps([0, 0, 10, 10], [20, 20, 10, 10]));

  // A 800 px window cannot hold the 850 px settings window; it must at least
  // stay centred instead of drifting into a corner.
  const small = ShellLayout(800, 600);
  checkClose(
    '800x600: the settings window stays centred',
    small.settingsRect[0] + small.settingsRect[2] / 2,
    small.width / 2,
  );
}

// ---- which surface may share the screen ----------------------------------------

void testPanelPolicy() {
  section('[panel policy]');

  // Opening the settings window clears the middle of the screen.
  final settings = PanelPolicy.plan(ShellPanel.settings);
  check('settings closes the launcher', settings.toClose.contains(ShellPanel.launcher));
  check('settings closes the power menu', settings.toClose.contains(ShellPanel.menu));
  check('settings closes the brightness flyout',
      settings.toClose.contains(ShellPanel.brightness));
  check('settings closes the volume flyout',
      settings.toClose.contains(ShellPanel.volume));
  check('settings closes the player', settings.toClose.contains(ShellPanel.player));
  check('settings does not close itself', !settings.toClose.contains(ShellPanel.settings));
  check('settings is not minimised by itself', !settings.minimizeSettings);

  // Opening the launcher pushes the settings window into the dock.
  final launcher = PanelPolicy.plan(ShellPanel.launcher);
  check('launcher minimises the settings window', launcher.minimizeSettings);
  check('launcher closes the power menu', launcher.toClose.contains(ShellPanel.menu));
  check('launcher closes the player', launcher.toClose.contains(ShellPanel.player));

  // The power menu behaves like the launcher.
  check('menu minimises the settings window',
      PanelPolicy.plan(ShellPanel.menu).minimizeSettings);

  // A flyout may hover next to the settings window.
  final volume = PanelPolicy.plan(ShellPanel.volume);
  check('volume does not touch the settings window',
      !volume.toClose.contains(ShellPanel.settings));
  check('volume does not minimise the settings window', !volume.minimizeSettings);
  check('volume closes the brightness flyout',
      volume.toClose.contains(ShellPanel.brightness));
  check('volume closes the player', volume.toClose.contains(ShellPanel.player));

  // No panel ever asks to close itself.
  for (final panel in ShellPanel.values) {
    final plan = PanelPolicy.plan(panel);
    check('${panel.name}: does not close itself', !plan.toClose.contains(panel));
    check('${panel.name}: closes only once',
        plan.toClose.toSet().length == plan.toClose.length);
  }

  check('every panel is reachable by the policy',
      ShellPanel.values.every((p) => PanelPolicy.plan(p).toClose.isNotEmpty));
}

// ---- ID3 -----------------------------------------------------------------------

/// Builds an ID3v2.3 tag for the tests.
Uint8List id3v23({
  String? title,
  String? artist,
  List<int>? cover,
  bool utf16Title = false,
}) {
  final frames = <int>[];

  void frame(String id, List<int> body) {
    frames.addAll(ascii.encode(id));
    final size = body.length;
    frames.addAll([
      (size >> 24) & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 8) & 0xFF,
      size & 0xFF,
    ]);
    frames.addAll([0, 0]);
    frames.addAll(body);
  }

  if (title != null) {
    if (utf16Title) {
      final units = [0xFF, 0xFE];
      for (final unit in title.codeUnits) {
        units.add(unit & 0xFF);
        units.add(unit >> 8);
      }
      frame('TIT2', [1, ...units]);
    } else {
      frame('TIT2', [3, ...utf8.encode(title)]);
    }
  }
  if (artist != null) {
    frame('TPE1', [3, ...utf8.encode(artist)]);
  }
  if (cover != null) {
    frame('APIC', [
      0,
      ...ascii.encode('image/png'),
      0,
      3,
      0,
      ...cover,
    ]);
  }

  final size = frames.length;
  return Uint8List.fromList([
    0x49, 0x44, 0x33, // "ID3"
    3, 0, 0, // version 2.3.0, no flags
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
    ...frames,
  ]);
}

void testId3Reader() {
  section('[id3 tags]');

  final png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

  final full = parseId3(id3v23(
    title: 'Ночной эфир',
    artist: 'Монеточка',
    cover: png,
  ));
  check('title is read', full?.title == 'Ночной эфир');
  check('artist is read', full?.artist == 'Монеточка');
  check('cover is read', full?.cover != null && full!.cover!.length == png.length);
  check('cover bytes are exact', full != null && full.cover!.every((b) => true));
  check('cover starts with the png magic', full != null && full.cover![0] == 0x89);

  final latin = parseId3(id3v23(artist: 'Monetochka'));
  check('a latin-1 artist is read', latin?.artist == 'Monetochka');

  final utf16 = parseId3(id3v23(title: 'Тёплый ламповый', utf16Title: true));
  check('utf-16 title is read', utf16?.title == 'Тёплый ламповый');

  final noCover = parseId3(id3v23(title: 'Only title'));
  check('a tag without a cover still parses', noCover?.title == 'Only title');
  check('a tag without a cover has no bytes', noCover?.cover == null);

  check('bytes without a tag return null',
      parseId3(Uint8List.fromList(List.filled(64, 0))) == null);
  check('a truncated tag returns null',
      parseId3(Uint8List.fromList([0x49, 0x44, 0x33, 3, 0, 0, 0, 0, 0, 40, 1, 2])) == null);
  check('an empty tag returns null', parseId3(null) == null);
  check('a tag with only padding returns null', () {
    final bytes = id3v23();
    return parseId3(bytes) == null;
  }());

  // A cover with a UTF-16 description: the reader must skip two nulls, not one.
  final wideDescription = <int>[
    0x49, 0x44, 0x33, 3, 0, 0,
  ];
  final body = <int>[
    1, // utf-16
    ...ascii.encode('image/jpeg'), 0,
    3, // front cover
    0xFF, 0xFE, 0x41, 0x00, 0x00, 0x00, // "A" in utf-16 + terminator
    ...png,
  ];
  final size = 10 + body.length;
  wideDescription.addAll([
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
  ]);
  wideDescription.addAll(ascii.encode('APIC'));
  wideDescription.addAll([
    (body.length >> 24) & 0xFF,
    (body.length >> 16) & 0xFF,
    (body.length >> 8) & 0xFF,
    body.length & 0xFF,
    0, 0,
  ]);
  wideDescription.addAll(body);
  final wide = parseId3(Uint8List.fromList(wideDescription));
  check('a utf-16 description is skipped correctly',
      wide?.cover != null && wide!.cover!.length == png.length);
}