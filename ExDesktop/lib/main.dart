// EXpaDesktop: one Windows window that *is* the desktop.
//
// Everything the user opens lives in here. The applications are in-app
// windows (see desktop/), the player is a controller (see playback/), and the
// shell itself only owns the wallpaper, the waybar, the dock and the floating
// panels. The old version handed tiles to Windows (`calc.exe`, `mspaint.exe`,
// the default browser); that is why this file imports no launcher anymore.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'apps/audio_pick.dart';
import 'apps/music_library.dart';
import 'apps/music_scanner.dart';
import 'audio_sessions.dart';
import 'apps/display_math.dart';
import 'apps/file_pick.dart';
import 'apps/files_model.dart';
import 'command_router.dart';
import 'desktop/app_catalog.dart';
import 'desktop/app_icons.dart';
import 'desktop/apps/browser_app.dart';
import 'desktop/apps/calculator_app.dart';
import 'desktop/apps/calendar_app.dart';
import 'desktop/apps/clipboard_app.dart';
import 'desktop/apps/configs_app.dart';
import 'desktop/apps/emoji_app.dart';
import 'desktop/apps/files_app.dart';
import 'desktop/apps/musics_app.dart';
import 'desktop/apps/notepad_app.dart';
import 'desktop/apps/notifications_app.dart';
import 'desktop/apps/paint_app.dart';
import 'desktop/apps/settings_view.dart';
import 'desktop/apps/snip_app.dart';
import 'desktop/apps/tasks_app.dart';
import 'desktop/apps/terminal_app.dart';
import 'desktop/apps/updater_app.dart';
import 'desktop/desktop_surface.dart';
import 'desktop/shell_window.dart';
import 'desktop/window_manager.dart' hide Rect4;
import 'exwm/snap.dart';
import 'exwm/wm_server.dart';
import 'expa/de_config.dart';
import 'expa/default_apps.dart';
import 'expa/expa_theme.dart';
import 'expa/notifications.dart';
import 'expa/update_runner.dart';
import 'expa/version.dart';
import 'i18n.dart';
import 'native/sysctl.dart';
import 'id3_art.dart';
import 'liquid_glass/morph_controller.dart';
import 'liquid_glass/morph_glass.dart';
import 'liquid_glass/wave_slider.dart';
import 'shell_prefs.dart';
import 'wifi_control.dart';
import 'windows_apps.dart';
import 'playback/player_controller.dart';
import 'playback/track.dart';
import 'player.dart';
import 'radio_control.dart';
import 'shell_layout.dart';
import 'shell_panels.dart';
import 'sound_control.dart';
import 'system_actions.dart';
import 'system_actions.dart' as sys;
import 'ui/glass.dart';
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
  Loc.load();
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
  const MyHomePage({
    super.key,
    this.radio,
    this.sound,
    this.audio,
    this.wifiNetworks,
  });

  /// Test seams: the widget tests pass recorders so no test spawns
  /// PowerShell, moves the machine's volume or plays a sound.
  final RadioSource? radio;
  final SoundSource? sound;
  final AudioEngine? audio;

  /// Test seam: a fixed network list so the flyout can be driven without
  /// WLAN hardware or a running wlansvc.
  final List<WifiNetwork>? wifiNetworks;

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

  /// EXWM owns the windows: one manager per in-app desktop.
  late final WmServer _wm;
  Size _viewport = Size.zero;

  /// The whole shell, so the Snip app can photograph it.
  final GlobalKey _shellKey = GlobalKey();

  /// EXPA's visual/behaviour configuration, persisted in prefs.cfg.
  DeConfig _de = DeConfig.defaults;

  /// In-shell notifications (the Notifications widget reads this).
  final NotificationCenter _notifications = NotificationCenter();

  /// The desktop's file associations (Files uses them on double-click).
  late FileAssociations _associations = FileAssociations.standard;

  /// A path the Files window should open (the drives pane).
  final ValueNotifier<String?> _filesOpenPath = ValueNotifier<String?>(null);
  final ValueNotifier<String?> _notepadOpenPath = ValueNotifier<String?>(null);
  final ValueNotifier<String?> _browserOpenUrl = ValueNotifier<String?>(null);
  final ValueNotifier<FilePickRequest?> _filePick =
      ValueNotifier<FilePickRequest?>(null);

  /// The in-desktop lock screen.
  bool _locked = false;
  String _lockError = '';
  final TextEditingController _lockController = TextEditingController();
  final FocusNode _lockFocus = FocusNode();
  Timer? _lockTimer;
  DateTime _lastActivity = DateTime.now();

  /// The latest toast; a short-lived copy of the newest notification.
  ShellNotification? _toast;
  Timer? _toastTimer;

  /// The player: audio, playlist, progress, and the artwork spin.
  late final PlayerController _player;

  /// Sends an already-open settings window to a section.
  final SettingsNavigator _settingsNav = SettingsNavigator();

  Timer? _backgroundTimer;
  Timer? _radioTimer;
  Timer? _replyTimer;

  /// Bumped when the wallpaper changes on its own (the 12 s slideshow).
  /// The wallpaper redraws; the shell — and every open window — does not.
  final ValueNotifier<int> _wallpaperTick = ValueNotifier<int>(0);

  /// Bumped when a radio reading lands, so only the waybar rebuilds.
  final ValueNotifier<int> _waybarTick = ValueNotifier<int>(0);

  /// Where the user's imported tracks live and how they are imported.
  final MusicLibrary _library = MusicLibrary();

  /// Set while Musics is waiting for a file from the Files window.
  final ValueNotifier<AudioPickRequest?> _pickRequest =
      ValueNotifier<AudioPickRequest?>(null);

  /// A short "Added: …" line in Musics.
  final ValueNotifier<String?> _musicNotice = ValueNotifier<String?>(null);
  Timer? _noticeTimer;

  /// Bundled tracks come from the asset scan; file tracks from the library.
  List<Track> _assetTracks = _seedTracks;
  List<Track> _fileTracks = const [];
  Map<String, Uint8List> _assetCovers = const {};
  Map<String, Uint8List> _fileCovers = const {};

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
  // window size (and so the button/menu rects) is known. The power menu
  // replaced the old 700x550 panel: it is a small dropdown over the
  // launcher's power button now.
  MorphPanelController? _powerMorph;
  MorphPanelController? _brightnessMorph;
  MorphPanelController? _playerMorph;
  MorphPanelController? _volumeMorph;
  MorphPanelController? _wifiMorph;
  MorphPanelController? _launcherMorph;
  MorphPanelController? _desktopsMorph;
  MorphPanelController? _appsMorph;

  bool get _isPowerOpen => _powerMorph?.active ?? false;
  bool get _isBrightnessOpen => _brightnessMorph?.active ?? false;
  bool get _isPlayerOpen => _playerMorph?.active ?? false;
  bool get _isVolumeOpen => _volumeMorph?.active ?? false;
  bool get _isWifiOpen => _wifiMorph?.active ?? false;
  bool get _isLauncherOpen => _launcherMorph?.active ?? false;
  bool get _isDesktopsOpen => _desktopsMorph?.active ?? false;
  bool get _isAppsOpen => _appsMorph?.active ?? false;

  // ---- the real Windows Start-menu (the programs panel) ----------------------
  // Scanned once in the background at startup; the panel only filters by
  // search text afterwards.
  List<WindowsAppEntry> _windowsApps = const [];
  final TextEditingController _appsSearch = TextEditingController();
  final FocusNode _appsFocus = FocusNode();

  // System volume mirrored from the audio endpoint.
  double _volume = 0.7;
  bool _muted = false;

  // ---- per-app volume (the mixer's rows under the master slider) ------------
  // Scanned when the sound flyout opens and re-polled every few seconds while
  // it stays open: sessions appear and vanish with the apps themselves.
  List<AudioAppSession> _audioSessions = const [];
  Timer? _sessionsTimer;
  Timer? _wifiPoll;

  // ---- the wi-fi flyout ------------------------------------------------------
  // Scanned once when the flyout lands (netsh takes a moment) and re-scanned
  // on demand; the expanded network card holds the password field.
  List<WifiNetwork> _wifiNetworks = const [];
  bool _wifiScanning = false;
  bool _wifiSearchOpen = false;
  String _wifiQuery = '';
  String? _wifiExpanded;
  final TextEditingController _wifiSearch = TextEditingController();
  final FocusNode _wifiSearchFocus = FocusNode();
  final TextEditingController _wifiPassword = TextEditingController();
  bool _wifiAutoJoin = true;
  bool _wifiBusy = false;

  // ---- clock / region / display (the settings' new panes) --------------------
  /// The desktop clock adds these minutes to the system time: the chosen
  /// Windows time zone's offset versus this machine's own, re-synced every
  /// 10 min so daylight changes are small and slow.
  int _tzDeltaMin = 0;

  /// The chosen Windows zone id; '' means "use this machine's zone".
  String _tzZone = '';

  /// "Pick the zone automatically" — off by default, as requested.
  bool _tzAuto = false;

  /// The region the Date & time pane shows; formats and locale in one knob.
  String _region = 'ru-RU';
  Timer? _tzTimer;

  /// The Display pane's dropdowns: mock values, persisted like everything
  /// else. 'auto' stands for the recommended auto-detect anywhere sensible.
  String _displayRes = 'auto';
  String _displayOrient = 'auto';
  String _displayHz = 'auto';

  /// The Configs switch: when false the wallpaper timer only ticks.
  bool _slideshowOn = true;

  /// The wallpaper timer's period in seconds (was hard-wired to 12).
  int _slideshowPeriod = 12;

  /// Keys the vibe-bar pane is allowed to put on the waybar's right side.
  static const List<String> _waybarItemKeys = [
    'bluetooth',
    'sound',
    'wifi',
    'brightness',
    'clipboard',
    'emoji',
    'updates',
    'calendar',
    'notifications',
  ];

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
  WindowManager get _windows => _wm.activeManager;

  @override
  void initState() {
    super.initState();
    _workspaces = WorkspaceController(backgroundCount: _backgrounds.length);
    _wm = WmServer(
      workspaces: _workspaces,
      area: DesktopArea(_viewport.width, _viewport.height),
    )..addListener(_onWmChanged);
    _wifiNetworks = widget.wifiNetworks ?? const [];
    _player = PlayerController(engine: widget.audio, vsync: this);
    _player.setTracks(_seedTracks, const {});
    _loadBrightnessLib();
    _router = CommandRouter(sink: this);
    unawaited(_refreshRadios());
    _radioTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(_refreshRadios());
    });
    // Everything the settings panes remember (slideshow period, time zone,
    // region, display choices, the vibe bar's waybar buttons) comes from
    // prefs.cfg before the first frame, so the shell opens exactly as closed.
    _slideshowOn = ShellPrefs.getBool('slideshow', true);
    _slideshowPeriod = ShellPrefs.getInt('slideshow_period', 12);
    _tzZone = ShellPrefs.get('tz');
    _tzAuto = ShellPrefs.getBool('tz_auto', false);
    _region = ShellPrefs.get('region', 'ru-RU');
    _displayRes = ShellPrefs.get('display_res', 'auto');
    _displayOrient = ShellPrefs.get('display_orient', 'auto');
    _displayHz = ShellPrefs.get('display_hz', 'auto');
    _de = DeConfig.fromMap(ShellPrefs.get);
    _wm.configure(snapEnabled: _de.snapEnabled, snapGap: _de.snapGap);
    _notifications.addListener(_onNotifications);
    _associations = FileAssociations.fromRead(ShellPrefs.get);
    _lockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkAutoLock(),
    );
    final savedItems = ShellPrefs.get('waybar_items');
    if (savedItems.isNotEmpty) {
      var items = _sanitizeWaybarItems(savedItems);
      // Old prefs predate brightness being a removable panel. Add it once;
      // after the version key exists the user's removal is respected.
      if (ShellPrefs.get('waybar_version').isEmpty) {
        if (!items.contains('brightness')) items = [...items, 'brightness'];
        ShellPrefs.set('waybar_version', '2');
      }
      ShellLayout.waybarRightItems = items;
    }
    _backgroundTimer = Timer.periodic(
      Duration(seconds: _slideshowPeriod.clamp(5, 1 << 16)),
      (_) {
        // The settings switch freezes the slideshow without killing the timer.
        if (!mounted || !_slideshowOn) return;
        _workspaces.cycleBackground();
        _wallpaperTick.value++;
      },
    );
    if (_tzZone.isNotEmpty && !_tzAuto) {
      _tzTimer = Timer.periodic(
          const Duration(minutes: 10), (_) => unawaited(_syncClockDelta()));
      unawaited(_syncClockDelta());
    }
    unawaited(_scanMusicAssets());
    unawaited(_loadFileLibrary());
    // The Start-menu is read in the background: the power shell call takes a
    // second or two and must never block the shell's first frame.
    unawaited(_scanWindowsApps());
    // Rebuild the whole shell when the language flips in settings/configs.
    Loc.notifier.addListener(_onLanguageChanged);
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  // ---- settings-owned shell state (prefs.cfg) -------------------------------
  //
  // Everything below is written by the settings window and applied right
  // here: the shell is the runtime, the panes are its knobs.

  /// Keeps only real waybar keys, drops duplicates, and always leaves the
  /// three radio buttons present at the head (the flyouts must exist even if
  /// the vibe pane is mid-drag).
  List<String> _sanitizeWaybarItems(String csv) {
    final out = <String>[];
    for (final raw in csv.split(',')) {
      final key = raw.trim();
      if (!_waybarItemKeys.contains(key)) continue;
      if (out.contains(key)) continue;
      out.add(key);
    }
    return out;
  }

  /// The vibe-bar pane changed the waybar's right side (a trash click or an
  /// add): persist it, retarget the panels whose anchors moved, and close a
  /// flyout whose button has just been trashed.
  void _setWaybarItems(List<String> items) {
    ShellLayout.waybarRightItems = items;
    ShellPrefs.set('waybar_items', items.join(','));
    ShellPrefs.set('waybar_version', '2');
    if (!items.contains('sound') && _isVolumeOpen) _volumeMorph?.close();
    if (!items.contains('wifi') && _isWifiOpen) _wifiMorph?.close();
    if (!items.contains('brightness') && _isBrightnessOpen) {
      _brightnessMorph?.close();
    }
    // didChangeDependencies only fires on MediaQuery changes, so re-anchor
    // the morphs here for the new (possibly wider) waybar.
    final l = ShellLayout(_viewport.width, _viewport.height);
    _powerMorph?.retarget(l.powerButton, l.powerRect, 15.0);
    _brightnessMorph?.retarget(l.brightnessButton, l.brightnessRect, 25.0);
    _playerMorph?.retarget(l.playerButton, l.playerRect, 25.0);
    _volumeMorph?.retarget(l.volumeButton, l.volumeRect, 20.0);
    _wifiMorph?.retarget(l.wifiButton, l.wifiRect, 20.0);
    _launcherMorph?.retarget(l.launcherButton, l.launcherRect, 20.0);
    _desktopsMorph?.retarget(l.desktopsButton, l.desktopsRect, 20.0);
    _appsMorph?.retarget(l.appsButton, l.appsRect, 20.0);
    setState(() {});
  }

  /// The wallpaper slideshow switch + period, now living in the settings
  /// ('wallpaper & theme' tile) instead of the Configs app.
  void _setSlideshow(bool on, int period) {
    _slideshowOn = on;
    _slideshowPeriod = period.clamp(5, 3600);
    ShellPrefs.set('slideshow', _slideshowOn ? '1' : '0');
    ShellPrefs.set('slideshow_period', '$_slideshowPeriod');
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer.periodic(
      Duration(seconds: _slideshowPeriod),
      (_) {
        if (!mounted || !_slideshowOn) return;
        _workspaces.cycleBackground();
        _wallpaperTick.value++;
      },
    );
    setState(() {});
  }

  /// Computes the chosen Windows time zone's current offset versus this
  /// machine's clock, in whole minutes. Uses one short powershell round-trip
  /// per sync (open + every 10 min), so DST changes stay small drifts.
  Future<void> _syncClockDelta() async {
    if (_tzZone.isEmpty || _tzAuto) return;
    final zoneOffset = SysCtl.timezoneOffset(_tzZone);
    if (!mounted || zoneOffset == null) return;
    // The clock ticks on local wall time; add the difference between the
    // chosen zone and this machine. DST is already inside zoneOffset.
    final localOffset = DateTime.now().timeZoneOffset.inMinutes;
    setState(() {
      _tzDeltaMin = zoneOffset - localOffset;
    });
  }

  /// The Date & time pane picked a zone (or ticked the auto switch).
  void _setTimezone(String zone, {required bool auto}) {
    _tzZone = zone;
    _tzAuto = auto;
    ShellPrefs.set('tz', zone);
    ShellPrefs.set('tz_auto', auto ? '1' : '0');
    _tzTimer?.cancel();
    if (auto || zone.isEmpty) {
      // Automatic = trust the machine: the delta resets and the clock shows
      // its own time again.
      if (mounted) setState(() => _tzDeltaMin = 0);
      return;
    }
    _tzTimer = Timer.periodic(
        const Duration(minutes: 10), (_) => unawaited(_syncClockDelta()));
    unawaited(_syncClockDelta());
  }

  void _setRegion(String region) {
    _region = region;
    ShellPrefs.set('region', region);
    setState(() {});
  }

  void _setDisplayRes(String value) {
    if (value != 'auto') {
      final parts = value.split('x');
      final width = int.tryParse(parts.first);
      final height = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (width == null || height == null) return;
      final current = SysCtl.displayState().current;
      final ok = SysCtl.applyDisplay(
        width: width,
        height: height,
        hz: current?.hz ?? 0,
        orientation: current?.orientation ?? -1,
      );
      if (!ok) return;
    }
    _displayRes = value;
    ShellPrefs.set('display_res', value);
    setState(() {});
  }

  void _setDisplayOrient(String value) {
    if (value != 'auto') {
      final orientation = int.tryParse(value);
      if (orientation == null) return;
      final current = SysCtl.displayState().current;
      if (current == null) return;
      final ok = SysCtl.applyDisplay(
        width: current.width,
        height: current.height,
        hz: current.hz,
        orientation: orientation,
      );
      if (!ok) return;
    }
    _displayOrient = value;
    ShellPrefs.set('display_orient', value);
    setState(() {});
  }

  void _setDisplayHz(String value) {
    if (value != 'auto') {
      final hz = int.tryParse(value);
      if (hz == null) return;
      final current = SysCtl.displayState().current;
      final ok = SysCtl.applyDisplay(
        width: current?.width ?? 0,
        height: current?.height ?? 0,
        hz: hz,
        orientation: current?.orientation ?? -1,
      );
      if (!ok) return;
    }
    _displayHz = value;
    ShellPrefs.set('display_hz', value);
    setState(() {});
  }

  /// One background read of the machine's Start-menu for the programs panel.
  Future<void> _scanWindowsApps() async {
    final apps = await WindowsApps.scan();
    if (!mounted || apps.isEmpty) return;
    setState(() => _windowsApps = apps);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewport = MediaQuery.of(context).size;
    _wm.retarget(DesktopArea(_viewport.width, _viewport.height));

    // Where each panel's glass is born from, and where it lands. The numbers
    // live in [ShellLayout] so the mock suite can check every one of them
    // against the dock and the screen edges on any window size.
    final l = ShellLayout(_viewport.width, _viewport.height);
    if (_powerMorph == null) {
      _powerMorph = MorphPanelController(
        buttonRect: l.powerButton,
        menuRect: l.powerRect,
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
      _wifiMorph = MorphPanelController(
        buttonRect: l.wifiButton,
        menuRect: l.wifiRect,
        menuRadius: 20.0,
      )..attach(this);
      _launcherMorph = MorphPanelController(
        buttonRect: l.launcherButton,
        menuRect: l.launcherRect,
        menuRadius: 20.0,
        // The 9-dots menu opens at its place right away: no drop that starts
        // a bit too high and settles a second later, and the tiles are
        // hoverable from the first frame.
        instantOpen: true,
      )..attach(this);
      _desktopsMorph = MorphPanelController(
        buttonRect: l.desktopsButton,
        menuRect: l.desktopsRect,
        menuRadius: 20.0,
      )..attach(this);
      _appsMorph = MorphPanelController(
        buttonRect: l.appsButton,
        menuRect: l.appsRect,
        menuRadius: 20.0,
      )..attach(this);
      for (final morph in [
        _powerMorph,
        _brightnessMorph,
        _playerMorph,
        _volumeMorph,
        _wifiMorph,
        _launcherMorph,
        _desktopsMorph,
        _appsMorph,
      ]) {
        _watchMorph(morph!);
      }
    } else {
      _powerMorph!.retarget(l.powerButton, l.powerRect, 15.0);
      _brightnessMorph!.retarget(l.brightnessButton, l.brightnessRect, 25.0);
      _playerMorph!.retarget(l.playerButton, l.playerRect, 25.0);
      _volumeMorph!.retarget(l.volumeButton, l.volumeRect, 20.0);
      _wifiMorph!.retarget(l.wifiButton, l.wifiRect, 20.0);
      _launcherMorph!.retarget(l.launcherButton, l.launcherRect, 20.0);
      _desktopsMorph!.retarget(l.desktopsButton, l.desktopsRect, 20.0);
      _appsMorph!.retarget(l.appsButton, l.appsRect, 20.0);
    }
  }

  @override
  void dispose() {
    _backgroundTimer?.cancel();
    _radioTimer?.cancel();
    _replyTimer?.cancel();
    _wallpaperTick.dispose();
    _waybarTick.dispose();
    _pickRequest.dispose();
    _musicNotice.dispose();
    _noticeTimer?.cancel();
    _brightnessFx?.cancel();
    _contrastFx?.cancel();
    _warmthFx?.cancel();
    _commandController.dispose();
    _commandFocus.dispose();
    _player.dispose();
    Loc.notifier.removeListener(_onLanguageChanged);
    _powerMorph?.dispose();
    _brightnessMorph?.dispose();
    _playerMorph?.dispose();
    _volumeMorph?.dispose();
    _wifiMorph?.dispose();
    _launcherMorph?.dispose();
    _desktopsMorph?.dispose();
    _wm.dispose();
    _notifications.removeListener(_onNotifications);
    _filesOpenPath.dispose();
    _notepadOpenPath.dispose();
    _browserOpenUrl.dispose();
    _filePick.dispose();
    _lockTimer?.cancel();
    _toastTimer?.cancel();
    _lockController.dispose();
    _lockFocus.dispose();
    _appsMorph?.dispose();
    _appsSearch.dispose();
    _appsFocus.dispose();
    _wifiSearch.dispose();
    _wifiSearchFocus.dispose();
    _wifiPassword.dispose();
    _sessionsTimer?.cancel();
    _wifiPoll?.cancel();
    _tzTimer?.cancel();
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
    _assetTracks = tracks;
    _assetCovers = covers;
    _publishTracks();
  }

  /// Rebuilds the player's library from the bundled tracks and the files the
  /// user added. Both scans land independently; whichever finishes last still
  /// sees both lists.
  void _publishTracks() {
    _player.setTracks(
      [..._assetTracks, ..._fileTracks],
      {..._assetCovers, ..._fileCovers},
    );
  }

  /// Imported tracks get a `library/` key prefix, so a file that happens to
  /// share a name with a bundled asset cannot steal its cover.
  Track _keyedFileTrack(Track track) => Track(
        title: track.title,
        artist: track.artist,
        file: 'library/${track.file}',
        path: track.path,
        avatar: track.avatar,
        duration: track.duration,
      );

  /// Reads `%APPDATA%\EXpaDesktop\Music` off the UI thread.
  Future<void> _loadFileLibrary() async {
    final directory = _library.musicDir;
    final cache = _library.coverCacheDir;
    List<LibraryTrack> scanned;
    try {
      // The Rust scanner is one native pass (and it extracts the covers);
      // without the DLL the same job is done in Dart inside an isolate.
      final native = await MusicScanner.scan(directory, cache);
      scanned = native ?? await Isolate.run(() => scanMusicDirectory(directory));
    } catch (_) {
      scanned = const [];
    }
    if (!mounted || scanned.isEmpty) return;
    final tracks = <Track>[];
    final covers = <String, Uint8List>{};
    for (final entry in scanned) {
      final keyed = _keyedFileTrack(entry.track);
      tracks.add(keyed);
      if (entry.cover != null) covers[keyed.file] = entry.cover!;
    }
    _fileTracks = tracks;
    _fileCovers = covers;
    _publishTracks();
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
      // A flyout can close by its own button *or* by the tap-away layer.
      // Both paths end here, so the pollers stop even when the panel was not
      // closed through _toggleWifiPanel/_toggleVolume.
      if (!animating && !morph.active) {
        if (identical(morph, _wifiMorph)) {
          _wifiPoll?.cancel();
          _wifiPoll = null;
          _wifiSearchOpen = false;
          _wifiQuery = '';
          _wifiSearch.clear();
        }
        if (identical(morph, _volumeMorph)) {
          _sessionsTimer?.cancel();
          _sessionsTimer = null;
        }
      }
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
      final current = normalizeBrightness(_getBrightness!()) ?? _brightness;
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
        case ShellPanel.power:
          if (_isPowerOpen) _powerMorph?.close();
        case ShellPanel.launcher:
          if (_isLauncherOpen) _launcherMorph?.close();
        case ShellPanel.apps:
          if (_isAppsOpen) _appsMorph?.close();
        case ShellPanel.brightness:
          if (_isBrightnessOpen) _brightnessMorph?.close();
        case ShellPanel.volume:
          if (_isVolumeOpen) _volumeMorph?.close();
        case ShellPanel.wifi:
          if (_isWifiOpen) _wifiMorph?.close();
        case ShellPanel.player:
          if (_isPlayerOpen) _playerMorph?.close();
        case ShellPanel.desktops:
          if (_isDesktopsOpen) _desktopsMorph?.close();
      }
    }
  }

  /// Closes every floating panel; used when an app window is opened.
  ///
  /// [fast] plays the same shrink-back spring at 2.6x. A menu that is being
  /// dismissed because an app is launching should not sit over the middle of
  /// the screen for the whole morph while the window animates behind it.
  void _closePanels({bool fast = false}) {
    final speed = fast ? 2.6 : 1.0;
    if (_isPowerOpen) _powerMorph?.close(speed: speed);
    if (_isLauncherOpen) _launcherMorph?.close(speed: speed);
    if (_isAppsOpen) _appsMorph?.close(speed: speed);
    if (_isBrightnessOpen) _brightnessMorph?.close(speed: speed);
    if (_isVolumeOpen) _volumeMorph?.close(speed: speed);
    if (_isWifiOpen) _wifiMorph?.close(speed: speed);
    if (_isPlayerOpen) _playerMorph?.close(speed: speed);
    if (_isDesktopsOpen) _desktopsMorph?.close(speed: speed);
  }

  bool get _isAnyPanelOpen =>
      _isPowerOpen ||
      _isLauncherOpen ||
      _isAppsOpen ||
      _isBrightnessOpen ||
      _isVolumeOpen ||
      _isWifiOpen ||
      _isPlayerOpen ||
      _isDesktopsOpen;

  void _dismissFloatingSurfaces() {
    if (!_isVolumeOpen &&
        !_isWifiOpen &&
        !_isBrightnessOpen &&
        !_isPlayerOpen &&
        !_isPowerOpen &&
        !_isLauncherOpen &&
        !_isAppsOpen &&
        !_isDesktopsOpen) {
      return;
    }
    _closePanels();
    setState(() {});
  }

  /// The power dropdown toggles over the launcher's power button. It closes
  /// nothing: the launcher stays open underneath it.
  void _togglePowerMenu() {
    final m = _powerMorph;
    if (m == null) return;
    _applyPanelPlan(ShellPanel.power);
    m.toggle();
    setState(() {});
  }

  /// The real-programs panel toggles from the waybar's 4-squares button;
  /// it is a centred panel, so the launcher and every flyout close first.
  void _toggleAppsMenu() {
    final m = _appsMorph;
    if (m == null) return;
    _applyPanelPlan(ShellPanel.apps);
    m.toggle();
    // The search field grabs the keyboard the moment the panel lands, so
    // "type to find" works without a second click.
    if (m.active) {
      // The search field grabs the keyboard the moment the panel lands, so
      // "type to find" works without a second click.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _appsFocus.requestFocus();
      });
    }
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
  /// desktop stays exactly where it is. On open it also pulls the live
  /// per-app session list and, while the panel stays up, re-polls it —
  /// games and tabs come and go faster than a settings page would think.
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
      unawaited(_refreshAudioSessions());
      _sessionsTimer?.cancel();
      _sessionsTimer = Timer.periodic(
          const Duration(seconds: 3), (_) => unawaited(_refreshAudioSessions()));
    } else {
      _sessionsTimer?.cancel();
    }
    m.toggle();
    setState(() {});
  }

  /// One scan of the mixer's sessions (fail-soft: an empty list keeps the
  /// master row alone).
  Future<void> _refreshAudioSessions() async {
    try {
      final sessions = await AudioSessions.instance.sessions();
      if (!mounted) return;
      setState(() => _audioSessions = sessions);
    } catch (_) {}
  }

  /// Writes one app's volume (the slider under a mixer row).
  void _setAudioSessionVolume(int pid, double value) {
    // Optimistic: the row moves at once; the COM write follows synchronously.
    final list = [
      for (final s in _audioSessions)
        if (s.pid == pid) s..volume = value else s,
    ];
    setState(() => _audioSessions = list);
    AudioSessions.instance.setVolume(pid, value);
  }

  /// Mutes one app's row.
  void _setAudioSessionMute(int pid, bool muted) {
    final list = [
      for (final s in _audioSessions)
        if (s.pid == pid) s..muted = muted else s,
    ];
    setState(() => _audioSessions = list);
    AudioSessions.instance.setMute(pid, muted);
  }

  // ---- the wi-fi flyout ------------------------------------------------------

  /// The wifi list drops out of its own waybar button — the settings window
  /// stays where it is, like every other flyout.
  void _toggleWifiPanel() {
    final m = _wifiMorph;
    if (m == null) return;
    _applyPanelPlan(ShellPanel.wifi);
    if (!m.active) {
      _wifiQuery = '';
      _wifiSearch.clear();
      _wifiExpanded = null;
      if (widget.wifiNetworks != null) {
        _wifiNetworks = widget.wifiNetworks!;
      } else {
        unawaited(_wifiScan());
        _wifiPoll?.cancel();
        _wifiPoll = Timer.periodic(
            const Duration(seconds: 10), (_) => unawaited(_wifiScan()));
      }
    } else {
      _wifiPoll?.cancel();
    }
    m.toggle();
    setState(() {});
  }

  /// One netsh pass; the pin (connected state) rides in the network list.
  Future<void> _wifiScan() async {
    if (_wifiScanning) return;
    _wifiScanning = true;
    if (mounted) setState(() {});
    try {
      final nets = await WifiControl.networks();
      if (!mounted) return;
      setState(() {
        _wifiNetworks = nets;
        _wifiScanning = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _wifiScanning = false);
      }
    }
  }

  /// "Подключиться": known networks join straight away; password networks go
  /// through the profile writer first. Failures surface in the row itself.
  Future<bool> _wifiConnect(WifiNetwork net, String password) async {
    if (_wifiBusy) return false;
    _wifiBusy = true;
    if (mounted) setState(() {});
    try {
      final ok = await WifiControl.connect(
        net,
        password: password,
        autoConnect: _wifiAutoJoin,
      );
      if (mounted) {
        setState(() => _wifiBusy = false);
      }
      if (ok) unawaited(_wifiScan());
      _notify(
        ok ? 'Wi-Fi connected' : 'Wi-Fi connection failed',
        net.ssid,
        category: 'network',
      );
      return ok;
    } catch (_) {
      if (mounted) setState(() => _wifiBusy = false);
      return false;
    }
  }

  /// "Отключить" on a pinned network.
  Future<void> _wifiDisconnect(WifiNetwork net) async {
    if (_wifiBusy) return;
    _wifiBusy = true;
    if (mounted) setState(() {});
    try {
      await WifiControl.disconnect();
    } catch (_) {}
    if (mounted) setState(() => _wifiBusy = false);
    _notify('Wi-Fi disconnected', net.ssid, category: 'network');
    unawaited(_wifiScan());
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
  ///
  /// If a panel was covering the middle of the screen, it is dismissed at
  /// 2.6x speed and the window starts its own entrance ~150 ms later: by then
  /// the menu has shrunk out of the way, so the spring is actually visible.
  /// Without this, launching from the launcher played the whole entrance
  /// behind the closing menu and looked like the window simply appeared.
  void _openApp(ShellApp app, {String? section}) {
    final panelWasOpen = _isAnyPanelOpen;
    _closePanels(fast: panelWasOpen);
    if (app == ShellApp.settings && section != null) {
      _settingsNav.show(section);
    }
    final manager = _windows;

    void open() {
      if (!mounted) return;
      manager.open(app);
      setState(() {});
    }

    open();
  }

  /// The dock's running-window buttons: focus, or minimize if already focused.
  void _toggleAppWindow(AppWindow window) {
    if (_windows.activeId == window.id && !window.minimized) {
      // Fold through the genie: the dock button asks the live window widget
      // to play the macOS-style squeeze before the manager hides it.
      // The restore path is the mirror: a minimized window re-mounts its
      // ShellWindow on focus, and the entrance plays the genie backwards.
      ShellWindow.minimizeAnimated(_windows, window.id);
    } else {
      _windows.focus(window.id);
    }
    setState(() {});
  }

  void _openSettingsAt(String? section) {
    _openApp(ShellApp.settings, section: section);
    if (section == 'wifi' || section == 'bluetooth') {
      unawaited(_refreshRadios());
    }
  }

  /// The Tracks pill: the player flyout dismisses itself and Musics opens.
  void _openMusics() => _openApp(ShellApp.musics);

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

  // ---- adding music ---------------------------------------------------------

  /// Musics' Add track button: ask the Files window for an audio file.
  void _requestAddTrack() {
    if (_pickRequest.value != null) return;
    _pickRequest.value = AudioPickRequest(
      onPick: (path) => unawaited(_importAudio(path)),
      onCancel: () => _pickRequest.value = null,
    );
    _openApp(ShellApp.files);
  }

  /// Copies the chosen file into the library, reads its tags off the UI
  /// thread and puts it in the player's list.
  Future<void> _importAudio(String sourcePath) async {
    _pickRequest.value = null;
    final destination = await _library.import(sourcePath);
    if (!mounted) return;
    if (destination == null) {
      _showMusicNotice('That file could not be added');
      return;
    }
    final root = _library.musicDir;
    LibraryTrack? scanned;
    try {
      scanned = await Isolate.run(
        () => readLibraryTrack(File(destination), root),
      );
    } catch (_) {
      scanned = null;
    }
    if (!mounted) return;
    if (scanned == null) {
      _showMusicNotice('Could not read that file');
      return;
    }
    final keyed = _keyedFileTrack(scanned.track);
    _fileTracks = [..._fileTracks, keyed];
    if (scanned.cover != null) {
      _fileCovers = {..._fileCovers, keyed.file: scanned.cover!};
    }
    _publishTracks();
    final musics = _windows.forApp(ShellApp.musics.id);
    if (musics != null) _windows.focus(musics.id);
    setState(() {});
    _showMusicNotice('Added: ');
    _notify('Track added', keyed.title, category: 'music');
  }

  void _showMusicNotice(String text) {
    _musicNotice.value = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) _musicNotice.value = null;
    });
  }

  Widget _windowContent(AppWindow window) {
    switch (window.app) {
      case ShellApp.calculator:
        return const CalculatorApp();
      case ShellApp.notepad:
        return NotepadApp(openPath: _notepadOpenPath);
      case ShellApp.files:
        return FilesApp(
          audioPick: _pickRequest,
          openPath: _filesOpenPath,
          onOpenDefault: _openDefaultApp,
          filePick: _filePick,
        );
      case ShellApp.paint:
        return const PaintApp();
      case ShellApp.snip:
        return SnipApp(capture: _captureShell);
      case ShellApp.tasks:
        return const TasksApp();
      case ShellApp.browser:
        return BrowserApp(openUrl: _browserOpenUrl);
      case ShellApp.musics:
        return MusicsApp(
          player: _player,
          onAddTrack: _requestAddTrack,
          notice: _musicNotice,
        );
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
          // The wallpaper timer's new home inside the wallpaper pane.
          slideshowOn: _slideshowOn,
          slideshowPeriod: _slideshowPeriod,
          onSlideshow: _setSlideshow,
          // The vibe bar's waybar buttons (add + trash, autosaved).
          waybarItems: ShellLayout.waybarRightItems,
          onWaybarItems: _setWaybarItems,
          // Date & time: the desktop clock's zone and the region.
          tzZone: _tzZone,
          tzAuto: _tzAuto,
          region: _region,
          onTimezone: _setTimezone,
          onRegion: _setRegion,
          // Display: persisted dropdown choices.
          displayRes: _displayRes,
          displayOrient: _displayOrient,
          displayHz: _displayHz,
          onDisplayRes: _setDisplayRes,
          onDisplayOrient: _setDisplayOrient,
          onDisplayHz: _setDisplayHz,
          // Updates: real links are handled by the shell.
          onOpenUpdater: () => _openApp(ShellApp.updates),
          config: _de,
          onConfig: _setDeConfig,
          associations: _associations,
          onAssociations: _setAssociations,
          notifications: _notifications,
          onLock: _lockNow,
          onOpenPath: _openFilesAt,
        );
      case ShellApp.configs:
        return ConfigsApp(
          config: _de,
          onConfig: _setDeConfig,
          waybarItems: ShellLayout.waybarRightItems,
          onWaybarItems: _setWaybarItems,
          windows: _windows.windows,
          activeId: _windows.activeId,
          onFocusWindow: (window) {
            _windows.focus(window.id);
            setState(() {});
          },
          onCloseWindow: (window) {
            _windows.close(window.id);
            setState(() {});
          },
          version: appVersion,
          prefsPath: ShellPrefs.path,
          repoPath: UpdateRunner.findRepo(),
          pickZip: _pickZipPreset,
        );
      case ShellApp.terminal:
        return const TerminalApp();
      case ShellApp.clipboard:
        return const ClipboardApp();
      case ShellApp.notifications:
        return NotificationsApp(center: _notifications);
      case ShellApp.calendar:
        return const CalendarApp();
      case ShellApp.emoji:
        return const EmojiApp();
      case ShellApp.updates:
        return UpdaterApp(
          current: appVersion,
          onUpdate: _startUpdate,
        );
    }
  }

  void _setAssociations(FileAssociations next) {
    setState(() => _associations = next);
    final map = next.toMap();
    for (final entry in map.entries) {
      ShellPrefs.set(entry.key, entry.value);
    }
  }

  void _openNotepadAt(String path) {
    _notepadOpenPath.value = path;
    _openApp(ShellApp.notepad);
  }

  bool _openDefaultApp(FileEntry entry) {
    final app = _associations.appFor(entry.path);
    switch (app) {
      case 'notepad':
        _openNotepadAt(entry.path);
        return true;
      case 'musics':
        _openApp(ShellApp.musics);
        return true;
      case 'browser':
        _browserOpenUrl.value = Uri.file(entry.path).toString();
        _openApp(ShellApp.browser);
        return true;
      default:
        return false;
    }
  }

  void _openFilesAt(String path) {
    _filesOpenPath.value = path;
    _openApp(ShellApp.files);
  }

  void _lockNow() {
    setState(() {
      _locked = true;
      _lockError = '';
      _lockController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _lockFocus.requestFocus());
  }

  void _checkAutoLock() {
    if (!mounted || _locked || _de.autoLockMinutes <= 0) return;
    final idle = DateTime.now().difference(_lastActivity).inMinutes;
    if (idle >= _de.autoLockMinutes) _lockNow();
  }

  void _unlock() {
    final pin = _de.lockPin;
    if (pin.isNotEmpty && _lockController.text != pin) {
      setState(() => _lockError = Loc.t('Wrong PIN', 'Неверный PIN'));
      return;
    }
    setState(() {
      _locked = false;
      _lockError = '';
      _lockController.clear();
      _lastActivity = DateTime.now();
    });
  }

  void _openWidget(String key) {
    final app = ShellApp.byId(key);
    if (app != null) _openApp(app);
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
    setState(_workspaces.closeActive);
  }

  void _selectWorkspace(int index) {
    setState(() => _workspaces.select(index));
  }

  void _onWmChanged() {
    if (mounted) setState(() {});
  }

  void _onNotifications() {
    if (mounted) setState(() {});
  }

  /// Posts a desktop notification when the user has them enabled.
  void _notify(String title, String body, {String category = 'system'}) {
    if (!_de.notificationsEnabled) return;
    final item =
        _notifications.post(title, body, category: category);
    setState(() => _toast = item);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _toast?.id == item.id) {
        setState(() => _toast = null);
      }
    });
  }

  /// The Updater window's action: start the Rust helper, then close this
  /// process so the build can replace the exe. The helper relaunches it.
  Future<String?> _pickZipPreset() {
    _filePick.value?.onCancel?.call();
    final completer = Completer<String?>();
    _filePick.value = FilePickRequest(
      title: 'Choose a .zip preset pack',
      accepts: (path) => path.toLowerCase().endsWith('.zip'),
      onPick: (path) {
        if (!completer.isCompleted) completer.complete(path);
        _filePick.value = null;
      },
      onCancel: () {
        if (!completer.isCompleted) completer.complete(null);
        _filePick.value = null;
      },
    );
    _openApp(ShellApp.files);
    return completer.future;
  }

  Future<String?> _startUpdate(String mode, String target, String repo) async {
    final ok = await UpdateRunner.start(
      repo: repo,
      mode: mode,
      target: target,
      pid: pid,
    );
    if (!ok) {
      return Loc.t(
        'updater.exe was not found next to the app.',
        'updater.exe не найден рядом с приложением.',
      );
    }
    Future<void>.delayed(const Duration(milliseconds: 500), () => exit(0));
    return null;
  }

  /// Saves every desktop-environment knob and applies the behaviour ones to
  /// EXWM immediately. Called by Settings and the Configs app.
  void _setDeConfig(DeConfig next) {
    setState(() {
      _de = next;
    });
    final map = next.toMap();
    for (final entry in map.entries) {
      ShellPrefs.set(entry.key, entry.value);
    }
    _wm.configure(snapEnabled: next.snapEnabled, snapGap: next.snapGap);
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
    _wifiStatus = wifi;
    _bluetoothStatus = bluetooth;
    // Only the waybar reads these; a full shell rebuild every 45 s was
    // rebuilding every open window for two icons.
    _waybarTick.value++;
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
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          control: true,
          alt: true,
        ): () => _snapActive(SnapZone.leftHalf),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          control: true,
          alt: true,
        ): () => _snapActive(SnapZone.rightHalf),
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          control: true,
          alt: true,
        ): () => _snapActive(SnapZone.maximize),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          control: true,
          alt: true,
        ): () => _snapActive(SnapZone.bottomHalf),
        const SingleActivator(
          LogicalKeyboardKey.digit1,
          control: true,
          alt: true,
        ): () => _snapActive(SnapZone.topLeft),
        const SingleActivator(
          LogicalKeyboardKey.digit2,
          control: true,
          alt: true,
        ): () => _snapActive(SnapZone.topRight),
        const SingleActivator(
          LogicalKeyboardKey.digit3,
          control: true,
          alt: true,
        ): () => _snapActive(SnapZone.bottomLeft),
        const SingleActivator(
          LogicalKeyboardKey.digit4,
          control: true,
          alt: true,
        ): () => _snapActive(SnapZone.bottomRight),
        if (_commandBarOpen)
          const SingleActivator(LogicalKeyboardKey.escape): _toggleCommandBar,
      };

  void _snapActive(SnapZone zone) {
    _wm.snapActive(zone);
    setState(() {});
  }

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
      if (kind == RadioKind.wifi) {
        _wifiStatus = result.status;
      } else {
        _bluetoothStatus = result.status;
      }
      _waybarTick.value++;
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

  Widget _buildWallpaper() {
    return AnimatedSwitcher(
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
          '${_workspaces.activeIndex}-'
          '${_workspaces.active.backgroundIndex}',
        ),
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              _backgrounds[
                  _workspaces.active.backgroundIndex % _backgrounds.length],
            ),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }

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
            // Only this layer rebuilds on the 12 s slideshow tick: the shell
            // used to setState there, which rebuilt every open app window on
            // a timer and made the desktop hitch once a minute.
            Positioned.fill(
              child: RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: _wallpaperTick,
                  builder: (context, _, __) => _buildWallpaper(),
                ),
              ),
            ),
            if (_de.wallpaperDim > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: _de.wallpaperDim),
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
            Positioned(
              top: 20.0,
              left: 30.0,
              child: _Clock(
                deltaMinutes: _tzAuto ? 0 : _tzDeltaMin,
                showSeconds: _de.clockSeconds,
              ),
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
                  // The dismiss layer only sits over the screen when a panel
                  // is open; a click anywhere then closes them all.
                  final open = _isPowerOpen ||
                      _isBrightnessOpen ||
                      _isPlayerOpen ||
                      _isVolumeOpen ||
                      _isLauncherOpen ||
                      _isAppsOpen;
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
              child: ValueListenableBuilder<int>(
                valueListenable: _waybarTick,
                builder: (context, _, __) => _Waybar(
                  key: const ValueKey('waybar'),
                  player: _player,
                  onPlayer: _togglePlayer,
                  onApps: _toggleAppsMenu,
                  onBrightness: _toggleBrightness,
                  wifiOn: _wifiStatus.isOn,
                  bluetoothOn: _bluetoothStatus.isOn,
                  muted: _muted,
                  // The wifi button opens its own flyout now, like sound does.
                  onWifi: _toggleWifiPanel,
                  onBluetooth: () => _openSettingsAt('bluetooth'),
                  onVolume: _toggleVolume,
                  rightItems: ShellLayout.waybarRightItems,
                  onWidget: _openWidget,
                  notificationsUnread: _notifications.unread,
                ),
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
                  interactive: true,
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
            // Windows-11-style mixer: a master row first (small mute icon on
            // the left, the slider, the loudness icon on the right), a short
            // divider, then every running app that owns an audio session —
            // each with its own slider and mute toggle.
            ListenableBuilder(
              listenable: _volumeMorph ?? const AlwaysStoppedAnimation<int>(0),
              builder: (context, _) {
                final morph = _volumeMorph;
                final f = morph?.frame;
                if (morph == null || f == null) return const SizedBox.shrink();
                return MorphGlass(
                  frame: f,
                  restWidth: 340,
                  restHeight: 300,
                  interactive: true,
                  child: Padding(
                    key: const ValueKey('volume-flyout'),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: SizedBox(
                      width: 340,
                      height: 300,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The master row: slider first, then the small mute icon and the
// percentage on the right. The first row is the system volume; the
// per-app rows below the divider follow the same shape.
                          Row(
                            children: [
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
                              const SizedBox(width: 10),
                              GestureDetector(
                                key: const ValueKey('volume-master-mute'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  final sound = _soundSource;
                                  setState(() {
                                    sound.muted = !sound.muted;
                                    _muted = sound.muted;
                                    _volume = sound.volume;
                                  });
                                },
                                child: Icon(
                                  _muted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  size: 17,
                                ),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 32,
                                child: Text(
                                  '${(_volume * 100).round()}%',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 10.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // The short divider between master and apps.
                          Container(
                            width: 64,
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                          const SizedBox(height: 10),
                          if (_audioSessions.isEmpty)
                            Caption(Loc.t(
                                'No apps are playing right now',
                                'Сейчас нет приложений со звуком'))
                          else
                            Expanded(
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: _audioSessions.length,
                                itemExtent: 40,
                                itemBuilder: (context, i) {
                                  final s = _audioSessions[i];
                                  final name = s.exe.isEmpty
                                      ? Loc.t('App ${(s.pid % 10000)}',
                                          'Приложение ${(s.pid % 10000)}')
                                      : '${s.exe[0].toUpperCase()}${s.exe.substring(1)}';
                                  return Row(
                                    children: [
                                      Icon(
                                        _audioAppIcon(s.exe),
                                        size: 17,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 104,
                                        child: Text(
                                          name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12.5),
                                        ),
                                      ),
                                      Expanded(
                                        child: WaveSlider(
                                          value: s.muted ? 0.0 : s.volume,
                                          onChanged: (value) =>
                                              _setAudioSessionVolume(
                                                  s.pid, value),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () =>
                                            _setAudioSessionMute(
                                                s.pid, !s.muted),
                                        child: Icon(
                                          s.muted
                                              ? Icons.volume_off
                                              : Icons.volume_up,
                                          size: 16,
                                          color: s.muted
                                              ? Colors.white38
                                              : Colors.white70,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // ---- wi-fi flyout -------------------------------------------------
            // Header ('Сети' + loupe), a divider, then the network rows: a
            // signal-bars icon, the name, the lock. Tapping a row expands an
            // in-row card — password entry for new networks, 'Отключить' for
            // the pinned (already connected) one.
            ListenableBuilder(
              listenable: _wifiMorph ?? const AlwaysStoppedAnimation<int>(0),
              builder: (context, _) {
                final morph = _wifiMorph;
                final f = morph?.frame;
                if (morph == null || f == null) return const SizedBox.shrink();
                final nets = [
                  for (final net in _wifiNetworks)
                    if (_wifiQuery.isEmpty ||
                        net.ssid.toLowerCase().contains(_wifiQuery))
                      net,
                ];
                return MorphGlass(
                  frame: f,
                  restWidth: 360,
                  restHeight: 430,
                  interactive: true,
                  child: Padding(
                    key: const ValueKey('wifi-flyout'),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: SizedBox(
                      width: 360,
                      height: 430,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                Loc.t('Networks', 'Сети'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () => setState(() {
                                  _wifiSearchOpen = !_wifiSearchOpen;
                                  if (!_wifiSearchOpen) {
                                    _wifiSearch.clear();
                                    _wifiQuery = '';
                                  } else {
                                    WidgetsBinding.instance.addPostFrameCallback(
                                        (_) => _wifiSearchFocus.requestFocus());
                                  }
                                }),
                                icon: Icon(
                                  _wifiSearchOpen
                                      ? Icons.close_rounded
                                      : Icons.search_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 30, minHeight: 30),
                              ),
                            ],
                          ),
                          // The search field slides in under the header.
                          AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: _wifiSearchOpen
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: TextField(
                                      controller: _wifiSearch,
                                      onChanged: (q) =>
                                          setState(() => _wifiQuery =
                                              q.trim().toLowerCase()),
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: Loc.t(
                                            'Search a network', 'Найти сеть'),
                                        hintStyle: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 12.5),
                                        prefixIcon: const Icon(
                                            Icons.search_rounded,
                                            size: 16,
                                            color: Colors.white54),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: _wifiScanning && nets.isEmpty
                                ? const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                            Colors.white70),
                                      ),
                                    ),
                                  )
                                : nets.isEmpty
                                    ? Center(
                                        child: Caption(Loc.t(
                                            'No networks nearby',
                                            'Сетей поблизости нет')),
                                      )
                                    : ListView.builder(
                                        padding: EdgeInsets.zero,
                                        itemCount: nets.length,
                                        itemBuilder: (context, i) =>
                                            _WifiRow(
                                          key: ValueKey(
                                              'wifi-${nets[i].ssid}'),
                                          network: nets[i],
                                          expanded: _wifiExpanded ==
                                              nets[i].ssid,
                                          busy: _wifiBusy,
                                          autoJoin: _wifiAutoJoin,
                                          passwordController: _wifiPassword,
                                          onToggle: () => setState(() {
                                            _wifiExpanded = _wifiExpanded ==
                                                    nets[i].ssid
                                                ? null
                                                : nets[i].ssid;
                                            _wifiPassword.clear();
                                            // A network Windows already knows
                                            // starts with the auto box on.
                                            _wifiAutoJoin = nets[i].auto;
                                          }),
                                          onAutoChanged: (v) =>
                                              setState(() => _wifiAutoJoin = v),
                                          onConnect: () => unawaited(
                                              _wifiConnect(
                                                  nets[i],
                                                  _wifiPassword.text)),
                                          onConnectOpen: () => unawaited(
                                              _wifiConnect(nets[i], '')),
                                          onDisconnect: () => unawaited(
                                              _wifiDisconnect(nets[i])),
                                        ),
                                      ),
                          ),
                        ],
                      ),
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
                  restWidth: 380,
                  restHeight: 360,
                  interactive: true,
                  child: SizedBox(
                    width: 380,
                    height: 360,
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 358,
                            height: 266,
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              runAlignment: WrapAlignment.center,
                              spacing: 6,
                              runSpacing: 6,
                              // No per-app entrance animation: the tiles are
                              // already inside the morphing glass, another
                              // motion on top only made the menu feel slow.
                              children: [
                                for (var i = 0; i < _launcherApps.length; i++)
                                  _LauncherTile(
                                    key: ValueKey(
                                        'launcher-app-${_launcherApps[i].id}'),
                                    icon: iconForApp(_launcherApps[i]),
                                    accent: accentForApp(_launcherApps[i]),
                                    label: _launcherLabel(_launcherApps[i]),
                                    onTap: () => _openApp(_launcherApps[i]),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          _LauncherStrip(
                            onSettings: () => _openSettingsAt(null),
                            // The power menu: a small dropdown over the
                            // launcher's own power button (not the old panel).
                            onPower: _togglePowerMenu,
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
                  interactive: true,
                  child: SizedBox(
                    width: 340,
                    height: 270,
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            // "Desktop 1 of 4" in the shell language.
                            '${Loc.t('Desktop', 'Стол')} '
                            '${_workspaces.activeIndex + 1} '
                            '${Loc.t('of', 'из')} ${_workspaces.count}',
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
                                label: Loc.t('New', 'Создать'),
                                enabled: _workspaces.canCreate,
                                onTap: _newWorkspace,
                              ),
                              const SizedBox(width: 4),
                              _WorkspaceAction(
                                key: const ValueKey('workspace-prev'),
                                icon: Icons.arrow_back_rounded,
                                label: Loc.t('Back', 'Назад'),
                                enabled: _workspaces.count > 1,
                                onTap: _previousWorkspace,
                              ),
                              const SizedBox(width: 4),
                              _WorkspaceAction(
                                key: const ValueKey('workspace-next'),
                                icon: Icons.arrow_forward_rounded,
                                label: Loc.t('Forward', 'Вперёд'),
                                enabled: _workspaces.count > 1,
                                onTap: _nextWorkspace,
                              ),
                              const SizedBox(width: 4),
                              _WorkspaceAction(
                                key: const ValueKey('workspace-close'),
                                icon: Icons.delete_outline_rounded,
                                label: Loc.t('Close', 'Закрыть'),
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
            // ---- power flyout -----------------------------------------------
            // A small dropdown that rises above the launcher's power button
            // with the four real system actions. Every item fires instantly,
            // no confirm dialogs.
            ListenableBuilder(
              listenable: _powerMorph ?? const AlwaysStoppedAnimation<int>(0),
              builder: (context, _) {
                final morph = _powerMorph;
                final f = morph?.frame;
                if (morph == null || f == null) return const SizedBox.shrink();
                return MorphGlass(
                  frame: f,
                  restWidth: 200,
                  restHeight: 180,
                  interactive: true,
                  child: Padding(
                    key: const ValueKey('power-flyout'),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _PowerMenuItem(
                          icon: Icons.power_settings_new,
                          label: Loc.t('Shut down', 'Выключить'),
                          onTap: () {
                            morph.close();
                            unawaited(shutdownMachine());
                          },
                        ),
                        _PowerMenuItem(
                          icon: Icons.restart_alt,
                          label: Loc.t('Restart', 'Перезагрузить'),
                          onTap: () {
                            morph.close();
                            unawaited(restartMachine());
                          },
                        ),
                        _PowerMenuItem(
                          icon: Icons.bedtime,
                          label: Loc.t('Sleep', 'Спящий режим'),
                          onTap: () {
                            morph.close();
                            unawaited(sleepMachine());
                          },
                        ),
                        _PowerMenuItem(
                          icon: Icons.logout,
                          label: Loc.t('Exit to Windows', 'Выйти в Windows'),
                          onTap: () {
                            morph.close();
                            unawaited(signOut());
                          },
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
                  interactive: true,
                  child: PlayerPanel(
                    key: const ValueKey('player-flyout'),
                    player: _player,
                    onOpenTracks: _openMusics,
                  ),
                );
              },
            ),
            // ---- programs panel ----------------------------------------------
            // The machine's Start-menu: a search on top, every installed app
            // below, a click launches it through explorer. Clicking anywhere
            // outside the glass closes it (the shared dismiss layer).
            ListenableBuilder(
              listenable: _appsMorph ?? const AlwaysStoppedAnimation<int>(0),
              builder: (context, _) {
                final morph = _appsMorph;
                final f = morph?.frame;
                if (morph == null || f == null) return const SizedBox.shrink();
                return MorphGlass(
                  key: const ValueKey('apps-flyout'),
                  frame: f,
                  restWidth: 520,
                  restHeight: 480,
                  interactive: true,
                  tint: const Color(0xB8111113),
                  child: _AppsPanel(
                    windowsApps: _windowsApps,
                    search: _appsSearch,
                    focus: _appsFocus,
                    onLaunch: (entry) {
                      unawaited(WindowsApps.launch(entry));
                      _appsMorph?.close();
                      setState(() {});
                    },
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
                key: const ValueKey('dock'),
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
                    child: Stack(
                      children: [
                        // The task strip scrolls in its own layer, with room
                        // at the bottom for the launcher. The desktops button
                        // floats dead centre of the dock, independent of how
                        // many windows are open.
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          bottom: 62,
                          child: SingleChildScrollView(
                            child: _DockTasks(
                              windows: openWindows,
                              activeId: manager.activeId,
                              onTap: _toggleAppWindow,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.center,
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
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: PanelIcon(
                            key: const ValueKey('apps-button'),
                            icon: _isLauncherOpen ? Icons.close : Icons.apps,
                            onTap: _toggleLauncher,
                            spacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_toast != null)
              Positioned(
                top: 72,
                right: 92,
                child: _ToastCard(
                  key: const ValueKey('shell-toast'),
                  notification: _toast!,
                  onTap: () {
                    setState(() => _toast = null);
                    _openApp(ShellApp.notifications);
                  },
                ),
              ),
            if (_locked)
              Positioned.fill(
                child: _LockOverlay(
                  key: const ValueKey('lock-screen'),
                  controller: _lockController,
                  focus: _lockFocus,
                  error: _lockError,
                  pinRequired: _de.lockPin.isNotEmpty,
                  onUnlock: _unlock,
                ),
              ),
          ],
        ),
      ),
    );

    final themed = ExpaTheme(
      config: _de,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(_de.fontScale),
        ),
        child: shell,
      ),
    );
    return CallbackShortcuts(
      bindings: _shortcutBindings,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _lastActivity = DateTime.now(),
        onPointerHover: (_) => _lastActivity = DateTime.now(),
        onPointerSignal: (_) => _lastActivity = DateTime.now(),
        child: Focus(autofocus: true, child: themed),
      ),
    );
  }

  /// Launcher tiles in their shelf order; Configs sits right after Musics.
  List<ShellApp> get _launcherApps => const [
        ShellApp.calculator,
        ShellApp.notepad,
        ShellApp.files,
        ShellApp.paint,
        ShellApp.snip,
        ShellApp.tasks,
        ShellApp.browser,
        ShellApp.musics,
        ShellApp.configs,
        ShellApp.settings,
        ShellApp.terminal,
        ShellApp.clipboard,
        ShellApp.notifications,
        ShellApp.calendar,
        ShellApp.emoji,
        ShellApp.updates,
      ];

  /// Launcher tile labels in the shell language. Windows titles (the window
  /// chrome) stay English; the launcher is what the user reads.
  String _launcherLabel(ShellApp app) => Loc.t(app.title, switch (app.id) {
        'calculator' => 'Калькулятор',
        'notepad' => 'Блокнот',
        'files' => 'Файлы',
        'paint' => 'Рисование',
        'snip' => 'Ножницы',
        'tasks' => 'Задачи',
        'browser' => 'Браузер',
        'musics' => 'Музыка',
        'configs' => 'Конфиги',
        'settings' => 'Настройки',
        'terminal' => 'Терминал',
        'clipboard' => 'Буфер',
        'notifications' => 'Уведомления',
        'calendar' => 'Календарь',
        'emoji' => 'Эмодзи',
        'updates' => 'Обновления',
        _ => app.title,
      });

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
}

// === part 4 ===

/// A short-lived notification card in the top-right corner. Tapping it opens
/// the Notifications window; it fades in and is replaced by the next toast.
class _ToastCard extends StatelessWidget {
  final ShellNotification notification;
  final VoidCallback onTap;

  const _ToastCard({
    super.key,
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(24 * (1 - t), 0), child: child),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xF014171C),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                switch (notification.category) {
                  'music' => Icons.music_note_rounded,
                  'network' => Icons.wifi_rounded,
                  'updates' => Icons.system_update_rounded,
                  _ => Icons.notifications_none_rounded,
                },
                size: 17,
                color: Colors.white70,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  size: 15, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}

/// The in-desktop lock screen. It covers the shell and keeps the desktop
/// processes alive behind it; the PIN is the one from Settings → Lock screen.
class _LockOverlay extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final String error;
  final bool pinRequired;
  final VoidCallback onUnlock;

  const _LockOverlay({
    super.key,
    required this.controller,
    required this.focus,
    required this.error,
    required this.pinRequired,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xEE08090B), Color(0xEE11151C)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded,
                size: 42, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(height: 14),
            const Text(
              'EXpaDesktop',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Caption(Loc.t('Locked', 'Заблокировано')),
            const SizedBox(height: 18),
            if (pinRequired)
              SizedBox(
                width: 220,
                child: TextField(
                  key: const ValueKey('lock-pin'),
                  controller: controller,
                  focusNode: focus,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => onUnlock(),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, letterSpacing: 5),
                  decoration: InputDecoration(
                    hintText: 'PIN',
                    hintStyle: const TextStyle(
                        color: Colors.white24, letterSpacing: 2),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            if (pinRequired) const SizedBox(height: 12),
            PillButton(
              key: const ValueKey('lock-unlock'),
              label: Loc.t('Unlock', 'Разблокировать'),
              icon: Icons.lock_open_rounded,
              onTap: onUnlock,
            ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(error,
                  style: const TextStyle(
                      color: Color(0xFFFF8A8A), fontSize: 11.5)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The giant clock. It owns its one-second timer, so the shell does not
/// rebuild the whole desktop (and every open window) every second.
class _Clock extends StatefulWidget {
  const _Clock({this.deltaMinutes = 0, this.showSeconds = false});

  /// The chosen zone's offset minus this machine's offset. The clock ticks in
  /// UTC and re-localizes through it, so DST is handled by the zone table.
  final int deltaMinutes;

  /// EXPA customization: show hh:mm:ss instead of hh:mm.
  final bool showSeconds;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late String _time;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _time = _format(_now(), seconds: widget.showSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _format(_now(), seconds: widget.showSeconds);
      if (mounted && next != _time) setState(() => _time = next);
    });
  }

  DateTime _now() =>
      DateTime.now().add(Duration(minutes: widget.deltaMinutes));

  @override
  void didUpdateWidget(covariant _Clock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deltaMinutes == widget.deltaMinutes) return;
    final next = _format(_now(), seconds: widget.showSeconds);
    if (next != _time) setState(() => _time = next);
  }

  static String _format(DateTime now, {bool seconds = false}) =>
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}'
      '${seconds ? ':${now.second.toString().padLeft(2, '0')}' : ''}';

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
/// four-squares programs button right before the player, the radios and the
/// sound on the right.
class _Waybar extends StatelessWidget {
  final PlayerController player;
  final VoidCallback onPlayer;
  final VoidCallback onApps;
  final VoidCallback onBrightness;
  final VoidCallback onWifi;
  final VoidCallback onBluetooth;
  final VoidCallback onVolume;
  final List<String> rightItems;
  final bool wifiOn;
  final bool bluetoothOn;
  final bool muted;
  final void Function(String key) onWidget;
  final int notificationsUnread;

  const _Waybar({
    super.key,
    required this.player,
    required this.onPlayer,
    required this.onApps,
    required this.onBrightness,
    required this.onWifi,
    required this.onBluetooth,
    required this.onVolume,
    required this.rightItems,
    required this.wifiOn,
    required this.bluetoothOn,
    required this.muted,
    required this.onWidget,
    this.notificationsUnread = 0,
  });

  @override
  Widget build(BuildContext context) {
    final right = [
      for (final key in rightItems)
        if (key != 'brightness') key,
    ];
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
              // The four-squares button and the mini player are one centred
              // row. As a Positioned pair they overlapped once the bar
              // widened, and the button disappeared under the player.
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _WaybarButton(
                      key: const ValueKey('topbar-programs'),
                      icon: Icons.grid_view_rounded,
                      tooltip: Loc.t('Programs', 'Программы'),
                      onTap: onApps,
                    ),
                    const SizedBox(width: 8),
                    MiniPlayer(player: player, onOpen: onPlayer),
                  ],
                ),
              ),
              if (rightItems.contains('brightness'))
                Positioned(
                  left: 5,
                  top: 10,
                  child: _WaybarButton(
                    key: const ValueKey('topbar-brightness'),
                    icon: Icons.brightness_6,
                    tooltip: Loc.t('Brightness', 'Яркость'),
                    onTap: onBrightness,
                  ),
                ),
              Positioned(
                right: 5,
                top: 10,
                child: Row(
                  // Data-driven right side: the vibe-bar pane's list decides
                  // what sits here. Brightness is painted on the left, so it
                  // is filtered from this row (and its index math). Gaps only
                  // between buttons, so the last one lands exactly on the
                  // morph anchor from ShellLayout.
                  children: [
                    for (var i = 0; i < right.length; i++) ...[
                      _rightButton(right[i]),
                      if (i < right.length - 1) const SizedBox(width: 4),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rightButton(String key) {
    switch (key) {
      case 'bluetooth':
        return _WaybarButton(
          key: const ValueKey('topbar-bluetooth'),
          icon: Icons.bluetooth,
          tooltip: Loc.t('Bluetooth', 'Блютус'),
          active: bluetoothOn,
          onTap: onBluetooth,
        );
      case 'sound':
        return _WaybarButton(
          key: const ValueKey('topbar-volume'),
          icon: muted ? Icons.volume_off : Icons.volume_up,
          tooltip: Loc.t('Sound', 'Звук'),
          onTap: onVolume,
        );
      case 'wifi':
        return _WaybarButton(
          key: const ValueKey('topbar-wifi'),
          icon: Icons.wifi,
          tooltip: Loc.t('Wi-Fi', 'Wi-Fi'),
          active: wifiOn,
          onTap: onWifi,
        );
      default:
        // User-added waybar panels open their in-shell app.
        return _WaybarButton(
          key: ValueKey('topbar-$key'),
          icon: _waybarItemIcon(key, muted),
          tooltip: _waybarItemLabel(key),
          badge: key == 'notifications' ? notificationsUnread : 0,
          onTap: () => onWidget(key),
        );
    }
  }

  static IconData _waybarItemIcon(String key, bool muted) => switch (key) {
        'sound' => muted ? Icons.volume_off : Icons.volume_up,
        'wifi' => Icons.wifi,
        'bluetooth' => Icons.bluetooth,
        'clipboard' => Icons.content_paste_rounded,
        'emoji' => Icons.emoji_emotions_rounded,
        'updates' => Icons.system_update_rounded,
        'calendar' => Icons.calendar_today_rounded,
        'notifications' => Icons.notifications_none_rounded,
        _ => Icons.extension_rounded,
      };

  static String _waybarItemLabel(String key) => switch (key) {
        'sound' => Loc.t('Sound', 'Звук'),
        'wifi' => Loc.t('Wi-Fi', 'Wi-Fi'),
        'bluetooth' => Loc.t('Bluetooth', 'Блютус'),
        'clipboard' => Loc.t('Clipboard', 'Буфер обмена'),
        'emoji' => Loc.t('Emoji', 'Эмодзи'),
        'updates' => Loc.t('Updates', 'Обновления'),
        'calendar' => Loc.t('Calendar', 'Календарь'),
        'notifications' => Loc.t('Notifications', 'Уведомления'),
        _ => key,
      };
}

class _WaybarButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final int badge;

  const _WaybarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = true,
    this.badge = 0,
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  widget.icon,
                  color: widget.active ? Colors.white : Colors.white38,
                  size: 20,
                ),
                if (widget.badge > 0)
                  Positioned(
                    right: 5,
                    top: 6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 13),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8AB4F8),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        widget.badge > 9 ? '9+' : '${widget.badge}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
     );
  }
}

// ---- wi-fi flyout pieces ------------------------------------------------------

/// Signal quality as four bars. A two-bar network shows two bars — the rest
/// are simply absent, not dimmed, exactly as asked.
class _WifiBars extends StatelessWidget {
  final int signal;
  final Color color;

  const _WifiBars({required this.signal, required this.color});

  int get level {
    if (signal >= 78) return 4;
    if (signal >= 55) return 3;
    if (signal >= 30) return 2;
    if (signal >= 10) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 19,
      height: 15,
      child: CustomPaint(
        painter: _WifiBarsPainter(level: level, color: color),
      ),
    );
  }
}

class _WifiBarsPainter extends CustomPainter {
  final int level;
  final Color color;

  const _WifiBarsPainter({required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const widths = 3.0;
    const gap = 2.2;
    for (var i = 0; i < 4; i++) {
      if (i >= level) continue;
      final height = 4.0 + i * 3.2;
      final left = i * (widths + gap);
      final bottom = size.height;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, bottom - height, widths, height),
        const Radius.circular(1.4),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WifiBarsPainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.color != color;
}

/// A tiny icon for a mixer row, guessed from the exe name.
IconData _audioAppIcon(String exe) {
  if (exe.contains('chrome') ||
      exe.contains('msedge') ||
      exe.contains('firefox') ||
      exe.contains('opera')) {
    return Icons.public_rounded;
  }
  if (exe.contains('spotify') || exe.contains('music')) {
    return Icons.music_note_rounded;
  }
  if (exe.contains('discord') || exe.contains('telegram') ||
      exe.contains('teams')) {
    return Icons.chat_bubble_rounded;
  }
  if (exe.contains('steam') || exe.contains('game')) {
    return Icons.sports_esports_rounded;
  }
  return Icons.app_shortcut_rounded;
}

/// One network row: [bars] [ssid] [lock]; expanded, the connect card slides
/// out underneath — a password field + the auto-join checkbox for new
/// networks, 'Подключено' + 'Отключить' for the pinned one.
class _WifiRow extends StatelessWidget {
  final WifiNetwork network;
  final bool expanded;
  final bool busy;
  final bool autoJoin;
  final TextEditingController passwordController;
  final VoidCallback onToggle;
  final ValueChanged<bool> onAutoChanged;
  final VoidCallback onConnect;
  final VoidCallback onConnectOpen;
  final VoidCallback onDisconnect;

  const _WifiRow({
    super.key,
    required this.network,
    required this.expanded,
    required this.busy,
    required this.autoJoin,
    required this.passwordController,
    required this.onToggle,
    required this.onAutoChanged,
    required this.onConnect,
    required this.onConnectOpen,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final net = network;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The whole row is the expander. It was wired to a callback that
        // nothing called, so tapping a network did nothing at all.
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey('wifi-row-${net.ssid}'),
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  _WifiBars(
                    signal: net.signal,
                    color: net.connected ? Colors.white : Colors.white70,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      net.ssid,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight:
                            net.connected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (net.connected)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: Text(
                        Loc.t('Connected', 'Подключено'),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                    ),
                  Icon(
                    net.secure
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    size: 13,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
        ),
        // The expandable card under the row.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: expanded ? _card() : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _card() {
    final net = network;
    Widget content;
    if (net.connected) {
      // The pinned network: joined on Windows, so it stays joined here. The
      // card is vertical: the flyout is only 360 px wide and the checkbox
      // label plus a button on one line overflowed it.
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Loc.t('Connected, pinned', 'Подключено, закреплено'),
            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
          ),
          const SizedBox(height: 6),
          _checkRow(autoJoin, onAutoChanged),
          const SizedBox(height: 8),
          _cardButton(
            Loc.t('Disconnect', 'Отключить'),
            onTap: onDisconnect,
            danger: true,
          ),
        ],
      );
    } else if (!net.secure) {
      // Open network: no password ever needed.
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _checkRow(autoJoin, onAutoChanged),
          const SizedBox(height: 8),
          _cardButton(
            Loc.t('Connect', 'Подключиться'),
            onTap: onConnectOpen,
          ),
        ],
      );
    } else {
      // Password network: the input expands right below the row.
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: passwordController,
            obscureText: true,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            onSubmitted: (_) => onConnect(),
            decoration: InputDecoration(
              isDense: true,
              hintText: Loc.t('Enter password', 'Введите пароль'),
              hintStyle:
                  const TextStyle(color: Colors.white38, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 8),
          _checkRow(autoJoin, onAutoChanged),
          const SizedBox(height: 8),
          if (busy)
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white70),
                ),
              ),
            )
          else
            _cardButton(
              Loc.t('Connect', 'Подключиться'),
              onTap: onConnect,
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 4, 10),
      child: content,
    );
  }

  Widget _cardButton(
    String label, {
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: danger ? 0.10 : 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: danger ? Colors.white70 : Colors.white,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  /// The auto-join checkbox, drawn in-shell so it matches the glass panels.
  static Widget _checkRow(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              color: value
                  ? Colors.white.withValues(alpha: 0.85)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color:
                      Colors.white.withValues(alpha: value ? 0.85 : 0.4)),
            ),
            child: value
                ? const Icon(Icons.check_rounded,
                    size: 11, color: Colors.black87)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              Loc.t(
                'Connect automatically',
                'Подключаться автоматически',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// One running window in the dock: click to focus, click again to minimize.
/// The dock's running-window strip.
///
/// Stable order (creation, not z-order), and every icon arrives and leaves
/// with its own little spring instead of popping in on the frame a window
/// opens. A leaving icon stays in the list until its fade finishes.
class _DockTasks extends StatefulWidget {
  final List<AppWindow> windows;
  final int? activeId;
  final ValueChanged<AppWindow> onTap;

  const _DockTasks({
    required this.windows,
    required this.activeId,
    required this.onTap,
  });

  @override
  State<_DockTasks> createState() => _DockTasksState();
}

class _DockTasksState extends State<_DockTasks> {
  final List<AppWindow> _shown = [];
  final Set<int> _leaving = {};

  static List<AppWindow> _sorted(List<AppWindow> windows) =>
      List<AppWindow>.from(windows)..sort((a, b) => a.id.compareTo(b.id));

  @override
  void initState() {
    super.initState();
    _shown.addAll(_sorted(widget.windows));
  }

  @override
  void didUpdateWidget(covariant _DockTasks oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _sorted(widget.windows);
    final currentIds = current.map((w) => w.id).toSet();

    // A window that came back (restored) stops leaving.
    for (final id in currentIds) {
      _leaving.remove(id);
    }

    // A window that closed fades out first; the list drops it after the fade.
    for (final window in _shown) {
      if (currentIds.contains(window.id) || _leaving.contains(window.id)) {
        continue;
      }
      _leaving.add(window.id);
      // One dock-fade is 240 ms; the timer that drops the row waits a bit
      // over that, so a window never vanishes before its fade ends.
      Timer(const Duration(milliseconds: 260), () {
        if (!mounted) return;
        setState(() {
          _shown.removeWhere((w) => w.id == window.id);
          _leaving.remove(window.id);
        });
      });
    }

    final leaving = _shown.where((w) => !currentIds.contains(w.id)).toList();
    _shown
      ..clear()
      ..addAll(current)
      ..addAll(leaving);
  }

  @override
  Widget build(BuildContext context) {
    if (_shown.isEmpty) return const SizedBox(width: 44);
    return Column(
      children: [
        for (final window in _shown)
          _DockTask(
            key: ValueKey(
              window.appId == 'settings'
                  ? 'dock-settings'
                  : 'dock-app-${window.appId}',
            ),
            icon: iconForApp(window.app),
            accent: accentForApp(window.app),
            active: widget.activeId == window.id && !window.minimized,
            minimized: window.minimized,
            leaving: _leaving.contains(window.id),
            onTap: () => widget.onTap(window),
          ),
      ],
    );
  }
}

/// One running window in the dock: click to focus, click again to minimize.
class _DockTask extends StatefulWidget {
  final IconData icon;
  final Color accent;
  final bool active;
  final bool minimized;
  final bool leaving;
  final VoidCallback onTap;

  const _DockTask({
    super.key,
    required this.icon,
    required this.accent,
    required this.active,
    required this.minimized,
    required this.leaving,
    required this.onTap,
  });

  @override
  State<_DockTask> createState() => _DockTaskState();
}

class _DockTaskState extends State<_DockTask>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 190),
  )..forward();

  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  late final CurvedAnimation _pop = CurvedAnimation(
    parent: _reveal,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0.55, 0),
    end: Offset.zero,
  ).animate(_fade);

  bool _hovered = false;

  @override
  void didUpdateWidget(covariant _DockTask oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leaving == oldWidget.leaving) return;
    if (widget.leaving) {
      _reveal.reverse();
    } else {
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _pop.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.55, end: 1.0).animate(_pop),
          child: _content(),
        ),
      ),
    );
  }

  Widget _content() {
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
            color: widget.minimized
                ? Colors.transparent
                : widget.active
                    ? widget.accent.withValues(alpha: 0.18)
                    : (_hovered
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.transparent),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                widget.icon,
                // Bigger running-app icons in the dock: more visible at a
                // glance, the hit area is unchanged.
                size: 24,
                color: widget.minimized
                    ? Colors.white38
                    : (widget.active ? widget.accent : Colors.white70),
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
            child: Icon(
              widget.icon,
              color: Colors.white,
              size: 26 * ExpaTheme.configOf(context).dockIconScale,
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of the power dropdown: icon + label, whole row is the button.
/// Rows start as bare text: only hovering lights a soft white background —
/// there is no pressed effect and no outline around the rows.
class _PowerMenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PowerMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_PowerMenuItem> createState() => _PowerMenuItemState();
}

class _PowerMenuItemState extends State<_PowerMenuItem> {
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
          duration: const Duration(milliseconds: 130),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          // No border and no pressed state by request: the hover tint is the
          // only feedback a row gives.
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _isHovered ? 0.12 : 0.0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: Colors.white, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
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

/// One launcher tile: icon over a short label.
class _LauncherTile extends StatefulWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final VoidCallback onTap;

  const _LauncherTile({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.onTap,
  });

  @override
  State<_LauncherTile> createState() => _LauncherTileState();
}

class _LauncherTileState extends State<_LauncherTile> {
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
        child: AnimatedScale(
          scale: _hovered ? 1.06 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            width: 84,
            height: 62,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: widget.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.accent.withValues(
                          alpha: _hovered ? 0.65 : 0.30),
                    ),
                  ),
                  child: Icon(widget.icon, color: widget.accent, size: 19),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _hovered ? Colors.white : Colors.white70,
                    fontSize: 8.8,
                    height: 1.1,
                  ),
                ),
              ],
            ),
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
              label: Loc.t('Settings', 'Настройки'),
              onTap: onSettings,
            ),
          ),
          Expanded(
            child: _LauncherAction(
              key: const ValueKey('launcher-power'),
              icon: Icons.power_settings_new,
              label: Loc.t('Power', 'Питание'),
              onTap: onPower,
            ),
          ),
          Expanded(
            child: _LauncherAction(
              key: const ValueKey('launcher-terminal'),
              icon: Icons.terminal_outlined,
              label: Loc.t('Terminal', 'Терминал'),
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
/// The real-programs panel: a dark glass card with the machine's Start-menu.
/// The search row filters as the user types; a row launches its app through
/// explorer.exe and closes the panel.
class _AppsPanel extends StatefulWidget {
  /// What Get-StartApps returned (empty while the background scan runs).
  final List<WindowsAppEntry> windowsApps;
  final TextEditingController search;
  final FocusNode focus;
  final ValueChanged<WindowsAppEntry> onLaunch;

  const _AppsPanel({
    required this.windowsApps,
    required this.search,
    required this.focus,
    required this.onLaunch,
  });

  @override
  State<_AppsPanel> createState() => _AppsPanelState();
}

class _AppsPanelState extends State<_AppsPanel> {
  @override
  void initState() {
    super.initState();
    // Typing filters the list; the shell itself must not rebuild for that.
    widget.search.addListener(_onSearch);
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // The controller is owned by the shell; just stop listening.
    widget.search.removeListener(_onSearch);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.search.text.trim().toLowerCase();
    final rows = widget.windowsApps
        .where((a) => a.name.toLowerCase().contains(query))
        .toList();
    return Padding(
      key: const ValueKey('apps-panel'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The search row: type and the list narrows under your fingers.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.white54, size: 17),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    key: const ValueKey('apps-search'),
                    controller: widget.search,
                    focusNode: widget.focus,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: Loc.t('Search apps', 'Поиск приложений'),
                      hintStyle: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                if (widget.search.text.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      widget.search.clear();
                      _appsFocusBack();
                    },
                    child: const Icon(Icons.close, color: Colors.white38, size: 15),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      // Empty while the background Start-menu scan runs; the
                      // "nothing found" line answers a filtered search.
                      widget.windowsApps.isEmpty
                          ? Loc.t('Reading the Start menu...', 'Читаю меню Пуск...')
                          : Loc.t('Nothing found', 'Ничего не найдено'),
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : ListView(
                    key: const ValueKey('apps-list'),
                    children: [
                      for (final app in rows)
                        _AppsRow(entry: app, onTap: () => widget.onLaunch(app)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// The clear "x" only clears the text; keeping focus lets the user keep
  /// typing right after.
  void _appsFocusBack() {
    setState(() {});
    widget.focus.requestFocus();
  }
}

/// One installed app in the programs panel: icon on the left, name above the
/// category subtitle.
class _AppsRow extends StatefulWidget {
  final WindowsAppEntry entry;
  final VoidCallback onTap;

  const _AppsRow({required this.entry, required this.onTap});

  @override
  State<_AppsRow> createState() => _AppsRowState();
}

class _AppsRowState extends State<_AppsRow> {
  bool _hovered = false;

  IconData get _icon => switch (widget.entry.description) {
        'browser' => Icons.public_rounded,
        'game' => Icons.sports_esports_rounded,
        _ => Icons.apps_rounded,
      };

  String get _subtitle => Loc.t(switch (widget.entry.description) {
        'browser' => 'Browser',
        'game' => 'Game',
        _ => 'Application',
      }, switch (widget.entry.description) {
        'browser' => 'Браузер',
        'game' => 'Игра',
        _ => 'Приложение',
      });

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
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hovered ? 0.10 : 0.0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(_icon, color: Colors.white70, size: 17),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
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
