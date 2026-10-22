// The Settings window's content.
//
// Two panes: the shell's categories on the left, one detail sheet on the
// right. The window chrome, entrance and drag belong to [ShellWindow]; this
// file owns only the list and the panes.
//
// No dead rows: every control either changes something or opens the Windows
// page that owns it.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio_sessions.dart';
import '../../expa/de_config.dart';
import '../../expa/default_apps.dart';
import 'dart:io' show Platform;

import '../../expa/drives.dart';
import '../../expa/input_settings.dart';
import '../../expa/notifications.dart';
import '../../expa/waybar_catalog.dart';
import '../../i18n.dart';
import '../../liquid_glass/wave_slider.dart';
import '../../native/sysctl.dart';
import '../../radio_control.dart';
import '../../sound_control.dart';
import '../../ui/glass.dart';

/// The display parameters the shell owns, plus the callbacks that apply them.
class DisplaySettings {
  final double brightness;
  final double contrast;
  final double warmth;
  final ValueChanged<double> onBrightness;
  final ValueChanged<double> onContrast;
  final ValueChanged<double> onWarmth;

  const DisplaySettings({
    required this.brightness,
    required this.contrast,
    required this.warmth,
    required this.onBrightness,
    required this.onContrast,
    required this.onWarmth,
  });
}

/// Which section the settings should show, so the waybar's Wi-Fi button can
/// send an already-open window to the Wi-Fi pane.
class SettingsNavigator extends ChangeNotifier {
  String? _section;

  String? get section => _section;

  void show(String? section) {
    if (_section == section) return;
    _section = section;
    notifyListeners();
  }
}

/// One row of the settings list.
class SettingsItem {
  final String id;
  final IconData icon;
  final String label;
  final String section;
  const SettingsItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.section,
  });
}

class _SettingsSection {
  final String title;
  final List<SettingsItem> items;

  const _SettingsSection(this.title, this.items);
}

/// The regions the Date & time pane offers. Windows' own locale ids are far
/// too many for a dropdown; these are the common ones, and the choice is
/// saved for the shell's date formatting.
const List<(String, String)> regions = [
  ('ru-RU', 'Россия — ru-RU'),
  ('en-US', 'United States — en-US'),
  ('en-GB', 'United Kingdom — en-GB'),
  ('de-DE', 'Deutschland — de-DE'),
  ('fr-FR', 'France — fr-FR'),
  ('es-ES', 'España — es-ES'),
  ('it-IT', 'Italia — it-IT'),
  ('pt-BR', 'Brasil — pt-BR'),
  ('pl-PL', 'Polska — pl-PL'),
  ('uk-UA', 'Україна — uk-UA'),
  ('tr-TR', 'Türkiye — tr-TR'),
  ('ja-JP', '日本 — ja-JP'),
  ('zh-CN', '中国 — zh-CN'),
  ('ko-KR', '한국 — ko-KR'),
];

class SettingsView extends StatefulWidget {
  final SettingsNavigator navigator;
  final RadioSource? radio;
  final SoundSource? sound;
  final DisplaySettings display;

  /// The wallpapers the shell has, its current one, and what to do when a
  /// thumbnail is clicked.
  final List<String> wallpapers;
  final int activeWallpaper;
  final ValueChanged<int>? onWallpaper;

  /// Wallpaper timer, owned by the Wallpaper & theme sheet.
  final bool slideshowOn;
  final int slideshowPeriod;
  final void Function(bool on, int period)? onSlideshow;

  /// The Vibe bar editor's current keys.
  final List<String> waybarItems;
  final ValueChanged<List<String>>? onWaybarItems;

  /// Date & time: the clock's zone and the region.
  final String tzZone;
  final bool tzAuto;
  final String region;
  final void Function(String zone, {required bool auto})? onTimezone;
  final ValueChanged<String>? onRegion;

  /// Display dropdowns (persisted by the shell, applied there too).
  final String displayRes;
  final String displayOrient;
  final String displayHz;
  final ValueChanged<String>? onDisplayRes;
  final ValueChanged<String>? onDisplayOrient;
  final ValueChanged<String>? onDisplayHz;

  /// Opens the in-shell Updater window (Settings → Updates).
  final VoidCallback? onOpenUpdater;

  /// EXPA customization. Every sheet edits this object and saves it through
  /// [onConfig]; the shell applies it immediately.
  final DeConfig config;
  final ValueChanged<DeConfig>? onConfig;

  /// The DE's file associations and notification center.
  final FileAssociations associations;
  final ValueChanged<FileAssociations>? onAssociations;
  final NotificationCenter? notifications;

  /// Locks the desktop right now (the shell shows the lock overlay).
  final VoidCallback? onLock;

  /// Opens a drive/folder in the Files window.
  final ValueChanged<String>? onOpenPath;

  /// The pointer/keyboard backend; the tests inject a recorder.
  final InputSource? inputSource;

  /// Test seam for the Drives pane.
  final List<DriveEntry>? drives;

  // Test seams: real values are loaded from the native backend when omitted.
  final DisplayState? displayState;
  final List<TimezoneRow>? timezones;
  final List<AudioAppSession>? audioSessions;

  const SettingsView({
    super.key,
    required this.navigator,
    required this.display,
    this.radio,
    this.sound,
    this.wallpapers = const [],
    this.activeWallpaper = 0,
    this.onWallpaper,
    this.slideshowOn = true,
    this.slideshowPeriod = 12,
    this.onSlideshow,
    this.waybarItems = const ['sound', 'bluetooth', 'wifi', 'brightness'],
    this.onWaybarItems,
    this.tzZone = '',
    this.tzAuto = false,
    this.region = 'ru-RU',
    this.onTimezone,
    this.onRegion,
    this.displayRes = 'auto',
    this.displayOrient = 'auto',
    this.displayHz = 'auto',
    this.onDisplayRes,
    this.onDisplayOrient,
    this.onDisplayHz,
    this.onOpenUpdater,
    this.config = DeConfig.defaults,
    this.onConfig,
    this.associations = FileAssociations.standard,
    this.onAssociations,
    this.notifications,
    this.onLock,
    this.onOpenPath,
    this.inputSource,
    this.drives,
    this.displayState,
    this.timezones,
    this.audioSessions,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  String? _selectedId;
  int _hoveredIndex = -1;

  /// null = the appearance tiles; 'wallpaper' / 'vibe' = one of their sheets.
  String? _appearanceDetail;

  final Map<RadioKind, RadioStatus> _radio = {
    RadioKind.wifi:
        const RadioStatus(kind: RadioKind.wifi, state: RadioState.unknown),
    RadioKind.bluetooth: const RadioStatus(
        kind: RadioKind.bluetooth, state: RadioState.unknown),
  };
  bool _radioBusy = false;

  List<AudioAppSession> _sessions = const [];
  bool _sessionsLoaded = false;
  Timer? _sessionPoll;

  List<TimezoneRow> _timezones = const [];
  bool _loadingTimezones = false;

  DisplayState _displayState = DisplayState.empty;
  late DeConfig _draft;
  late InputSettings _input;
  List<DriveEntry> _drives = const [];
  late final TextEditingController _pinController;

  late final TextEditingController _periodController;

  // The left column. A function, not a const table: the titles follow the
  // shell language, while the ids/sections stay stable for tests.
  static List<_SettingsSection> _sections() => [
        _SettingsSection(Loc.t('Input & output', 'Ввод и вывод'), [
          SettingsItem(
            id: 'sound',
            icon: Icons.speaker,
            label: Loc.t('Sound', 'Звук'),
            section: 'sound',
          ),
          SettingsItem(
            id: 'display',
            icon: Icons.monitor,
            label: Loc.t('Display & monitor', 'Дисплей и монитор'),
            section: 'display',
          ),
          SettingsItem(
            id: 'mouse',
            icon: Icons.mouse,
            label: Loc.t('Mouse & touchpad', 'Мышь и сенсорная панель'),
            section: 'pointer',
          ),
          SettingsItem(
            id: 'keyboard',
            icon: Icons.keyboard,
            label: Loc.t('Keyboard', 'Клавиатура'),
            section: 'keyboard',
          ),
          SettingsItem(
            id: 'accessibility',
            icon: Icons.accessibility,
            label: Loc.t('Accessibility', 'Специальные возможности'),
            section: 'accessibility',
          ),
        ]),
        _SettingsSection(Loc.t('Connected devices', 'Подключённые устройства'),
            [
              SettingsItem(
                id: 'bluetooth',
                icon: Icons.bluetooth,
                label: Loc.t('Bluetooth', 'Блютус'),
                section: 'bluetooth',
              ),
              SettingsItem(
                id: 'devices',
                icon: Icons.storage_rounded,
                label: Loc.t('Drives & storage', 'Диски и хранилище'),
                section: 'drives',
              ),
            ]),
        _SettingsSection(Loc.t('Network & connectivity', 'Сеть'), [
          SettingsItem(
            id: 'wifi',
            icon: Icons.wifi,
            label: Loc.t('Wi-Fi & internet', 'Wi-Fi и интернет'),
            section: 'wifi',
          ),
        ]),
        _SettingsSection(Loc.t('Appearance', 'Оформление'), [
          SettingsItem(
            id: 'appearance',
            icon: Icons.palette,
            label: Loc.t('Appearance', 'Внешний вид'),
            section: 'appearance',
          ),
        ]),
        _SettingsSection(Loc.t('Apps & windows', 'Приложения и окна'), [
          SettingsItem(
            id: 'defaultapps',
            icon: Icons.apps,
            label: Loc.t('Default apps', 'Приложения по умолчанию'),
            section: 'associations',
          ),
          SettingsItem(
            id: 'notifications',
            icon: Icons.notifications,
            label: Loc.t('Notifications', 'Уведомления'),
            section: 'notifications',
          ),
          SettingsItem(
            id: 'multitasking',
            icon: Icons.window,
            label: Loc.t('Multitasking & windows', 'Многозадачность и окна'),
            section: 'multitasking',
          ),
        ]),
        _SettingsSection(Loc.t('Lock screen', 'Экран блокировки'), [
          SettingsItem(
            id: 'lockscreen',
            icon: Icons.lock,
            label: Loc.t('Lock screen & PIN', 'Экран блокировки и PIN'),
            section: 'lock',
          ),
        ]),
        _SettingsSection(Loc.t('Language & time', 'Язык и время'), [
          SettingsItem(
            id: 'datetime',
            icon: Icons.calendar_today,
            label: Loc.t('Date & time', 'Дата и время'),
            section: 'datetime',
          ),
          SettingsItem(
            id: 'region',
            icon: Icons.language,
            label: Loc.t('Language & region', 'Язык и регион'),
            section: 'language',
          ),
        ]),
        _SettingsSection(Loc.t('Updates', 'Обновления'), [
          SettingsItem(
            id: 'updates',
            icon: Icons.system_update,
            label: Loc.t('Updates', 'Обновления'),
            section: 'updates',
          ),
        ]),
      ];

  @override
  void initState() {
    super.initState();
    widget.navigator.addListener(_onNavigator);
    _selectedId = _idForSection(widget.navigator.section);
    _sessions = widget.audioSessions ?? const [];
    _sessionsLoaded = widget.audioSessions != null;
    _displayState = widget.displayState ?? SysCtl.displayState();
    _draft = widget.config;
    _input = InputSettings(widget.inputSource ?? const NativeInputSource())
      ..load();
    _drives = widget.drives ?? const [];
    if (widget.drives == null) unawaited(_loadDrives());
    _pinController = TextEditingController(text: widget.config.lockPin);
    widget.notifications?.addListener(_onNotifications);
    _timezones = widget.timezones ?? const [];
    if (widget.timezones == null) unawaited(_loadTimezones());
    _periodController =
        TextEditingController(text: '${widget.slideshowPeriod}');
    _refreshIfRadio();
    if (_selectedSection == 'sound') _startSessionPoll();
  }

  @override
  void didUpdateWidget(covariant SettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigator != widget.navigator) {
      oldWidget.navigator.removeListener(_onNavigator);
      widget.navigator.addListener(_onNavigator);
    }
    if (widget.audioSessions != null &&
        oldWidget.audioSessions != widget.audioSessions) {
      setState(() => _sessions = widget.audioSessions!);
    }
    if (oldWidget.slideshowPeriod != widget.slideshowPeriod) {
      _periodController.text = '${widget.slideshowPeriod}';
    }
    if (oldWidget.displayState != widget.displayState &&
        widget.displayState != null) {
      _displayState = widget.displayState!;
    }
    if (oldWidget.config != widget.config) _draft = widget.config;
    if (oldWidget.notifications != widget.notifications) {
      oldWidget.notifications?.removeListener(_onNotifications);
      widget.notifications?.addListener(_onNotifications);
    }
  }

  @override
  void dispose() {
    widget.navigator.removeListener(_onNavigator);
    _sessionPoll?.cancel();
    _pinController.dispose();
    widget.notifications?.removeListener(_onNotifications);
    _periodController.dispose();
    super.dispose();
  }

  Future<void> _loadTimezones() async {
    if (_loadingTimezones) return;
    _loadingTimezones = true;
    final rows = await SysCtl.timezonesAsync();
    if (!mounted) return;
    setState(() {
      _timezones = rows;
      _loadingTimezones = false;
    });
  }

  Future<void> _refreshSessions() async {
    if (widget.audioSessions != null) return;
    final rows = await AudioSessions.instance.sessions();
    if (!mounted) return;
    setState(() {
      _sessions = rows;
      _sessionsLoaded = true;
    });
  }

  void _startSessionPoll() {
    unawaited(_refreshSessions());
    _sessionPoll?.cancel();
    _sessionPoll =
        Timer.periodic(const Duration(seconds: 3), (_) => _refreshSessions());
  }

  void _stopSessionPoll() {
    _sessionPoll?.cancel();
    _sessionPoll = null;
  }

  Future<void> _setSessionVolume(int pid, double value) async {
    setState(() {
      _sessions = [
        for (final session in _sessions)
          if (session.pid == pid) session..volume = value else session,
      ];
    });
    AudioSessions.instance.setVolume(pid, value);
  }

  Future<void> _setSessionMute(int pid, bool muted) async {
    setState(() {
      _sessions = [
        for (final session in _sessions)
          if (session.pid == pid) session..muted = muted else session,
      ];
    });
    AudioSessions.instance.setMute(pid, muted);
  }

  void _onNavigator() {
    final id = _idForSection(widget.navigator.section);
    if (id != null) {
      _select(_itemById(id)!);
    } else {
      setState(() => _selectedId = null);
    }
  }

  void _refreshIfRadio() {
    final section = _selectedSection;
    if (section == 'wifi' || section == 'bluetooth') {
      unawaited(_refreshRadios());
    }
  }

  Future<void> _refreshRadios() async {
    if (_radioBusy) return;
    _radioBusy = true;
    try {
      final source = _radioSource;
      final wifi = await source.status(RadioKind.wifi);
      final bluetooth = await source.status(RadioKind.bluetooth);
      if (!mounted) return;
      setState(() {
        _radio[RadioKind.wifi] = wifi;
        _radio[RadioKind.bluetooth] = bluetooth;
      });
    } finally {
      _radioBusy = false;
    }
  }

  Future<void> _toggleRadio(RadioKind kind, bool on) async {
    setState(() => _radioBusy = true);
    final result = await _radioSource.setPower(kind, on);
    if (!mounted) return;
    setState(() {
      _radioBusy = false;
      _radio[kind] = result.status;
    });
  }

  void _select(SettingsItem item) {
    setState(() {
      _selectedId = item.id;
      _appearanceDetail = null;
    });
    if (item.section == 'sound') {
      _startSessionPoll();
    } else {
      _stopSessionPoll();
    }
    _refreshIfRadio();
  }

  static SettingsItem? _itemById(String? id) {
    if (id == null) return null;
    for (final group in _sections()) {
      for (final item in group.items) {
        if (item.id == id) return item;
      }
    }
    return null;
  }

  static String? _idForSection(String? section) {
    if (section == null) return null;
    for (final group in _sections()) {
      for (final item in group.items) {
        if (item.section == section || item.id == section) return item.id;
      }
    }
    return null;
  }

  SettingsItem? get _selectedItem => _itemById(_selectedId);
  String? get _selectedSection => _selectedItem?.section;

  RadioSource get _radioSource => widget.radio ?? RadioControl.instance;
  SoundSource get _soundSource => widget.sound ?? SoundControl.instance;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: Loc.notifier,
      builder: (context, _, __) => LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          return SingleChildScrollView(
            child: SizedBox(
              width: constraints.maxWidth,
              height: height < 430 ? 430 : height,
              child: Row(
                children: [
                  SizedBox(width: 262, child: _nav()),
                  const SizedBox(width: 10),
                  Expanded(child: _detail()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _nav() {
    final widgets = <Widget>[];
    var itemIndex = 0;
    for (final section in _sections()) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
        child: Text(
          section.title,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ));
      for (final item in section.items) {
        final currentIndex = itemIndex++;
        final selected = _selectedId == item.id;
        widgets.add(MouseRegion(
          onEnter: (_) => setState(() => _hoveredIndex = currentIndex),
          onExit: (_) => setState(() => _hoveredIndex = -1),
          child: GestureDetector(
            key: ValueKey('settings-row-${item.id}'),
            onTap: () => _select(item),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.16)
                    : _hoveredIndex == currentIndex
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    color: selected ? Colors.white : Colors.white54,
                    size: 16,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (item.section == 'wifi' || item.section == 'bluetooth')
                    Icon(
                      _radioIsOn(item.section)
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: _radioIsOn(item.section)
                          ? Colors.white
                          : Colors.white24,
                      size: 13,
                    ),
                ],
              ),
            ),
          ),
        ));
      }
    }
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: ListView(
        key: const ValueKey('settings-nav'),
        padding: EdgeInsets.zero,
        children: widgets,
      ),
    );
  }

  bool _radioIsOn(String section) {
    if (section == 'wifi') return _radio[RadioKind.wifi]?.isOn ?? false;
    if (section == 'bluetooth') {
      return _radio[RadioKind.bluetooth]?.isOn ?? false;
    }
    return false;
  }

  Widget _detail() {
    final item = _selectedItem;
    if (item == null) {
      return GlassPanel(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded,
                  size: 34, color: Colors.white.withValues(alpha: 0.14)),
              const SizedBox(height: 10),
              Caption(
                  Loc.t('Select a section on the left', 'Выбери раздел слева')),
            ],
          ),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.02, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: GlassPanel(
        key: ValueKey<String>(item.id),
        padding: const EdgeInsets.all(20),
        child: switch (item.section) {
          'sound' => _soundPane(item),
          'wifi' => _radioPane(item, RadioKind.wifi),
          'bluetooth' => _radioPane(item, RadioKind.bluetooth),
          'display' => _displayPane(item),
          'pointer' => _pointerPane(item),
          'keyboard' => _keyboardPane(item),
          'accessibility' => _accessibilityPane(item),
          'drives' => _drivesPane(item),
          'associations' => _associationsPane(item),
          'notifications' => _notificationsPane(item),
          'multitasking' => _multitaskingPane(item),
          'lock' => _lockPane(item),
          'appearance' => _appearancePane(item),
          'datetime' => _dateTimePane(item),
          'updates' => _updatesPane(item),
          'language' when item.id == 'region' => _languagePane(item),
          _ => _paneTitle(item),
        },
      ),
    );
  }

  Future<void> _loadDrives() async {
    final drives = await loadDrives();
    if (!mounted) return;
    setState(() => _drives = drives);
  }

  void _onNotifications() {
    if (mounted) setState(() {});
  }

  Widget _paneTitle(SettingsItem item, {Widget? trailing}) {
    return Row(
      children: [
        Icon(item.icon, color: Colors.white, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

// ---- sound ----------------------------------------------------------------

  Widget _soundPane(SettingsItem item) {
    final sound = _soundSource;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 30,
                child: WaveSlider(
                  key: const ValueKey('settings-master-volume'),
                  value: sound.muted ? 0.0 : sound.volume,
                  onChanged: (value) {
                    setState(() {
                      sound.volume = value;
                      if (value > 0 && sound.muted) sound.muted = false;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              key: const ValueKey('settings-sound-mute'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => sound.muted = !sound.muted),
              child: Icon(
                sound.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 18,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
              child: Text(
                '${sound.percent}%',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 11.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // The short divider the user asked for between master and app rows.
        Container(
          width: 64,
          height: 1,
          color: Colors.white.withValues(alpha: 0.22),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              Loc.t('Applications', 'Приложения'),
              style: const TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
            const Spacer(),
            if (_sessionsLoaded)
              Text(
                '${_sessions.length}',
                style: const TextStyle(color: Colors.white38, fontSize: 10.5),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(child: _sessionsView()),
      ],
    );
  }

  Widget _sessionsView() {
    if (!_sessionsLoaded && _sessions.isEmpty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: Colors.white38,
          ),
        ),
      );
    }
    if (_sessions.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Caption(Loc.t(
          'No apps are playing right now',
          'Сейчас нет приложений со звуком',
        )),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _sessions.length,
      itemExtent: 44,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final name = session.exe.isEmpty
            ? Loc.t('App ${session.pid % 10000}',
                'Приложение ${session.pid % 10000}')
            : '${session.exe[0].toUpperCase()}${session.exe.substring(1)}';
        return Row(
          key: ValueKey('settings-audio-${session.pid}'),
          children: [
            Icon(
              _iconForExe(session.exe),
              size: 16,
              color: Colors.white60,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SizedBox(
                height: 26,
                child: WaveSlider(
                  value: session.muted ? 0.0 : session.volume,
                  onChanged: (value) =>
                      unawaited(_setSessionVolume(session.pid, value)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              key: ValueKey('settings-audio-mute-${session.pid}'),
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  unawaited(_setSessionMute(session.pid, !session.muted)),
              child: Icon(
                session.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 15,
                color: session.muted ? Colors.white30 : Colors.white60,
              ),
            ),
          ],
        );
      },
    );
  }

  static IconData _iconForExe(String exe) {
    if (exe.contains('chrome') ||
        exe.contains('msedge') ||
        exe.contains('firefox') ||
        exe.contains('opera')) {
      return Icons.public_rounded;
    }
    if (exe.contains('spotify') || exe.contains('music')) {
      return Icons.music_note_rounded;
    }
    if (exe.contains('discord') ||
        exe.contains('telegram') ||
        exe.contains('teams')) {
      return Icons.chat_bubble_rounded;
    }
    if (exe.contains('steam') || exe.contains('game')) {
      return Icons.sports_esports_rounded;
    }
    return Icons.app_shortcut_rounded;
  }

  // ---- radios ---------------------------------------------------------------

  Widget _radioPane(SettingsItem item, RadioKind kind) {
    final status =
        _radio[kind] ?? RadioStatus(kind: kind, state: RadioState.unknown);
    final wifi = kind == RadioKind.wifi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(wifi ? Icons.wifi : Icons.bluetooth,
                size: 17, color: Colors.white70),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status.label,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13.5)),
                  if (status.deviceName != null) Caption(status.deviceName!),
                ],
              ),
            ),
            GlassToggle(
              value: status.isOn,
              onChanged: (on) => unawaited(_toggleRadio(kind, on)),
            ),
          ],
        ),
        if (wifi) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.signal_wifi_4_bar,
                  size: 15, color: Colors.white38),
              const SizedBox(width: 8),
              Caption(status.connected
                  ? Loc.t('Network connected', 'Сеть подключена')
                  : Loc.t('Not connected', 'Не подключено')),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (status.state == RadioState.unavailable)
          Caption(Loc.t('No such device on this machine.',
              'На этом компьютере такого устройства нет.'))
        else if (!status.canToggle)
          Caption(Loc.t(
              'The system will not switch the radio. Turn it on in Windows Settings.',
              'Система не переключает радиомодуль. Включи его в настройках Windows.'))
        else
          Caption(Loc.t(
              'Switching goes through the Windows radio API: no UAC, no windows.',
              'Переключение идёт через API радиомодулей Windows: без UAC и окон.')),
        const Spacer(),
      ],
    );
  }

  // ---- display --------------------------------------------------------------

  Widget _displayPane(SettingsItem item) {
    final current = _displayState.current;
    final currentSize = current == null
        ? '—'
        : '${current.width} × ${current.height}';
    final resolutionOptions = <(String, String)>[
      (
        'auto',
        '${Loc.t('Automatic (recommended)', 'Автоматически (рекомендуется)')}'
            ' · $currentSize'
      ),
      for (final resolution in _displayState.resolutions)
        (
          '${resolution.width}x${resolution.height}',
          '${resolution.width} × ${resolution.height}'
        ),
    ];
    if (widget.displayRes != 'auto' &&
        !resolutionOptions.any((entry) => entry.$1 == widget.displayRes) &&
        RegExp(r'^\d+x\d+$').hasMatch(widget.displayRes)) {
      resolutionOptions.add((
        widget.displayRes,
        widget.displayRes.replaceAll('x', ' × '),
      ));
    }

    final orientationOptions = <(String, String)>[
      ('auto', Loc.t('Automatic', 'Автоматически')),
      ('0', Loc.t('Landscape', 'Альбомная')),
      ('1', Loc.t('Portrait', 'Портретная')),
      ('2', Loc.t('Landscape (flipped)', 'Альбомная (перевёрнутая)')),
      ('3', Loc.t('Portrait (flipped)', 'Портретная (перевёрнутая)')),
    ];
    final refreshOptions = <(String, String)>[
      (
        'auto',
        '${Loc.t('Automatic', 'Автоматически')}'
            '${current == null ? '' : ' · ${current.hz} Hz'}'
      ),
      for (final hz in _displayState.refreshRates) ('$hz', '$hz Hz'),
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paneTitle(item),
          const SizedBox(height: 16),
          _selectRow(
            key: const ValueKey('settings-display-res'),
            label: Loc.t('Display resolution', 'Разрешение дисплея'),
            value: _optionLabel(resolutionOptions, widget.displayRes),
            options: resolutionOptions,
            onChanged: widget.onDisplayRes,
          ),
          const SizedBox(height: 8),
          _selectRow(
            key: const ValueKey('settings-display-orient'),
            label: Loc.t('Display orientation', 'Ориентация дисплея'),
            value: _optionLabel(orientationOptions, widget.displayOrient),
            options: orientationOptions,
            onChanged: widget.onDisplayOrient,
          ),
          const SizedBox(height: 8),
          _selectRow(
            key: const ValueKey('settings-display-hz'),
            label: Loc.t('Refresh rate', 'Частота обновления'),
            value: _optionLabel(refreshOptions, widget.displayHz),
            options: refreshOptions,
            onChanged: widget.onDisplayHz,
          ),
          const SizedBox(height: 16),
          Container(
            width: 64,
            height: 1,
            color: Colors.white.withValues(alpha: 0.22),
          ),
          const SizedBox(height: 12),
          Text(
            Loc.t('Brightness & effects', 'Яркость и эффекты'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          DisplaySlider(
            label: Loc.t('Brightness', 'Яркость'),
            value: widget.display.brightness,
            onChanged: widget.display.onBrightness,
          ),
          const SizedBox(height: 10),
          DisplaySlider(
            label: Loc.t('Contrast', 'Контрастность'),
            value: widget.display.contrast,
            onChanged: widget.display.onContrast,
          ),
          const SizedBox(height: 10),
          DisplaySlider(
            label: Loc.t('Warmth', 'Теплота'),
            value: widget.display.warmth,
            onChanged: widget.display.onWarmth,
          ),
          const SizedBox(height: 10),
          Caption(Loc.t(
            'Brightness and contrast go through DDC/CI, warmth through the '
            'gamma ramp. Resolution, orientation and refresh rate are the '
            'modes Windows reports for this monitor.',
            'Яркость и контрастность идут через DDC/CI, теплота — через гамму. '
            'Разрешение, ориентация и частота — реальные режимы этого монитора.',
          )),
        ],
      ),
    );
  }

  String _optionLabel(List<(String, String)> options, String value) {
    for (final option in options) {
      if (option.$1 == value) return option.$2;
    }
    return options.isEmpty ? value : options.first.$2;
  }

  Widget _selectRow({
    required Key key,
    required String label,
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String>? onChanged,
  }) {
    return PopupMenuButton<String>(
      key: key,
      tooltip: '',
      enabled: options.isNotEmpty && onChanged != null,
      color: const Color(0xF01A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<String>(
            value: option.$1,
            child: Text(
              option.$2,
              style: TextStyle(
                color: option.$1 == value ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight:
                    option.$1 == value ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }

// ---- date & time ----------------------------------------------------------

  Widget _dateTimePane(SettingsItem item) {
    final zoneOptions = <(String, String)>[
      ('', Loc.t('Automatic (system)', 'Автоматически (система)')),
      for (final zone in _timezones) (zone.id, zone.name),
    ];
    var zoneValue = widget.tzAuto ? '' : widget.tzZone;
    if (zoneValue.isNotEmpty &&
        !zoneOptions.any((option) => option.$1 == zoneValue)) {
      zoneOptions.add((zoneValue, zoneValue));
    }
    final regionOptions = <(String, String)>[
      for (final region in regions) (region.$1, region.$2),
    ];
    if (!regionOptions.any((option) => option.$1 == widget.region)) {
      regionOptions.add((widget.region, widget.region));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 16),
        Text(
          Loc.t('Time zone', 'Часовой пояс'),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        _selectRow(
          key: const ValueKey('settings-tz-zone'),
          label: Loc.t('Time zone', 'Часовой пояс'),
          value: _optionLabel(zoneOptions, zoneValue),
          options: zoneOptions,
          onChanged: (value) =>
              widget.onTimezone?.call(value, auto: value.isEmpty),
        ),
        if (_loadingTimezones) ...[
          const SizedBox(height: 6),
          const LinearProgressIndicator(
            minHeight: 1.5,
            color: Colors.white38,
            backgroundColor: Colors.white10,
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                Loc.t('Set the time zone automatically',
                    'Определять часовой пояс автоматически'),
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 10),
            GlassToggle(
              key: const ValueKey('settings-tz-auto'),
              value: widget.tzAuto,
              onChanged: (on) =>
                  widget.onTimezone?.call(widget.tzZone, auto: on),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Caption(Loc.t(
          'The clock on the desktop follows the chosen zone. Automatic uses '
          "this machine's own Windows setting.",
          'Часы на рабочем столе идут по выбранному поясу. «Автоматически» — '
          'по настройке Windows этого компьютера.',
        )),
        const SizedBox(height: 14),
        Container(
          width: 64,
          height: 1,
          color: Colors.white.withValues(alpha: 0.22),
        ),
        const SizedBox(height: 12),
        Text(
          Loc.t('Region', 'Регион'),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        _selectRow(
          key: const ValueKey('settings-region'),
          label: Loc.t('Region', 'Регион'),
          value: _optionLabel(regionOptions, widget.region),
          options: regionOptions,
          onChanged: widget.onRegion,
        ),
        const SizedBox(height: 10),
        Caption(Loc.t(
          'Region formatting is saved with the shell. Windows keeps its own '
          'locale.',
          'Формат региона сохраняется в оболочке. У Windows свой язык.',
        )),
        const Spacer(),
      ],
    );
  }

  // ---- input ----------------------------------------------------------------

  Widget _pointerPane(SettingsItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 14),
        _inputSlider(
          label: Loc.t('Pointer speed', 'Скорость указателя'),
          value: ((_input.mouseSpeed - 1) / 19).clamp(0.0, 1.0),
          text: '${_input.mouseSpeed}',
          onChanged: (value) => setState(
              () => _input.mouseSpeed = (1 + value * 19).round().clamp(1, 20)),
          onEnd: () => _input.updateMouseSpeed(_input.mouseSpeed),
        ),
        const SizedBox(height: 8),
        _inputSlider(
          label: Loc.t('Scroll lines per notch', 'Строк на щелчок колеса'),
          value: ((_input.wheelLines - 1) / 19).clamp(0.0, 1.0),
          text: '${_input.wheelLines}',
          onChanged: (value) => setState(
              () => _input.wheelLines = (1 + value * 19).round().clamp(1, 20)),
          onEnd: () => _input.updateWheelLines(_input.wheelLines),
        ),
        const SizedBox(height: 8),
        _configToggle(
          key: const ValueKey('settings-mouse-swap'),
          label: Loc.t('Swap primary and secondary buttons',
              'Поменять основную и дополнительную кнопки'),
          hint: Loc.t('Left-handed layout', 'Раскладка для левой руки'),
          value: _input.mouseSwap,
          onChanged: (on) {
            setState(() => _input.updateMouseSwap(on));
          },
        ),
        const SizedBox(height: 8),
        Caption(Loc.t(
          'These are the system pointer settings, applied immediately.',
          'Это системные настройки указателя, применяются сразу.',
        )),
        const Spacer(),
      ],
    );
  }

  Widget _keyboardPane(SettingsItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 14),
        _inputSlider(
          label: Loc.t('Repeat delay', 'Задержка повтора'),
          value: (_input.keyDelay / 3).clamp(0.0, 1.0),
          text: _input.keyDelay == 0
              ? Loc.t('short', 'короткая')
              : _input.keyDelay >= 3
                  ? Loc.t('long', 'длинная')
                  : '${_input.keyDelay}',
          onChanged: (value) => setState(
              () => _input.keyDelay = (value * 3).round().clamp(0, 3)),
          onEnd: () => _input.updateKeyDelay(_input.keyDelay),
        ),
        const SizedBox(height: 8),
        _inputSlider(
          label: Loc.t('Repeat rate', 'Частота повтора'),
          value: (_input.keySpeed / 31).clamp(0.0, 1.0),
          text: '${_input.keySpeed}',
          onChanged: (value) => setState(
              () => _input.keySpeed = (value * 31).round().clamp(0, 31)),
          onEnd: () => _input.updateKeySpeed(_input.keySpeed),
        ),
        const SizedBox(height: 8),
        Caption(Loc.t(
          'The same repeat delay and rate Windows uses. No Settings page is '
          'opened.',
          'Те же задержка и частота повтора, что и в Windows. Страница '
          'настроек не открывается.',
        )),
        const Spacer(),
      ],
    );
  }

  Widget _inputSlider({
    required String label,
    required double value,
    required String text,
    required ValueChanged<double> onChanged,
    required VoidCallback onEnd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
        SizedBox(
          height: 30,
          child: WaveSlider(
            value: value,
            onChanged: onChanged,
            onChangeEnd: (_) => onEnd(),
          ),
        ),
      ],
    );
  }

  Widget _accessibilityPane(SettingsItem item) {
    final font = ((_draft.fontScale - 0.85) / 0.35).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 14),
        _configToggle(
          key: const ValueKey('settings-accessibility-animations'),
          label: Loc.t('Reduce motion', 'Меньше движения'),
          hint: Loc.t('Turn off window and panel animations',
              'Выключить анимации окон и панелей'),
          value: !_draft.animationsEnabled,
          onChanged: (reduce) =>
              _commitConfig(_draft.copyWith(animationsEnabled: !reduce)),
        ),
        const SizedBox(height: 8),
        _configSlider(
          key: const ValueKey('settings-accessibility-font'),
          label: Loc.t('Text scale', 'Масштаб текста'),
          value: font,
          text: '${(_draft.fontScale * 100).round()}%',
          onPreview: (value) => _previewConfig(
              _draft.copyWith(fontScale: 0.85 + value * 0.35)),
          onCommit: () => _commitConfig(_draft),
        ),
        const SizedBox(height: 8),
        Caption(Loc.t(
          'The shell scales its own text and motion. Windows keeps its own '
          'accessibility settings.',
          'Оболочка масштабирует свой текст и движение. У Windows свои '
          'настройки доступности.',
        )),
        const Spacer(),
      ],
    );
  }

  // ---- drives / associations / notifications / multitasking / lock ----------

  Widget _drivesPane(SettingsItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(
          item,
          trailing: PillButton(
            key: const ValueKey('settings-drives-refresh'),
            label: Loc.t('Refresh', 'Обновить'),
            icon: Icons.refresh_rounded,
            onTap: () => unawaited(_loadDrives()),
          ),
        ),
        const SizedBox(height: 12),
        if (_drives.isEmpty)
          Caption(Loc.t(
            'No drives were reported by the system.',
            'Система не сообщила о дисках.',
          ))
        else
          Expanded(
            child: ListView.builder(
              itemCount: _drives.length,
              itemBuilder: (context, index) {
                final drive = _drives[index];
                return Padding(
                  key: ValueKey('settings-drive-${drive.id}'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.storage_rounded,
                          size: 17, color: Colors.white60),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${drive.id}  ${drive.label}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12.5),
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: drive.usedFraction,
                                minHeight: 4,
                                color: const Color(0xFF8AB4F8),
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Caption(drive.sizeText, size: 9.5),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        key: ValueKey('settings-drive-open-${drive.id}'),
                        label: Loc.t('Open', 'Открыть'),
                        onTap: () => widget.onOpenPath
                            ?.call('${drive.id}${Platform.pathSeparator}'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _associationsPane(SettingsItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 6),
        Caption(Loc.t(
          'Double-clicking a file in Files opens the app chosen here. The '
          'mapping belongs to the desktop, not to Windows.',
          'Двойной клик по файлу в Файлах открывает выбранное приложение. '
          'Таблица принадлежит оболочке, а не Windows.',
        )),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: FileAssociations.editableExtensions.length,
            itemBuilder: (context, index) {
              final extension =
                  FileAssociations.editableExtensions[index];
              final app = widget.associations.byExtension[extension] ?? 'files';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  key: ValueKey('settings-assoc-$extension'),
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(
                        '.$extension',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PopupMenuButton<String>(
                        key: ValueKey('settings-assoc-app-$extension'),
                        tooltip: '',
                        color: const Color(0xF01A1A1A),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        onSelected: (value) => widget.onAssociations?.call(
                          widget.associations
                              .withAssociation(extension, value),
                        ),
                        itemBuilder: (context) => [
                          for (final appId
                              in FileAssociations.builtInApps)
                            PopupMenuItem<String>(
                              value: appId,
                              child: Text(
                                appId,
                                style: TextStyle(
                                  color: app == appId
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  app,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11.5),
                                ),
                              ),
                              const Icon(Icons.expand_more_rounded,
                                  size: 14, color: Colors.white38),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _notificationsPane(SettingsItem item) {
    final center = widget.notifications;
    final recent = center?.items.take(6).toList() ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 10),
        _configToggle(
          key: const ValueKey('settings-notifications-enabled'),
          label: Loc.t('Desktop notifications', 'Уведомления оболочки'),
          hint: Loc.t('Show a toast and keep the history',
              'Показывать тост и хранить историю'),
          value: _draft.notificationsEnabled,
          onChanged: (on) =>
              _commitConfig(_draft.copyWith(notificationsEnabled: on)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Caption(center == null
                ? ''
                : '${center.unread} ${Loc.t('unread', 'непрочитанных')}'),
            const Spacer(),
            if (center != null) ...[
              PillButton(
                key: const ValueKey('settings-notifications-read'),
                label: Loc.t('Read all', 'Прочитать'),
                onTap: center.markAllRead,
              ),
              const SizedBox(width: 6),
              PillButton(
                key: const ValueKey('settings-notifications-clear'),
                label: Loc.t('Clear', 'Очистить'),
                icon: Icons.delete_sweep_outlined,
                onTap: center.clear,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: recent.isEmpty
              ? Caption(Loc.t(
                  'No notifications yet. Adding a track or joining a network '
                  'will show up here.',
                  'Уведомлений пока нет. Добавление трека или подключение к '
                  'сети появятся здесь.',
                ))
              : ListView(
                  children: [
                    for (final entry in recent)
                      GestureDetector(
                        key: ValueKey(
                            'settings-notification-${entry.id}'),
                        onTap: () => center?.markRead(entry),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Icon(
                                entry.read
                                    ? Icons.circle_outlined
                                    : Icons.circle,
                                size: 8,
                                color: entry.read
                                    ? Colors.white24
                                    : const Color(0xFF8AB4F8),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(entry.title,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11.5)),
                                    Text(entry.body,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 10)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _multitaskingPane(SettingsItem item) {
    final gap = (_draft.snapGap / 20).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 10),
        _configToggle(
          key: const ValueKey('settings-snap'),
          label: Loc.t('Snap windows to edges', 'Прилипание окон к краям'),
          hint: Loc.t(
            'Drag to an edge or use Ctrl+Alt+arrows. The window manager '
            'tiles it.',
            'Перетащи к краю или используй Ctrl+Alt+стрелки — оконный '
            'менеджер разложит окно.',
          ),
          value: _draft.snapEnabled,
          onChanged: (on) =>
              _commitConfig(_draft.copyWith(snapEnabled: on)),
        ),
        const SizedBox(height: 8),
        _configSlider(
          key: const ValueKey('settings-snap-gap'),
          label: Loc.t('Gap between tiles', 'Зазор между плитками'),
          value: gap,
          text: '${_draft.snapGap.round()} px',
          enabled: _draft.snapEnabled,
          onPreview: (value) =>
              _previewConfig(_draft.copyWith(snapGap: value * 20)),
          onCommit: () => _commitConfig(_draft),
        ),
        const SizedBox(height: 8),
        _configToggle(
          key: const ValueKey('settings-multitask-animations'),
          label: Loc.t('Window animations', 'Анимации окон'),
          hint: Loc.t('Open, close and the genie', 'Открытие, закрытие и genie'),
          value: _draft.animationsEnabled,
          onChanged: (on) =>
              _commitConfig(_draft.copyWith(animationsEnabled: on)),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _lockPane(SettingsItem item) {
    final auto = (_draft.autoLockMinutes / 60).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 12),
        _configSlider(
          key: const ValueKey('settings-auto-lock'),
          label: Loc.t('Auto-lock after', 'Автоблокировка через'),
          value: auto,
          text: _draft.autoLockMinutes == 0
              ? Loc.t('off', 'выкл')
              : '${_draft.autoLockMinutes} ${Loc.t('min', 'мин')}',
          onPreview: (value) => _previewConfig(
              _draft.copyWith(autoLockMinutes: (value * 60).round())),
          onCommit: () => _commitConfig(_draft),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('settings-lock-pin'),
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: Loc.t('PIN (optional)', 'PIN (необязательно)'),
                  hintStyle:
                      const TextStyle(color: Colors.white38, fontSize: 11.5),
                ),
                onSubmitted: (_) => _savePin(),
              ),
            ),
            const SizedBox(width: 8),
            PillButton(
              key: const ValueKey('settings-lock-save-pin'),
              label: Loc.t('Save', 'Сохранить'),
              onTap: _savePin,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Caption(Loc.t(
                'The PIN unlocks this desktop. It is stored in prefs.cfg.',
                'PIN разблокирует этот рабочий стол. Хранится в prefs.cfg.',
              )),
            ),
            const SizedBox(width: 8),
            PillButton(
              key: const ValueKey('settings-lock-now'),
              label: Loc.t('Lock now', 'Заблокировать'),
              icon: Icons.lock_rounded,
              onTap: widget.onLock,
            ),
          ],
        ),
        const Spacer(),
      ],
    );
  }

  void _savePin() {
    final digits = _pinController.text.replaceAll(RegExp(r'[^0-9]'), '');
    _pinController.text = digits;
    _commitConfig(_draft.copyWith(lockPin: digits));
  }

  // ---- appearance -----------------------------------------------------------

  Widget _appearancePane(SettingsItem item) {
    final title = switch (_appearanceDetail) {
      'wallpaper' => Loc.t('Wallpaper & theme', 'Обои и тема'),
      'vibe' => Loc.t('Vibe bar', 'Вайбар'),
      'animations' => Loc.t('Animations & effects', 'Анимации и эффекты'),
      'colors' => Loc.t('Colors & accent', 'Цвета и акцент'),
      'window' => Loc.t('Window styling', 'Оформление окон'),
      'dock' => Loc.t('Dock & icons', 'Док и значки'),
      'desktop' => Loc.t('Desktop & clock', 'Рабочий стол и часы'),
      'behavior' => Loc.t('System & notifications', 'Система и уведомления'),
      _ => null,
    };
    if (title != null) {
      return _appearanceSheet(title: title, child: _appearanceSheetBody());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 6),
        Caption(Loc.t(
          'Choose a part of the shell to style. Every change is saved as you '
          'make it.',
          'Выбери часть оболочки. Каждое изменение сохраняется сразу.',
        )),
        const SizedBox(height: 14),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 460 ? 1 : 2;
              final width =
                  (constraints.maxWidth - 10 * (columns - 1)) / columns;
              final tiles = <(String, IconData, String, String)>[
                (
                  'wallpaper',
                  Icons.wallpaper_rounded,
                  Loc.t('Wallpaper & theme', 'Обои и тема'),
                  Loc.t('Pictures, timer', 'Картинки, таймер'),
                ),
                (
                  'vibe',
                  Icons.dock_rounded,
                  Loc.t('Vibe bar', 'Вайбар'),
                  Loc.t('Panels in the top bar', 'Панели в верхней полосе'),
                ),
                (
                  'animations',
                  Icons.animation_rounded,
                  Loc.t('Animations & effects', 'Анимации и эффекты'),
                  Loc.t('Speed, reduce motion', 'Скорость, меньше движения'),
                ),
                (
                  'colors',
                  Icons.palette_rounded,
                  Loc.t('Colors & accent', 'Цвета и акцент'),
                  Loc.t('Accent of the shell', 'Акцент оболочки'),
                ),
                (
                  'window',
                  Icons.web_asset_rounded,
                  Loc.t('Window styling', 'Оформление окон'),
                  Loc.t('Corner radius, borders', 'Скругление, рамки'),
                ),
                (
                  'dock',
                  Icons.view_sidebar_rounded,
                  Loc.t('Dock & icons', 'Док и значки'),
                  Loc.t('Icon size', 'Размер значков'),
                ),
                (
                  'desktop',
                  Icons.wb_sunny_rounded,
                  Loc.t('Desktop & clock', 'Рабочий стол и часы'),
                  Loc.t('Dim, seconds, text size', 'Затемнение, секунды, шрифт'),
                ),
                (
                  'behavior',
                  Icons.tune_rounded,
                  Loc.t('System & notifications', 'Система и уведомления'),
                  Loc.t('Snap, gaps, toasts', 'Прилипание, зазоры, уведомления'),
                ),
              ];
              return SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final tile in tiles)
                      _AppearanceTile(
                        key: ValueKey('appearance-tile-${tile.$1}'),
                        width: width,
                        icon: tile.$2,
                        label: tile.$3,
                        hint: tile.$4,
                        onTap: () =>
                            setState(() => _appearanceDetail = tile.$1),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _appearanceSheetBody() {
    return switch (_appearanceDetail) {
      'wallpaper' => _wallpaperSheet(),
      'vibe' => _vibeSheet(),
      'animations' => _animationsSheet(),
      'colors' => _colorsSheet(),
      'window' => _windowSheet(),
      'dock' => _dockSheet(),
      'desktop' => _desktopSheet(),
      'behavior' => _behaviorSheet(),
      _ => const SizedBox.shrink(),
    };
  }

  void _previewConfig(DeConfig next) {
    setState(() => _draft = next);
  }

  void _commitConfig(DeConfig next) {
    setState(() => _draft = next);
    widget.onConfig?.call(next);
  }

  Widget _configSlider({
    required Key key,
    required String label,
    required double value,
    required String text,
    required ValueChanged<double> onPreview,
    required VoidCallback onCommit,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
                const Spacer(),
                Text(text,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
            SizedBox(
              height: 30,
              child: WaveSlider(
                key: key,
                value: value,
                onChanged: onPreview,
                onChangeEnd: (_) => onCommit(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _configToggle({
    required Key key,
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12.5)),
                if (hint.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Caption(hint),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GlassToggle(key: key, value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _animationsSheet() {
    final speed = ((_draft.animationSpeed - 0.5) / 1.1).clamp(0.0, 1.0);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _configToggle(
            key: const ValueKey('customize-animations'),
            label: Loc.t('Animations', 'Анимации'),
            hint: Loc.t(
              'Window pops, the genie, panel morphs. Turning this off makes '
              'every action instant.',
              'Появление окон, genie, морфы панелей. Выключение делает всё '
              'мгновенным.',
            ),
            value: _draft.animationsEnabled,
            onChanged: (on) => _commitConfig(
              _draft.copyWith(animationsEnabled: on),
            ),
          ),
          const SizedBox(height: 8),
          _configSlider(
            key: const ValueKey('customize-animation-speed'),
            label: Loc.t('Animation speed', 'Скорость анимаций'),
            value: speed,
            text: '${(_draft.animationSpeed * 100).round()}%',
            enabled: _draft.animationsEnabled,
            onPreview: (value) => _previewConfig(
              _draft.copyWith(animationSpeed: 0.5 + value * 1.1),
            ),
            onCommit: () => _commitConfig(_draft),
          ),
          Caption(Loc.t(
            'Speed applies to window entrances, closes and the snap glide.',
            'Скорость влияет на появление, закрытие и скольжение окон.',
          )),
        ],
      ),
    );
  }

  Widget _colorsSheet() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Loc.t('Accent color', 'Акцентный цвет'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < DeConfig.accents.length; i++)
                GestureDetector(
                  key: ValueKey('customize-accent-$i'),
                  onTap: () =>
                      _commitConfig(_draft.copyWith(accentIndex: i)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Color(DeConfig.accents[i]),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _draft.accentIndex == i
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.16),
                        width: _draft.accentIndex == i ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Caption(Loc.t(
            'The accent marks the active window border and the selected rows.',
            'Акцент подсвечивает рамку активного окна и выбранные строки.',
          )),
        ],
      ),
    );
  }

  Widget _windowSheet() {
    final radius = ((_draft.windowRadius - 8) / 18).clamp(0.0, 1.0);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _configSlider(
            key: const ValueKey('customize-window-radius'),
            label: Loc.t('Corner radius', 'Скругление углов'),
            value: radius,
            text: '${_draft.windowRadius.round()} px',
            onPreview: (value) => _previewConfig(
              _draft.copyWith(windowRadius: 8 + value * 18),
            ),
            onCommit: () => _commitConfig(_draft),
          ),
          const SizedBox(height: 8),
          Caption(Loc.t(
            'The radius of every in-app window. Maximized windows keep the '
            'tight 10 px frame.',
            'Радиус каждого окна внутри оболочки. Развёрнутые окна оставляют '
            'узкие 10 px.',
          )),
        ],
      ),
    );
  }

  Widget _dockSheet() {
    final scale = ((_draft.dockIconScale - 0.8) / 0.6).clamp(0.0, 1.0);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _configSlider(
            key: const ValueKey('customize-dock-scale'),
            label: Loc.t('Dock icon size', 'Размер значков дока'),
            value: scale,
            text: '${(_draft.dockIconScale * 100).round()}%',
            onPreview: (value) => _previewConfig(
              _draft.copyWith(dockIconScale: 0.8 + value * 0.6),
            ),
            onCommit: () => _commitConfig(_draft),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Icon(Icons.widgets_rounded, size: 26, color: Colors.white54),
          ),
          Caption(Loc.t(
            'Running-app icons in the right dock.',
            'Значки запущенных приложений в правом доке.',
          )),
        ],
      ),
    );
  }

  Widget _desktopSheet() {
    final dim = (_draft.wallpaperDim / 0.65).clamp(0.0, 1.0);
    final font = ((_draft.fontScale - 0.85) / 0.35).clamp(0.0, 1.0);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _configSlider(
            key: const ValueKey('customize-wallpaper-dim'),
            label: Loc.t('Wallpaper dim', 'Затемнение обоев'),
            value: dim,
            text: '${(_draft.wallpaperDim * 100).round()}%',
            onPreview: (value) =>
                _previewConfig(_draft.copyWith(wallpaperDim: value * 0.65)),
            onCommit: () => _commitConfig(_draft),
          ),
          const SizedBox(height: 8),
          _configSlider(
            key: const ValueKey('customize-font-scale'),
            label: Loc.t('Text scale', 'Масштаб текста'),
            value: font,
            text: '${(_draft.fontScale * 100).round()}%',
            onPreview: (value) => _previewConfig(
              _draft.copyWith(fontScale: 0.85 + value * 0.35),
            ),
            onCommit: () => _commitConfig(_draft),
          ),
          const SizedBox(height: 8),
          _configToggle(
            key: const ValueKey('customize-clock-seconds'),
            label: Loc.t('Clock seconds', 'Секунды на часах'),
            hint: Loc.t('Show hh:mm:ss', 'Показывать чч:мм:сс'),
            value: _draft.clockSeconds,
            onChanged: (on) =>
                _commitConfig(_draft.copyWith(clockSeconds: on)),
          ),
        ],
      ),
    );
  }

  Widget _behaviorSheet() {
    final gap = (_draft.snapGap / 20).clamp(0.0, 1.0);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _configToggle(
            key: const ValueKey('customize-snap'),
            label: Loc.t('Snap windows to edges', 'Прилипание окон к краям'),
            hint: Loc.t(
              'Drag a window to a screen edge to tile it; Ctrl+Alt+arrows '
              'also snap.',
              'Перетащи окно к краю, чтобы разложить; Ctrl+Alt+стрелки тоже '
              'прилипают.',
            ),
            value: _draft.snapEnabled,
            onChanged: (on) =>
                _commitConfig(_draft.copyWith(snapEnabled: on)),
          ),
          _configSlider(
            key: const ValueKey('customize-snap-gap'),
            label: Loc.t('Gap between tiles', 'Зазор между плитками'),
            value: gap,
            text: '${_draft.snapGap.round()} px',
            enabled: _draft.snapEnabled,
            onPreview: (value) =>
                _previewConfig(_draft.copyWith(snapGap: value * 20)),
            onCommit: () => _commitConfig(_draft),
          ),
          const SizedBox(height: 8),
          _configToggle(
            key: const ValueKey('customize-notifications'),
            label: Loc.t('Desktop notifications', 'Уведомления оболочки'),
            hint: Loc.t(
              'Show a toast and keep history for music, network and updates.',
              'Показывать тост и хранить историю музыки, сети и обновлений.',
            ),
            value: _draft.notificationsEnabled,
            onChanged: (on) =>
                _commitConfig(_draft.copyWith(notificationsEnabled: on)),
          ),
        ],
      ),
    );
  }

  Widget _appearanceSheet({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('appearance-back'),
              onPressed: () => setState(() => _appearanceDetail = null),
              icon: const Icon(Icons.arrow_back_rounded,
                  size: 18, color: Colors.white70),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 30, minHeight: 30),
              tooltip: Loc.t('Back', 'Назад'),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: child),
      ],
    );
  }

  Widget _wallpaperSheet() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Caption(Loc.t(
            'Each desktop keeps its own wallpaper. Click a picture to set it '
            'for the desktop you are on.',
            'У каждого стола свои обои. Клик по картинке ставит её для того '
            'стола, на котором ты сейчас.',
          )),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < widget.wallpapers.length; i++)
                _WallpaperTile(
                  key: ValueKey('settings-wallpaper-$i'),
                  asset: widget.wallpapers[i],
                  selected: i == widget.activeWallpaper,
                  width: 148,
                  height: 92,
                  onTap: () => widget.onWallpaper?.call(i),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: 64,
            height: 1,
            color: Colors.white.withValues(alpha: 0.22),
          ),
          const SizedBox(height: 12),
          Text(
            Loc.t('Wallpaper timer', 'Таймер обоев'),
            style: const TextStyle(
                color: Colors.white, fontSize: 12.5,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  Loc.t('Change the wallpaper on a timer',
                      'Менять обои по таймеру'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              GlassToggle(
                key: const ValueKey('slideshow-switch'),
                value: widget.slideshowOn,
                onChanged: (on) {
                  final parsed = int.tryParse(_periodController.text.trim()) ??
                      widget.slideshowPeriod;
                  widget.onSlideshow
                      ?.call(on, parsed.clamp(5, 3600).toInt());
                },
              ),
            ],
          ),
          if (widget.slideshowOn) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  Loc.t('Change every', 'Менять каждые'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 74,
                  child: TextField(
                    key: const ValueKey('slideshow-period'),
                    controller: _periodController,
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _applyPeriod(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.07),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('sec',
                    style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                const SizedBox(width: 6),
                IconButton(
                  key: const ValueKey('slideshow-apply'),
                  onPressed: _applyPeriod,
                  icon: const Icon(Icons.check_rounded,
                      size: 17, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  tooltip: Loc.t('Apply', 'Применить'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Caption(Loc.t(
              '5 seconds minimum, 1 hour maximum.',
              'Минимум 5 секунд, максимум 1 час.',
            )),
          ],
        ],
      ),
    );
  }

  void _applyPeriod() {
    final parsed = int.tryParse(_periodController.text.trim());
    if (parsed == null) {
      _periodController.text = '${widget.slideshowPeriod}';
      return;
    }
    final period = parsed.clamp(5, 3600).toInt();
    _periodController.text = '$period';
    widget.onSlideshow?.call(widget.slideshowOn, period);
  }

  List<String> get _orderedWaybarItems => [
        for (final key in waybarKeys)
          if (widget.waybarItems.contains(key)) key,
        for (final key in widget.waybarItems)
          if (!waybarKeys.contains(key)) key,
      ];

  Widget _vibeSheet() {
    final current = _orderedWaybarItems;
    final addable = [
      for (final key in waybarKeys)
        if (!widget.waybarItems.contains(key)) key,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                Loc.t('Panels in the waybar', 'Панели в вайбаре'),
                style: const TextStyle(
                    color: Colors.white, fontSize: 12.5,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              key: const ValueKey('waybar-add'),
              tooltip: '',
              enabled: addable.isNotEmpty && widget.onWaybarItems != null,
              color: const Color(0xF01A1A1A),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              onSelected: (key) {
                widget.onWaybarItems
                    ?.call([...widget.waybarItems, key]);
              },
              itemBuilder: (context) => [
                for (final key in addable)
                  PopupMenuItem<String>(
                    value: key,
                    child: Row(
                      children: [
                        Icon(
                          waybarMeta[key]?.$2 ?? Icons.extension_rounded,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          waybarLabel(key),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
              ],
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.add_rounded,
                        size: 15, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      Loc.t('Add', 'Добавить'),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            key: const ValueKey('settings-waybar-list'),
            padding: EdgeInsets.zero,
            children: [
              for (final key in current) _waybarRow(key),
              if (addable.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Caption(Loc.t(
                    'Every panel is already on the bar.',
                    'Все панели уже на полосе.',
                  )),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Caption(Loc.t(
          'The bar widens when it needs room. Every panel opens its in-shell '
          'app: Clipboard, Emoji, Updater, Calendar or Notifications.',
          'Полоса расширяется, когда нужно место. Каждая панель открывает '
          'приложение внутри: буфер, эмодзи, обновления, календарь или '
          'уведомления.',
        )),
      ],
    );
  }

  Widget _waybarRow(String key) {
    final icon = waybarMeta[key]?.$2 ?? Icons.extension_rounded;
    return Padding(
      key: ValueKey('waybar-item-$key'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              waybarLabel(key),
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
          IconButton(
            key: ValueKey('waybar-remove-$key'),
            onPressed: widget.onWaybarItems == null
                ? null
                : () {
                    final next = [...widget.waybarItems]..remove(key);
                    widget.onWaybarItems?.call(next);
                  },
            icon: const Icon(Icons.delete_outline_rounded,
                size: 16, color: Colors.white54),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            tooltip: Loc.t('Remove from the bar', 'Убрать с полосы'),
          ),
        ],
      ),
    );
  }

  // ---- updates --------------------------------------------------------------

  Widget _updatesPane(SettingsItem item) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paneTitle(item),
          const SizedBox(height: 16),
          _updateCard(
            key: const ValueKey('updates-expa'),
            title: Loc.t('EXpaDesktop updates', 'Обновления EXpaDesktop'),
            caption: Loc.t(
              'Open the in-shell Updater: it compares this build with the '
              'latest GitHub release and main commit, shows both changelogs '
              'and can rebuild and restart the app.',
              'Открой встроенное обновление: оно сравнит эту сборку с '
              'последним релизом и коммитом main на GitHub, покажет изменения '
              'и сможет пересобрать и перезапустить приложение.',
            ),
            button: Loc.t('Open Updater', 'Открыть Updater'),
            onTap: () => widget.onOpenUpdater?.call(),
          ),
        ],
      ),
    );
  }

  Widget _updateCard({
    required Key key,
    required String title,
    required String caption,
    required String button,
    required VoidCallback onTap,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Caption(caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PillButton(label: button, onTap: onTap),
        ],
      ),
    );
  }

  Widget _languagePane(SettingsItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 18),
        const _LanguageDropdown(),
        const SizedBox(height: 14),
        Caption(Loc.t(
          'Only the shell is translated here: menus, panels, app labels. '
          'Windows keeps its own language.',
          'Здесь переводится только оболочка: меню, панели, подписи '
          'приложений. Windows остаётся на своём языке.',
        )),
        const Spacer(),
      ],
    );
  }
}

// ---- small widgets ---------------------------------------------------------

class _WallpaperTile extends StatefulWidget {
  final String asset;
  final bool selected;
  final VoidCallback onTap;
  final double width;
  final double height;

  const _WallpaperTile({
    super.key,
    required this.asset,
    required this.selected,
    required this.onTap,
    this.width = 148,
    this.height = 92,
  });

  @override
  State<_WallpaperTile> createState() => _WallpaperTileState();
}

class _WallpaperTileState extends State<_WallpaperTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: widget.selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: _hovered ? 0.4 : 0.12),
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  widget.asset,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (context, error, stack) =>
                      const ColoredBox(color: Color(0xFF232326)),
                ),
                if (widget.selected)
                  const Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(Icons.check_circle,
                          size: 15, color: Colors.white),
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

/// One large appearance tile. Deliberately no 3D tilt: the old matrix
/// perspective shimmered at the edges and made text blurry. A 1.5% lift and
/// a brighter border read as depth without touching the pixels.
class _AppearanceTile extends StatefulWidget {
  final double width;
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  const _AppearanceTile({
    super.key,
    required this.width,
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  @override
  State<_AppearanceTile> createState() => _AppearanceTileState();
}

class _AppearanceTileState extends State<_AppearanceTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.015 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: widget.width,
            height: 96,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _hovered ? 0.10 : 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: _hovered ? 0.22 : 0.10),
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled 0..1 slider for the display pane.
class DisplaySlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const DisplaySlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            Text('${(value * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 30,
          child: WaveSlider(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

/// A glass switch: a knob that slides inside a capsule.
class GlassToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const GlassToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 46,
          height: 26,
          padding: const EdgeInsets.all(3),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value
                ? Colors.white.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value ? Colors.black87 : Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

/// The language dropdown of the settings: English by default, Russian
/// optional. Clicking a row applies the language immediately (Loc.set also
/// saves it for the next start) and the whole shell rebuilds through
/// Loc.notifier.
class _LanguageDropdown extends StatefulWidget {
  const _LanguageDropdown();

  @override
  State<_LanguageDropdown> createState() => _LanguageDropdownState();
}

class _LanguageDropdownState extends State<_LanguageDropdown> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: Loc.notifier,
      builder: (context, _, __) {
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: PopupMenuButton<AppLanguage>(
            color: const Color(0xF01A1A1A),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (lang) => unawaited(Loc.set(lang)),
            itemBuilder: (context) => [
              for (final lang in AppLanguage.values)
                PopupMenuItem(
                  value: lang,
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      Text(
                        lang.display,
                        style: TextStyle(
                          color: Loc.language == lang
                              ? Colors.white
                              : Colors.white70,
                          fontSize: 13,
                          fontWeight: Loc.language == lang
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      const Spacer(),
                      if (Loc.language == lang)
                        const Icon(Icons.check, color: Colors.white, size: 15),
                    ],
                  ),
                ),
            ],
            child: AnimatedContainer(
              key: const ValueKey('settings-language'),
              duration: const Duration(milliseconds: 140),
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color:
                    Colors.white.withValues(alpha: _hovered ? 0.10 : 0.06),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.language, color: Colors.white70, size: 17),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      Loc.t('Language', 'Язык'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    Loc.language.display,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.expand_more,
                      color: Colors.white54, size: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}