// Preset persistence and .zip import.
//
// A pack is a zip of one or more .lua files (nested folders are fine). They
// are decoded in memory; nothing is extracted to disk and nothing is executed.
// Limits keep a hostile archive from exhausting the desktop.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'builtin_presets.dart';
import 'lua_preset.dart';

class PresetImportResult {
  final List<LuaPreset> presets;
  final List<String> errors;

  const PresetImportResult(this.presets, this.errors);

  bool get isEmpty => presets.isEmpty;
}

class PresetStore {
  PresetStore({String? root}) : _root = root;

  static const int maxEntries = 50;
  static const int maxLuaBytes = 256 * 1024;
  static const int maxZipBytes = 4 * 1024 * 1024;

  final String? _root;

  bool get _memory =>
      _root == null && Platform.environment['FLUTTER_TEST'] == 'true';

  String get rootDir {
    final explicit = _root;
    if (explicit != null) return explicit;
    final appData = Platform.environment['APPDATA'];
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final base = (appData == null || appData.isEmpty) ? home : appData;
    return '$base${Platform.pathSeparator}EXpaDesktop';
  }

  String get path => '$rootDir${Platform.pathSeparator}presets.json';

  /// Built-ins first, then the user's/imported presets from disk.
  List<LuaPreset> loadAll() => [...builtInPresets(), ...loadCustom()];

  List<LuaPreset> loadCustom() {
    if (_memory) return const [];
    try {
      final file = File(path);
      if (!file.existsSync()) return const [];
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) return const [];
      final presets = <LuaPreset>[];
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final source = '${raw['source'] ?? ''}';
        if (source.trim().isEmpty) continue;
        try {
          presets.add(LuaPreset.parse(
            source,
            imported: raw['imported'] == true,
          ));
        } catch (_) {
          // A stale/corrupt saved preset is skipped, not fatal.
        }
      }
      return presets;
    } catch (_) {
      return const [];
    }
  }

  void saveCustom(List<LuaPreset> presets) {
    if (_memory) return;
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final payload = [
        for (final preset in presets)
          if (!preset.builtIn)
            {'source': preset.source, 'imported': preset.imported},
      ];
      final temp = File('${file.path}.tmp');
      temp.writeAsStringSync(jsonEncode(payload), flush: true);
      if (file.existsSync()) file.deleteSync();
      temp.renameSync(file.path);
    } catch (_) {
      // A read-only profile keeps the presets in memory for this session.
    }
  }

  Future<PresetImportResult> importZip(String archivePath) async {
    try {
      final file = File(archivePath);
      if (!file.existsSync()) {
        return const PresetImportResult([], ['The archive does not exist.']);
      }
      // Sync on purpose: the file is small and this keeps the widget test's
      // fake-async timeline deterministic.
      final bytes = file.readAsBytesSync();
      return importBytes(bytes);
    } catch (error) {
      return PresetImportResult([], ['Could not read the archive: $error']);
    }
  }

  static PresetImportResult importBytes(List<int> bytes) {
    if (bytes.length > maxZipBytes) {
      return const PresetImportResult(
          [], ['The archive is larger than 4 MB.']);
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (error) {
      return PresetImportResult([], ['Not a readable .zip: $error']);
    }

    final presets = <LuaPreset>[];
    final errors = <String>[];
    var seen = 0;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (!file.name.toLowerCase().endsWith('.lua')) continue;
      seen++;
      if (seen > maxEntries) {
        errors.add('Stopped after $maxEntries Lua files.');
        break;
      }
      if (file.size > maxLuaBytes) {
        errors.add('${file.name}: larger than 256 KB, skipped.');
        continue;
      }
      try {
        final content = file.content;
        final byteList = content is List<int>
            ? content
            : content is List
                ? content.cast<int>()
                : const <int>[];
        final source = utf8.decode(byteList, allowMalformed: false);
        final base = file.name
            .split('/')
            .last
            .replaceAll(RegExp(r'\.lua$', caseSensitive: false), '');
        final preset = LuaPreset.parse(
          source,
          fallbackName: base.isEmpty ? 'Imported preset' : base,
          imported: true,
        );
        presets.add(preset);
        if (preset.warnings.isNotEmpty) {
          errors.addAll(preset.warnings.map((w) => '${file.name}: $w'));
        }
      } on LuaPresetException catch (error) {
        errors.add('${file.name}: $error');
      } catch (error) {
        errors.add('${file.name}: $error');
      }
    }
    if (seen == 0) {
      errors.add('No .lua files were found in the archive.');
    }
    return PresetImportResult(presets, errors);
  }
}