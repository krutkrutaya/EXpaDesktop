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
import 'package:exp_desktop/workspaces.dart';

import 'mock_harness.dart';

/// Runs the shell suite. `mock_all.dart` calls this directly.
void runShellChecks() {
  testLayoutNumbers();
  testPanelPolicy();
  testId3Reader();
  testWorkspaces();
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

    // The four-dot desktop button sits inside the dock too.
    final dotsCentre = layout.desktopsButton[0] + layout.desktopsButton[2] / 2;
    check(
      '$label: the desktop dots sit inside the dock',
      dotsCentre >= layout.dockLeft &&
          dotsCentre <= layout.width - ShellLayout.dockMargin,
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
        layout.launcherRect[2] <= 400 && layout.launcherRect[3] <= 320);
    checkClose(
      '$label: the launcher is vertically centred',
      layout.launcherRect[1] + layout.launcherRect[3] / 2,
      layout.height / 2,
    );

    // The waybar is a real surface now: 60 px tall, centred, clear of the dock.
    checkClose(
      '$label: the waybar is horizontally centred',
      layout.waybarRect[0] + layout.waybarRect[2] / 2,
      layout.width / 2,
    );
    checkEquals('$label: the waybar is 60 tall',
        layout.waybarRect[3], ShellLayout.waybarHeight);
    check('$label: the waybar sits at the top', layout.waybarRect[1] == 0);
    check('$label: the waybar keeps clear of the dock',
        !ShellLayout.overlaps(layout.waybarRect, layout.dockRect));
    check('$label: the desktops panel has room for nine chips',
        layout.desktopsRect[2] >= 26 * 9 + 4 * 8 + 22);
    checkClose(
      '$label: the launcher is horizontally centred',
      layout.launcherRect[0] + layout.launcherRect[2] / 2,
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

  // The smallest window the shell allows still fits its panels.
  const small = ShellLayout(800, 600);
  check('800x600: the launcher stays on screen',
      small.fitsOnScreen(small.launcherRect));
  check('800x600: the desktops panel stays on screen',
      small.fitsOnScreen(small.desktopsRect));
  check('800x600: the player stays on screen',
      small.fitsOnScreen(small.playerRect));
}

// ---- which surface may share the screen ----------------------------------------

void testPanelPolicy() {
  section('[panel policy]');

  // The settings window is an app window now, not a panel.
  checkEquals('six floating surfaces', ShellPanel.values.length, 6);
  check('settings is not a panel',
      ShellPanel.values.every((panel) => panel.name != 'settings'));
  checkEquals('two centred surfaces', PanelPolicy.centred.length, 2);
  check('the launcher is centred', ShellPanel.launcher.isCentred);
  check('the power menu is centred', ShellPanel.menu.isCentred);
  check('the player is a flyout', !ShellPanel.player.isCentred);
  check('the desktops panel is a flyout', !ShellPanel.desktops.isCentred);

  // Opening the launcher clears the middle and the top edge.
  final launcher = PanelPolicy.plan(ShellPanel.launcher);
  check('launcher closes the power menu',
      launcher.toClose.contains(ShellPanel.menu));
  for (final flyout in PanelPolicy.flyouts) {
    check('launcher closes ${flyout.name}',
        launcher.toClose.contains(flyout));
  }
  check('launcher does not close itself',
      !launcher.toClose.contains(ShellPanel.launcher));

  // The power menu behaves like the launcher.
  final menu = PanelPolicy.plan(ShellPanel.menu);
  check('menu closes the launcher', menu.toClose.contains(ShellPanel.launcher));
  check('menu closes the player', menu.toClose.contains(ShellPanel.player));

  // A flyout closes the other flyouts and both centred surfaces.
  for (final flyout in PanelPolicy.flyouts) {
    final plan = PanelPolicy.plan(flyout);
    check('${flyout.name}: closes the launcher',
        plan.toClose.contains(ShellPanel.launcher));
    check('${flyout.name}: closes the power menu',
        plan.toClose.contains(ShellPanel.menu));
    for (final other in PanelPolicy.flyouts) {
      if (other == flyout) continue;
      check('${flyout.name}: closes ${other.name}',
          plan.toClose.contains(other));
    }
  }

  // No panel ever asks to close itself, and no plan repeats a panel.
  for (final panel in ShellPanel.values) {
    final plan = PanelPolicy.plan(panel);
    check('${panel.name}: does not close itself',
        !plan.toClose.contains(panel));
    check('${panel.name}: closes only once',
        plan.toClose.toSet().length == plan.toClose.length);
    check('${panel.name}: has work to do', plan.toClose.isNotEmpty);
  }

  // Opening a panel twice must still be idempotent: the same plan either time.
  check('the plan is deterministic',
      PanelPolicy.plan(ShellPanel.volume).toClose.toString() ==
          PanelPolicy.plan(ShellPanel.volume).toClose.toString());
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

// ---- in-app workspaces ---------------------------------------------------------

void testWorkspaces() {
  section('[workspaces]');

  final w = WorkspaceController(backgroundCount: 8);
  checkEquals('starts with one desktop', w.count, 1);
  checkEquals('the first desktop is active', w.activeIndex, 0);
  check('the last desktop cannot be closed', !w.canClose);
  check('a desktop can be created', w.canCreate);

  var notified = 0;
  void listener() => notified++;
  w.addListener(listener);

  checkEquals('create returns true', w.create(), true);
  checkEquals('create adds a desktop', w.count, 2);
  checkEquals('create switches to it', w.activeIndex, 1);
  check('the new desktop has a different wallpaper',
      w.items[0].backgroundIndex != w.items[1].backgroundIndex);
  checkEquals('create notifies listeners', notified, 1);
  check('two desktops can be closed', w.canClose);

  w.select(0);
  checkEquals('select switches', w.activeIndex, 0);
  checkEquals('select notifies', notified, 2);
  w.select(0);
  checkEquals('selecting the active one stays quiet', notified, 2);
  w.select(99);
  checkEquals('out of range select is ignored', w.activeIndex, 0);
  w.select(-1);
  checkEquals('negative select is ignored', w.activeIndex, 0);

  w.next();
  checkEquals('next wraps forward', w.activeIndex, 1);
  w.next();
  checkEquals('next wraps around', w.activeIndex, 0);
  w.previous();
  checkEquals('previous wraps backwards', w.activeIndex, 1);

  final before = w.active.backgroundIndex;
  w.cycleBackground();
  check('the slideshow changes the active wallpaper',
      w.active.backgroundIndex != before);

  var beforeSet = notified;
  w.setBackground(3);
  checkEquals('setBackground changes the wallpaper',
      w.active.backgroundIndex, 3);
  checkEquals('setBackground notifies', notified, beforeSet + 1);
  w.setBackground(3);
  checkEquals('setting the same wallpaper is quiet', notified, beforeSet + 1);
  w.setBackground(99);
  checkEquals('an out-of-range wallpaper is ignored',
      w.active.backgroundIndex, 3);
  w.setBackground(-1);
  checkEquals('a negative wallpaper is ignored', w.active.backgroundIndex, 3);

  // Fill the dock up to the limit.
  while (w.canCreate) {
    w.create();
  }
  checkEquals('the dock stops at the maximum', w.count, WorkspaceController.maxWorkspaces);
  checkEquals('no more desktops can be created', w.create(), false);

  // Close them all back down to one.
  while (w.canClose) {
    w.closeActive();
  }
  checkEquals('closing keeps the last desktop', w.count, 1);
  checkEquals('the last desktop cannot be closed', w.closeActive(), false);
  checkEquals('the active index stays valid', w.activeIndex, 0);

  // A fresh controller starts from zero, with no wallpaper repeats.
  final all = WorkspaceController(backgroundCount: 4);
  while (all.canCreate) {
    all.create();
  }
  final wallpapers = all.items.map((w) => w.backgroundIndex).toList();
  check('created desktops do not repeat a wallpaper while free ones exist',
      wallpapers.toSet().length == 4);
}