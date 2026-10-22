// The Dart side of sysctl.dll.
//
// One binding object, one lazy load, and small parsers for the JSON the Rust
// backend emits. Every call returns null / an empty list when the DLL is not
// built for this checkout: the shell then keeps its visual state and simply
// cannot change the machine, exactly like the brightness DLL.
//
// The JSON parsers are pure and covered by test/system_check.dart, so the
// shapes are verified on CI where the native library is absent.

import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

// ---- C signatures -----------------------------------------------------------

typedef _F32VoidNative = Double Function();
typedef _F32VoidDart = double Function();
typedef _I32F32Native = Int32 Function(Double);
typedef _I32F32Dart = int Function(double);
typedef _I32I32Native = Int32 Function(Int32);
typedef _I32I32Dart = int Function(int);
typedef _I32VoidNative = Int32 Function();
typedef _I32VoidDart = int Function();
typedef _U32VoidNative = Uint32 Function();
typedef _U32VoidDart = int Function();
typedef _I32BoolNative = Int32 Function(Int32);
typedef _I32BoolDart = int Function(int);
typedef _StrVoidNative = Pointer<Utf8> Function();
typedef _StrVoidDart = Pointer<Utf8> Function();
typedef _I32StrNative = Int32 Function(Pointer<Utf8>);
typedef _I32StrDart = int Function(Pointer<Utf8>);
typedef _I32PidF32Native = Int32 Function(Uint32, Double);
typedef _I32PidF32Dart = int Function(int, double);
typedef _I32PidBoolNative = Int32 Function(Uint32, Int32);
typedef _I32PidBoolDart = int Function(int, int);
typedef _ConnectNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32, Int32);
typedef _ConnectDart = int Function(Pointer<Utf8>, Pointer<Utf8>, int, int);
typedef _DisplayNative = Int32 Function(Uint32, Uint32, Uint32, Int32);
typedef _DisplayDart = int Function(int, int, int, int);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

class _Bindings {
  final _F32VoidDart masterVolumeGet;
  final _I32F32Dart masterVolumeSet;
  final _I32VoidDart masterMuteGet;
  final _I32BoolDart masterMuteSet;
  final _StrVoidDart sessionsJson;
  final _I32PidF32Dart sessionVolume;
  final _I32PidBoolDart sessionMute;
  final _I32VoidDart mouseSpeedGet;
  final _I32I32Dart mouseSpeedSet;
  final _I32VoidDart mouseSwapGet;
  final _I32I32Dart mouseSwapSet;
  final _I32VoidDart wheelLinesGet;
  final _I32I32Dart wheelLinesSet;
  final _I32VoidDart keyboardDelayGet;
  final _I32I32Dart keyboardDelaySet;
  final _I32VoidDart keyboardSpeedGet;
  final _I32I32Dart keyboardSpeedSet;
  final _StrVoidDart wifiJson;
  final _ConnectDart wifiConnect;
  final _I32VoidDart wifiDisconnect;
  final _StrVoidDart displayJson;
  final _DisplayDart displayApply;
  final _StrVoidDart timezonesJson;
  final _I32StrDart timezoneOffset;
  final _U32VoidDart clipboardSequence;
  final _StrVoidDart clipboardText;
  final _I32StrDart clipboardSet;
  final _I32VoidDart clipboardClear;
  final _FreeDart freeString;

  _Bindings(DynamicLibrary library)
      : masterVolumeGet = library.lookupFunction<_F32VoidNative, _F32VoidDart>(
            'master_volume_get'),
        masterVolumeSet = library.lookupFunction<_I32F32Native, _I32F32Dart>(
            'master_volume_set'),
        masterMuteGet = library.lookupFunction<_I32VoidNative, _I32VoidDart>(
            'master_mute_get'),
        masterMuteSet = library.lookupFunction<_I32BoolNative, _I32BoolDart>(
            'master_mute_set'),
        sessionsJson = library.lookupFunction<_StrVoidNative, _StrVoidDart>(
            'audio_sessions_json'),
        sessionVolume = library
            .lookupFunction<_I32PidF32Native, _I32PidF32Dart>(
                'audio_session_set_volume'),
        sessionMute = library
            .lookupFunction<_I32PidBoolNative, _I32PidBoolDart>(
                'audio_session_set_mute'),
        mouseSpeedGet = library
            .lookupFunction<_I32VoidNative, _I32VoidDart>('mouse_speed_get'),
        mouseSpeedSet = library
            .lookupFunction<_I32I32Native, _I32I32Dart>('mouse_speed_set'),
        mouseSwapGet = library
            .lookupFunction<_I32VoidNative, _I32VoidDart>('mouse_swap_get'),
        mouseSwapSet = library
            .lookupFunction<_I32I32Native, _I32I32Dart>('mouse_swap_set'),
        wheelLinesGet = library
            .lookupFunction<_I32VoidNative, _I32VoidDart>('wheel_lines_get'),
        wheelLinesSet = library
            .lookupFunction<_I32I32Native, _I32I32Dart>('wheel_lines_set'),
        keyboardDelayGet = library
            .lookupFunction<_I32VoidNative, _I32VoidDart>('keyboard_delay_get'),
        keyboardDelaySet = library
            .lookupFunction<_I32I32Native, _I32I32Dart>('keyboard_delay_set'),
        keyboardSpeedGet = library
            .lookupFunction<_I32VoidNative, _I32VoidDart>('keyboard_speed_get'),
        keyboardSpeedSet = library
            .lookupFunction<_I32I32Native, _I32I32Dart>('keyboard_speed_set'),
        wifiJson = library.lookupFunction<_StrVoidNative, _StrVoidDart>(
            'wifi_networks_json'),
        wifiConnect = library
            .lookupFunction<_ConnectNative, _ConnectDart>('wifi_connect'),
        wifiDisconnect = library
            .lookupFunction<_I32VoidNative, _I32VoidDart>('wifi_disconnect'),
        displayJson = library.lookupFunction<_StrVoidNative, _StrVoidDart>(
            'display_state_json'),
        displayApply = library
            .lookupFunction<_DisplayNative, _DisplayDart>('display_apply'),
        timezonesJson = library.lookupFunction<_StrVoidNative, _StrVoidDart>(
            'timezones_json'),
        timezoneOffset = library
            .lookupFunction<_I32StrNative, _I32StrDart>('timezone_offset'),
        clipboardSequence = library
            .lookupFunction<_U32VoidNative, _U32VoidDart>('clipboard_sequence'),
        clipboardText = library
            .lookupFunction<_StrVoidNative, _StrVoidDart>('clipboard_text'),
        clipboardSet = library
            .lookupFunction<_I32StrNative, _I32StrDart>('clipboard_set'),
        clipboardClear = library
            .lookupFunction<_I32VoidNative, _I32VoidDart>('clipboard_clear'),
        freeString = library
            .lookupFunction<_FreeNative, _FreeDart>('free_string');
}

_Bindings? _bindings;
bool _tried = false;

_Bindings? _load() {
  if (_tried) return _bindings;
  _tried = true;
  for (final candidate in const [
    'sysctl.dll',
    'lib/rust/sysctl/sysctl.dll',
    'lib/rust/sysctl.dll',
    'data/flutter_assets/lib/rust/sysctl/sysctl.dll',
  ]) {
    try {
      _bindings = _Bindings(DynamicLibrary.open(candidate));
      return _bindings;
    } catch (_) {
      // Try the next location.
    }
  }
  return null;
}

String? _readJson(Pointer<Utf8> Function(_Bindings) call) {
  final bindings = _load();
  if (bindings == null) return null;
  final pointer = call(bindings);
  if (pointer == nullptr) return null;
  try {
    return pointer.toDartString();
  } finally {
    bindings.freeString(pointer);
  }
}

/// One row from `audio_sessions_json`.
class AudioSessionRow {
  final int pid;
  final String exe;
  final double volume;
  final bool muted;

  const AudioSessionRow({
    required this.pid,
    required this.exe,
    required this.volume,
    required this.muted,
  });
}

/// One row from `wifi_networks_json`.
class WifiRow {
  final String ssid;
  final int signal;
  final bool secure;
  final bool known;
  final bool connected;

  /// The Windows profile's connection mode: auto-join when in range.
  final bool auto;

  const WifiRow({
    required this.ssid,
    required this.signal,
    required this.secure,
    required this.known,
    required this.connected,
    required this.auto,
  });
}

/// One row from `display_state_json`.
class DisplayModeRow {
  final int width;
  final int height;
  final int hz;
  final int orientation;
  final int bits;

  const DisplayModeRow({
    required this.width,
    required this.height,
    required this.hz,
    required this.orientation,
    required this.bits,
  });
}

/// The monitor's current mode and everything it supports.
class DisplayState {
  final DisplayModeRow? current;
  final List<({int width, int height})> resolutions;
  final List<int> refreshRates;

  const DisplayState({
    required this.current,
    required this.resolutions,
    required this.refreshRates,
  });

  static const DisplayState empty = DisplayState(
    current: null,
    resolutions: [],
    refreshRates: [60],
  );
}

/// One row from `timezones_json`.
class TimezoneRow {
  final String id;
  final String name;
  final int offsetMinutes;

  const TimezoneRow({
    required this.id,
    required this.name,
    required this.offsetMinutes,
  });
}

// ---- pure parsers -----------------------------------------------------------

List<AudioSessionRow> parseAudioSessionsJson(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    final rows = <AudioSessionRow>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final pid = item['pid'];
      if (pid is! num) continue;
      rows.add(AudioSessionRow(
        pid: pid.toInt(),
        exe: '${item['exe'] ?? ''}',
        volume: ((item['volume'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        muted: item['muted'] == true,
      ));
    }
    rows.sort((a, b) => a.exe.compareTo(b.exe));
    return rows;
  } catch (_) {
    return const [];
  }
}

List<WifiRow> parseWifiJson(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    final rows = <WifiRow>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final ssid = '${item['ssid'] ?? ''}'.trim();
      if (ssid.isEmpty) continue;
      rows.add(WifiRow(
        ssid: ssid,
        signal: ((item['signal'] as num?)?.toInt() ?? 0).clamp(0, 100),
        secure: item['secure'] == true,
        known: item['known'] == true,
        connected: item['connected'] == true,
        auto: item['auto'] == true,
      ));
    }
    // The native list is already sorted; keep it stable but let a caller feed
    // hand-written JSON in any order.
    rows.sort((a, b) {
      if (a.connected != b.connected) return a.connected ? -1 : 1;
      return b.signal.compareTo(a.signal);
    });
    return rows;
  } catch (_) {
    return const [];
  }
}

DisplayState parseDisplayStateJson(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return DisplayState.empty;
    DisplayModeRow? current;
    final rawCurrent = decoded['current'];
    if (rawCurrent is Map) {
      current = DisplayModeRow(
        width: (rawCurrent['width'] as num?)?.toInt() ?? 0,
        height: (rawCurrent['height'] as num?)?.toInt() ?? 0,
        hz: (rawCurrent['hz'] as num?)?.toInt() ?? 0,
        orientation: (rawCurrent['orientation'] as num?)?.toInt() ?? 0,
        bits: (rawCurrent['bits'] as num?)?.toInt() ?? 32,
      );
    }
    final resolutions = <({int width, int height})>[];
    final rawResolutions = decoded['resolutions'];
    if (rawResolutions is List) {
      for (final entry in rawResolutions) {
        if (entry is! List || entry.length < 2) continue;
        final width = (entry[0] as num?)?.toInt() ?? 0;
        final height = (entry[1] as num?)?.toInt() ?? 0;
        if (width > 0 && height > 0) {
          resolutions.add((width: width, height: height));
        }
      }
    }
    final refresh = <int>[];
    final rawRefresh = decoded['refresh'];
    if (rawRefresh is List) {
      for (final value in rawRefresh) {
        final hz = (value as num?)?.toInt() ?? 0;
        if (hz > 0) refresh.add(hz);
      }
    }
    if (refresh.isEmpty) refresh.add(60);
    resolutions.sort((a, b) => a.width == b.width
        ? a.height.compareTo(b.height)
        : a.width.compareTo(b.width));
    refresh.sort();
    return DisplayState(
      current: current,
      resolutions: resolutions,
      refreshRates: refresh,
    );
  } catch (_) {
    return DisplayState.empty;
  }
}

List<TimezoneRow> parseTimezonesJson(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    final rows = <TimezoneRow>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final id = '${item['id'] ?? ''}';
      if (id.isEmpty) continue;
      rows.add(TimezoneRow(
        id: id,
        name: '${item['name'] ?? id}',
        offsetMinutes: (item['offset'] as num?)?.toInt() ?? 0,
      ));
    }
    rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
  } catch (_) {
    return const [];
  }
}

// ---- public surface ---------------------------------------------------------

abstract final class SysCtl {
  /// True when sysctl.dll was found and its symbols resolved.
  static bool get available => _load() != null;

  static double? get masterVolume {
    final bindings = _load();
    if (bindings == null) return null;
    final value = bindings.masterVolumeGet();
    return value < 0 ? null : value.clamp(0.0, 1.0);
  }

  static bool setMasterVolume(double value) {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.masterVolumeSet(value.clamp(0.0, 1.0)) != 0;
  }

  static bool? get masterMuted {
    final bindings = _load();
    if (bindings == null) return null;
    final value = bindings.masterMuteGet();
    if (value < 0) return null;
    return value != 0;
  }

  static bool setMasterMuted(bool muted) {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.masterMuteSet(muted ? 1 : 0) != 0;
  }

  /// The raw JSON string, for an isolate or a test.
  static String? audioSessionsJson() =>
      _readJson((bindings) => bindings.sessionsJson());

  static List<AudioSessionRow> audioSessions() {
    final json = audioSessionsJson();
    return json == null ? const [] : parseAudioSessionsJson(json);
  }

  static Future<List<AudioSessionRow>> audioSessionsAsync() async {
    if (!available) return const [];
    try {
      final json = await Isolate.run(audioSessionsJson);
      return json == null ? const [] : parseAudioSessionsJson(json);
    } catch (_) {
      return const [];
    }
  }

  static bool setSessionVolume(int pid, double value) {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.sessionVolume(pid, value.clamp(0.0, 1.0)) != 0;
  }

  static bool setSessionMute(int pid, bool muted) {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.sessionMute(pid, muted ? 1 : 0) != 0;
  }

  static String? wifiJson() => _readJson((bindings) => bindings.wifiJson());

  static List<WifiRow> wifiNetworks() {
    final json = wifiJson();
    return json == null ? const [] : parseWifiJson(json);
  }

  static Future<List<WifiRow>> wifiNetworksAsync() async {
    if (!available) return const [];
    try {
      final json = await Isolate.run(wifiJson);
      return json == null ? const [] : parseWifiJson(json);
    } catch (_) {
      return const [];
    }
  }

  static bool wifiConnect(
    String ssid, {
    String password = '',
    bool autoConnect = true,
    bool secure = true,
  }) {
    final bindings = _load();
    if (bindings == null) return false;
    final ssidPointer = ssid.toNativeUtf8();
    final passwordPointer = password.toNativeUtf8();
    try {
      return bindings.wifiConnect(
            ssidPointer,
            passwordPointer,
            autoConnect ? 1 : 0,
            secure ? 1 : 0,
          ) ==
          0;
    } finally {
      malloc.free(ssidPointer);
      malloc.free(passwordPointer);
    }
  }

  static bool wifiDisconnect() {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.wifiDisconnect() == 0;
  }

  static DisplayState displayState() {
    final json = _readJson((bindings) => bindings.displayJson());
    return json == null ? DisplayState.empty : parseDisplayStateJson(json);
  }

  static bool applyDisplay({
    required int width,
    required int height,
    required int hz,
    int orientation = -1,
  }) {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.displayApply(width, height, hz, orientation) == 1;
  }

  static List<TimezoneRow> timezones() {
    final json = _readJson((bindings) => bindings.timezonesJson());
    return json == null ? const [] : parseTimezonesJson(json);
  }

  static Future<List<TimezoneRow>> timezonesAsync() async {
    if (!available) return const [];
    try {
      final json = await Isolate.run(
        () => _readJson((bindings) => bindings.timezonesJson()),
      );
      return json == null ? const [] : parseTimezonesJson(json);
    } catch (_) {
      return const [];
    }
  }

  static int? timezoneOffset(String id) {
    final bindings = _load();
    if (bindings == null) return null;
    final pointer = id.toNativeUtf8();
    try {
      final value = bindings.timezoneOffset(pointer);
      return value == -9999 ? null : value;
    } finally {
      malloc.free(pointer);
    }
  }

  static int? get mouseSpeed {
    final bindings = _load();
    if (bindings == null) return null;
    final value = bindings.mouseSpeedGet();
    return value < 0 ? null : value;
  }

  static bool setMouseSpeed(int value) {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.mouseSpeedSet(value.clamp(1, 20)) != 0;
  }

  static bool? get mouseSwap {
    final bindings = _load();
    if (bindings == null) return null;
    final value = bindings.mouseSwapGet();
    return value < 0 ? null : value != 0;
  }

  static bool setMouseSwap(bool value) {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.mouseSwapSet(value ? 1 : 0) != 0;
  }

  static int? get wheelLines {
    final bindings = _load();
    if (bindings == null) return null;
    final value = bindings.wheelLinesGet();
    return value < 0 ? null : value;
  }

  static bool setWheelLines(int value) {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.wheelLinesSet(value.clamp(1, 100)) != 0;
  }

  static int? get keyboardDelay {
    final bindings = _load();
    if (bindings == null) return null;
    final value = bindings.keyboardDelayGet();
    return value < 0 ? null : value;
  }

  static bool setKeyboardDelay(int value) {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.keyboardDelaySet(value.clamp(0, 3)) != 0;
  }

  static int? get keyboardSpeed {
    final bindings = _load();
    if (bindings == null) return null;
    final value = bindings.keyboardSpeedGet();
    return value < 0 ? null : value;
  }

  static bool setKeyboardSpeed(int value) {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.keyboardSpeedSet(value.clamp(0, 31)) != 0;
  }

  /// Changes whenever anything writes to the Windows clipboard. Polling this
  /// is much cheaper than reading the text every tick.
  static int get clipboardSequence {
    final bindings = _load();
    if (bindings == null) return 0;
    return bindings.clipboardSequence();
  }

  static String? get clipboardText {
    final bindings = _load();
    if (bindings == null) return null;
    final pointer = bindings.clipboardText();
    if (pointer == nullptr) return null;
    try {
      return pointer.toDartString();
    } finally {
      bindings.freeString(pointer);
    }
  }

  static bool setClipboardText(String text) {
    final bindings = _load();
    if (bindings == null) return false;
    final pointer = text.toNativeUtf8();
    try {
      return bindings.clipboardSet(pointer) != 0;
    } finally {
      malloc.free(pointer);
    }
  }

  static bool clearClipboard() {
    final bindings = _load();
    if (bindings == null) return false;
    return bindings.clipboardClear() != 0;
  }
}