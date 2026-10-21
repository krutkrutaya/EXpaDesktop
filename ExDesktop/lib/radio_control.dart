// Wi-Fi and Bluetooth, read and written through Windows' own radio API.
//
// The shell does not guess: every answer comes from the system, and the UI
// shows exactly what the machine reports. Switching a radio goes through
// Windows.Devices.Radios.Radio (the API behind the taskbar's quick settings),
// which works for the signed-in user without elevation — no UAC prompt, no
// "open Windows Settings and click it yourself".
//
// When the radio API is not there (a locked-down machine, a VM without a
// wireless stack) the Wi-Fi adapter can still be flipped with netsh, and the
// caller is told honestly when nothing could be changed.

import 'hidden_process.dart';
import 'radio_script.dart';

/// The two radios the shell knows how to drive.
enum RadioKind {
  wifi('WiFi', 'Wi-Fi', 'ms-settings:network-wifi'),
  bluetooth('Bluetooth', 'Bluetooth', 'ms-settings:bluetooth');

  const RadioKind(this.winRtKind, this.label, this.settingsUri);

  /// The kind name the WinRT radio API uses.
  final String winRtKind;

  /// The Russian label shown in the UI.
  final String label;

  /// Where Windows keeps this radio's own settings, used as the fallback.
  final String settingsUri;
}

/// What the machine says about a radio.
enum RadioState {
  on,
  off,

  /// Switched off by policy or by the user in the system settings.
  blocked,

  /// The radio is there but the system would not tell us its state.
  unknown,

  /// No such radio on this machine.
  unavailable;

  String get label => switch (this) {
        RadioState.on => 'Включено',
        RadioState.off => 'Выключено',
        RadioState.blocked => 'Отключено системой',
        RadioState.unknown => 'Неизвестно',
        RadioState.unavailable => 'Устройство не найдено',
      };
}

/// A snapshot of one radio.
class RadioStatus {
  final RadioKind kind;
  final RadioState state;

  /// The radio's own name, e.g. "Intel(R) Wi-Fi 6E AX211".
  final String? deviceName;

  /// The network adapter's name, e.g. "Wi-Fi" — what netsh wants.
  final String? adapterName;

  /// Whether the link is up (Wi-Fi: associated with a network).
  final bool connected;

  /// Whether the shell is able to switch this radio itself.
  final bool canToggle;

  const RadioStatus({
    required this.kind,
    required this.state,
    this.deviceName,
    this.adapterName,
    this.connected = false,
    this.canToggle = false,
  });

  bool get isOn => state == RadioState.on;

  /// Short Russian description used in replies and captions.
  String get label {
    if (state == RadioState.on && connected) return '${state.label}, подключено';
    return state.label;
  }

  @override
  String toString() => 'RadioStatus(${kind.name}, ${state.name})';
}

/// The outcome of a switch attempt.
class RadioActionResult {
  final bool ok;
  final RadioStatus status;
  final String message;

  const RadioActionResult({
    required this.ok,
    required this.status,
    required this.message,
  });
}

/// What the settings window needs from a radio backend.
///
/// [RadioControl] is the real one; the widget tests use a recorder, so the
/// UI can be driven without touching the machine's radios.
abstract class RadioSource {
  Future<RadioStatus> status(RadioKind kind, {bool force});
  Future<RadioActionResult> setPower(RadioKind kind, bool on);
}

/// Reads and writes the machine's radios.
class RadioControl implements RadioSource {
  static final RadioControl instance = RadioControl._();

  RadioControl._();

  final Map<RadioKind, RadioStatus> _cache = {};
  final Map<RadioKind, DateTime> _cacheTime = {};

  /// How long a reading stays fresh. The quick-settings panel of Windows
  /// refreshes at a similar pace, and it keeps a burst of clicks from
  /// spawning a process per click.
  static const Duration cacheTtl = Duration(seconds: 2);

  /// The current state of [kind], from the cache when it is still fresh.
  @override
  Future<RadioStatus> status(RadioKind kind, {bool force = false}) async {
    if (!force) {
      final at = _cacheTime[kind];
      final cached = _cache[kind];
      if (cached != null &&
          at != null &&
          DateTime.now().difference(at) < cacheTtl) {
        return cached;
      }
    }
    final snapshot = await _readSnapshot(force: force);
    return _cache[kind] ?? snapshot.statusOf(kind);
  }

  /// Switches [kind] on or off and reports what the system says afterwards.
  @override
  Future<RadioActionResult> setPower(RadioKind kind, bool on) async {
    final before = await status(kind, force: true);
    if (before.state == RadioState.unavailable) {
      return RadioActionResult(
        ok: false,
        status: before,
        message: '${kind.label}: устройство не найдено',
      );
    }

    final result = await runPowerShell(
      buildRadioSetScript(kind: kind.winRtKind, on: on),
    );
    var ok = false;
    var message = '';
    for (final line in result.lines) {
      if (line.startsWith('ok|')) {
        // The script reports what the radio API answered: only "Allowed"
        // means the switch actually happened.
        final access = line.substring(3);
        ok = access == 'Allowed';
        message = ok ? 'ok' : access;
      } else if (line.startsWith('err|')) {
        message = line.substring(4);
      }
    }

    if (!ok) {
      // The radio API said no. For Wi-Fi the adapter can still be flipped
      // with netsh - that one wants an elevated shell, so it may fail too.
      final fallback = await _fallbackSetPower(kind, on);
      if (fallback != null) {
        ok = true;
        message = fallback;
      }
    }

    final after = await status(kind, force: true);
    if (!ok) {
      return RadioActionResult(
        ok: false,
        status: after,
        message: message.isEmpty
            ? '${kind.label}: система не дала переключить'
            : '${kind.label}: $message',
      );
    }
    return RadioActionResult(
      ok: true,
      status: after,
      message: after.state.label,
    );
  }

  /// Drops the cached readings, so the next question hits the system.
  void invalidate() {
    _cache.clear();
    _cacheTime.clear();
  }

  // ---- internals ------------------------------------------------------------

  Future<String?> _fallbackSetPower(RadioKind kind, bool on) async {
    if (kind != RadioKind.wifi) return null;
    final adapter = _cache[RadioKind.wifi]?.adapterName;
    if (adapter == null || adapter.isEmpty) return null;
    final result = await runHidden('netsh.exe', [
      'interface',
      'set',
      'interface',
      'name=$adapter',
      'admin=${on ? 'enabled' : 'disabled'}',
    ]);
    if (result.ok) return 'adapter $adapter';
    return null;
  }

  Future<RadioSnapshot> _readSnapshot({bool force = false}) async {
    final result = await runPowerShell(buildRadioStateScript());
    final snapshot = RadioSnapshot.parse(result);
    for (final entry in snapshot.statuses.entries) {
      _cache[entry.key] = entry.value;
      _cacheTime[entry.key] = DateTime.now();
    }
    if (force) {
      // A forced read must not hand back a stale value for a radio the
      // script did not mention.
      for (final kind in RadioKind.values) {
        if (!snapshot.statuses.containsKey(kind)) {
          _cache[kind] = snapshot.statusOf(kind);
          _cacheTime[kind] = DateTime.now();
        }
      }
    }
    return snapshot;
  }
}

/// Everything one radio script run told us.
class RadioSnapshot {
  final Map<RadioKind, RadioStatus> statuses;
  final String? access;
  final String? error;

  const RadioSnapshot({
    required this.statuses,
    this.access,
    this.error,
  });

  /// Reads the line protocol the radio script speaks.
  factory RadioSnapshot.parse(HiddenResult result) {
    final radios = <String, RadioStatus>{};
    final adapters = <String, ({String name, String status, String media})>{};
    String? access;
    String? error;

    for (final line in result.lines) {
      if (line.startsWith('access=')) {
        access = line.substring(7);
      } else if (line.startsWith('err|')) {
        error = line.substring(4);
      } else if (line.startsWith('radio|')) {
        final parts = line.split('|');
        if (parts.length < 4) continue;
        // Key by the kind the shell understands, so a radio Windows knows
        // about but the shell does not (mobile broadband) still lands in the
        // right bucket instead of vanishing.
        final kind = _kindOf(parts[1]);
        radios[kind.winRtKind] = RadioStatus(
          kind: kind,
          state: _stateOf(parts[3]),
          deviceName: parts[2],
          canToggle: true,
        );
      } else if (line.startsWith('adapter|')) {
        final parts = line.split('|');
        if (parts.length < 4) continue;
        adapters['wifi'] = (name: parts[1], status: parts[2], media: parts[3]);
      }
    }

    final statuses = <RadioKind, RadioStatus>{};
    for (final kind in RadioKind.values) {
      final radio = radios[kind.winRtKind];
      final adapter = kind == RadioKind.wifi ? adapters['wifi'] : null;
      if (radio == null && adapter == null) {
        statuses[kind] = RadioStatus(
          kind: kind,
          state: RadioState.unavailable,
        );
        continue;
      }
      var state = radio?.state ?? RadioState.unknown;
      if (radio == null && adapter != null) {
        // No radio API (an old or locked-down machine): the adapter's own
        // status is all we have. "Disabled" is off; a live adapter is on,
        // whether or not it is associated with a network.
        state = switch (adapter.status.toLowerCase()) {
          'up' || 'down' => RadioState.on,
          'disabled' => RadioState.off,
          _ => RadioState.unknown,
        };
      }
      if (adapter != null && adapter.status.toLowerCase() == 'disabled') {
        state = RadioState.off;
      }
      final connected =
          adapter != null && adapter.media.toLowerCase() == 'connected';
      statuses[kind] = RadioStatus(
        kind: kind,
        state: state,
        deviceName: radio?.deviceName ?? adapter?.name,
        adapterName: adapter?.name,
        connected: connected,
        canToggle: radio != null,
      );
    }

    return RadioSnapshot(statuses: statuses, access: access, error: error);
  }

  RadioStatus statusOf(RadioKind kind) => statuses[kind] ??
      RadioStatus(kind: kind, state: RadioState.unknown);

  static RadioKind _kindOf(String winRtKind) {
    for (final kind in RadioKind.values) {
      if (kind.winRtKind.toLowerCase() == winRtKind.toLowerCase()) return kind;
    }
    return RadioKind.wifi;
  }

  static RadioState _stateOf(String raw) => switch (raw.toLowerCase()) {
        'on' => RadioState.on,
        'off' => RadioState.off,
        'disabledbyuser' => RadioState.blocked,
        'disabledbysystem' => RadioState.blocked,
        _ => RadioState.unknown,
      };
}
