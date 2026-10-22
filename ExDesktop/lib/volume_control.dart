// The master endpoint's volume, through the Rust backend.
//
// This used to be hand-written COM in Dart. The native library owns the
// endpoint now; this class is the cached face the shell and the settings pane
// share. Writes are throttled to ~30 ms: a slider drag fires 60 times a second
// and each WASAPI write opens a COM endpoint, which is enough work to be felt
// in the animation. The thumb stays instant (the cache); the machine follows
// a few milliseconds behind, and the last value is always flushed.

import 'dart:async';

import 'native/sysctl.dart';

class VolumeControl {
  VolumeControl._();

  static final VolumeControl instance = VolumeControl._();

  double _volume = 0.7;
  bool _muted = false;
  bool _loaded = false;

  Timer? _writeTimer;
  double _pending = 0;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  /// True when sysctl.dll could be loaded: the tests use it to decide whether
  /// a real endpoint exists on the machine.
  bool get available => SysCtl.available;

  /// Master volume in [0..1]. The cache answers instantly; the native value
  /// replaces it on the first read after a refresh.
  double get volume {
    _load();
    return _volume;
  }

  set volume(double value) {
    final next = value.clamp(0.0, 1.0);
    _volume = next;
    _loaded = true;
    _pending = next;

    final since = DateTime.now().difference(_lastWrite).inMilliseconds;
    if (since >= 30) {
      _writeTimer?.cancel();
      _writeTimer = null;
      _lastWrite = DateTime.now();
      SysCtl.setMasterVolume(next);
      return;
    }
    if (_writeTimer?.isActive ?? false) return;
    _writeTimer = Timer(Duration(milliseconds: 30 - since), () {
      _writeTimer = null;
      _lastWrite = DateTime.now();
      SysCtl.setMasterVolume(_pending);
    });
  }

  bool get muted {
    _load();
    return _muted;
  }

  set muted(bool value) {
    _muted = value;
    _loaded = true;
    SysCtl.setMasterMuted(value);
  }

  /// Re-reads the endpoint after another program changed it.
  void refresh() {
    _writeTimer?.cancel();
    _writeTimer = null;
    _loaded = false;
    _load();
  }

  void _load() {
    if (_loaded) return;
    _loaded = true;
    final volume = SysCtl.masterVolume;
    if (volume != null) _volume = volume;
    final muted = SysCtl.masterMuted;
    if (muted != null) _muted = muted;
  }
}