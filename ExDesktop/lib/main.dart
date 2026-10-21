import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:ffi';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'player.dart';
import 'settings_app.dart';
import 'package:audioplayers/audioplayers.dart';
import 'liquid_glass/morph_controller.dart';
import 'liquid_glass/morph_glass.dart';
import 'liquid_glass/wave_slider.dart';

typedef SetBrightnessNative = Int32 Function(Double level);
typedef SetBrightnessDart = int Function(double level);
typedef GetBrightnessNative = Double Function();
typedef GetBrightnessDart = double Function();
typedef SetContrastNative = Int32 Function(Double level);
typedef SetContrastDart = int Function(double level);
typedef SetWarmthNative = Int32 Function(Double level);
typedef SetWarmthDart = int Function(double level);
typedef ResetGammaNative = Int32 Function();
typedef ResetGammaDart = int Function();
typedef SetBrightnessBoostNative = Int32 Function(Double level);
typedef SetBrightnessBoostDart = int Function(double level);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: MyHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  late String _timeString;
  late Timer _timer;
  late Timer _backgroundTimer;
  Timer? _progressTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _currentTime = '0:00';
  String _totalDuration = '2:00';
  Duration? _audioDuration;

  int _currentBackgroundIndex = 0;
  final List<String> _backgrounds = [
    'assets/fons/fon1.jpg',
    'assets/fons/fon2.jpg',
    'assets/fons/fon3.jpg',
    'assets/fons/fon4.jpg',
    'assets/fons/fon5.jpg',
    'assets/fons/fon6.jpg',
    'assets/fons/fon8.jpg',
  ];

  bool _isDotsHovered = false;
  bool _isTopPanelHovered = false;
  bool _isPlaying = false;
  bool _isWifiHovered = false;
  bool _isBluetoothHovered = false;
  bool _isVolumeHovered = false;
  bool _isAppsHovered = false;
  bool _isBrightnessHovered = false;
  bool _isSettingsOpen = false;
  bool _isSettingsMinimized = false;
  Offset _settingsPosition = Offset.zero;
  double _brightness = 0.7;
  double _contrast = 0.7;
  double _warmth = 0.5;
  int _selectedTrack = 0;
  double _trackProgress = 0.0;

  // Playback modes, wired to the player panel.
  bool _isLooping = false; // loop the current track
  bool _isRepeatPlaylist = true; // wrap around at the end of the list
  bool _isShuffle = false; // random next track

  // Liquid-glass panel morphs; created in didChangeDependencies, where the
  // window size (and so the button/menu rects) is known.
  MorphPanelController? _menuMorph;
  MorphPanelController? _brightnessMorph;
  MorphPanelController? _playerMorph;

  bool get _isMenuOpen => _menuMorph?.active ?? false;
  bool get _isBrightnessOpen => _brightnessMorph?.active ?? false;
  bool get _isPlayerOpen => _playerMorph?.active ?? false;

  // Hand-written metadata for files we know; every other .mp3 found in
  // assets/music is named from its filename automatically, so a new song
  // only needs to be dropped into the folder.
  static const Map<String, Map<String, String>> _trackMetaOverride = {
    'morgenshtern-ice.mp3': {
      'title': 'ICE',
      'artist': 'Morgenshtern',
      'avatar': 'assets/music/ava-track-1.jpg',
    },
    'b5607d8a7d89812.mp3': {
      'title': 'Track Test',
      'artist': 'Неизвестно',
      'avatar': '',
    },
    'monetochka-kazhdyjj-raz.mp3': {
      'title': 'Каждый раз',
      'artist': 'Монеточка',
      'avatar': 'assets/music/ava-track-3.jpg',
    },
  };

  // Seeded with the known tracks so the player is usable from the very
  // first frame; the folder scan replaces this list as soon as it lands.
  // The maps stay mutable: playing a track writes the real duration into
  // its entry.
  List<Map<String, String>> _tracks = [
    {
      'title': 'ICE',
      'artist': 'Morgenshtern',
      'duration': '2:00',
      'avatar': 'assets/music/ava-track-1.jpg',
      'file': 'morgenshtern-ice.mp3',
    },
    {
      'title': 'Track Test',
      'artist': 'Неизвестно',
      'duration': '2:00',
      'avatar': '',
      'file': 'b5607d8a7d89812.mp3',
    },
    {
      'title': 'Каждый раз',
      'artist': 'Монеточка',
      'duration': '2:00',
      'avatar': 'assets/music/ava-track-3.jpg',
      'file': 'monetochka-kazhdyjj-raz.mp3',
    },
  ];

  DynamicLibrary? _brightnessLib;
  SetBrightnessDart? _setBrightness;
  GetBrightnessDart? _getBrightness;
  SetContrastDart? _setContrast;
  SetWarmthDart? _setWarmth;
  ResetGammaDart? _resetGamma;
  SetBrightnessBoostDart? _setBrightnessBoost;
  
  DateTime _lastBrightnessUpdate = DateTime.now();
  DateTime _lastContrastUpdate = DateTime.now();
  DateTime _lastWarmthUpdate = DateTime.now();

  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _timeString = _formatTime(DateTime.now());
    _loadBrightnessLib();
    _initAudioPlayer();

    _rotationController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _timeString = _formatTime(DateTime.now());
        });
      }
    });

    _backgroundTimer = Timer.periodic(const Duration(seconds: 12), (timer) {
      if (mounted) {
        setState(() {
          _currentBackgroundIndex = (_currentBackgroundIndex + 1) % _backgrounds.length;
        });
      }
    });

    unawaited(_scanMusicAssets());
  }

  // The asset folder cannot be listed at runtime directly, but Flutter's
  // asset manifest lists every bundled file. Newer Flutter ships it as a
  // binary blob, older as JSON — both are handled.
  static const String _musicPrefix = 'assets/music/';

  Future<void> _scanMusicAssets() async {
    final files = await _musicAssetFiles();
    if (!mounted || files.isEmpty) return;
    setState(() {
      _tracks = [for (final file in files) _trackFromFile(file)];
      if (_selectedTrack >= _tracks.length) _selectedTrack = 0;
    });
  }

  Future<List<String>> _musicAssetFiles() async {
    final files = <String>[];
    try {
      final manifest = await rootBundle.load('AssetManifest.bin');
      final decoded =
          const StandardMessageCodec().decodeMessage(manifest);
      if (decoded is Map) {
        files.addAll(_filterMusicFiles(decoded.keys.whereType<String>()));
      }
    } catch (_) {
      try {
        final json = await rootBundle.loadString('AssetManifest.json');
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        files.addAll(_filterMusicFiles(decoded.keys.whereType<String>()));
      } catch (_) {}
    }
    // The manifest always ships in Flutter builds; the fallback keeps the
    // player alive with the already-known files even if reading it fails.
    if (files.isEmpty) {
      return _tracks
          .map((track) => track['file'] ?? '')
          .where((file) => file.isNotEmpty)
          .toSet()
          .toList();
    }
    return files;
  }

  List<String> _filterMusicFiles(Iterable<String> keys) {
    return keys
        .map((key) => key.replaceAll('\\', '/'))
        .where((path) => path.startsWith(_musicPrefix) && path.endsWith('.mp3'))
        .map((path) => path.substring(_musicPrefix.length))
        .where((file) => file.isNotEmpty && !file.contains('/'))
        .toSet()
        .toList()
      ..sort();
  }

  Map<String, String> _trackFromFile(String file) {
    final known = _trackMetaOverride[file];
    return {
      'title': known?['title'] ?? _autoTitle(file),
      'artist': known?['artist'] ?? 'Unknown artist',
      'duration': '',
      'avatar': known?['avatar'] ?? '',
      'file': file,
    };
  }

  String _autoTitle(String file) {
    final words = file
        .split('.')
        .first
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase());
    final title = words.join(' ');
    return title.isEmpty ? file : title;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;

    // Where each panel's glass is born from, and where it lands:
    // the apps button in the right dock -> the power menu (700x550),
    // the brightness button in the top panel -> the brightness panel,
    // the mini-player capsule in the top panel -> the full player.
    final menuButton = [w - 67.0, h - 72.0, 52.0, 52.0];
    final menuRect = [w - 789.0, h - 570.0, 700.0, 550.0];

    final brightButton = [w / 2 - 345.0, 10.0, 40.0, 40.0];
    final brightRect = [w / 2 - 350.0, 60.0, 350.0, 180.0];

    final playerButton = [w / 2 - 95.0, 5.0, 190.0, 50.0];
    final playerRect = [w / 2 - 300.0, 70.0, 600.0, 400.0];

    if (_menuMorph == null) {
      _menuMorph = MorphPanelController(
        buttonRect: menuButton,
        menuRect: menuRect,
        menuRadius: 15.0,
      )..attach(this);
      _brightnessMorph = MorphPanelController(
        buttonRect: brightButton,
        menuRect: brightRect,
        menuRadius: 25.0,
      )..attach(this);
      _playerMorph = MorphPanelController(
        buttonRect: playerButton,
        menuRect: playerRect,
        menuRadius: 25.0,
      )..attach(this);
    } else {
      _menuMorph!.retarget(menuButton, menuRect, 15.0);
      _brightnessMorph!.retarget(brightButton, brightRect, 25.0);
      _playerMorph!.retarget(playerButton, playerRect, 25.0);
    }
  }

  void _initAudioPlayer() {
    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _currentTime = '${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}';
          if (_audioDuration != null && _audioDuration!.inMilliseconds > 0) {
            _trackProgress = (position.inMilliseconds / _audioDuration!.inMilliseconds).clamp(0.0, 1.0);
          }
        });
      }
    });
    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _audioDuration = duration;
          _totalDuration = '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
          _tracks[_selectedTrack]['duration'] = _totalDuration;
        });
      }
    });
    _audioPlayer.onPlayerComplete.listen((event) {
      if (!mounted) return;
      if (_isLooping) {
        // Replay the same track from the top.
        final file = _tracks[_selectedTrack]['file'];
        if (file != null && file.isNotEmpty) {
          _audioPlayer.play(AssetSource('music/$file'));
        }
        return;
      }
      if (_isRepeatPlaylist || _selectedTrack < _tracks.length - 1) {
        _goToTrack(_pickNext());
      } else {
        setState(() => _isPlaying = false);
        _rotationController.stop();
        _progressTimer?.cancel();
      }
    });
  }

  void _loadBrightnessLib() {
    try {
      _brightnessLib = DynamicLibrary.open('lib/rust/brightness.dll');
      _setBrightness = _brightnessLib!
          .lookup<NativeFunction<SetBrightnessNative>>('set_brightness')
          .asFunction();
      _getBrightness = _brightnessLib!
          .lookup<NativeFunction<GetBrightnessNative>>('get_brightness')
          .asFunction();
      _setContrast = _brightnessLib!
          .lookup<NativeFunction<SetContrastNative>>('set_contrast')
          .asFunction();
      _setWarmth = _brightnessLib!
          .lookup<NativeFunction<SetWarmthNative>>('set_warmth')
          .asFunction();
      _resetGamma = _brightnessLib!
          .lookup<NativeFunction<ResetGammaNative>>('reset_gamma')
          .asFunction();
      _setBrightnessBoost = _brightnessLib!
          .lookup<NativeFunction<SetBrightnessBoostNative>>('set_brightness_boost')
          .asFunction();
      final current = _getBrightness!();
      setState(() {
        _brightness = current;
      });
    } catch (e) {
      _brightnessLib = null;
    }
  }

  // Trailing-edge debounce: the monitor lags if updates arrive faster than
  // 40 ms apart, but the very last value of a drag burst must still land.
  Timer? _brightnessFx;
  Timer? _contrastFx;
  Timer? _warmthFx;

  void _setSystemBrightness(double value) {
    void apply() {
      if (value > 0.7) {
        _setBrightness?.call(0.7);
        _setBrightnessBoost?.call((value - 0.7) / 0.3);
      } else {
        _setBrightness?.call(value);
        _setBrightnessBoost?.call(0.0);
      }
      _lastBrightnessUpdate = DateTime.now();
    }

    final since =
        DateTime.now().difference(_lastBrightnessUpdate).inMilliseconds;
    _brightnessFx?.cancel();
    if (since > 40) {
      apply();
    } else {
      _brightnessFx = Timer(Duration(milliseconds: 40 - since), apply);
    }
  }

  void _setSystemContrast(double value) {
    void apply() {
      _setContrast?.call(value);
      _lastContrastUpdate = DateTime.now();
    }

    final since = DateTime.now().difference(_lastContrastUpdate).inMilliseconds;
    _contrastFx?.cancel();
    if (since > 40) {
      apply();
    } else {
      _contrastFx = Timer(Duration(milliseconds: 40 - since), apply);
    }
  }

  void _setSystemWarmth(double value) {
    void apply() {
      _setWarmth?.call(value);
      _lastWarmthUpdate = DateTime.now();
    }

    final since = DateTime.now().difference(_lastWarmthUpdate).inMilliseconds;
    _warmthFx?.cancel();
    if (since > 40) {
      apply();
    } else {
      _warmthFx = Timer(Duration(milliseconds: 40 - since), apply);
    }
  }

  Future<void> _playWithDelay() async {
    await Future.delayed(const Duration(milliseconds: 300));
    await _audioPlayer.stop();
    _currentTime = '0:00';
    _audioDuration = null;
    final file = _tracks[_selectedTrack]['file'];
    if (file != null && file.isNotEmpty) {
      await _audioPlayer.play(AssetSource('music/$file'));
    }
  }

  void _toggleTrackPlay() async {
    setState(() {
      _isPlaying = !_isPlaying;
    });
    
    if (_isPlaying) {
      _rotationController.repeat();
      _startTrackProgress();
      await _playWithDelay();
    } else {
      _rotationController.stop();
      _progressTimer?.cancel();
      await _audioPlayer.pause();
    }
  }

  void _startTrackProgress() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      final position = await _audioPlayer.getCurrentPosition();
      if (position != null && _audioDuration != null && _audioDuration!.inMilliseconds > 0 && mounted) {
        setState(() {
          _trackProgress = (position.inMilliseconds / _audioDuration!.inMilliseconds).clamp(0.0, 1.0);
        });
      }
    });
  }

  void _goToTrack(int index) {
    setState(() {
      _selectedTrack = index;
      _trackProgress = 0.0;
      _currentTime = '0:00';
      _audioDuration = null;
    });
    if (_isPlaying) {
      _startTrackProgress();
      _playWithDelay();
    } else {
      _audioPlayer.stop();
    }
  }

  int _pickNext() {
    if (_isShuffle && _tracks.length > 1) {
      final rnd = Random();
      var n = _selectedTrack;
      while (n == _selectedTrack) {
        n = rnd.nextInt(_tracks.length);
      }
      return n;
    }
    return (_selectedTrack + 1) % _tracks.length;
  }

  void _toggleLoop() {
    setState(() {
      _isLooping = !_isLooping;
    });
  }

  void _nextTrack() => _goToTrack(_pickNext());

  void _prevTrack() =>
      _goToTrack((_selectedTrack - 1 + _tracks.length) % _tracks.length);

  void _selectTrack(int index) => _goToTrack(index);

  void _seekTrack(double value) async {
    setState(() {
      _trackProgress = value.clamp(0.0, 1.0);
    });
    if (_audioDuration != null) {
      await _audioPlayer.seek(Duration(milliseconds: (_audioDuration!.inMilliseconds * value).toInt()));
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _backgroundTimer.cancel();
    _progressTimer?.cancel();
    _brightnessFx?.cancel();
    _contrastFx?.cancel();
    _warmthFx?.cancel();
    _audioPlayer.dispose();
    _rotationController.dispose();
    _menuMorph?.dispose();
    _brightnessMorph?.dispose();
    _playerMorph?.dispose();
    _brightnessLib = null;
    super.dispose();
  }

  String _formatTime(DateTime now) {
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _toggleMenu() {
    final m = _menuMorph;
    if (m == null) return;
    if (_isPlayerOpen) _playerMorph?.close();
    if (_isBrightnessOpen) _brightnessMorph?.close();
    m.toggle();
    setState(() {});
  }

  void _closeMenu() {
    if (_isMenuOpen) {
      _toggleMenu();
    }
  }

  void _toggleBrightness() {
    final m = _brightnessMorph;
    if (m == null) return;
    if (_isPlayerOpen) _playerMorph?.close();
    if (_isMenuOpen) _menuMorph?.close();
    m.toggle();
    setState(() {});
  }

  void _togglePlayer() {
    final m = _playerMorph;
    if (m == null) return;
    if (_isBrightnessOpen) _brightnessMorph?.close();
    if (_isMenuOpen) _menuMorph?.close();
    m.toggle();
    setState(() {});
  }

  void _toggleSettings() {
    setState(() {
      _isSettingsOpen = !_isSettingsOpen;
      _isSettingsMinimized = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const double panelWidth = 72.0;
    const double panelMargin = 5.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 1400),
            switchInCurve: Curves.fastOutSlowIn,
            switchOutCurve: Curves.fastOutSlowIn,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1.03, end: 1.0).animate(animation),
                  child: child,
                ),
              );
            },
            child: Container(
              key: ValueKey<int>(_currentBackgroundIndex),
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(_backgrounds[_currentBackgroundIndex]),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.35),
                ],
              ),
            ),
          ),
          Positioned(
            top: 20.0,
            left: 30.0,
            child: Transform(
              transform: Matrix4.diagonal3Values(0.85, 1.50, 1.0),
              alignment: Alignment.topLeft,
              child: Text(
                _timeString,
                style: TextStyle(
                  fontSize: 145,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withValues(alpha: 0.85),
                  letterSpacing: -6.0,
                  height: 0.8,
                ),
              ),
            ),
          ),
          if (_isMenuOpen || _isBrightnessOpen || _isPlayerOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  if (_isMenuOpen) _closeMenu();
                  if (_isBrightnessOpen) _toggleBrightness();
                  if (_isPlayerOpen) _togglePlayer();
                },
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.shrink(),
              ),
            ),
          Positioned(
            top: 0,
            left: MediaQuery.of(context).size.width / 2 - 350,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(25.0),
                bottomRight: Radius.circular(25.0),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  width: 700.0,
                  height: 60.0,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(25.0),
                      bottomRight: Radius.circular(25.0),
                    ),
                    border: const Border(
                      bottom: BorderSide(
                        color: Colors.white24,
                        width: 1.0,
                      ),
                      left: BorderSide(
                        color: Colors.white24,
                        width: 1.0,
                      ),
                      right: BorderSide(
                        color: Colors.white24,
                        width: 1.0,
                      ),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MouseRegion(
                              onEnter: (event) => setState(() => _isAppsHovered = true),
                              onExit: (event) => setState(() => _isAppsHovered = false),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _isAppsHovered ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10.0),
                                ),
                                child: const Icon(
                                  Icons.widgets_outlined,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _togglePlayer,
                              child: MouseRegion(
                                onEnter: (event) => setState(() => _isTopPanelHovered = true),
                                onExit: (event) => setState(() => _isTopPanelHovered = false),
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeInOut,
                                    height: 50,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(_isTopPanelHovered ? 10.0 : 20.0),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AnimatedBuilder(
                                          animation: _rotationController,
                                          builder: (context, child) {
                                            return Transform.rotate(
                                              angle: _rotationController.value * 2 * 3.14159,
                                              child: Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: Colors.grey,
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(10),
                                                  child: Image.asset(
                                                    _tracks[_selectedTrack]['avatar']?.isNotEmpty == true
                                                        ? _tracks[_selectedTrack]['avatar']!
                                                        : 'assets/music/ava-track-3.jpg',
                                                    width: 40,
                                                    height: 40,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context, error, stack) {
                                                      return Icon(
                                                        Icons.music_note,
                                                        color: Colors.white.withValues(alpha: 0.8),
                                                        size: 24,
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              _tracks[_selectedTrack]['title'] ?? '',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              _tracks[_selectedTrack]['artist'] ?? '',
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 10),
                                        GestureDetector(
                                          onTap: _toggleTrackPlay,
                                          child: Icon(
                                            _isPlaying ? Icons.pause : Icons.play_arrow_rounded,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 5,
                        top: 10,
                        child: Row(
                          children: [
                            MouseRegion(
                              onEnter: (event) => setState(() => _isBluetoothHovered = true),
                              onExit: (event) => setState(() => _isBluetoothHovered = false),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _isBluetoothHovered ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10.0),
                                ),
                                child: const Icon(Icons.bluetooth, color: Colors.white, size: 20),
                              ),
                            ),
                            const SizedBox(width: 4),
                            MouseRegion(
                              onEnter: (event) => setState(() => _isVolumeHovered = true),
                              onExit: (event) => setState(() => _isVolumeHovered = false),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _isVolumeHovered ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10.0),
                                ),
                                child: const Icon(Icons.volume_up, color: Colors.white, size: 20),
                              ),
                            ),
                            const SizedBox(width: 4),
                            MouseRegion(
                              onEnter: (event) => setState(() => _isWifiHovered = true),
                              onExit: (event) => setState(() => _isWifiHovered = false),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _isWifiHovered ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10.0),
                                ),
                                child: const Icon(Icons.wifi, color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 5,
                        top: 10,
                        child: MouseRegion(
                          onEnter: (event) => setState(() => _isBrightnessHovered = true),
                          onExit: (event) => setState(() => _isBrightnessHovered = false),
                          child: GestureDetector(
                            onTap: _toggleBrightness,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _isBrightnessHovered ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                              child: const Icon(Icons.brightness_6, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _brightnessMorph ?? const AlwaysStoppedAnimation<int>(0),
            builder: (context, _) {
              final morph = _brightnessMorph;
              final f = morph?.frame;
              if (morph == null || f == null) return const SizedBox.shrink();
              return MorphGlass(
                frame: f,
                restWidth: 350,
                restHeight: 180,
                interactive: !morph.animating,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.brightness_6, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: WaveSlider(
                              value: _brightness,
                              onChanged: (value) {
                                setState(() {
                                  _brightness = value;
                                });
                                _setSystemBrightness(value);
                              },
                            ),
                          ),
                          Text(
                            '${(_brightness * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _brightness = 0.7;
                              });
                              _setSystemBrightness(0.7);
                            },
                            icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.contrast, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: WaveSlider(
                              value: _contrast,
                              onChanged: (value) {
                                setState(() {
                                  _contrast = value;
                                });
                                _setSystemContrast(value);
                              },
                            ),
                          ),
                          Text(
                            '${(_contrast * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _contrast = 0.7;
                              });
                              _setSystemContrast(0.7);
                            },
                            icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.wb_sunny, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: WaveSlider(
                              value: _warmth,
                              onChanged: (value) {
                                setState(() {
                                  _warmth = value;
                                });
                                _setSystemWarmth(value);
                              },
                            ),
                          ),
                          Text(
                            '${(_warmth * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _warmth = 0.5;
                              });
                              _resetGamma?.call();
                            },
                            icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          ListenableBuilder(
            listenable: _menuMorph ?? const AlwaysStoppedAnimation<int>(0),
            builder: (context, _) {
              final morph = _menuMorph;
              final f = morph?.frame;
              if (morph == null || f == null) return const SizedBox.shrink();
              return MorphGlass(
                frame: f,
                restWidth: 700,
                restHeight: 550,
                interactive: !morph.animating,
                child: SizedBox(
                  width: 700,
                  height: 550,
                  child: Stack(
                    children: [
                      Positioned(
                        bottom: 1.0,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _PowerButton(
                              icon: Icons.description,
                              onTap: () {},
                            ),
                            const SizedBox(width: 1),
                            _PowerButton(
                              icon: Icons.restart_alt,
                              onTap: () {},
                            ),
                            const SizedBox(width: 1),
                            _PowerButton(
                              icon: Icons.power_settings_new,
                              onTap: () {},
                            ),
                            const SizedBox(width: 1),
                            _PowerButton(
                              icon: Icons.bedtime,
                              onTap: () {},
                            ),
                            const SizedBox(width: 1),
                            _PowerButton(
                              icon: Icons.settings,
                              onTap: _toggleSettings,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_isSettingsOpen && !_isSettingsMinimized)
            Positioned(
              top: MediaQuery.of(context).size.height / 2 - 260,
              left: MediaQuery.of(context).size.width / 2 - 425,
              child: SettingsApp(
                initialPosition: _settingsPosition,
                onPositionChanged: (pos) {
                  _settingsPosition = pos;
                },
                onClose: () {
                  setState(() {
                    _isSettingsOpen = false;
                    _isSettingsMinimized = false;
                  });
                },
                onMinimize: () {
                  setState(() {
                    _isSettingsOpen = false;
                    _isSettingsMinimized = true;
                  });
                },
              ),
            ),
          ListenableBuilder(
            listenable: _playerMorph ?? const AlwaysStoppedAnimation<int>(0),
            builder: (context, _) {
              final morph = _playerMorph;
              final f = morph?.frame;
              if (morph == null || f == null) return const SizedBox.shrink();
              return MorphGlass(
                frame: f,
                restWidth: 600,
                restHeight: 400,
                // The player styles its own halves: the left panel keeps a
                // dark blurred backdrop, the right list has none — only the
                // track cards carry a background there, no overall tint and
                // no white outline.
                tint: Colors.transparent,
                borderColor: Colors.transparent,
                interactive: !morph.animating,
                child: PlayerPanel(
                  isPlaying: _isPlaying,
                  selectedTrack: _selectedTrack,
                  progress: _trackProgress,
                  tracks: _tracks,
                  currentTime: _currentTime,
                  totalDuration: _totalDuration,
                  onTogglePlay: _toggleTrackPlay,
                  onNextTrack: _nextTrack,
                  onPrevTrack: _prevTrack,
                  onSeek: _seekTrack,
                  onSelectTrack: _selectTrack,
                  isLooping: _isLooping,
                  onToggleLoop: _toggleLoop,
                  isRepeatPlaylist: _isRepeatPlaylist,
                  onToggleRepeatPlaylist: (v) =>
                      setState(() => _isRepeatPlaylist = v),
                  isShuffle: _isShuffle,
                  onToggleShuffle: (v) => setState(() => _isShuffle = v),
                ),
              );
            },
          ),
          Positioned(
            top: 10.0,
            right: panelMargin,
            bottom: 10.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15.0),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  width: panelWidth,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(15.0),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1.0,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 5.0),
                  child: Column(
                    children: [
                      if (_isSettingsOpen || _isSettingsMinimized)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _isSettingsMinimized = false;
                                _isSettingsOpen = true;
                              });
                            },
                            child: Container(
                              width: 52,
                              height: 52,
                              margin: const EdgeInsets.only(top: 1),
                              decoration: BoxDecoration(
                                color: _isSettingsOpen && !_isSettingsMinimized
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Image.asset(
                                'assets/icons/settings-app-ico.png',
                                width: 40,
                                height: 40,
                                errorBuilder: (context, error, stack) {
                                  return const Icon(Icons.settings, color: Colors.white, size: 26);
                                },
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Center(
                          child: MouseRegion(
                            onEnter: (event) => setState(() => _isDotsHovered = true),
                            onExit: (event) => setState(() => _isDotsHovered = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              width: 52,
                              height: 100,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(_isDotsHovered ? 15.0 : 25.0),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      PanelIcon(
                        icon: _isMenuOpen ? Icons.close : Icons.apps,
                        onTap: _toggleMenu,
                        spacing: 1.0,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PanelIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double spacing;

  const PanelIcon({
    super.key,
    required this.icon,
    this.onTap,
    this.spacing = 8.0,
  });

  @override
  State<PanelIcon> createState() => _PanelIconState();
}

class _PanelIconState extends State<PanelIcon> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.spacing, horizontal: 10.0),
      child: MouseRegion(
        onEnter: (event) => setState(() => _isHovered = true),
        onExit: (event) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: GestureDetector(
          onTapDown: (details) => setState(() => _isPressed = true),
          onTapUp: (details) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.0),
              color: _isPressed
                  ? Colors.white.withValues(alpha: 0.3)
                  : _isHovered
                      ? Colors.white.withValues(alpha: 0.5)
                      : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class _PowerButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _PowerButton({
    required this.icon,
    this.onTap,
  });

  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: MouseRegion(
        onEnter: (event) => setState(() => _isHovered = true),
        onExit: (event) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: GestureDetector(
          onTapDown: (details) => setState(() => _isPressed = true),
          onTapUp: (details) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _isPressed
                  ? Colors.white.withValues(alpha: 0.3)
                  : _isHovered
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Icon(
              widget.icon,
              color: Colors.white,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}