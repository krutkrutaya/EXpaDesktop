import 'dart:async';
import 'dart:ffi';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'player.dart';
import 'settings-app.dart';
import 'package:audioplayers/audioplayers.dart';

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

  bool _isMenuOpen = false;
  bool _isDotsHovered = false;
  bool _isTopPanelHovered = false;
  bool _isPlaying = false;
  bool _isWifiHovered = false;
  bool _isBluetoothHovered = false;
  bool _isVolumeHovered = false;
  bool _isAppsHovered = false;
  bool _isBrightnessHovered = false;
  bool _isBrightnessOpen = false;
  bool _isPlayerOpen = false;
  bool _isSettingsOpen = false;
  bool _isSettingsMinimized = false;
  Offset _settingsPosition = Offset.zero;
  double _brightness = 0.7;
  double _contrast = 0.7;
  double _warmth = 0.5;
  int _selectedTrack = 0;
  double _trackProgress = 0.0;

  final List<Map<String, String>> _tracks = [
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
    ...List.generate(
      12,
      (i) => {
        'title': 'Test ${i + 4}',
        'artist': 'Test Artist ${i + 4}',
        'duration': '2:00',
        'avatar': '',
        'file': '',
      },
    ),
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

  late final AnimationController _menuAnimationController;
  late final Animation<double> _offsetAnimation;
  late final Animation<double> _opacityAnimation;
  
  late final AnimationController _rotationController;
  
  late final AnimationController _brightnessPanelController;
  late final Animation<double> _brightnessPanelAnimation;

  late final AnimationController _playerController;
  late final Animation<double> _playerOffsetAnimation;
  late final Animation<double> _playerOpacityAnimation;

  @override
  void initState() {
    super.initState();
    _timeString = _formatTime(DateTime.now());
    _loadBrightnessLib();
    _initAudioPlayer();

    _menuAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      reverseDuration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _offsetAnimation = Tween<double>(begin: 600.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _menuAnimationController,
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeInQuart,
      ),
    );

    _opacityAnimation = CurvedAnimation(
      parent: _menuAnimationController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      reverseCurve: const Interval(0.6, 1.0, curve: Curves.easeIn),
    );

    _rotationController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    _brightnessPanelController = AnimationController(
      duration: const Duration(milliseconds: 600),
      reverseDuration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _brightnessPanelAnimation = CurvedAnimation(
      parent: _brightnessPanelController,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInQuart,
    );

    _playerController = AnimationController(
      duration: const Duration(milliseconds: 600),
      reverseDuration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _playerOffsetAnimation = Tween<double>(begin: -400.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _playerController,
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeInQuart,
      ),
    );

    _playerOpacityAnimation = CurvedAnimation(
      parent: _playerController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      reverseCurve: const Interval(0.6, 1.0, curve: Curves.easeIn),
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
      if (mounted && _isPlaying) {
        _nextTrack();
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

  void _setSystemBrightness(double value) {
    final now = DateTime.now();
    if (now.difference(_lastBrightnessUpdate).inMilliseconds > 40) {
      if (value > 0.7) {
        _setBrightness?.call(0.7);
        _setBrightnessBoost?.call((value - 0.7) / 0.3);
      } else {
        _setBrightness?.call(value);
        _setBrightnessBoost?.call(0.0);
      }
      _lastBrightnessUpdate = now;
    }
  }

  void _setSystemContrast(double value) {
    final now = DateTime.now();
    if (now.difference(_lastContrastUpdate).inMilliseconds > 40) {
      _setContrast?.call(value);
      _lastContrastUpdate = now;
    }
  }

  void _setSystemWarmth(double value) {
    final now = DateTime.now();
    if (now.difference(_lastWarmthUpdate).inMilliseconds > 40) {
      _setWarmth?.call(value);
      _lastWarmthUpdate = now;
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

  void _nextTrack() async {
    setState(() {
      _selectedTrack = (_selectedTrack + 1) % _tracks.length;
      _trackProgress = 0.0;
      _currentTime = '0:00';
      _audioDuration = null;
    });
    if (_isPlaying) {
      _startTrackProgress();
      await _playWithDelay();
    }
  }

  void _prevTrack() async {
    setState(() {
      _selectedTrack = (_selectedTrack - 1 + _tracks.length) % _tracks.length;
      _trackProgress = 0.0;
      _currentTime = '0:00';
      _audioDuration = null;
    });
    if (_isPlaying) {
      _startTrackProgress();
      await _playWithDelay();
    }
  }

  void _seekTrack(double value) async {
    setState(() {
      _trackProgress = value.clamp(0.0, 1.0);
    });
    if (_audioDuration != null) {
      await _audioPlayer.seek(Duration(milliseconds: (_audioDuration!.inMilliseconds * value).toInt()));
    }
  }

  void _selectTrack(int index) async {
    setState(() {
      _selectedTrack = index;
      _trackProgress = 0.0;
      _currentTime = '0:00';
      _audioDuration = null;
    });
    if (_isPlaying) {
      _startTrackProgress();
      await _playWithDelay();
    } else {
      await _audioPlayer.stop();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _backgroundTimer.cancel();
    _progressTimer?.cancel();
    _audioPlayer.dispose();
    _menuAnimationController.dispose();
    _rotationController.dispose();
    _brightnessPanelController.dispose();
    _playerController.dispose();
    _brightnessLib = null;
    super.dispose();
  }

  String _formatTime(DateTime now) {
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _toggleMenu() {
    setState(() {
      if (_isPlayerOpen) {
        _isPlayerOpen = false;
        _playerController.reverse();
      }
      if (_isBrightnessOpen) {
        _isBrightnessOpen = false;
        _brightnessPanelController.reverse();
      }
      _isMenuOpen = !_isMenuOpen;
      if (_isMenuOpen) {
        _menuAnimationController.forward();
      } else {
        _menuAnimationController.reverse();
      }
    });
  }

  void _closeMenu() {
    if (_isMenuOpen) {
      _toggleMenu();
    }
  }

  void _toggleBrightness() {
    setState(() {
      if (_isPlayerOpen) {
        _isPlayerOpen = false;
        _playerController.reverse();
      }
      if (_isMenuOpen) {
        _isMenuOpen = false;
        _menuAnimationController.reverse();
      }
      _isBrightnessOpen = !_isBrightnessOpen;
      if (_isBrightnessOpen) {
        _brightnessPanelController.forward();
      } else {
        _brightnessPanelController.reverse();
      }
    });
  }

  void _togglePlayer() {
    setState(() {
      if (_isBrightnessOpen) {
        _isBrightnessOpen = false;
        _brightnessPanelController.reverse();
      }
      if (_isMenuOpen) {
        _isMenuOpen = false;
        _menuAnimationController.reverse();
      }
      _isPlayerOpen = !_isPlayerOpen;
      if (_isPlayerOpen) {
        _playerController.forward();
      } else {
        _playerController.reverse();
      }
    });
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
          Positioned(
            top: 0,
            left: MediaQuery.of(context).size.width / 2 - 350,
            child: AnimatedBuilder(
              animation: _brightnessPanelAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -191 + (_brightnessPanelAnimation.value * 251)),
                  child: Opacity(
                    opacity: _brightnessPanelAnimation.value,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(25.0),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Container(
                          width: 350,
                          height: 180,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(25.0),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 1.0,
                            ),
                          ),
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
                                      child: Slider(
                                        value: _brightness,
                                        onChanged: (value) {
                                          setState(() {
                                            _brightness = value;
                                          });
                                          _setSystemBrightness(value);
                                        },
                                        activeColor: Colors.white,
                                        inactiveColor: Colors.white24,
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
                                      child: Slider(
                                        value: _contrast,
                                        onChanged: (value) {
                                          setState(() {
                                            _contrast = value;
                                          });
                                          _setSystemContrast(value);
                                        },
                                        activeColor: Colors.white,
                                        inactiveColor: Colors.white24,
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
                                      child: Slider(
                                        value: _warmth,
                                        onChanged: (value) {
                                          setState(() {
                                            _warmth = value;
                                          });
                                          _setSystemWarmth(value);
                                        },
                                        activeColor: Colors.white,
                                        inactiveColor: Colors.white24,
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
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: 20,
            right: panelWidth + panelMargin + 12.0,
            child: AnimatedBuilder(
              animation: _menuAnimationController,
              builder: (context, _) {
                return Transform.translate(
                  offset: Offset(0, _offsetAnimation.value),
                  child: FadeTransition(
                    opacity: _opacityAnimation,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15.0),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Container(
                          width: 700.0,
                          height: 550.0,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(15.0),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 30,
                                offset: const Offset(-10, 10),
                              ),
                            ],
                          ),
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
                      ),
                    ),
                  ),
                );
              },
            ),
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
          Positioned(
            top: 70,
            left: MediaQuery.of(context).size.width / 2 - 300,
            child: AnimatedBuilder(
              animation: _playerController,
              builder: (context, _) {
                return Transform.translate(
                  offset: Offset(0, _playerOffsetAnimation.value),
                  child: FadeTransition(
                    opacity: _playerOpacityAnimation,
                    child: IgnorePointer(
                      ignoring: !_isPlayerOpen,
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
                      ),
                    ),
                  ),
                );
              },
            ),
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