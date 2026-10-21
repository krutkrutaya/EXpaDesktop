// EXpaDesktop: one Windows window that *is* the desktop.
//
// Everything the user opens lives in here. The applications are in-app
// windows (see desktop/), the player is a controller (see playback/), and the
// shell itself only owns the wallpaper, the waybar, the dock and the floating
// panels. The old version handed tiles to Windows (`calc.exe`, `mspaint.exe`,
// the default browser); that is why this file imports no launcher anymore.

import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:ffi' hide Size;
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'command_router.dart';
import 'desktop/app_catalog.dart';
import 'desktop/app_icons.dart';
import 'desktop/apps/browser_app.dart';
import 'desktop/apps/calculator_app.dart';
import 'desktop/apps/files_app.dart';
import 'desktop/apps/musics_app.dart';
import 'desktop/apps/notepad_app.dart';
import 'desktop/apps/paint_app.dart';
import 'desktop/apps/settings_view.dart';
import 'desktop/apps/snip_app.dart';
import 'desktop/apps/tasks_app.dart';
import 'desktop/apps/terminal_app.dart';
import 'desktop/desktop_surface.dart';
import 'desktop/window_manager.dart' hide Rect4;
import 'id3_art.dart';
import 'liquid_glass/morph_controller.dart';
import 'liquid_glass/morph_glass.dart';
import 'liquid_glass/wave_slider.dart';
import 'playback/player_controller.dart';
import 'playback/track.dart';
import 'player.dart';
import 'radio_control.dart';
import 'shell_layout.dart';
import 'shell_panels.dart';
import 'sound_control.dart';
import 'system_actions.dart';
import 'system_actions.dart' as sys;
import 'ui/mini_player.dart';
import 'workspaces.dart';

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
  const MyHomePage({super.key, this.radio, this.sound, this.audio});

  /// Test seams: the widget tests pass recorders so no test spawns
  /// PowerShell, moves the machine's volume or plays a sound.
  final RadioSource? radio;
  final SoundSource? sound;
  final AudioEngine? audio;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with TickerProviderStateMixin
    implements SystemCommandSink {
  /// In-app desktops: each one keeps its own wallpaper *and* its own windows.
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

  /// One window manager per in-app desktop, created on first use.
  final Map<int, WindowManager> _managers = {};
  Size _viewport = Size.zero;

  /// The whole shell, so the Snip app can photograph it.
  final GlobalKey _shellKey = GlobalKey();

  /// The player: audio, playlist, progress, and the artwork spin.
  late final PlayerController _player;

  /// Sends an already-open settings window to a section.
  final SettingsNavigator _settingsNav = SettingsNavigator();

  Timer? _backgroundTimer;
  Timer? _radioTimer;
  Timer? _replyTimer;

  bool _isDesktopsHovered = false;

  /// Whether each morph is mid-flight, so the shell rebuilds once when a
  /// panel finishes closing (the dock's app icon, the dismiss layer).
  final Map<MorphPanelController, bool> _morphAnimating = {};

  // The radios' real state, mirrored from the system for the waybar.
  RadioStatus _wifiStatus =
      const RadioStatus(kind: RadioKind.wifi, state: RadioState.unknown);
  RadioStatus _bluetoothStatus =
      const RadioStatus(kind: RadioKind.bluetooth, state: RadioState.unknown);

  // The command line: Ctrl+Alt+Space opens it, Enter runs the phrase.
  final TextEditingController _commandController = TextEditingController();
  final FocusNode _commandFocus = FocusNode();
  bool _commandBarOpen = false;
  String _commandReply = '';
  late final CommandRouter _router;

  RadioSource get _radioSource => widget.radio ?? RadioControl.instance;
  SoundSource get _soundSource => widget.sound ?? SoundControl.instance;

  double _brightness = 0.7;
  double _contrast = 0.7;

  /// 0 is neutral: [set_warmth] multiplies the red/blue channels down as the
  /// value grows, so 0.5 was actually a strong warm cast and the panel lied
  /// about the screen's real state.
  double _warmth = 0.0;

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

  // System volume mirrored from the audio endpoint.
  double _volume = 0.7;
  bool _muted = false;

  // Hand-written metadata for files we know; every other .mp3 found in
  // assets/music is named from its filename automatically.
  static const Map<String, Map<String, String>> _trackMetaOverride = {
    'morgenshtern-ice.mp3': {
      'title': 'ICE',
      'artist': 'Morgenshtern',
      'avatar': 'assets/music/ava-track-1.jpg',
    },
    'b5607d8a7d89812.mp3': {
      'title': 'Track Test',
      'artist': 'Unknown artist',
      'avatar': '',
    },
    'monetochka-kazhdyjj-raz.mp3': {
      'title': 'Каждый раз',
      'artist': 'Монеточка',
      'avatar': 'assets/music/ava-track-3.jpg',
    },
  };

  static const List<Track> _seedTracks = [
    Track(
      title: 'ICE',
      artist: 'Morgenshtern',
      file: 'morgenshtern-ice.mp3',
      avatar: 'assets/music/ava-track-1.jpg',
    ),
    Track(
      title: 'Track Test',
      artist: 'Unknown artist',
      file: 'b5607d8a7d89812.mp3',
    ),
    Track(
      title: 'Каждый раз',
      artist: 'Монеточка',
      file: 'monetochka-kazhdyjj-raz.mp3',
      avatar: 'assets/music/ava-track-3.jpg',
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
  Timer? _brightnessFx;
  Timer? _contrastFx;
  Timer? _warmthFx;

  /// The manager of the desktop that is on screen.
  WindowManager get _windows => _managers.putIfAbsent(
        _workspaces.active.id,
        () => WindowManager(area: DesktopArea(_viewport.width, _viewport.height)),
      );

  @override
  void initState() {
    super.initState();
    _workspaces = WorkspaceController(backgroundCount: _backgrounds.length);
    _player = PlayerController(engine: widget.audio, vsync: this);
    _player.setTracks(_seedTracks, const {});
    _loadBrightnessLib();
    _router = CommandRouter(sink: this);
    unawaited(_refreshRadios());
    _radioTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(_refreshRadios());
    });
    _backgroundTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) setState(_workspaces.cycleBackground);
    });
    unawaited(_scanMusicAssets());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewport = MediaQuery.of(context).size;
    for (final manager in _managers.values) {
      manager.retarget(DesktopArea(_viewport.width, _viewport.height));
    }

    // Where each panel's glass is born from, and where it lands. The numbers
    // live in [ShellLayout] so the mock suite can check every one of them
    // against the dock and the screen edges on any window size.
    final l = ShellLayout(_viewport.width, _viewport.height);
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
      for (final morph in [
        _menuMorph,
        _brightnessMorph,
        _playerMorph,
        _volumeMorph,
        _launcherMorph,
        _desktopsMorph,
      ]) {
        _watchMorph(morph!);
      }
    } else {
      _menuMorph!.retarget(l.menuButton, l.menuRect, 15.0);
      _brightnessMorph!.retarget(l.brightnessButton, l.brightnessRect, 25.0);
      _playerMorph!.retarget(l.playerButton, l.playerRect, 25.0);
      _volumeMorph!.retarget(l.volumeButton, l.volumeRect, 20.0);
      _launcherMorph!.retarget(l.launcherButton, l.launcherRect, 20.0);
      _desktopsMorph!.retarget(l.desktopsButton, l.desktopsRect, 20.0);
    }
  }

  @override
  void dispose() {
    _backgroundTimer?.cancel();
    _radioTimer?.cancel();
    _replyTimer?.cancel();
    _brightnessFx?.cancel();
    _contrastFx?.cancel();
    _warmthFx?.cancel();
    _commandController.dispose();
    _commandFocus.dispose();
    _player.dispose();
    _menuMorph?.dispose();
    _brightnessMorph?.dispose();
    _playerMorph?.dispose();
    _volumeMorph?.dispose();
    _launcherMorph?.dispose();
    _desktopsMorph?.dispose();
    _brightnessLib = null;
    super.dispose();
  }

  // ---- the library ------------------------------------------------------------

  Future<void> _scanMusicAssets() async {
    final files = await _musicAssetFiles();
    if (!mounted || files.isEmpty) return;

    // Every file is asked for its own ID3 tags: a real title, a real artist
    // and the cover art that is already inside the mp3. No hard-coded table.
    final tracks = <Track>[];
    final covers = <String, Uint8List>{};
    for (final file in files) {
      final known = _trackMetaOverride[file];
      var title = known?['title'] ?? _autoTitle(file);
      var artist = known?['artist'] ?? 'Unknown artist';
      try {
        final data = await rootBundle.load('$_musicPrefix$file');
        final tags = parseId3(data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ));
        if (tags != null) {
          if (tags.title != null) title = tags.title!;
          if (tags.artist != null) artist = tags.artist!;
          if (tags.cover != null) covers[file] = tags.cover!;
        }
      } catch (_) {
        // A broken file must not take the whole list down.
      }
      tracks.add(Track(
        title: title,
        artist: artist,
        file: file,
        avatar: known?['avatar'] ?? '',
      ));
    }

    if (!mounted) return;
    _player.setTracks(tracks, covers);
  }

  static const String _musicPrefix = 'assets/music/';

  Future<List<String>> _musicAssetFiles() async {
    final files = <String>[];
    try {
      final manifest = await rootBundle.load('AssetManifest.bin');
      final decoded = const StandardMessageCodec().decodeMessage(manifest);
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
    if (files.isEmpty) {
      return _seedTracks.map((track) => track.file).toSet().toList();
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

  // ---- brightness DLL ---------------------------------------------------------

  /// Rebuilds the shell once when a morph starts or finishes. Listening to
  /// every frame would rebuild the desktop 60 times a second during a panel
  /// animation; the flag only changes twice.
  void _watchMorph(MorphPanelController morph) {
    _morphAnimating[morph] = morph.animating;
    morph.addListener(() {
      final animating = morph.animating;
      if (_morphAnimating[morph] == animating) return;
      _morphAnimating[morph] = animating;
      if (mounted) setState(() {});
    });
  }

  void _loadBrightnessLib() {
    try {
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
          .lookup<NativeFunction<SetBrightnessBoostNative>>(
              'set_brightness_boost')
          .asFunction();
      final current = _getBrightness!();
      if (mounted) {
        setState(() => _brightness = current);
      } else {
        _brightness = current;
      }
    } catch (_) {
      _brightnessLib = null;
    }
  }

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

  // ---- panels ---------------------------------------------------------------

  /// Closes whatever would overlap [opening].
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
      }
    }
  }

  /// Closes every floating panel; used when an app window is opened.
  void _closePanels() {
    if (_isMenuOpen) _menuMorph?.close();
    if (_isLauncherOpen) _launcherMorph?.close();
    if (_isBrightnessOpen) _brightnessMorph?.close();
    if (_isVolumeOpen) _volumeMorph?.close();
    if (_isPlayerOpen) _playerMorph?.close();
    if (_isDesktopsOpen) _desktopsMorph?.close();
  }

  void _dismissFloatingSurfaces() {
    if (!_isVolumeOpen &&
        !_isBrightnessOpen &&
        !_isPlayerOpen &&
        !_isMenuOpen &&
        !_isLauncherOpen &&
        !_isDesktopsOpen) {
      return;
    }
    _closePanels();
    setState(() {});
  }

  void _toggleMenu() {
    final m = _menuMorph;
    if (m == null) return;
    _applyPanelPlan(ShellPanel.menu);
    m.toggle();
    setState(() {});
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

  /// The sound flyout. It only ever opens the panel: sound is sound, the
  /// desktop stays exactly where it is.
  void _toggleVolume() {
    final m = _volumeMorph;
    if (m == null) return;
    _applyPanelPlan(ShellPanel.volume);
    if (!m.active) {
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

  // ---- apps -----------------------------------------------------------------

  /// Opens (or focuses) an app window on the current desktop.
  void _openApp(ShellApp app, {String? section}) {
    _closePanels();
    if (app == ShellApp.settings && section != null) {
      _settingsNav.show(section);
    }
    _windows.open(app);
    setState(() {});
  }

  /// The dock's running-window buttons: focus, or minimize if already focused.
  void _toggleAppWindow(AppWindow window) {
    if (_windows.activeId == window.id && !window.minimized) {
      _windows.minimize(window.id);
    } else {
      _windows.focus(window.id);
    }
    setState(() {});
  }

  void _openSettingsAt(String? section) {
    _closePanels();
    _settingsNav.show(section);
    _windows.open(ShellApp.settings);
    setState(() {});
    if (section == 'wifi' || section == 'bluetooth') {
      unawaited(_refreshRadios());
    }
  }

  /// The Tracks pill: close the flyout and open the Musics window.
  void _openMusics() {
    _playerMorph?.close();
    _openApp(ShellApp.musics);
  }

  Future<Uint8List?> _captureShell() async {
    final boundary = _shellKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    try {
      final image = await boundary.toImage(pixelRatio: 1.2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Widget _windowContent(AppWindow window) {
    switch (window.app) {
      case ShellApp.calculator:
        return const CalculatorApp();
      case ShellApp.notepad:
        return const NotepadApp();
      case ShellApp.files:
        return const FilesApp();
      case ShellApp.paint:
        return const PaintApp();
      case ShellApp.snip:
        return SnipApp(capture: _captureShell);
      case ShellApp.tasks:
        return const TasksApp();
      case ShellApp.browser:
        return const BrowserApp();
      case ShellApp.musics:
        return MusicsApp(player: _player);
      case ShellApp.settings:
        return SettingsView(
          navigator: _settingsNav,
          radio: widget.radio,
          sound: widget.sound,
          wallpapers: _backgrounds,
          activeWallpaper: _workspaces.active.backgroundIndex,
          onWallpaper: _setWallpaper,
          display: DisplaySettings(
            brightness: _brightness,
            contrast: _contrast,
            warmth: _warmth,
            onBrightness: _setBrightnessFromUi,
            onContrast: _setContrastFromUi,
            onWarmth: _setWarmthFromUi,
          ),
        );
      case ShellApp.terminal:
        return const TerminalApp();
    }
  }

  void _setWallpaper(int index) {
    setState(() => _workspaces.setBackground(index));
  }

  void _setBrightnessFromUi(double value) {
    setState(() => _brightness = value);
    _setSystemBrightness(value);
  }

  void _setContrastFromUi(double value) {
    setState(() => _contrast = value);
    _setSystemContrast(value);
  }

  void _setWarmthFromUi(double value) {
    setState(() => _warmth = value);
    _setSystemWarmth(value);
  }

  // ---- workspaces -----------------------------------------------------------

  void _newWorkspace() {
    setState(_workspaces.create);
  }

  void _closeWorkspace() {
    final id = _workspaces.active.id;
    setState(() {
      final closed = _workspaces.closeActive();
      if (closed) _managers.remove(id);
    });
  }

  void _selectWorkspace(int index) {
    setState(() => _workspaces.select(index));
  }

  void _nextWorkspace() {
    if (_workspaces.count < 2) return;
    setState(_workspaces.next);
  }

  void _previousWorkspace() {
    if (_workspaces.count < 2) return;
    setState(_workspaces.previous);
  }

  DateTime _lastDesktopWheel = DateTime.fromMillisecondsSinceEpoch(0);

  /// Mouse wheel over the dock's dots: the quickest way to scroll desktops.
  /// A trackpad fires dozens of events per gesture; one desktop per 180 ms.
  void _onDesktopWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _workspaces.count < 2) return;
    final now = DateTime.now();
    if (now.difference(_lastDesktopWheel).inMilliseconds < 180) return;
    _lastDesktopWheel = now;
    if (event.scrollDelta.dy > 0) {
      _nextWorkspace();
    } else if (event.scrollDelta.dy < 0) {
      _previousWorkspace();
    }
  }

  // ---- radios ---------------------------------------------------------------

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

  Map<ShortcutActivator, VoidCallback> get _shortcutBindings => {
        const SingleActivator(
          LogicalKeyboardKey.space,
          control: true,
          alt: true,
        ): _toggleCommandBar,
        const SingleActivator(LogicalKeyboardKey.tab, control: true):
            _cycleWindows,
        if (_commandBarOpen)
          const SingleActivator(LogicalKeyboardKey.escape): _toggleCommandBar,
      };

  void _cycleWindows() {
    if (_windows.cycleFocus() == null) return;
    setState(() {});
  }

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
        key: const ValueKey('command-bar'),
        width: 500,
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
                    key: const ValueKey('command-input'),
                    controller: _commandController,
                    focusNode: _commandFocus,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText:
                          'turn on wifi • volume 40 • open sound settings',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                    onSubmitted: (_) => _submitCommand(),
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
    setState(() => _brightness = level);
    _setSystemBrightness(level);
  }

  @override
  Future<void> adjustBrightness(double direction) async {
    final level = (_brightness + 0.05 * direction).clamp(0.0, 1.0);
    setState(() => _brightness = level);
    _setSystemBrightness(level);
  }

  @override
  Future<void> mediaPlayPause() => _player.toggle();

  @override
  Future<void> mediaNext() => _player.next();

  @override
  Future<void> mediaPrevious() => _player.previous();

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

  // === part 3 ===

  @override
  Widget build(BuildContext context) {
    const panelWidth = 72.0;
    const panelMargin = 5.0;
    final size = MediaQuery.of(context).size;
    final manager = _windows;
    final openWindows = manager.windows;
    final shell = Scaffold(
      backgroundColor: Colors.black,
      body: RepaintBoundary(
        key: _shellKey,
        child: Stack(
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
                    scale: Tween<double>(begin: 1.03, end: 1.0)
                        .animate(animation),
                    child: child,
                  ),
                );
              },
              child: Container(
                key: ValueKey<String>(
                  '${_workspaces.activeIndex}-'
                  '${_workspaces.active.backgroundIndex}',
                ),
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(
                      _backgrounds[_workspaces.active.backgroundIndex %
                          _backgrounds.length],
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
            // Tap-away layer: sits under every window and panel, so a click on
            // the bare desktop closes the flyouts. Windows swallow their own
            // clicks because they are above this layer.
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('desktop-backdrop'),
                behavior: HitTestBehavior.opaque,
                onTap: _dismissFloatingSurfaces,
              ),
            ),
            const Positioned(
              top: 20.0,
              left: 30.0,
              child: _Clock(),
            ),
            // The windows: above the wallpaper, below the waybar and panels.
            Positioned.fill(
              child: DesktopSurface(
                manager: manager,
                builder: _windowContent,
                onChanged: () => setState(() {}),
              ),
            ),
            // Tap-away for open panels. It stays in the tree (so it can never
            // go stale) and ignores pointers while nothing is open; an
            // IgnorePointer above the windows is the difference between a
            // clickable desktop and a dead one.
            Positioned.fill(
              child: ListenableBuilder(
                listenable: Listenable.merge(_morphAnimating.keys.toList()),
                builder: (context, _) {
                  final open = _isMenuOpen ||
                      _isBrightnessOpen ||
                      _isPlayerOpen ||
                      _isVolumeOpen ||
                      _isLauncherOpen;
                  return IgnorePointer(
                    ignoring: !open,
                    child: GestureDetector(
                      onTap: _dismissFloatingSurfaces,
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),
            // ---- the waybar -------------------------------------------------
            Positioned(
              top: 0,
              left: size.width / 2 - ShellLayout.waybarWidth / 2,
              child: _Waybar(
                key: const ValueKey('waybar'),
                player: _player,
                onPlayer: _togglePlayer,
                onBrightness: _toggleBrightness,
                wifiOn: _wifiStatus.isOn,
                bluetoothOn: _bluetoothStatus.isOn,
                muted: _muted,
                onWifi: () => _openSettingsAt('wifi'),
                onBluetooth: () => _openSettingsAt('bluetooth'),
                onVolume: _toggleVolume,
              ),
            ),
            // ---- brightness flyout -----------------------------------------
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _sliderRow(
                          icon: Icons.brightness_6,
                          value: _brightness,
                          onChanged: (value) {
                            setState(() => _brightness = value);
                            _setSystemBrightness(value);
                          },
                          onReset: () {
                            setState(() => _brightness = 0.7);
                            _setSystemBrightness(0.7);
                          },
                        ),
                        _sliderRow(
                          icon: Icons.contrast,
                          value: _contrast,
                          onChanged: (value) {
                            setState(() => _contrast = value);
                            _setSystemContrast(value);
                          },
                          onReset: () {
                            setState(() => _contrast = 0.7);
                            _setSystemContrast(0.7);
                          },
                        ),
                        _sliderRow(
                          icon: Icons.wb_sunny,
                          value: _warmth,
                          onChanged: (value) {
                            setState(() => _warmth = value);
                            _setSystemWarmth(value);
                          },
                          onReset: () {
                            setState(() => _warmth = 0.0);
                            _resetGamma?.call();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            // ---- volume flyout ---------------------------------------------
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
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
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
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            // ---- launcher ---------------------------------------------------
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
                          SizedBox(
                            width: 298,
                            height: 210,
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              runAlignment: WrapAlignment.center,
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final app in _launcherApps)
                                  _LauncherTile(
                                    key: ValueKey('launcher-app-${app.id}'),
                                    icon: iconForApp(app),
                                    label: app.title,
                                    onTap: () => _openApp(app),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          _LauncherStrip(
                            onSettings: () => _openSettingsAt(null),
                            onPower: () {
                              _launcherMorph?.close();
                              _toggleMenu();
                            },
                            onTerminal: () => _openApp(ShellApp.terminal),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // ---- desktops panel ---------------------------------------------
            ListenableBuilder(
              listenable: _desktopsMorph ?? const AlwaysStoppedAnimation<int>(0),
              builder: (context, _) {
                final morph = _desktopsMorph;
                final f = morph?.frame;
                if (morph == null || f == null) return const SizedBox.shrink();
                return MorphGlass(
                  frame: f,
                  restWidth: 340,
                  restHeight: 270,
                  interactive: !morph.animating,
                  child: SizedBox(
                    width: 340,
                    height: 270,
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Desktop ${_workspaces.activeIndex + 1} '
                            'of ${_workspaces.count}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 4,
                            runSpacing: 6,
                            children: [
                              for (var i = 0; i < _workspaces.count; i++)
                                GestureDetector(
                                  key: ValueKey('workspace-chip-$i'),
                                  onTap: () => _selectWorkspace(i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 26,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: i == _workspaces.activeIndex
                                            ? 0.85
                                            : 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        color: i == _workspaces.activeIndex
                                            ? Colors.black
                                            : Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _WorkspaceAction(
                                key: const ValueKey('workspace-new'),
                                icon: Icons.add_rounded,
                                label: 'New',
                                enabled: _workspaces.canCreate,
                                onTap: _newWorkspace,
                              ),
                              const SizedBox(width: 4),
                              _WorkspaceAction(
                                key: const ValueKey('workspace-prev'),
                                icon: Icons.arrow_back_rounded,
                                label: 'Back',
                                enabled: _workspaces.count > 1,
                                onTap: _previousWorkspace,
                              ),
                              const SizedBox(width: 4),
                              _WorkspaceAction(
                                key: const ValueKey('workspace-next'),
                                icon: Icons.arrow_forward_rounded,
                                label: 'Forward',
                                enabled: _workspaces.count > 1,
                                onTap: _nextWorkspace,
                              ),
                              const SizedBox(width: 4),
                              _WorkspaceAction(
                                key: const ValueKey('workspace-close'),
                                icon: Icons.delete_outline_rounded,
                                label: 'Close',
                                enabled: _workspaces.canClose,
                                onTap: _closeWorkspace,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // ---- power menu -------------------------------------------------
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
                              const _PowerButton(
                                icon: Icons.lock_outline,
                                onTap: lockWorkstation,
                              ),
                              const SizedBox(width: 1),
                              _PowerButton(
                                icon: Icons.logout,
                                onTap: () => _confirmThen(signOut, 'Sign out?'),
                              ),
                              const SizedBox(width: 1),
                              _PowerButton(
                                icon: Icons.restart_alt,
                                onTap: () => _confirmThen(
                                  restartMachine,
                                  'Restart the computer?',
                                ),
                              ),
                              const SizedBox(width: 1),
                              _PowerButton(
                                icon: Icons.bedtime,
                                onTap: () => _confirmThen(
                                  sleepMachine,
                                  'Put the computer to sleep?',
                                ),
                              ),
                              const SizedBox(width: 1),
                              _PowerButton(
                                icon: Icons.power_settings_new,
                                onTap: () => _confirmThen(
                                  shutdownMachine,
                                  'Shut down the computer?',
                                ),
                              ),
                              const SizedBox(width: 1),
                              _PowerButton(
                                icon: Icons.settings,
                                onTap: () => _openSettingsAt(null),
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
            // ---- player flyout ----------------------------------------------
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
                  tint: Colors.transparent,
                  borderColor: Colors.transparent,
                  interactive: !morph.animating,
                  child: PlayerPanel(
                    player: _player,
                    onOpenTracks: _openMusics,
                  ),
                );
              },
            ),
            if (_commandBarOpen) _buildCommandBar(),
            // ---- the dock ----------------------------------------------------
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
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 5.0),
                    child: Column(
                      children: [
                        if (openWindows.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 176),
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  for (final window in openWindows)
                                    _DockTask(
                                      key: ValueKey(
                                        window.appId == 'settings'
                                            ? 'dock-settings'
                                            : 'dock-app-${window.appId}',
                                      ),
                                      icon: iconForApp(window.app),
                                      active: manager.activeId == window.id &&
                                          !window.minimized,
                                      minimized: window.minimized,
                                      onTap: () => _toggleAppWindow(window),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        Expanded(
                          child: Center(
                            child: Listener(
                              onPointerSignal: _onDesktopWheel,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                onEnter: (_) =>
                                    setState(() => _isDesktopsHovered = true),
                                onExit: (_) =>
                                    setState(() => _isDesktopsHovered = false),
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
                                        alpha: _isDesktopsOpen || _isDesktopsHovered
                                            ? 0.16
                                            : 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(15.0),
                                    ),
                                    child: Center(
                                      child: Builder(
                                        builder: (context) {
                                          // One slot per desktop, sized so even
                                          // nine dots fit the 44 px inside the
                                          // pill. The slot never animates, the
                                          // bar inside it does, so adding a
                                          // desktop cannot overflow the dock.
                                          final count = _workspaces.count;
                                          final gap = count <= 4
                                              ? 5.0
                                              : (count <= 6 ? 3.0 : 2.0);
                                          final slot =
                                              ((44 - gap * (count - 1)) / count)
                                                  .clamp(3.0, 14.0);
                                          final idleHeight =
                                              (slot * 0.62).clamp(2.0, 8.0);
                                          final width =
                                              (slot * 0.8).clamp(2.5, 8.0);
                                          return Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              for (var i = 0; i < count; i++) ...[
                                                if (i > 0) SizedBox(height: gap),
                                                SizedBox(
                                                  height: slot,
                                                  child: Center(
                                                    child: AnimatedContainer(
                                                      key: ValueKey(
                                                          'workspace-dot-$i'),
                                                      duration:
                                                          const Duration(
                                                              milliseconds: 160),
                                                      width: width,
                                                      height: i ==
                                                              _workspaces
                                                                  .activeIndex
                                                          ? slot
                                                          : idleHeight,
                                                      decoration: BoxDecoration(
                                                        color: i ==
                                                                _workspaces
                                                                    .activeIndex
                                                            ? Colors.white
                                                            : Colors.white
                                                                .withValues(
                                                                    alpha: 0.35),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                6),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        PanelIcon(
                          key: const ValueKey('apps-button'),
                          icon: _isLauncherOpen ? Icons.close : Icons.apps,
                          onTap: _toggleLauncher,
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
      ),
    );

    return CallbackShortcuts(
      bindings: _shortcutBindings,
      child: Focus(autofocus: true, child: shell),
    );
  }

  List<ShellApp> get _launcherApps => const [
        ShellApp.calculator,
        ShellApp.notepad,
        ShellApp.files,
        ShellApp.paint,
        ShellApp.snip,
        ShellApp.tasks,
        ShellApp.browser,
        ShellApp.musics,
      ];

  Widget _sliderRow({
    required IconData icon,
    required double value,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: WaveSlider(value: value, onChanged: onChanged),
        ),
        Text(
          '${(value * 100).round()}%',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        IconButton(
          onPressed: onReset,
          icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        ),
      ],
    );
  }

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
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(action());
            },
            child: const Text('Yes', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// === part 4 ===

/// The giant clock. It owns its one-second timer, so the shell does not
/// rebuild the whole desktop (and every open window) every second.
class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late String _time;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _time = _format(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _format(DateTime.now());
      if (mounted && next != _time) setState(() => _time = next);
    });
  }

  static String _format(DateTime now) =>
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform(
      transform: Matrix4.diagonal3Values(0.85, 1.50, 1.0),
      alignment: Alignment.topLeft,
      child: Text(
        _time,
        style: TextStyle(
          fontSize: 145,
          fontWeight: FontWeight.w900,
          color: Colors.white.withValues(alpha: 0.85),
          letterSpacing: -6.0,
          height: 0.8,
        ),
      ),
    );
  }
}

/// The top bar: brightness on the left, the mini player in the middle, the
/// radios and the sound on the right. The old four-squares button next to the
/// player is gone — it was decoration that did nothing.
class _Waybar extends StatelessWidget {
  final PlayerController player;
  final VoidCallback onPlayer;
  final VoidCallback onBrightness;
  final VoidCallback onWifi;
  final VoidCallback onBluetooth;
  final VoidCallback onVolume;
  final bool wifiOn;
  final bool bluetoothOn;
  final bool muted;

  const _Waybar({
    super.key,
    required this.player,
    required this.onPlayer,
    required this.onBrightness,
    required this.onWifi,
    required this.onBluetooth,
    required this.onVolume,
    required this.wifiOn,
    required this.bluetoothOn,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(25.0),
        bottomRight: Radius.circular(25.0),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          width: ShellLayout.waybarWidth,
          height: ShellLayout.waybarHeight,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(25.0),
              bottomRight: Radius.circular(25.0),
            ),
            border: const Border(
              bottom: BorderSide(color: Colors.white24),
              left: BorderSide(color: Colors.white24),
              right: BorderSide(color: Colors.white24),
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: MiniPlayer(player: player, onOpen: onPlayer),
              ),
              Positioned(
                left: 5,
                top: 10,
                child: _WaybarButton(
                  key: const ValueKey('topbar-brightness'),
                  icon: Icons.brightness_6,
                  tooltip: 'Brightness',
                  onTap: onBrightness,
                ),
              ),
              Positioned(
                right: 5,
                top: 10,
                child: Row(
                  children: [
                    _WaybarButton(
                      key: const ValueKey('topbar-bluetooth'),
                      icon: Icons.bluetooth,
                      tooltip: 'Bluetooth',
                      active: bluetoothOn,
                      onTap: onBluetooth,
                    ),
                    const SizedBox(width: 4),
                    _WaybarButton(
                      key: const ValueKey('topbar-volume'),
                      icon: muted ? Icons.volume_off : Icons.volume_up,
                      tooltip: 'Sound',
                      onTap: onVolume,
                    ),
                    const SizedBox(width: 4),
                    _WaybarButton(
                      key: const ValueKey('topbar-wifi'),
                      icon: Icons.wifi,
                      tooltip: 'Wi-Fi',
                      active: wifiOn,
                      onTap: onWifi,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaybarButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _WaybarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = true,
  });

  @override
  State<_WaybarButton> createState() => _WaybarButtonState();
}

class _WaybarButtonState extends State<_WaybarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Icon(
              widget.icon,
              color: widget.active ? Colors.white : Colors.white38,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

/// One running window in the dock: click to focus, click again to minimize.
class _DockTask extends StatefulWidget {
  final IconData icon;
  final bool active;
  final bool minimized;
  final VoidCallback onTap;

  const _DockTask({
    super.key,
    required this.icon,
    required this.active,
    required this.minimized,
    required this.onTap,
  });

  @override
  State<_DockTask> createState() => _DockTaskState();
}

class _DockTaskState extends State<_DockTask> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: Colors.white.withValues(
              alpha: widget.active ? 0.20 : (_hovered ? 0.12 : 0.0),
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                widget.icon,
                size: 19,
                color: widget.minimized
                    ? Colors.white38
                    : (widget.active ? Colors.white : Colors.white70),
              ),
              Positioned(
                bottom: 4,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: widget.active ? 10 : 4,
                  height: 2,
                  decoration: BoxDecoration(
                    color: widget.minimized
                        ? Colors.white24
                        : Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dock icon with the shell's hover/press feel.
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
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
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
            child: Icon(widget.icon, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

class _PowerButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _PowerButton({required this.icon, this.onTap});

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
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
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
            child: Icon(widget.icon, color: Colors.white, size: 21),
          ),
        ),
      ),
    );
  }
}

/// One launcher tile: icon over a short label.
class _LauncherTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LauncherTile({
    super.key,
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
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
              Icon(widget.icon, color: Colors.white, size: 23),
              const SizedBox(height: 3),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 9.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The strip under the launcher grid: Settings, Power, Terminal.
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _LauncherAction(
              key: const ValueKey('launcher-settings'),
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: onSettings,
            ),
          ),
          Expanded(
            child: _LauncherAction(
              key: const ValueKey('launcher-power'),
              icon: Icons.power_settings_new,
              label: 'Power',
              onTap: onPower,
            ),
          ),
          Expanded(
            child: _LauncherAction(
              key: const ValueKey('launcher-terminal'),
              icon: Icons.terminal_outlined,
              label: 'Terminal',
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
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 17, color: Colors.white),
              const SizedBox(height: 3),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One desktop action: icon, label, and a real disabled state when the list
/// cannot grow (nine desktops) or shrink (the last one). The old buttons did
/// nothing when they hit the limit, which read as "the click did not land".
class _WorkspaceAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _WorkspaceAction({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_WorkspaceAction> createState() => _WorkspaceActionState();
}

class _WorkspaceActionState extends State<_WorkspaceAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 70,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(
              alpha: !enabled ? 0.03 : (_hovered ? 0.14 : 0.07),
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: Colors.white.withValues(alpha: enabled ? 0.12 : 0.05),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: enabled ? Colors.white : Colors.white24,
              ),
              const SizedBox(height: 3),
              Text(
                widget.label,
                style: TextStyle(
                  color: enabled ? Colors.white70 : Colors.white24,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}