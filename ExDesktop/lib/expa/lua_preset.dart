// EXPA presets are Lua files. This is a deliberately small, safe Lua subset:
// comments, local variables, assignments, return, and tables of literals.
// There is no interpreter, no I/O and no function call — a preset cannot do
// anything except describe a desktop.
//
// A file looks like:
//
//   -- Midnight Glass
//   local preset = {
//     name = "Midnight Glass",
//     description = "Deep blue glass with soft motion",
//     accent = "sky",
//     radius = 18,
//     dim = 0.22,
//     dock = 1.05,
//     animation_speed = 1.0,
//     animations = true,
//     snap = true,
//     gap = 6,
//     notifications = true,
//     clock_seconds = false,
//     font_scale = 1.0,
//     auto_lock = 10,
//   }
//   return preset
//
// Imported .zip packs may contain one or more .lua files; each becomes a
// preset. Unknown fields are reported as warnings, not silently applied.

import 'de_config.dart';

class LuaPresetException implements Exception {
  final String message;
  final int line;
  final int column;

  const LuaPresetException(this.message, this.line, this.column);

  @override
  String toString() => 'Lua error at line $line:$column: $message';
}

class LuaPreset {
  final String name;
  final String description;
  final DeConfig config;
  final String source;
  final bool builtIn;
  final bool imported;
  final List<String> warnings;

  const LuaPreset({
    required this.name,
    required this.description,
    required this.config,
    required this.source,
    this.builtIn = false,
    this.imported = false,
    this.warnings = const [],
  });

  static LuaPreset parse(
    String source, {
    String fallbackName = 'Preset',
    bool builtIn = false,
    bool imported = false,
  }) {
    final table = _LuaParser(source).parseChunk();
    return _fromTable(
      table,
      source: source,
      fallbackName: fallbackName,
      builtIn: builtIn,
      imported: imported,
    );
  }

  static const Map<String, int> accentNames = {
    'sky': 0,
    'rose': 1,
    'mint': 2,
    'peach': 3,
    'lavender': 4,
    'frost': 5,
  };

  static LuaPreset _fromTable(
    Map<String, Object?> table, {
    required String source,
    required String fallbackName,
    required bool builtIn,
    required bool imported,
  }) {
    final warnings = <String>[];
    final prefs = <String, String>{};

    final rawName = table['name'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : fallbackName;
    final rawDescription = table['description'];
    final description = rawDescription is String ? rawDescription.trim() : '';

    void number(String key, String pref) {
      final value = table[key];
      if (value == null) return;
      if (value is num) {
        prefs[pref] = '$value';
      } else {
        throw LuaPresetException('$key must be a number', 1, 1);
      }
    }

    void boolean(String key, String pref) {
      final value = table[key];
      if (value == null) return;
      if (value is bool) {
        prefs[pref] = value ? '1' : '0';
      } else {
        throw LuaPresetException('$key must be true or false', 1, 1);
      }
    }

    final accent = table['accent'];
    if (accent != null) {
      if (accent is num) {
        prefs['ui_accent'] = '${accent.toInt()}';
      } else if (accent is String && accentNames.containsKey(accent)) {
        prefs['ui_accent'] = '${accentNames[accent]}';
      } else {
        throw LuaPresetException(
          'accent must be a number or one of '
          '${accentNames.keys.join(', ')}',
          1,
          1,
        );
      }
    }

    number('radius', 'ui_radius');
    number('window_radius', 'ui_radius');
    number('dim', 'ui_dim');
    number('wallpaper_dim', 'ui_dim');
    number('dock', 'ui_dock_scale');
    number('dock_scale', 'ui_dock_scale');
    number('animation_speed', 'ui_anim_speed');
    number('speed', 'ui_anim_speed');
    number('gap', 'wm_gap');
    number('font_scale', 'ui_font_scale');
    number('auto_lock', 'security_auto_lock');

    boolean('animations', 'ui_animations');
    boolean('snap', 'wm_snap');
    boolean('notifications', 'notif_enabled');
    boolean('clock_seconds', 'ui_clock_seconds');

    const known = {
      'name',
      'description',
      'accent',
      'radius',
      'window_radius',
      'dim',
      'wallpaper_dim',
      'dock',
      'dock_scale',
      'animation_speed',
      'speed',
      'gap',
      'font_scale',
      'auto_lock',
      'animations',
      'snap',
      'notifications',
      'clock_seconds',
    };
    for (final key in table.keys) {
      if (!known.contains(key)) warnings.add('Unknown field "$key" was ignored');
    }

    final config = DeConfig.fromMap(
      (key, [fallback = '']) => prefs[key] ?? fallback,
    );
    return LuaPreset(
      name: name,
      description: description,
      config: config,
      source: source,
      builtIn: builtIn,
      imported: imported,
      warnings: List.unmodifiable(warnings),
    );
  }

  bool get isCustom => !builtIn && !imported;
}

/// Serializes a desktop config as a valid preset in the same Lua subset.
String presetToLua(
  DeConfig config, {
  String name = 'My look',
  String description = 'Written in the Configs editor',
}) {
  String quote(String value) => "'${value
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n')}'";

  return '''
-- EXpaDesktop preset (Lua config)
-- Edit the values and press Apply, or save it as a named preset.
return {
  name = ${quote(name)},
  description = ${quote(description)},
  accent = ${config.accentIndex}, -- sky, rose, mint, peach, lavender, frost
  radius = ${config.windowRadius},
  dim = ${config.wallpaperDim},
  dock = ${config.dockIconScale},
  animation_speed = ${config.animationSpeed},
  animations = ${config.animationsEnabled},
  snap = ${config.snapEnabled},
  gap = ${config.snapGap},
  notifications = ${config.notificationsEnabled},
  clock_seconds = ${config.clockSeconds},
  font_scale = ${config.fontScale},
  auto_lock = ${config.autoLockMinutes},
}
''';
}

// ---- lexer -----------------------------------------------------------------

enum _Kind { identifier, number, string, symbol, eof }

class _Token {
  final _Kind kind;
  final String text;
  final Object? value;
  final int line;
  final int column;

  const _Token(this.kind, this.text, this.line, this.column, {this.value});
}

class _Lexer {
  _Lexer(this.source);

  final String source;
  int _index = 0;
  int _line = 1;
  int _column = 1;

  List<_Token> scan() {
    final tokens = <_Token>[];
    while (true) {
      _skipWhitespaceAndComments();
      if (_index >= source.length) {
        tokens.add(_Token(_Kind.eof, '', _line, _column));
        return tokens;
      }
      final startLine = _line;
      final startColumn = _column;
      final char = source[_index];
      if (char == "'" || char == '"') {
        tokens.add(_string(char, startLine, startColumn));
      } else if (_isDigit(char) ||
          (char == '-' && _isDigit(_peek(1)))) {
        tokens.add(_number(startLine, startColumn));
      } else if (_isIdentifierStart(char)) {
        final start = _index;
        while (_isIdentifierPart(_peek(0))) {
          _advance();
        }
        tokens.add(_Token(
          _Kind.identifier,
          source.substring(start, _index),
          startLine,
          startColumn,
        ));
      } else if ('{}[]=,;'.contains(char)) {
        _advance();
        tokens.add(_Token(_Kind.symbol, char, startLine, startColumn));
      } else {
        throw LuaPresetException(
          'Unexpected character "$char"',
          startLine,
          startColumn,
        );
      }
    }
  }

  _Token _string(String quote, int line, int column) {
    _advance(); // opening quote
    final buffer = StringBuffer();
    while (_index < source.length) {
      final char = source[_index];
      if (char == quote) {
        _advance();
        return _Token(_Kind.string, buffer.toString(), line, column,
            value: buffer.toString());
      }
      if (char == '\\') {
        _advance();
        if (_index >= source.length) break;
        final escaped = source[_index];
        buffer.write(switch (escaped) {
          'n' => '\n',
          't' => '\t',
          'r' => '\r',
          '\\' => '\\',
          '"' => '"',
          "'" => "'",
          _ => escaped,
        });
        _advance();
        continue;
      }
      if (char == '\n') {
        throw LuaPresetException('Unterminated string', line, column);
      }
      buffer.write(char);
      _advance();
    }
    throw LuaPresetException('Unterminated string', line, column);
  }

  _Token _number(int line, int column) {
    final start = _index;
    if (_peek(0) == '-') _advance();
    while (_isDigit(_peek(0))) {
      _advance();
    }
    if (_peek(0) == '.' && _isDigit(_peek(1))) {
      _advance();
      while (_isDigit(_peek(0))) {
        _advance();
      }
    }
    final text = source.substring(start, _index);
    final value = text.contains('.') ? double.parse(text) : int.parse(text);
    return _Token(_Kind.number, text, line, column, value: value);
  }

  void _skipWhitespaceAndComments() {
    while (_index < source.length) {
      final char = source[_index];
      if (char.trim().isEmpty) {
        _advance();
        continue;
      }
      if (char == '-' && _peek(1) == '-') {
        _advance();
        _advance();
        if (_peek(0) == '[' && _peek(1) == '[') {
          _advance();
          _advance();
          while (_index < source.length &&
              !(_peek(0) == ']' && _peek(1) == ']')) {
            _advance();
          }
          if (_index < source.length) {
            _advance();
            _advance();
          }
        } else {
          while (_index < source.length && source[_index] != '\n') {
            _advance();
          }
        }
        continue;
      }
      return;
    }
  }

  String _peek(int offset) {
    final index = _index + offset;
    return index < source.length ? source[index] : '';
  }

  void _advance() {
    if (_index >= source.length) return;
    if (source[_index] == '\n') {
      _line++;
      _column = 1;
    } else {
      _column++;
    }
    _index++;
  }

  static bool _isDigit(String char) =>
      char.isNotEmpty && char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;

  static bool _isIdentifierStart(String char) =>
      char.isNotEmpty &&
      ((char.codeUnitAt(0) >= 65 && char.codeUnitAt(0) <= 90) ||
          (char.codeUnitAt(0) >= 97 && char.codeUnitAt(0) <= 122) ||
          char == '_');

  static bool _isIdentifierPart(String char) =>
      _isIdentifierStart(char) || _isDigit(char);
}

// ---- parser ----------------------------------------------------------------

class _LuaParser {
  _LuaParser(String source) : _tokens = _Lexer(source).scan();

  final List<_Token> _tokens;
  int _position = 0;

  Map<String, Object?> parseChunk() {
    final variables = <String, Object?>{};
    Object? result;
    while (!_atEnd) {
      if (_matchKeyword('local')) {
        final name = _expectIdentifier();
        _expectSymbol('=');
        result = _value(variables);
        variables[name] = result;
      } else if (_check(_Kind.identifier) && _peek(1).text == '=') {
        final name = _advance().text;
        _expectSymbol('=');
        result = _value(variables);
        variables[name] = result;
      } else if (_matchKeyword('return')) {
        result = _value(variables);
        break;
      } else {
        result = _value(variables);
        break;
      }
      _matchSymbol(';');
    }
    if (result is Map<String, Object?>) return result;
    throw _error('Expected a preset table');
  }

  Object? _value(Map<String, Object?> variables) {
    if (_matchSymbol('{')) return _table(variables);
    if (_check(_Kind.number)) return _advance().value;
    if (_check(_Kind.string)) return _advance().value;
    if (_matchSymbol('-')) {
      final token = _advance();
      if (token.kind != _Kind.number) {
        throw _error('Expected a number after -');
      }
      return -(token.value as num);
    }
    if (_matchKeyword('true')) return true;
    if (_matchKeyword('false')) return false;
    if (_matchKeyword('nil')) return null;
    if (_check(_Kind.identifier)) {
      final name = _advance().text;
      if (!variables.containsKey(name)) {
        throw _error('Unknown variable "$name"');
      }
      return variables[name];
    }
    throw _error('Expected a value');
  }

  Map<String, Object?> _table(Map<String, Object?> variables) {
    final table = <String, Object?>{};
    while (!_checkSymbol('}')) {
      final String key;
      if (_matchSymbol('[')) {
        final keyValue = _value(variables);
        if (keyValue is! String) {
          throw _error('A field key must be a string');
        }
        key = keyValue;
        _expectSymbol(']');
        _expectSymbol('=');
      } else if (_check(_Kind.identifier) && _peek(1).text == '=') {
        key = _advance().text;
        _expectSymbol('=');
      } else {
        throw _error('Expected "name = value" or ["name"] = value');
      }
      table[key] = _value(variables);
      if (!_matchSymbol(',') && !_matchSymbol(';') && !_checkSymbol('}')) {
        throw _error('Expected , or }');
      }
    }
    _expectSymbol('}');
    return table;
  }

  bool get _atEnd => _check(_Kind.eof);

  bool _check(_Kind kind) => _peek(0).kind == kind;

  bool _checkSymbol(String symbol) =>
      _peek(0).kind == _Kind.symbol && _peek(0).text == symbol;

  bool _matchSymbol(String symbol) {
    if (!_checkSymbol(symbol)) return false;
    _advance();
    return true;
  }

  bool _matchKeyword(String word) {
    if (_peek(0).kind != _Kind.identifier || _peek(0).text != word) {
      return false;
    }
    _advance();
    return true;
  }

  _Token _advance() {
    final token = _tokens[_position];
    if (!_atEnd) _position++;
    return token;
  }

  _Token _peek(int offset) {
    final index = (_position + offset).clamp(0, _tokens.length - 1);
    return _tokens[index];
  }

  String _expectIdentifier() {
    if (_peek(0).kind != _Kind.identifier) {
      throw _error('Expected a variable name');
    }
    return _advance().text;
  }

  void _expectSymbol(String symbol) {
    if (!_matchSymbol(symbol)) throw _error('Expected "$symbol"');
  }

  LuaPresetException _error(String message) {
    final token = _peek(0);
    return LuaPresetException(message, token.line, token.column);
  }
}