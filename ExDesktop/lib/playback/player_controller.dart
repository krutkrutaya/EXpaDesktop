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
class AudioPlayersEngine implements AudioEngine {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> playAsset(String asset) => _start(AssetSource(asset));

  @override
  Future<void> playFile(String path) => _start(DeviceFileSource(path));

  /// Always starts at the very beginning. `play()` alone reused the previous
  /// source's position on some Windows builds; stopping first and seeking to
  /// zero makes a track switch deterministic (the reported bug).
  Future<void> _start(Source source) async {
    await _player.stop();
    await _player.play(source);
    try {
      await _player.seek(Duration.zero);
    } catch (_) {
      // A decoder can refuse a seek before it is ready; playback still starts
      // at zero from play().
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
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<Duration?> position() => _player.getCurrentPosition();

  @override
  Stream<Duration> get onPosition => _player.onPositionChanged;

  @override
  Stream<Duration> get onDuration => _player.onDurationChanged;

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> dispose() => _player.dispose();
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

  /// Position events that arrive right after a switch can belong to the old
  /// track (Media Foundation delivers a final position from the previous
  /// source). While this deadline is in the future the clock stays at 0:00.
  DateTime? _settlePositionsUntil;

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
    _settlePositionsUntil = DateTime.now().add(const Duration(milliseconds: 350));
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
    _settlePositionsUntil = DateTime.now().add(const Duration(milliseconds: 350));
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
    final settling = _settlePositionsUntil != null &&
        DateTime.now().isBefore(_settlePositionsUntil!);
    // A position past the new track's duration is a stale event from the
    // previous source even after the settle window.
    final stale = _duration > Duration.zero &&
        position > _duration + const Duration(milliseconds: 500);
    final effective = (settling || stale) ? Duration.zero : position;
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
    // The decoder has reported the new source: from here on, positions are
    // trustworthy again.
    _settlePositionsUntil = null;
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