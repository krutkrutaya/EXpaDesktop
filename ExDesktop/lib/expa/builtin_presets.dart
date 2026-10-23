// The presets that ship with EXPA. They are real Lua files (sources, not
// hand-built DeConfig objects), parsed through the same safe subset as an
// imported .zip. One bad built-in therefore fails the mock suite immediately.

import 'lua_preset.dart';

const String midnightGlassLua = '''
-- Midnight Glass: deep blue glass, gentle motion.
local preset = {
  name = "Midnight Glass",
  description = "Deep blue glass with soft, slow motion",
  accent = "sky",
  radius = 18,
  dim = 0.22,
  dock = 1.05,
  animation_speed = 0.95,
  animations = true,
  snap = true,
  gap = 6,
  notifications = true,
  clock_seconds = false,
  font_scale = 1.0,
  auto_lock = 10,
}
return preset
''';

const String neonBloomLua = '''
-- Neon Bloom: rose accent, quicker springs.
local preset = {
  name = "Neon Bloom",
  description = "Rose light, tight gaps and quick springs",
  accent = "rose",
  radius = 22,
  dim = 0.12,
  dock = 1.15,
  animation_speed = 1.35,
  animations = true,
  snap = true,
  gap = 4,
  notifications = true,
  clock_seconds = true,
  font_scale = 1.0,
  auto_lock = 5,
}
return preset
''';

const String mintPaperLua = '''
-- Mint Paper: flat and quiet, no motion.
local preset = {
  name = "Mint Paper",
  description = "Flat mint surfaces, square edges, no animations",
  accent = "mint",
  radius = 10,
  dim = 0,
  dock = 0.9,
  animation_speed = 1.0,
  animations = false,
  snap = true,
  gap = 0,
  notifications = true,
  clock_seconds = false,
  font_scale = 1.05,
  auto_lock = 0,
}
return preset
''';

const String frostedMonoLua = '''
-- Frosted Mono: frost accent, a dim, dense desktop.
local preset = {
  name = "Frosted Mono",
  description = "Frosted monochrome with a deep dim and compact dock",
  accent = "frost",
  radius = 14,
  dim = 0.35,
  dock = 1.0,
  animation_speed = 0.8,
  animations = true,
  snap = true,
  gap = 8,
  notifications = false,
  clock_seconds = false,
  font_scale = 0.95,
  auto_lock = 20,
}
return preset
''';

/// Parses the built-ins. Throws when a shipped preset is malformed, which is
/// exactly what the tests should catch.
List<LuaPreset> builtInPresets() => [
      LuaPreset.parse(midnightGlassLua, fallbackName: 'Midnight Glass', builtIn: true),
      LuaPreset.parse(neonBloomLua, fallbackName: 'Neon Bloom', builtIn: true),
      LuaPreset.parse(mintPaperLua, fallbackName: 'Mint Paper', builtIn: true),
      LuaPreset.parse(frostedMonoLua, fallbackName: 'Frosted Mono', builtIn: true),
    ];