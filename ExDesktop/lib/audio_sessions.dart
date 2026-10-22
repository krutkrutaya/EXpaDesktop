// Live per-application audio sessions, from the Rust WASAPI backend.
//
// Enumerating sessions is the one audio call that can take a noticeable
// moment (a browser has several streams), so [sessions] runs the native walk
// in an isolate and returns plain rows. A slider write is throttled per pid:
// each native write walks the session list again, and doing that 60 times a
// second during a drag would be visible in the row's animation. Mute toggles
// are discrete and go straight through.

import 'dart:async';

import 'native/sysctl.dart';

/// One adjustable audio session: a running process with its own slider.
class AudioAppSession {
  /// The Windows process id — the stable key used for slider updates.
  final int pid;

  /// Executable base name without .exe, lowercased ('chrome', 'spotify').
  /// Empty when the process refused to open (a protected/black-box process);
  /// the UI then falls back to a generic label.
  final String exe;

  double volume;
  bool muted;

  AudioAppSession({
    required this.pid,
    required this.exe,
    required this.volume,
    required this.muted,
  });
}

/// Live audio sessions of the default playback device.
class AudioSessions {
  AudioSessions._();

  static final AudioSessions instance = AudioSessions._();

  final Map<int, Timer> _volumeTimers = {};
  final Map<int, double> _pendingVolume = {};
  final Map<int, DateTime> _lastVolumeWrite = {};

  /// Whether the native backend is present on this machine.
  bool get available => SysCtl.available;

  /// The current snapshot of per-app sessions.
  ///
  /// Empty when the native library is missing or the audio service refuses:
  /// the UI then hides the per-app section instead of showing dead sliders.
  Future<List<AudioAppSession>> sessions() async {
    final rows = await SysCtl.audioSessionsAsync();
    return [
      for (final row in rows)
        AudioAppSession(
          pid: row.pid,
          exe: row.exe,
          volume: row.volume,
          muted: row.muted,
        ),
    ];
  }

  bool setVolume(int pid, double value) {
    final next = value.clamp(0.0, 1.0);
    _pendingVolume[pid] = next;
    final now = DateTime.now();
    final last = _lastVolumeWrite[pid];
    final since = last == null ? 1 << 30 : now.difference(last).inMilliseconds;
    if (since >= 40) {
      _volumeTimers.remove(pid)?.cancel();
      _lastVolumeWrite[pid] = now;
      return SysCtl.setSessionVolume(pid, next);
    }
    if (_volumeTimers[pid]?.isActive ?? false) return true;
    _volumeTimers[pid] = Timer(Duration(milliseconds: 40 - since), () {
      _volumeTimers.remove(pid);
      _lastVolumeWrite[pid] = DateTime.now();
      final pending = _pendingVolume.remove(pid);
      if (pending != null) SysCtl.setSessionVolume(pid, pending);
    });
    return true;
  }

  bool setMute(int pid, bool muted) => SysCtl.setSessionMute(pid, muted);
}