// The shell's sound state, in one place.
//
// The top panel's flyout, the settings window and the voice path all read
// and write the same endpoint through this object, so a gesture in one place
// is immediately true in the others. Nothing here can touch the window:
// sound is sound, and the desktop never hides because of it.

import 'volume_control.dart';

class SoundControl {
  static final SoundControl instance = SoundControl._();

  SoundControl._();

  final List<void Function()> _listeners = [];

  double _volume = 0.7;
  bool _muted = false;
  bool _loaded = false;

  /// Master volume in [0..1].
  double get volume {
    _load();
    return _volume;
  }

  set volume(double value) {
    final v = value.clamp(0.0, 1.0);
    _volume = v;
    _loaded = true;
    VolumeControl.instance.volume = v;
    if (v > 0 && _muted) {
      // Dragging the slider up is a clear "I want to hear it again".
      _muted = false;
      VolumeControl.instance.muted = false;
    }
    _notify();
  }

  /// Whether the default playback device is muted.
  bool get muted {
    _load();
    return _muted;
  }

  set muted(bool value) {
    _muted = value;
    _loaded = true;
    VolumeControl.instance.muted = value;
    _notify();
  }

  /// Volume in percent, as shown next to the slider.
  int get percent => (volume * 100).round();

  /// Moves the volume by one step in [direction] (-1 quieter, +1 louder).
  void stepVolume(double direction) {
    _load();
    final next = (_volume + 0.02 * direction).clamp(0.0, 1.0);
    _volume = next;
    VolumeControl.instance.volume = next;
    if (next > 0 && direction > 0 && _muted) {
      _muted = false;
      VolumeControl.instance.muted = false;
    }
    _notify();
  }

  /// Mutes or unmutes, whatever the current state is.
  void toggleMute() {
    muted = !muted;
  }

  /// Re-reads the endpoint, e.g. after another program changed the volume.
  void refresh() {
    _loaded = false;
    _load();
    _notify();
  }

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _load() {
    if (_loaded) return;
    _loaded = true;
    _volume = VolumeControl.instance.volume;
    _muted = VolumeControl.instance.muted;
  }

  void _notify() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }
}
