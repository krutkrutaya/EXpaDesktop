// EXPA: the desktop environment's own models. Pure Dart, no Flutter.

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:exp_desktop/expa/calendar_month.dart';
import 'package:exp_desktop/expa/clipboard_history.dart';
import 'package:exp_desktop/expa/de_config.dart';
import 'package:exp_desktop/expa/drives.dart';
import 'package:exp_desktop/expa/default_apps.dart';
import 'package:exp_desktop/expa/input_settings.dart';
import 'package:exp_desktop/expa/notifications.dart';
import 'package:exp_desktop/expa/update_service.dart';
import 'package:exp_desktop/expa/version.dart';

import 'mock_harness.dart';

void runExpaChecks() {
  _config();
  _associations();
  _notifications();
  _version();
  _clipboard();
  _calendar();
  _drives();
  _input();
}

void _config() {
  section('[expa config]');
  const defaults = DeConfig.defaults;
  checkEquals('radius default', defaults.windowRadius, 16.0);
  checkEquals('animations default on', defaults.animationsEnabled, true);
  checkEquals('snap default on', defaults.snapEnabled, true);
  checkEquals('notification default on', defaults.notificationsEnabled, true);
  check('accent is a valid argb', defaults.accent != 0);
  check('six accents', DeConfig.accents.length == 6);

  final tuned = defaults.copyWith(
    accentIndex: 3,
    windowRadius: 22,
    wallpaperDim: 0.4,
    dockIconScale: 1.25,
    animationSpeed: 1.4,
    animationsEnabled: false,
    snapEnabled: false,
    snapGap: 12,
    notificationsEnabled: false,
    clockSeconds: true,
    fontScale: 1.1,
  );
  checkEquals('copy accent', tuned.accentIndex, 3);
  checkEquals('copy radius', tuned.windowRadius, 22.0);
  check('the copy differs', tuned != defaults);

  final map = tuned.toMap();
  final back = DeConfig.fromMap((key, [fallback = '']) => map[key] ?? fallback);
  check('round-trip equality', back == tuned);
  checkEquals('round-trip radius', back.windowRadius, 22.0);
  checkEquals('round-trip snap', back.snapEnabled, false);

  final clamped = DeConfig.fromMap((key, [fallback = '']) => switch (key) {
        'ui_radius' => '999',
        'ui_dim' => '-4',
        'ui_dock_scale' => '99',
        'ui_anim_speed' => '0',
        'ui_accent' => '99',
        'ui_font_scale' => '9',
        'wm_gap' => '-2',
        'security_auto_lock' => '999',
        'security_pin' => '12ab345678999',
        _ => '',
      });
  checkClose('radius clamps', clamped.windowRadius, 26, 0.01);
  checkClose('dim clamps', clamped.wallpaperDim, 0, 0.01);
  checkClose('dock scale clamps', clamped.dockIconScale, 1.4, 0.01);
  checkClose('speed clamps', clamped.animationSpeed, 0.5, 0.01);
  checkEquals('accent clamps', clamped.accentIndex, 5);
  checkClose('font clamps', clamped.fontScale, 1.2, 0.01);
  checkClose('gap clamps', clamped.snapGap, 0, 0.01);
  checkEquals('auto-lock clamps', clamped.autoLockMinutes, 120);
  checkEquals('the pin keeps eight digits', clamped.lockPin, '12345678');

  final broken = DeConfig.fromMap((key, [fallback = '']) => 'garbage');
  checkEquals('garbage falls back to the radius', broken.windowRadius, 16.0);
  checkEquals('garbage falls back to notifications', broken.notificationsEnabled,
      true);
}

void _associations() {
  section('[expa file associations]');
  const table = FileAssociations.standard;
  checkEquals('a text file opens in Notepad', table.appFor('notes.txt'),
      'notepad');
  checkEquals('a picture opens in Paint', table.appFor('photo.PNG'), 'paint');
  checkEquals('an mp3 opens in Musics', table.appFor('song.mp3'), 'musics');
  checkEquals('an html file opens in the browser', table.appFor('page.html'),
      'browser');
  checkEquals('an unknown file stays in Files', table.appFor('archive.zip'),
      'files');
  checkEquals('a dot at the start is not an extension',
      FileAssociations.extensionOf('.gitignore'), '');
  checkEquals('the extension is lowercased',
      FileAssociations.extensionOf(r'C:\A\B.TXT'), 'txt');

  final custom = table.withAssociation('zip', 'files');
  check('a custom extension is kept', custom.byExtension['zip'] == 'files');
  final ignored = table.withAssociation('zip', 'cmd');
  check('a non-built-in app is refused', !ignored.byExtension.containsKey('zip'));

  final map = custom.toMap();
  final back = FileAssociations.fromRead((key, [fallback = '']) => map[key] ?? '');
  check('associations round-trip', back == custom);
  final fallback = FileAssociations.fromRead((key, [fallback = '']) => '');
  check('an empty map is the standard table',
      fallback.byExtension['txt'] == 'notepad');
}

void _notifications() {
  section('[expa notifications]');
  final center = NotificationCenter();
  var changes = 0;
  center.addListener(() => changes++);
  check('starts empty', center.isEmpty && center.unread == 0);

  final first = center.post('Track added', 'ICE', category: 'music');
  final second = center.post('Update available', '1.1.0', category: 'updates');
  checkEquals('two notifications', center.items.length, 2);
  checkEquals('newest first', center.items.first.id, second.id);
  checkEquals('both unread', center.unread, 2);
  check('posting notifies', changes >= 2);

  center.markRead(first);
  checkEquals('one read', center.unread, 1);
  final before = changes;
  center.markRead(first);
  checkEquals('marking twice does not notify', changes, before);

  center.markAllRead();
  checkEquals('all read', center.unread, 0);

  center.remove(second.id);
  checkEquals('remove', center.items.length, 1);
  center.clear();
  check('clear empties', center.isEmpty);
  center.removeListener(() {});
  check('a notification id is unique', second.id != first.id);
}

void _version() {
  section('[expa version]');
  final fromFile = VersionInfo.fromFile(
    'version_1.4.2.txt',
    'version=1.4.2' '\n' 'commit=abc1234' '\n',
  );
  check('the file name is parsed', fromFile != null);
  checkEquals('major', fromFile!.major, 1);
  checkEquals('minor', fromFile.minor, 4);
  checkEquals('patch', fromFile.patch, 2);
  checkEquals('commit', fromFile.commit, 'abc1234');
  check('a versioned asset name is required',
      VersionInfo.fromFile('version.txt', '') == null);

  final tag = VersionInfo.parseTag('v2.0.1');
  check('a tag without v parses', tag != null && tag.version == '2.0.1');
  check('a bad tag is rejected', VersionInfo.parseTag('latest') == null);
  check('1.0.1 is newer than 1.0.0',
      const VersionInfo(1, 0, 1).isNewerThan(const VersionInfo(1, 0, 0)));
  check('1.1.0 is newer than 1.0.9',
      const VersionInfo(1, 1, 0).isNewerThan(const VersionInfo(1, 0, 9)));
  check('the same version is not newer',
      !const VersionInfo(1, 0, 0).isNewerThan(const VersionInfo(1, 0, 0)));

  final release = UpdateService.parseRelease(
      '{"tag_name":"v1.1.0","name":"Spring","body":"Fixes","published_at":"2026-01-02T00:00:00Z"}');
  check('release tag', release?.tag == 'v1.1.0');
  check('release name', release?.name == 'Spring');
  final commit = UpdateService.parseCommit(
      '{"sha":"abcdef1234567","commit":{"message":"fix: music","author":{"date":"2026-01-03T00:00:00Z"}}}');
  check('commit sha', commit?.sha == 'abcdef1234567');
  check('short sha', commit?.shortSha == 'abcdef1');

  final checkResult = UpdateCheck(
    current: const VersionInfo(1, 0, 0, commit: '1111111'),
    release: release,
    commit: commit,
  );
  check('a newer release is seen', checkResult.hasNewerRelease);
  check('a different commit is seen', checkResult.commitDiffers);

  final versionFile = File(versionAsset);
  check('the version file exists', versionFile.existsSync());
  if (versionFile.existsSync()) {
    final parsed = VersionInfo.fromFile(
      versionFile.uri.pathSegments.last,
      versionFile.readAsStringSync(),
    );
    check('the version file parses', parsed != null);
    checkEquals('the version file matches the constant',
        parsed?.version, appVersion.version);
    checkEquals('the version file commit matches',
        parsed?.commit, appVersion.commit);
  }
}

void _clipboard() {
  section('[expa clipboard history]');
  final history = ClipboardHistory();
  final first = history.add('hello', at: DateTime(2026));
  history.add('world', at: DateTime(2026, 1, 2));
  checkEquals('two entries', history.entries.length, 2);
  checkEquals('newest first', history.entries.first.text, 'world');

  history.add('hello', at: DateTime(2026, 1, 3));
  checkEquals('a repeat moves, not duplicates', history.entries.length, 2);
  checkEquals('the repeat is now first', history.entries.first.text, 'hello');

  history.togglePin(first);
  check('pin toggles', first.pinned);
  for (var i = 0; i < ClipboardHistory.maxEntries + 5; i++) {
    history.add('item-');
  }
  check('the history is capped', history.entries.length <= ClipboardHistory.maxEntries);
  check('the pinned entry survives the trim',
      history.entries.any((entry) => entry.pinned));

  final json = history.toJson();
  final restored = ClipboardHistory.fromJson(json);
  checkEquals('the JSON round-trip keeps the count',
      restored.entries.length, history.entries.length);
  checkEquals('the round-trip keeps the text',
      restored.entries.first.text, history.entries.first.text);
  history.clear();
  check('clear', history.isEmpty);
}

void _calendar() {
  section('[expa calendar]');
  final grid = monthGrid(DateTime(2026, 10));
  checkEquals('six weeks', grid.length, 42);
  checkEquals('starts on Monday', grid.first.date.weekday, DateTime.monday);
  check('the first week includes the previous month', !grid.first.inMonth);
  check('October 1 is in the grid',
      grid.any((cell) => cell.inMonth && cell.date.day == 1));
  check('October 31 is in the grid',
      grid.any((cell) => cell.inMonth && cell.date.day == 31));
  check('Monday is the first weekday name', weekdayName(1) == 'Monday');
  check('October is the tenth month', monthName(10) == 'October');
  check('same-day comparison',
      isSameDay(DateTime(2026, 10, 23), DateTime(2026, 10, 23)));
  check('different days are not equal',
      !isSameDay(DateTime(2026, 10, 23), DateTime(2026, 10, 24)));

  final next = addMonths(DateTime(2026, 12), 1);
  checkEquals('month arithmetic rolls the year', next.year, 2027);
  checkEquals('month arithmetic rolls to January', next.month, 1);
}

void _drives() {
  section('[expa drives]');
  final drives = parseDrivesJson(
      '[{"DeviceID":"C:","VolumeName":"System","Size":100000000000,"FreeSpace":40000000000},'
      '{"DeviceID":"D:","VolumeName":"","Size":200000000000,"FreeSpace":100000000000}]');
  checkEquals('two drives', drives.length, 2);
  checkEquals('sorted by letter', drives.first.id, 'C:');
  checkEquals('the label falls back to the id', drives[1].label, 'D:');
  checkClose('used fraction', drives.first.usedFraction, 0.6, 0.001);
  check('the size text mentions GB',
      drives.first.sizeText.contains('GB'));
  check('garbage is empty', parseDrivesJson('not json').isEmpty);
  check('an empty list parses', parseDrivesJson('[]').isEmpty);
}

void _input() {
  section('[expa input settings]');
  final source = _FakeInputSource()
    ..mouseSpeed = 8
    ..mouseSwap = true
    ..wheelLines = 5
    ..keyDelay = 2
    ..keySpeed = 20;
  final settings = InputSettings(source)..load();
  checkEquals('speed loaded', settings.mouseSpeed, 8);
  check('swap loaded', settings.mouseSwap);
  checkEquals('wheel loaded', settings.wheelLines, 5);

  settings.updateMouseSpeed(99);
  checkEquals('speed clamps', settings.mouseSpeed, 20);
  checkEquals('the source got the clamped speed', source.mouseSpeed, 20);
  settings.updateKeyDelay(-4);
  checkEquals('delay clamps', settings.keyDelay, 0);
  settings.updateKeySpeed(99);
  checkEquals('rate clamps', settings.keySpeed, 31);
  settings.updateMouseSwap(false);
  check('swap writes', source.mouseSwap == false);

  final empty = InputSettings(_FakeInputSource())..load();
  checkEquals('an unavailable source keeps the default',
      empty.mouseSpeed, 10);
}

class _FakeInputSource implements InputSource {
  @override
  int? mouseSpeed;
  @override
  bool? mouseSwap;
  @override
  int? wheelLines;
  @override
  int? keyDelay;
  @override
  int? keySpeed;

  @override
  void setMouseSpeed(int value) => mouseSpeed = value;
  @override
  void setMouseSwap(bool value) => mouseSwap = value;
  @override
  void setWheelLines(int value) => wheelLines = value;
  @override
  void setKeyDelay(int value) => keyDelay = value;
  @override
  void setKeySpeed(int value) => keySpeed = value;
}

void main() {
  runExpaChecks();
  finish('expa');
}