import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'player.dart';
import 'settings_app.dart';
import 'system_actions.dart';
import 'system_actions.dart' as sys;
import 'command_router.dart';
import 'id3_art.dart';
import 'shell_layout.dart';
import 'workspaces.dart';
import 'radio_control.dart';
import 'shell_panels.dart';
import 'sound_control.dart';
import 'track_art.dart';
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
  const MyHomePage({super.key, this.radio, this.sound});

  /// Test seams: the widget tests pass recorders so no test spawns
  /// PowerShell or moves the machine's volume.
  final RadioSource? radio;
  final SoundSource? sound;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with TickerProviderStateMixin
    implements SystemCommandSink {
  late String _timeString;
  late Timer _timer;
  late Timer _backgroundTimer;
  Timer? _progressTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _currentTime = '0:00';
  String _totalDuration = '2:00';
  Duration? _audioDuration;

  /// In-app desktops: each one keeps its own wallpaper.
  late final WorkspaceController _workspaces;
  final List<String> _backgrounds = [
    'assets/fons/fon1.jpg',
    'assets/fons/fon2.jpg',
    'assets/fons/fon3.jpg',
    'assets/fons/fon4.jpg',
    'assets/fons/fon5.jpg',
    'assets/fons/fon6.jpg',
    'assets/fons/fon8.jpg',
  ];

  bool _isDesktopsHovered = false;
  bool _isTopPanelHovered = false;
  bool _isPlaying = false;

  /// Whether a track is sitting in the player, paused or playing. Pause keeps
  /// it true, so play resumes instead of restarting the track.
  bool _trackLoaded = false;
  bool _isWifiHovered = false;
  bool _isBluetoothHovered = false;
  bool _isVolumeHovered = false;
  bool _isAppsHovered = false;
  bool _isBrightnessHovered = false;
  bool _isSettingsOpen = false;
  bool _isSettingsMinimized = false;
  Offset _settingsPosition = Offset.zero;

  // Which section the settings window shows: 'wifi', 'bluetooth', 'sound'.
  String? _settingsSection;

  /// Drives the settings window's own springs: it shrinks into the dock
  /// instead of vanishing when another surface takes the middle of the screen.
  final SettingsAppController _settingsController = SettingsAppController();

  // The radios' real state, mirrored from the system for the top bar.
  RadioStatus _wifiStatus = const RadioStatus(
    kind: RadioKind.wifi,
    state: RadioState.unknown,
  );
  RadioStatus _bluetoothStatus = const RadioStatus(
    kind: RadioKind.bluetooth,
    state: RadioState.unknown,
  );
  Timer? _radioTimer;

  // The command line: Ctrl+Alt+Space opens it, Enter runs the phrase.
  final TextEditingController _commandController = TextEditingController();
  final FocusNode _commandFocus = FocusNode();
  bool _commandBarOpen = false;
  String _commandReply = '';
  Timer? _replyTimer;
  late final CommandRouter _router;

  RadioSource get _radioSource => widget.radio ?? RadioControl.instance;
  SoundSource get _soundSource => widget.sound ?? SoundControl.instance;

  double _brightness = 0.7;
  double _contrast = 0.7;

  /// 0 is neutral: [set_warmth] multiplies the red/blue channels down as the
  /// value grows, so 0.5 was actually a strong warm cast and the panel lied
  /// about the screen's real state.
  double _warmth = 0.0;
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
  MorphPanelController? _volumeMorph;
  MorphPanelController? _launcherMorph;
  MorphPanelController? _desktopsMorph;

  bool get _isMenuOpen => _menuMorph?.active ?? false;
  bool get _isBrightnessOpen => _brightnessMorph?.active ?? false;
  bool get _isPlayerOpen => _playerMorph?.active ?? false;
  bool get _isVolumeOpen => _volumeMorph?.active ?? false;
  bool get _isLauncherOpen => _launcherMorph?.active ?? false;
  bool get _isDesktopsOpen => _desktopsMorph?.active ?? false;

  // System volume mirrored from the audio endpoint; the mini panel reads it
  // on open and writes it on drag.
  double _volume = 0.7;
  bool _muted = false;

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
  /// Cover art pulled out of the mp3 tags, keyed by file name.
  Map<String, Uint8List> _covers = {};

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
    _workspaces = WorkspaceController(backgroundCount: _backgrounds.length);
    _loadBrightnessLib();
    _initAudioPlayer();
    _router = CommandRouter(sink: this);
    unawaited(_refreshRadios());
    _radioTimer = Timer.periodic(const Duration(seconds: 45), (timer) {
      unawaited(_refreshRadios());
    });

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
          _workspaces.cycleBackground();
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

    // Every file is asked for its own ID3 tags: a real title, a real artist
    // and the cover art that is already inside the mp3. No hard-coded table.
    final tracks = <Map<String, String>>[];
    final covers = <String, Uint8List>{};
    for (final file in files) {
      final track = _trackFromFile(file);
      try {
        final data = await rootBundle.load('$_musicPrefix$file');
        final tags = parseId3(data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ));
        if (tags != null) {
          if (tags.title != null) track['title'] = tags.title!;
          if (tags.artist != null) track['artist'] = tags.artist!;
          if (tags.cover != null) covers[file] = tags.cover!;
        }
      } catch (_) {
        // A broken file must not take the whole list down.
      }
      tracks.add(track);
    }

    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _covers = covers;
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

    // Where each panel's glass is born from, and where it lands. The numbers
    // live in [ShellLayout] so the mock suite can check every one of them
    // against the dock and the screen edges on any window size.
    final l = ShellLayout(size.width, size.height);

    if (_menuMorph == null) {
      _menuMorph = MorphPanelController(
        buttonRect: l.menuButton,
        menuRect: l.menuRect,
        menuRadius: 15.0,
      )..attach(this);
      _brightnessMorph = MorphPanelController(
        buttonRect: l.brightnessButton,
        menuRect: l.brightnessRect,
        menuRadius: 25.0,
      )..attach(this);
      _playerMorph = MorphPanelController(
        buttonRect: l.playerButton,
        menuRect: l.playerRect,
        menuRadius: 25.0,
      )..attach(this);
      _volumeMorph = MorphPanelController(
        buttonRect: l.volumeButton,
        menuRect: l.volumeRect,
        menuRadius: 20.0,
      )..attach(this);
      _launcherMorph = MorphPanelController(
        buttonRect: l.launcherButton,
        menuRect: l.launcherRect,
        menuRadius: 20.0,
      )..attach(this);
      _desktopsMorph = MorphPanelController(
        buttonRect: l.desktopsButton,
        menuRect: l.desktopsRect,
        menuRadius: 20.0,
      )..attach(this);
    } else {
      _menuMorph!.retarget(l.menuButton, l.menuRect, 15.0);
      _brightnessMorph!.retarget(l.brightnessButton, l.brightnessRect, 25.0);
      _playerMorph!.retarget(l.playerButton, l.playerRect, 25.0);
      _volumeMorph!.retarget(l.volumeButton, l.volumeRect, 20.0);
      _launcherMorph!.retarget(l.launcherButton, l.launcherRect, 20.0);
      _desktopsMorph!.retarget(l.desktopsButton, l.desktopsRect, 20.0);
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
      // Next to the exe in a release build (CMake copies it there), or in
      // lib/rust/ when running from the project with `flutter run`.
      Object? lastError;
      for (final candidate in const [
        'brightness.dll',
        'lib/rust/brightness.dll',
        'data/flutter_assets/lib/rust/brightness.dll',
      ]) {
        try {
          _brightnessLib = DynamicLibrary.open(candidate);
          break;
        } catch (e) {
          lastError = e;
        }
      }
      if (_brightnessLib == null) throw lastError ?? 'brightness.dll not found';
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

  /// Loads the selected track into the player and fades it in.
  ///
  /// The fade is deliberate: starting a track at full level slams the room
  /// with sound. Ten steps of ~24 ms is short enough to feel instant.
  Future<void> _playCurrentTrack() async {
    final file = _tracks[_selectedTrack]['file'];
    if (file == null || file.isEmpty) return;
    await _audioPlayer.setVolume(0.0);
    await _audioPlayer.play(AssetSource('music/$file'));
    _trackLoaded = true;
    unawaited(_fadeIn());
  }

  Future<void> _fadeIn() async {
    for (var step = 1; step <= 10; step++) {
      if (!mounted || !_isPlaying) return;
      await _audioPlayer.setVolume(step / 10);
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
    if (mounted && _isPlaying) await _audioPlayer.setVolume(1.0);
  }

  Future<void> _toggleTrackPlay() async {
    final next = !_isPlaying;
    setState(() {
      _isPlaying = next;
    });

    if (!next) {
      _rotationController.stop();
      _progressTimer?.cancel();
      // Pause, not stop: the next tap has to continue where this one left.
      await _audioPlayer.pause();
      return;
    }

    _rotationController.repeat();
    _startTrackProgress();
    if (_trackLoaded) {
      await _audioPlayer.resume();
      await _audioPlayer.setVolume(1.0);
    } else {
      await _playCurrentTrack();
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
    _trackLoaded = false;
    if (_isPlaying) {
      _startTrackProgress();
      unawaited(_playCurrentTrack());
    } else {
      // Nothing is playing: the next tap starts the freshly selected track.
      unawaited(_audioPlayer.stop());
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
    _radioTimer?.cancel();
    _replyTimer?.cancel();
    _commandController.dispose();
    _commandFocus.dispose();
    _audioPlayer.dispose();
    _rotationController.dispose();
    _menuMorph?.dispose();
    _brightnessMorph?.dispose();
    _playerMorph?.dispose();
    _volumeMorph?.dispose();
    _launcherMorph?.dispose();
    _desktopsMorph?.dispose();
    _brightnessLib = null;
    super.dispose();
  }

  String _formatTime(DateTime now) {
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Closes whatever would overlap [opening] and minimises the settings
  /// window when the opening surface needs the middle of the screen.
  ///
  /// The rule lives in [PanelPolicy]; this only translates it into morph
  /// calls. Before this existed, opening the settings window left the
  /// launcher (the nine dots) standing behind it.
  void _applyPanelPlan(ShellPanel opening) {
    final plan = PanelPolicy.plan(opening);
    for (final panel in plan.toClose) {
      switch (panel) {
        case ShellPanel.menu:
          if (_isMenuOpen) _menuMorph?.close();
        case ShellPanel.launcher:
          if (_isLauncherOpen) _launcherMorph?.close();
        case ShellPanel.brightness:
          if (_isBrightnessOpen) _brightnessMorph?.close();
        case ShellPanel.volume:
          if (_isVolumeOpen) _volumeMorph?.close();
        case ShellPanel.player:
          if (_isPlayerOpen) _playerMorph?.close();
        case ShellPanel.desktops:
          if (_isDesktopsOpen) _desktopsMorph?.close();
        case ShellPanel.settings:
          break;
      }
    }
    if (plan.minimizeSettings && _isSettingsOpen && !_isSettingsMinimized) {
      // The window animates itself into the dock; its onMinimize callback
      // flips the flags when the spring lands.
      _settingsController.minimize();
    }
  }

  void _toggleMenu() {
    final m = _menuMorph;
    if (m == null) return;
    _applyPanelPlan(ShellPanel.menu);
    m.toggle();
    setState(() {});
  }

  /// A click on the bare desktop closes every floating surface.
  ///
  /// The settings window is a window, not a flyout: it keeps its title bar
  /// and its X, and stays where it is. Everything else is transient.
  void _dismissFloatingSurfaces() {
    if (!_isVolumeOpen &&
        !_isBrightnessOpen &&
        !_isPlayerOpen &&
        !_isMenuOpen &&
        !_isLauncherOpen &&
        !_isDesktopsOpen) {
      return;
    }
    if (_isVolumeOpen) _volumeMorph?.close();
    if (_isBrightnessOpen) _brightnessMorph?.close();
    if (_isPlayerOpen) _playerMorph?.close();
    if (_isMenuOpen) _menuMorph?.close();
    if (_isLauncherOpen) _launcherMorph?.close();
    if (_isDesktopsOpen) _desktopsMorph?.close();
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
    _applyPanelPlan(ShellPanel.brightness);
    m.toggle();
    setState(() {});
  }

  void _togglePlayer() {
    final m = _playerMorph;
    if (m == null) return;
    _applyPanelPlan(ShellPanel.player);
    m.toggle();
    setState(() {});
  }

  /// The sound flyout. It only ever opens the panel: the sound itself is
  /// changed by the panel, and nothing on this path can hide the desktop.
  void _toggleVolume() {
    final m = _volumeMorph;
    if (m == null) return;
    _applyPanelPlan(ShellPanel.volume);
    if (!m.active) {
      // Read the real device state so the panel opens honest.
      final sound = _soundSource;
      sound.refresh();
      setState(() {
        _volume = sound.volume;
        _muted = sound.muted;
      });
    }
    m.toggle();
    setState(() {});
  }

  /// Workspace actions from the docker panel: everything happens inside the
  /// shell, no Windows desktops involved.
  void _runWorkspaceAction(void Function() action) {
    setState(action);
    _desktopsMorph?.close();
  }

  /// The four dots in the middle of the dock: virtual desktops.
  void _toggleDesktops() {
    final m = _desktopsMorph;
    if (m == null) return;
    _applyPanelPlan(ShellPanel.desktops);
    m.toggle();
    setState(() {});
  }

  void _toggleLauncher() {
    final m = _launcherMorph;
    if (m == null) return;
    _applyPanelPlan(ShellPanel.launcher);
    m.toggle();
    setState(() {});
  }

  Future<void> _launchTerminal() async {
    try {
      await Process.start('wt.exe', [], mode: ProcessStartMode.detached);
    } catch (_) {
      await launchExe('cmd.exe');
    }
  }

  // The launcher is a compact rounded rectangle in the middle of the
  // screen: nine icons in a 3x3 wrap, not a tall column of rows. Built
  // fresh on each build so the tiles feel the theme.
  List<Widget> get _launcherTiles => [
          _LauncherTile(
            icon: Icons.calculate_outlined,
            label: 'Калькулятор',
            onTap: () => unawaited(
              launchAppFolder('Microsoft.WindowsCalculator_8wekyb3d8bbwe!App'),
            ),
          ),
          _LauncherTile(
            icon: Icons.notes_outlined,
            label: 'Блокнот',
            onTap: () => unawaited(launchExe('notepad.exe')),
          ),
          _LauncherTile(
            icon: Icons.folder_outlined,
            label: 'Файлы',
            onTap: () => unawaited(launchExe('explorer.exe')),
          ),
          _LauncherTile(
            icon: Icons.brush_outlined,
            label: 'Paint',
            onTap: () => unawaited(launchExe('mspaint.exe')),
          ),
          _LauncherTile(
            icon: Icons.photo_camera_outlined,
            label: 'Снимок',
            onTap: () => unawaited(openShellLocation('ms-screenclip:')),
          ),
          _LauncherTile(
            icon: Icons.donut_large_outlined,
            label: 'Задачи',
            onTap: () => unawaited(launchExe('taskmgr.exe')),
          ),

          _LauncherTile(
            icon: Icons.public_outlined,
            label: 'Браузер',
            onTap: () => unawaited(launchExe('msedge.exe')),
          ),

      ];

  /// Asks once, then applies: restart, shutdown, sleep and sign-out go
  /// through this so one accidental press cannot turn the PC off. Takes the
  /// action unstarted — it fires only after the user confirms.
  void _confirmThen(Future<void> Function() action, String question) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xF01A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          question,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(action());
            },
            child: const Text(
              'Да',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the shell's own settings, optionally at a given section.
  void _openSettingsAt(String? section) {
    // The launcher, the power menu and the top-bar flyouts all have to get
    // out of the way: the settings window lands in the middle of the screen.
    _applyPanelPlan(ShellPanel.settings);
    setState(() {
      _settingsSection = section;
      _isSettingsOpen = true;
      _isSettingsMinimized = false;
    });
    if (section == 'wifi' || section == 'bluetooth') {
      unawaited(_refreshRadios());
    }
  }

  void _toggleSettings() {
    if (_isSettingsOpen && !_isSettingsMinimized) {
      _settingsController.close();
      return;
    }
    _openSettingsAt(null);
  }

  /// Reads both radios from the system, so the top bar shows the truth.
  Future<void> _refreshRadios() async {
    final wifi = await _radioSource.status(RadioKind.wifi);
    final bluetooth = await _radioSource.status(RadioKind.bluetooth);
    if (!mounted) return;
    setState(() {
      _wifiStatus = wifi;
      _bluetoothStatus = bluetooth;
    });
  }

  // ---- the command line ------------------------------------------------------

  /// Ctrl+Alt+Space opens the command line, Escape closes it. The bindings
  /// go through the focus system ([CallbackShortcuts]), not through
  /// [HardwareKeyboard.addHandler]: its callback type changed shape between
  /// Flutter versions, and the focus path is the documented one.
  Map<ShortcutActivator, VoidCallback> get _shortcutBindings => {
        const SingleActivator(
          LogicalKeyboardKey.space,
          control: true,
          alt: true,
        ): _toggleCommandBar,
        if (_commandBarOpen)
          const SingleActivator(LogicalKeyboardKey.escape): _toggleCommandBar,
      };

  void _toggleCommandBar() {
    setState(() {
      _commandBarOpen = !_commandBarOpen;
      _commandReply = '';
    });
    if (_commandBarOpen) {
      _commandFocus.requestFocus();
    } else {
      _commandController.clear();
    }
  }

  Future<void> _submitCommand() async {
    final text = _commandController.text.trim();
    if (text.isEmpty) return;
    final reply = await _router.run(text);
    if (!mounted) return;
    setState(() {
      _commandReply = reply;
      _commandController.clear();
    });
    _replyTimer?.cancel();
    _replyTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _commandReply = '');
    });
  }

  Widget _buildCommandBar() {
    final width = MediaQuery.of(context).size.width;
    return Positioned(
      top: 64,
      left: width / 2 - 250,
      child: Container(
        width: 500,
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal, color: Colors.white54, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    focusNode: _commandFocus,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText:
                          'включи вайфай • громкость 40 • открой настройки звука',
                      hintStyle:
                          TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                    onSubmitted: (value) => _submitCommand(),
                  ),
                ),
                IconButton(
                  onPressed: _toggleCommandBar,
                  icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
            if (_commandReply.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _commandReply,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- SystemCommandSink -----------------------------------------------------

  @override
  Future<double> setVolume(double value) async {
    final sound = _soundSource;
    sound.volume = value;
    if (mounted) {
      setState(() {
        _volume = sound.volume;
        _muted = sound.muted;
      });
    }
    return sound.volume;
  }

  @override
  Future<double> stepVolume(double direction) async {
    final sound = _soundSource;
    sound.stepVolume(direction);
    if (mounted) {
      setState(() {
        _volume = sound.volume;
        _muted = sound.muted;
      });
    }
    return sound.volume;
  }

  @override
  Future<bool> setMuted(bool muted) async {
    final sound = _soundSource;
    sound.muted = muted;
    if (mounted) {
      setState(() {
        _muted = sound.muted;
        _volume = sound.volume;
      });
    }
    return sound.muted;
  }

  @override
  Future<RadioStatus> setRadioPower(RadioKind kind, bool on) async {
    final result = await _radioSource.setPower(kind, on);
    if (mounted) {
      setState(() {
        if (kind == RadioKind.wifi) {
          _wifiStatus = result.status;
        } else {
          _bluetoothStatus = result.status;
        }
      });
    }
    return result.status;
  }

  @override
  Future<void> openBuiltInSection(String sectionId) async {
    _openSettingsAt(sectionId);
  }

  @override
  Future<void> openWindowsPage(String uri) async {
    await openSettingsPage(uri);
  }

  @override
  Future<void> setBrightness(double value) async {
    final level = value.clamp(0.0, 1.0);
    setState(() {
      _brightness = level;
    });
    _setSystemBrightness(level);
  }

  @override
  Future<void> adjustBrightness(double direction) async {
    final level = (_brightness + 0.05 * direction).clamp(0.0, 1.0);
    setState(() {
      _brightness = level;
    });
    _setSystemBrightness(level);
  }

  @override
  Future<void> mediaPlayPause() async {
    _toggleTrackPlay();
  }

  @override
  Future<void> mediaNext() async {
    _nextTrack();
  }

  @override
  Future<void> mediaPrevious() async {
    _prevTrack();
  }

  @override
  Future<void> lockScreen() async {
    lockWorkstation();
  }

  @override
  Future<void> sleepMachine() => sys.sleepMachine();

  @override
  Future<void> signOut() => sys.signOut();

  @override
  Future<void> restartMachine() => sys.restartMachine();

  @override
  Future<void> shutdownMachine() => sys.shutdownMachine();

  @override
  Widget build(BuildContext context) {
    const double panelWidth = 72.0;
    const double panelMargin = 5.0;

    // The shell owns its shortcuts through the focus system, not through
    // HardwareKeyboard.addHandler: the callback type there changed shape
    // between Flutter versions, and this way the key event is consumed
    // instead of leaking into whatever has the focus.
    final shell = Scaffold(
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
              key: ValueKey<String>(
                '${_workspaces.activeIndex}-${_workspaces.active.backgroundIndex}',
              ),
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(
                    _backgrounds[
                      _workspaces.active.backgroundIndex % _backgrounds.length
                    ],
                  ),
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
          // Tap-away layer: sits under every panel, so a click on the bare
          // desktop closes the flyouts and the launcher. Panels are above it
          // and swallow their own clicks.
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('desktop-backdrop'),
              behavior: HitTestBehavior.opaque,
              onTap: _dismissFloatingSurfaces,
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
          if (_isMenuOpen ||
              _isBrightnessOpen ||
              _isPlayerOpen ||
              _isVolumeOpen ||
              _isLauncherOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  if (_isMenuOpen) _closeMenu();
                  if (_isBrightnessOpen) _toggleBrightness();
                  if (_isPlayerOpen) _togglePlayer();
                  if (_isVolumeOpen) _toggleVolume();
                  if (_isLauncherOpen) _toggleLauncher();
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
                                              // The same artwork rule as the
                                              // full player: embedded cover,
                                              // then the bundled image, then
                                              // the shell's own placeholder.
                                              child: TrackArt(
                                                cover: _covers[_tracks[_selectedTrack]['file']],
                                                avatar: _tracks[_selectedTrack]['avatar'],
                                                size: 40,
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
                              child: GestureDetector(
                                key: const ValueKey('topbar-bluetooth'),
                                // The radio lives in the shell's own settings
                                // now: the button takes the user there, and
                                // the switch there really flips the radio.
                                onTap: () => _openSettingsAt('bluetooth'),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _isBluetoothHovered ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Icon(
                                    Icons.bluetooth,
                                    color: _bluetoothStatus.isOn
                                        ? Colors.white
                                        : Colors.white38,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            MouseRegion(
                              onEnter: (event) => setState(() => _isVolumeHovered = true),
                              onExit: (event) => setState(() => _isVolumeHovered = false),
                              child: GestureDetector(
                                key: const ValueKey('topbar-volume'),
                                // Sound only: the panel opens, the desktop
                                // stays exactly where it is.
                                onTap: _toggleVolume,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _isVolumeHovered ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Icon(
                                    _muted ? Icons.volume_off : Icons.volume_up,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            MouseRegion(
                              onEnter: (event) => setState(() => _isWifiHovered = true),
                              onExit: (event) => setState(() => _isWifiHovered = false),
                              child: GestureDetector(
                                key: const ValueKey('topbar-wifi'),
                                onTap: () => _openSettingsAt('wifi'),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _isWifiHovered ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Icon(
                                    Icons.wifi,
                                    color: _wifiStatus.isOn
                                        ? Colors.white
                                        : Colors.white38,
                                    size: 20,
                                  ),
                                ),
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
                                _warmth = 0.0;
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
            listenable: _volumeMorph ?? const AlwaysStoppedAnimation<int>(0),
            builder: (context, _) {
              final morph = _volumeMorph;
              final f = morph?.frame;
              if (morph == null || f == null) return const SizedBox.shrink();
              return MorphGlass(
                frame: f,
                restWidth: 320,
                restHeight: 100,
                interactive: !morph.animating,
                child: Padding(
                  key: const ValueKey('volume-flyout'),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          final sound = _soundSource;
                          setState(() {
                            sound.muted = !sound.muted;
                            _muted = sound.muted;
                            _volume = sound.volume;
                          });
                        },
                        icon: Icon(
                          _muted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                          size: 22,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: WaveSlider(
                          value: _muted ? 0.0 : _volume,
                          onChanged: (value) {
                            final sound = _soundSource;
                            setState(() {
                              sound.volume = value;
                              _volume = sound.volume;
                              _muted = sound.muted;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _muted ? 'Mute' : '${(_volume * 100).round()}%',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          ListenableBuilder(
            listenable: _launcherMorph ?? const AlwaysStoppedAnimation<int>(0),
            builder: (context, _) {
              final morph = _launcherMorph;
              final f = morph?.frame;
              if (morph == null || f == null) return const SizedBox.shrink();
              return MorphGlass(
                frame: f,
                restWidth: 320,
                restHeight: 296,
                interactive: !morph.animating,
                child: SizedBox(
                  width: 320,
                  height: 296,
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: Column(
                      children: [
                        // The app grid: a compact rounded rectangle.
                        SizedBox(
                          width: 298,
                          height: 210,
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            runAlignment: WrapAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            children: _launcherTiles,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // A strip of shell actions, the same width as the grid.
                        _LauncherStrip(
                          onSettings: () {
                            _launcherMorph?.close();
                            _openSettingsAt(null);
                          },
                          onPower: () {
                            _launcherMorph?.close();
                            _toggleMenu();
                          },
                          onTerminal: () {
                            _launcherMorph?.close();
                            unawaited(_launchTerminal());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          ListenableBuilder(
            listenable: _desktopsMorph ?? const AlwaysStoppedAnimation<int>(0),
            builder: (context, _) {
              final morph = _desktopsMorph;
              final f = morph?.frame;
              if (morph == null || f == null) return const SizedBox.shrink();
              return MorphGlass(
                frame: f,
                restWidth: 320,
                restHeight: 250,
                interactive: !morph.animating,
                child: SizedBox(
                  width: 320,
                  height: 250,
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Рабочий стол ${_workspaces.activeIndex + 1} из ${_workspaces.count}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        // One chip per desktop: tap to jump straight there.
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var i = 0; i < _workspaces.count; i++)
                              GestureDetector(
                                key: ValueKey('workspace-chip-$i'),
                                onTap: () => setState(() {
                                  _workspaces.select(i);
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 34,
                                  height: 30,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: i == _workspaces.activeIndex ? 0.85 : 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      color: i == _workspaces.activeIndex
                                          ? Colors.black
                                          : Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _LauncherTile(
                              icon: Icons.add_to_photos_outlined,
                              label: 'Новый',
                              onTap: () => _runWorkspaceAction(() {
                                _workspaces.create();
                              }),
                            ),
                            const SizedBox(width: 6),
                            _LauncherTile(
                              icon: Icons.arrow_back,
                              label: 'Назад',
                              onTap: () => _runWorkspaceAction(_workspaces.previous),
                            ),
                            const SizedBox(width: 6),
                            _LauncherTile(
                              icon: Icons.arrow_forward,
                              label: 'Вперёд',
                              onTap: () => _runWorkspaceAction(_workspaces.next),
                            ),
                            const SizedBox(width: 6),
                            _LauncherTile(
                              icon: Icons.delete_outline,
                              label: 'Закрыть',
                              onTap: () => _runWorkspaceAction(() {
                                _workspaces.closeActive();
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),          ListenableBuilder(
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
                            const _PowerButton(
                              icon: Icons.lock_outline,
                              onTap: lockWorkstation,
                            ),
                            const SizedBox(width: 1),
                            _PowerButton(
                              icon: Icons.logout,
                              onTap: () => _confirmThen(
                                signOut,
                                'Выйти из системы?',
                              ),
                            ),
                            const SizedBox(width: 1),
                            _PowerButton(
                              icon: Icons.restart_alt,
                              onTap: () => _confirmThen(
                                restartMachine,
                                'Перезагрузить компьютер?',
                              ),
                            ),
                            const SizedBox(width: 1),
                            _PowerButton(
                              icon: Icons.bedtime,
                              onTap: () => _confirmThen(
                                sleepMachine,
                                'Усыпить компьютер?',
                              ),
                            ),
                            const SizedBox(width: 1),
                            _PowerButton(
                              icon: Icons.power_settings_new,
                              onTap: () => _confirmThen(
                                shutdownMachine,
                                'Выключить компьютер?',
                              ),
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
                initialSection: _settingsSection,
                controller: _settingsController,
                radio: widget.radio,
                sound: widget.sound,
                display: DisplaySettings(
                  brightness: _brightness,
                  contrast: _contrast,
                  warmth: _warmth,
                  onBrightness: (value) {
                    setState(() {
                      _brightness = value;
                    });
                    _setSystemBrightness(value);
                  },
                  onContrast: (value) {
                    setState(() {
                      _contrast = value;
                    });
                    _setSystemContrast(value);
                  },
                  onWarmth: (value) {
                    setState(() {
                      _warmth = value;
                    });
                    _setSystemWarmth(value);
                  },
                ),
                onPositionChanged: (pos) {
                  _settingsPosition = pos;
                },
                onClose: () {
                  setState(() {
                    _isSettingsOpen = false;
                    _isSettingsMinimized = false;
                    _settingsSection = null;
                  });
                  unawaited(_refreshRadios());
                },
                onMinimize: () {
                  setState(() {
                    _isSettingsOpen = false;
                    _isSettingsMinimized = true;
                  });
                },
              ),
            ),
          if (_commandBarOpen) _buildCommandBar(),
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
                  covers: _covers,
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
                            key: const ValueKey('dock-settings'),
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
                      // Workspaces: one dot per desktop, the current one lit.
                      // Tapping a dot jumps straight to it; the pill opens the
                      // panel with create/close/next/previous.
                      Expanded(
                        child: Center(
                          child: MouseRegion(
                            onEnter: (event) => setState(() => _isDesktopsHovered = true),
                            onExit: (event) => setState(() => _isDesktopsHovered = false),
                            child: GestureDetector(
                              key: const ValueKey('desktop-dots'),
                              onTap: _toggleDesktops,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(
                                    alpha: _isDesktopsOpen || _isDesktopsHovered ? 0.16 : 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(15.0),
                                ),
                                // The dots are their own tap targets and sit
                                // inside the pill, so a tap on one selects a
                                // desktop instead of opening the panel.
                                child: Center(
                                  child: SizedBox(
                                    height: 40,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // One dot per desktop, the active one
                                        // elongated. Indicators only: the pill
                                        // opens the panel where you switch.
                                        for (var i = 0; i < _workspaces.count; i++) ...[
                                          if (i > 0) const SizedBox(height: 5),
                                          AnimatedContainer(
                                            key: ValueKey('workspace-dot-$i'),
                                            duration: const Duration(milliseconds: 160),
                                            width: 8,
                                            height: i == _workspaces.activeIndex ? 14 : 8,
                                            decoration: BoxDecoration(
                                              color: i == _workspaces.activeIndex
                                                  ? Colors.white
                                                  : Colors.white.withValues(alpha: 0.35),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Apps button: opens the launcher. The power menu moved
                      // into the strip under the app grid.
                      PanelIcon(
                        key: const ValueKey('apps-button'),
                        icon: _isLauncherOpen ? Icons.close : Icons.apps,
                        onTap: _toggleLauncher,
                        spacing: 1.0,
                      ),                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: _shortcutBindings,
      // The inner Focus makes the shell the primary focus from the first
      // frame, so Ctrl+Alt+Space works before anything else is clicked.
      child: Focus(autofocus: true, child: shell),
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

/// One launcher tile: icon over a short label, the classic light-canvas
/// hover lift of the rest of the shell.
class _LauncherTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LauncherTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_LauncherTile> createState() => _LauncherTileState();
}

class _LauncherTileState extends State<_LauncherTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) => setState(() => _isHovered = true),
      onExit: (event) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 92,
          height: 58,
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14.0),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: Colors.white, size: 24),
              const SizedBox(height: 3),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The horizontal strip under the app grid: the shell actions that used to
/// live in the dock. Same width as the grid above it.
class _LauncherStrip extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onPower;
  final VoidCallback onTerminal;

  const _LauncherStrip({
    required this.onSettings,
    required this.onPower,
    required this.onTerminal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 298,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      // Equal thirds: a long label can never push its neighbour out of the
      // strip (an ellipsis is cheaper than an overflow).
      child: Row(
        children: [
          Expanded(
            child: _LauncherAction(
              key: const ValueKey('launcher-settings'),
              icon: Icons.settings_outlined,
              label: 'Настройки',
              onTap: onSettings,
            ),
          ),
          Expanded(
            child: _LauncherAction(
              key: const ValueKey('launcher-power'),
              icon: Icons.power_settings_new,
              label: 'Питание',
              onTap: onPower,
            ),
          ),
          Expanded(
            child: _LauncherAction(
              key: const ValueKey('launcher-terminal'),
              icon: Icons.terminal_outlined,
              label: 'Терминал',
              onTap: onTerminal,
            ),
          ),
        ],
      ),
    );
  }
}

class _LauncherAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LauncherAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_LauncherAction> createState() => _LauncherActionState();
}

class _LauncherActionState extends State<_LauncherAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) => setState(() => _hovered = true),
      onExit: (event) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: Colors.white),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}