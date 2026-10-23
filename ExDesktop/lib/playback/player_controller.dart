// The player, lifted out of the shell's State.
//
// Before this file the shell stored `_isPlaying`, `_trackProgress`, `_tracks`
// and friends, and `setState` on every position event rebuilt the *whole*
// desktop — wallpaper, dock, waybar, every open window — ten times a second
// while a track played. Now the player is a ChangeNotifier: the mini player,
// the flyout and the Musics app listen to it, and nothing else rebuilds.
//
// It also owns the two pieces of animation the player needs:
//   * the artwork angle, which springs upright when playback pauses
//     (`SpinState`), published as a separate ValueNotifier so a frame of the
//     spin repaints the artwork and not the window around it;
//   * the progress, published through the same notifier path.
//
// The audio backend is an interface (`AudioEngine`), so the widget tests run
// against a recorder and never touch the machine's speakers.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'beat.dart';
import 'playlist.dart';
import 'spin.dart';
import 'track.dart';

/// The audio operations the controller needs.
abstract class AudioEngine {
  Future<void> playAsset(String asset);

  /// Plays a file from disk (an imported track).
  Future<void> playFile(String path);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<Duration?> position();

  Stream<Duration> get onPosition;
  Stream<Duration> get onDuration;
  Stream<void> get onComplete;

  Future<void> dispose();
}

/// The real backend: `audioplayers` on the platform channel.
///
/// Every track gets a **fresh `AudioPlayer`**. On Windows the Media Foundation
/// backend can keep the previous source's position when the same player object
/// is reused, even after `stop` + `seek(0)`: the new track then started at the
/// old timecode. A new player session cannot inherit that position, and the
/// broadcast bridges below keep the controller subscribed to the new session.
class AudioPlayersEngine implements AudioEngine {
  AudioPlayer _player = AudioPlayer();
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durations =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  final List<StreamSubscription<dynamic>> _bridges = [];
  double _volume = 1.0;
  Future<void> _sessionQueue = Future<void>.value();

  AudioPlayersEngine() {
    _bridge(_player);
  }

  void _bridge(AudioPlayer player) {
    _bridges.add(player.onPositionChanged.listen(_positions.add));
    _bridges.add(player.onDurationChanged.listen(_durations.add));
    _bridges.add(player.onPlayerComplete.listen((_) => _completions.add(null)));
  }

  @override
  Future<void> playAsset(String asset) => _start(AssetSource(asset));

  @override
  Future<void> playFile(String path) => _start(DeviceFileSource(path));

  Future<void> _start(Source source) {
    // Rapid track clicks must not interleave two native sessions.
    final result = _sessionQueue.then((_) => _reallyStart(source));
    _sessionQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _reallyStart(Source source) async {
    // Detach the old session first: no late position from it may reach the
    // controller after the new track has been selected.
    for (final bridge in _bridges) {
      await bridge.cancel();
    }
    _bridges.clear();
    final old = _player;
    _player = AudioPlayer();
    _bridge(_player);
    await old.dispose();
    await _player.setVolume(_volume);
    await _player.play(source);
    try {
      await _player.seek(Duration.zero);
    } catch (_) {
      // A decoder can refuse a seek before it is ready; play() still starts a
      // fresh session at zero.
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _player.setVolume(volume);
  }

  @override
  Future<Duration?> position() => _player.getCurrentPosition();

  @override
  Stream<Duration> get onPosition => _positions.stream;

  @override
  Stream<Duration> get onDuration => _durations.stream;

  @override
  Stream<void> get onComplete => _completions.stream;

  @override
  Future<void> dispose() async {
    for (final bridge in _bridges) {
      await bridge.cancel();
    }
    _bridges.clear();
    await _player.dispose();
    await _positions.close();
    await _durations.close();
    await _completions.close();
  }
}

class PlayerController extends ChangeNotifier {
  PlayerController({AudioEngine? engine, TickerProvider? vsync})
      : _engine = engine ?? AudioPlayersEngine(),
        _spin = SpinState() {
    _subscriptions.add(_engine.onPosition.listen(_onPosition));
    _subscriptions.add(_engine.onDuration.listen(_onDuration));
    _subscriptions.add(_engine.onComplete.listen((_) => _onComplete()));
    _ticker = vsync?.createTicker(_onTick) ?? Ticker(_onTick);
  }

  final AudioEngine _engine;
  final SpinState _spin;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late final Ticker _ticker;
  double _lastElapsed = 0;

  /// The artwork angle, in radians. Repaints only the artwork.
  final ValueNotifier<double> angle = ValueNotifier<double>(0);

  /// 0..1 through the current track. Repaints only the seek bar.
  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  /// The elapsed time as text, so the seek row repaints without rebuilding
  /// the whole app ten times a second.
  final ValueNotifier<String> time = ValueNotifier<String>('0:00');

  List<Track> _tracks = const [];
  Map<String, Uint8List> _covers = const {};
  int _index = 0;
  bool _isPlaying = false;
  bool _isLoaded = false;
  String _currentTime = '0:00';
  String _totalDuration = '0:00';
  Duration _duration = Duration.zero;

  bool _looping = false;
  bool _repeatPlaylist = true;
  bool _shuffle = false;

  int _fadeToken = 0;
  bool _disposed = false;

  /// A seek requested before the track had a duration (a click on the seek
  /// bar while the track was only selected, not playing yet).
  double? _pendingSeek;

  /// After a track switch the backend must prove it reset by reporting a
  /// position near zero. Older Windows sessions kept counting from the app
  /// launch and reported a large first value; until that near-zero event the
  /// clock stays at 0:00.
  bool _awaitingPositionReset = false;

  List<Track> get tracks => List<Track>.unmodifiable(_tracks);
  Map<String, Uint8List> get covers => _covers;
  int get index => _index;
  Track? get track => _tracks.isEmpty ? null : _tracks[_index];
  bool get isPlaying => _isPlaying;
  bool get isLoaded => _isLoaded;
  double get progressValue => progress.value;
  String get currentTime => _currentTime;
  String get totalDuration => _totalDuration;
  bool get looping => _looping;
  bool get repeatPlaylist => _repeatPlaylist;
  bool get shuffle => _shuffle;

  Uint8List? get currentCover => track?.coverIn(_covers);

  /// Replaces the library (the folder scan lands here).
  void setTracks(List<Track> tracks, Map<String, Uint8List> covers) {
    if (tracks.isEmpty) return;
    final currentFile = track?.file;
    _tracks = List<Track>.from(tracks);
    _covers = Map<String, Uint8List>.from(covers);
    final restored = currentFile == null
        ? -1
        : _tracks.indexWhere((t) => t.file == currentFile);
    _index = restored >= 0 ? restored : 0;
    notifyListeners();
  }

  /// Loads [index] and plays it from the top.
  Future<void> select(int index, {bool? autoplay}) async {
    if (_tracks.isEmpty) return;
    final wanted = index.clamp(0, _tracks.length - 1);
    final shouldPlay = autoplay ?? _isPlaying;
    _index = wanted;
    _isLoaded = false;
    _pendingSeek = null;
    _awaitingPositionReset = true;
    _duration = Duration.zero;
    _setProgress(0);
    _currentTime = '0:00';
    time.value = _currentTime;
    _totalDuration = track!.duration.isEmpty ? '0:00' : track!.duration;
    _duration = parsePlaybackTime(track!.duration) ?? Duration.zero;
    notifyListeners();

    if (shouldPlay) {
      await _playCurrent();
    } else {
      await _engine.stop();
    }
  }

  Future<void> toggle() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (_tracks.isEmpty) return;
    _isPlaying = true;
    notifyListeners();
    _startSpin();
    if (_isLoaded) {
      await _engine.resume();
      await _engine.setVolume(1.0);
    } else {
      await _playCurrent();
    }
  }

  Future<void> pause() async {
    if (!_isPlaying) return;
    _isPlaying = false;
    notifyListeners();
    // The art keeps its own ticker until it has settled upright.
    _startSpin();
    await _engine.pause();
  }

  Future<void> next() async {
    if (_tracks.isEmpty) return;
    final next = PlaylistPolicy.next(_index, _tracks.length, shuffle: _shuffle);
    await select(next, autoplay: _isPlaying);
  }

  Future<void> previous() async {
    if (_tracks.isEmpty) return;
    await select(PlaylistPolicy.previous(_index, _tracks.length),
        autoplay: _isPlaying);
  }

  Future<void> seekFraction(double fraction) async {
    if (_tracks.isEmpty) return;
    final value = fraction.clamp(0.0, 1.0);
    _setProgress(value);
    _currentTime = formatPlaybackTime(
      Duration(milliseconds: (_duration.inMilliseconds * value).round()),
    );
    time.value = _currentTime;
    if (_isLoaded && _duration > Duration.zero) {
      await _engine.seek(
        Duration(milliseconds: (_duration.inMilliseconds * value).round()),
      );
      _awaitingPositionReset = false;
    } else {
      _pendingSeek = value;
    }
  }

  void setLooping(bool value) {
    if (_looping == value) return;
    _looping = value;
    notifyListeners();
  }

  void setRepeatPlaylist(bool value) {
    if (_repeatPlaylist == value) return;
    _repeatPlaylist = value;
    notifyListeners();
  }

  void setShuffle(bool value) {
    if (_shuffle == value) return;
    _shuffle = value;
    notifyListeners();
  }

  /// The cover scale for the Musics app: a soft pulse on the beat.
  double beatScaleAt(double seconds) =>
      BeatPulse.scaleAt(seconds, playing: _isPlaying);

  // ---- audio plumbing --------------------------------------------------------

  Future<void> _playCurrent() async {
    final current = track;
    if (current == null || current.file.isEmpty) return;
    // A loop or a completion callback can reach here without select(); the
    // clock must snap to zero for the new session immediately, not wait for
    // the first position event.
    _currentTime = '0:00';
    time.value = _currentTime;
    _setProgress(0);
    final token = ++_fadeToken;
    await _engine.setVolume(0.0);
    if (current.isFile) {
      await _engine.playFile(current.path);
    } else {
      await _engine.playAsset('music/${current.file}');
    }
    // Belt and braces: even if the engine's source switch kept a position,
    // reset it explicitly and keep the clock at zero while the decoder
    // settles.
    try {
      await _engine.seek(Duration.zero);
    } catch (_) {}
    _awaitingPositionReset = true;
    _isLoaded = true;
    unawaited(_fadeIn(token));
  }

  /// Ramps 0 -> 1 over ~240 ms so a new track never slams the room.
  Future<void> _fadeIn(int token) async {
    for (var step = 1; step <= 10; step++) {
      if (token != _fadeToken || !_isPlaying) return;
      await _engine.setVolume(step / 10);
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
    if (token == _fadeToken && _isPlaying) {
      await _engine.setVolume(1.0);
    }
  }

  void _onPosition(Duration position) {
    // A new source must start near zero. Windows can deliver the previous
    // source's position (or a value measured from player creation) as the
    // first event; trusting it is what made a fresh track open at e.g. 4:12
    // after the desktop had been open for 4 minutes.
    if (_awaitingPositionReset) {
      if (position > const Duration(seconds: 1)) return;
      _awaitingPositionReset = false;
    }
    // A position past the new track's duration is a stale event from the
    // previous source even after the reset gate.
    final stale = _duration > Duration.zero &&
        position > _duration + const Duration(milliseconds: 500);
    final effective = stale ? Duration.zero : position;
    if (_duration.inMilliseconds > 0) {
      _setProgress(
        (effective.inMilliseconds / _duration.inMilliseconds)
            .clamp(0.0, 1.0),
      );
    }
    _currentTime = formatPlaybackTime(effective);
    time.value = _currentTime;
  }

  void _onDuration(Duration duration) {
    if (duration <= Duration.zero) return;
    _duration = duration;
    _totalDuration = formatPlaybackTime(duration);
    final current = track;
    if (current != null) {
      _tracks[_index] = current.withDuration(_totalDuration);
    }
    final pending = _pendingSeek;
    if (pending != null) {
      _pendingSeek = null;
      unawaited(_engine.seek(Duration(
        milliseconds: (duration.inMilliseconds * pending).round(),
      )));
    }
    notifyListeners();
  }

  Future<void> _onComplete() async {
    if (_tracks.isEmpty || !_isPlaying) return;
    if (_looping) {
      _isPlaying = true;
      await _playCurrent();
      return;
    }
    final last = _index >= _tracks.length - 1;
    if (_repeatPlaylist || !last) {
      _isPlaying = true;
      await select(PlaylistPolicy.next(_index, _tracks.length,
          shuffle: _shuffle));
      return;
    }
    _isPlaying = false;
    // The track ended: the next play has to start it over, not resume a
    // finished player.
    _isLoaded = false;
    _setProgress(1);
    _currentTime = _totalDuration;
    time.value = _currentTime;
    notifyListeners();
    _startSpin();
  }

  void _setProgress(double value) {
    progress.value = value.clamp(0.0, 1.0);
  }

  // ---- the artwork spin ------------------------------------------------------

  void _startSpin() {
    if (_ticker.isActive) return;
    _lastElapsed = 0;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    var dt = seconds - _lastElapsed;
    _lastElapsed = seconds;
    if (dt < 0) dt = 0;
    if (dt == 0) return;
    _spin.advance(dt, playing: _isPlaying);
    angle.value = _spin.angle;
    if (!_spin.needsFrames(_isPlaying)) {
      _ticker.stop();
      _lastElapsed = 0;
    }
  }

  @visibleForTesting
  double get debugAngle => _spin.angle;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Stops a fade that is still stepping: the engine is about to be disposed.
    _fadeToken++;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _ticker.dispose();
    angle.dispose();
    progress.dispose();
    time.dispose();
    unawaited(_engine.dispose());
    super.dispose();
  }
}