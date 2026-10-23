// The Lua preset subset, the built-in pack, and .zip import. Pure Dart; it
// runs with the other mock suites and never touches the network.

// Standalone script: bare print is its logging.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:exp_desktop/expa/builtin_presets.dart';
import 'package:exp_desktop/expa/de_config.dart';
import 'package:exp_desktop/expa/lua_preset.dart';
import 'package:exp_desktop/expa/preset_store.dart';

import 'mock_harness.dart';

void runLuaPresetChecks() {
  _builtIns();
  _parsing();
  _roundTrip();
  _zip();
  _store();
}

void _builtIns() {
  section('[lua built-ins]');
  final presets = builtInPresets();
  checkEquals('four built-in presets', presets.length, 4);
  check('all built-ins parsed', presets.every((p) => p.builtIn));
  check('names are unique', presets.map((p) => p.name).toSet().length == 4);
  check('Midnight Glass is present',
      presets.any((p) => p.name == 'Midnight Glass'));
  final midnight = presets.firstWhere((p) => p.name == 'Midnight Glass');
  checkEquals('the accent is sky', midnight.config.accentIndex, 0);
  checkClose('the radius comes from Lua', midnight.config.windowRadius, 18, 0.001);
  checkClose('the dim comes from Lua', midnight.config.wallpaperDim, 0.22, 0.001);
  check('the built-ins carry no warnings',
      presets.every((p) => p.warnings.isEmpty));
}

void _parsing() {
  section('[lua parser]');
  const source = '''
-- a comment
local preset = {
  name = 'Test Look',
  description = "Soft",
  accent = "rose",
  radius = 20,
  dim = 0.3,
  dock = 1.2,
  animation_speed = 1.4,
  animations = true,
  snap = false,
  gap = 12,
  notifications = false,
  clock_seconds = true,
  font_scale = 1.1,
  auto_lock = 30,
  ["extra-quote"] = 'ok',
}
return preset
''';
  final preset = LuaPreset.parse(source, fallbackName: 'fallback');
  checkEquals('the name is read', preset.name, 'Test Look');
  checkEquals('the description is read', preset.description, 'Soft');
  checkEquals('the accent name is read', preset.config.accentIndex, 1);
  checkClose('the radius is read', preset.config.windowRadius, 20, 0.001);
  checkClose('the dim is read', preset.config.wallpaperDim, 0.3, 0.001);
  checkClose('the dock is read', preset.config.dockIconScale, 1.2, 0.001);
  checkClose('the speed is read', preset.config.animationSpeed, 1.4, 0.001);
  check('animations is true', preset.config.animationsEnabled);
  check('snap is false', !preset.config.snapEnabled);
  checkClose('the gap is read', preset.config.snapGap, 12, 0.001);
  check('notifications is false', !preset.config.notificationsEnabled);
  check('clock seconds is true', preset.config.clockSeconds);
  checkClose('the font scale is read', preset.config.fontScale, 1.1, 0.001);
  checkEquals('auto-lock is read', preset.config.autoLockMinutes, 30);
  check('the unknown key is reported', preset.warnings.length == 1);

  const clamped = '''
return {
  name = "Clamp",
  radius = 999,
  dim = -4,
  dock = 99,
  animation_speed = 0,
  gap = -8,
  font_scale = 9,
  auto_lock = 999,
  accent = 99,
}
''';
  final clampedPreset = LuaPreset.parse(clamped);
  checkClose('the radius is clamped', clampedPreset.config.windowRadius, 26, 0.001);
  checkClose('the dim is clamped', clampedPreset.config.wallpaperDim, 0, 0.001);
  checkClose('the dock is clamped', clampedPreset.config.dockIconScale, 1.4, 0.001);
  checkClose('the speed is clamped', clampedPreset.config.animationSpeed, 0.5, 0.001);
  checkClose('the gap is clamped', clampedPreset.config.snapGap, 0, 0.001);
  checkClose('the font is clamped', clampedPreset.config.fontScale, 1.2, 0.001);
  checkEquals('the accent is clamped', clampedPreset.config.accentIndex, 5);
  checkEquals('the lock is clamped', clampedPreset.config.autoLockMinutes, 120);

  for (final (label, bad) in [
    ('a missing brace', 'return { name = "x"'),
    ('a non-table result', 'return 42'),
    ('an unterminated string', 'return { name = "x }'),
    ('an unknown variable', 'return preset'),
    ('a bad field value', 'return { animations = "yes" }'),
    ('a bad accent name', 'return { accent = "purple" }'),
  ]) {
    try {
      LuaPreset.parse(bad, fallbackName: 'bad');
      check('$label is rejected', false);
    } on LuaPresetException {
      check('$label is rejected', true);
    }
  }
}

void _roundTrip() {
  section('[lua serializer]');
  const config = DeConfig(
    accentIndex: 3,
    windowRadius: 21,
    wallpaperDim: 0.4,
    dockIconScale: 1.1,
    animationSpeed: 1.25,
    animationsEnabled: false,
    snapEnabled: true,
    snapGap: 9,
    notificationsEnabled: false,
    clockSeconds: true,
    fontScale: 1.05,
    autoLockMinutes: 15,
  );
  final source = presetToLua(config, name: 'Round trip', description: 'It is "good"');
  check('the serializer keeps the double quotes',
      source.contains('It is "good"'));
  final parsed = LuaPreset.parse(source);
  checkEquals('the accent survives', parsed.config.accentIndex, 3);
  checkClose('the radius survives', parsed.config.windowRadius, 21, 0.001);
  checkClose('the dim survives', parsed.config.wallpaperDim, 0.4, 0.001);
  check('animations survive', !parsed.config.animationsEnabled);
  check('notifications survive', !parsed.config.notificationsEnabled);
  check('clock seconds survive', parsed.config.clockSeconds);
  checkEquals('auto-lock survives', parsed.config.autoLockMinutes, 15);
}

List<int> _zipBytes(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive)!;
}

void _zip() {
  section('[preset zip]');
  final bytes = _zipBytes({
    'packs/Glow.lua': '''
return {
  name = "Glow",
  description = "Imported",
  accent = "peach",
  radius = 16,
  animations = true,
}
''',
    'notes.txt': 'not a preset',
    'broken.lua': 'return { name = ',
  });
  final result = PresetStore.importBytes(bytes);
  checkEquals('one good preset imported', result.presets.length, 1);
  checkEquals('the imported name', result.presets.first.name, 'Glow');
  check('the imported flag is set', result.presets.first.imported);
  check('the broken file is reported', result.errors.any((e) => e.contains('broken.lua')));
  check('the non-lua file is ignored', !result.errors.any((e) => e.contains('notes.txt')));

  final empty = PresetStore.importBytes(_zipBytes({'readme.md': 'hi'}));
  check('a zip without Lua is rejected', empty.presets.isEmpty);
  check('the missing Lua error is clear',
      empty.errors.any((e) => e.contains('No .lua files')));

  final notZip = PresetStore.importBytes(utf8.encode('hello'));
  check('a non-zip is rejected', notZip.presets.isEmpty);
}

void _store() {
  section('[preset store]');
  final dir = Directory.systemTemp.createTempSync('expa_presets');
  try {
    final store = PresetStore(root: dir.path);
    final preset = LuaPreset.parse('''
return {
  name = "Saved",
  accent = "mint",
  radius = 12,
}
''');
    store.saveCustom([preset]);
    final loaded = store.loadCustom();
    checkEquals('one custom preset loaded', loaded.length, 1);
    checkEquals('the name round-trips', loaded.first.name, 'Saved');
    checkEquals('the accent round-trips', loaded.first.config.accentIndex, 2);
    final all = store.loadAll();
    check('loadAll includes the built-ins', all.length == 5);
    check('the built-ins stay built-in', all.first.builtIn);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  runLuaPresetChecks();
  finish('lua presets');
}