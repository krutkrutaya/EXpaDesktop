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
import '../../i18n.dart';
import '../../liquid_glass/wave_slider.dart';
import '../../native/sysctl.dart';
import '../../radio_control.dart';
import '../../sound_control.dart';
import '../../system_actions.dart';
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
  final String? uri;

  /// True for a pane whose real control lives in Windows; the pane then ends
  /// with an "Open in Windows" button instead of pretending to own it.
  final bool native;

  const SettingsItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.section,
    this.uri,
    this.native = false,
  });
}

class _SettingsSection {
  final String title;
  final List<SettingsItem> items;

  const _SettingsSection(this.title, this.items);
}

/// The waybar keys the Vibe bar pane can manage, in the order it lists them.
const List<String> waybarKeys = [
  'sound',
  'bluetooth',
  'wifi',
  'brightness',
  'clipboard',
  'emoji',
  'updates',
  'calendar',
  'notifications',
];

const Map<String, (String, IconData)> waybarMeta = {
  'sound': ('Sound', Icons.volume_up_rounded),
  'bluetooth': ('Bluetooth', Icons.bluetooth_rounded),
  'wifi': ('Wi-Fi', Icons.wifi_rounded),
  'brightness': ('Brightness', Icons.brightness_6_rounded),
  'clipboard': ('Clipboard', Icons.content_paste_rounded),
  'emoji': ('Emoji', Icons.emoji_emotions_rounded),
  'updates': ('Updates', Icons.system_update_rounded),
  'calendar': ('Calendar', Icons.calendar_today_rounded),
  'notifications': ('Notifications', Icons.notifications_none_rounded),
};

const Map<String, (String, String, String)> waybarMetaRu = {
  'sound': ('Звук', 'Sound', 'Звук'),
  'bluetooth': ('Блютус', 'Bluetooth', 'Блютус'),
  'wifi': ('Сети', 'Wi-Fi', 'Сети'),
  'brightness': ('Яркость', 'Brightness', 'Яркость'),
  'clipboard': ('Буфер обмена', 'Clipboard', 'Буфер обмена'),
  'emoji': ('Эмодзи', 'Emoji', 'Эмодзи'),
  'updates': ('Обновления', 'Updates', 'Обновления'),
  'calendar': ('Календарь', 'Calendar', 'Календарь'),
  'notifications': ('Уведомления', 'Notifications', 'Уведомления'),
};

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

  /// Opens a URI: the updates pane's two buttons.
  final Future<void> Function(String uri)? onOpenUpdates;

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
    this.onOpenUpdates,
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
            section: 'input',
            uri: 'ms-settings:mousetouchpad',
            native: true,
          ),
          SettingsItem(
            id: 'keyboard',
            icon: Icons.keyboard,
            label: Loc.t('Keyboard', 'Клавиатура'),
            section: 'input',
            uri: 'ms-settings:typing',
            native: true,
          ),
          SettingsItem(
            id: 'accessibility',
            icon: Icons.accessibility,
            label: Loc.t('Accessibility', 'Специальные возможности'),
            section: 'accessibility',
            uri: 'ms-settings:easeofaccess',
            native: true,
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
                icon: Icons.camera,
                label: Loc.t('Drives & cameras', 'Диски и камеры'),
                section: 'devices',
                uri: 'ms-settings:connecteddevices',
                native: true,
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
            section: 'apps',
            uri: 'ms-settings:defaultapps',
            native: true,
          ),
          SettingsItem(
            id: 'notifications',
            icon: Icons.notifications,
            label: Loc.t('Notifications', 'Уведомления'),
            section: 'apps',
            uri: 'ms-settings:notifications',
            native: true,
          ),
          SettingsItem(
            id: 'multitasking',
            icon: Icons.window,
            label: Loc.t('Multitasking & windows', 'Многозадачность и окна'),
            section: 'apps',
            uri: 'ms-settings:multitasking',
            native: true,
          ),
        ]),
        _SettingsSection(Loc.t('Security & privacy', 'Безопасность'), [
          SettingsItem(
            id: 'signin',
            icon: Icons.login,
            label: Loc.t('Login screen', 'Экран входа'),
            section: 'security',
            uri: 'ms-settings:signinoptions',
            native: true,
          ),
          SettingsItem(
            id: 'lockscreen',
            icon: Icons.lock,
            label: Loc.t('Lock screen', 'Экран блокировки'),
            section: 'security',
            uri: 'ms-settings:lockscreen',
            native: true,
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
  }

  @override
  void dispose() {
    widget.navigator.removeListener(_onNavigator);
    _sessionPoll?.cancel();
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
          'appearance' => _appearancePane(item),
          'datetime' => _dateTimePane(item),
          'updates' => _updatesPane(item),
          'language' when item.id == 'region' => _languagePane(item),
          _ => _windowsPane(item),
        },
      ),
    );
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

  // ---- appearance -----------------------------------------------------------

  Widget _appearancePane(SettingsItem item) {
    if (_appearanceDetail == 'wallpaper') {
      return _appearanceSheet(
        title: Loc.t('Wallpaper & theme', 'Обои и тема'),
        child: _wallpaperSheet(),
      );
    }
    if (_appearanceDetail == 'vibe') {
      return _appearanceSheet(
        title: Loc.t('Vibe bar', 'Вайбар'),
        child: _vibeSheet(),
      );
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
              final columns = constraints.maxWidth < 420 ? 1 : 2;
              final width =
                  (constraints.maxWidth - 10 * (columns - 1)) / columns;
              return SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _AppearanceTile(
                      key: const ValueKey('appearance-tile-wallpaper'),
                      width: width,
                      icon: Icons.wallpaper_rounded,
                      label: Loc.t('Wallpaper & theme', 'Обои и тема'),
                      hint: Loc.t('Pictures, timer', 'Картинки, таймер'),
                      onTap: () => setState(
                          () => _appearanceDetail = 'wallpaper'),
                    ),
                    _AppearanceTile(
                      key: const ValueKey('appearance-tile-vibe'),
                      width: width,
                      icon: Icons.dock_rounded,
                      label: Loc.t('Vibe bar', 'Вайбар'),
                      hint: Loc.t('Panels in the top bar',
                          'Панели в верхней полосе'),
                      onTap: () =>
                          setState(() => _appearanceDetail = 'vibe'),
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
                          _waybarLabel(key),
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
          'The bar widens when it needs room. New panels are placeholders '
          'until their flyouts are built.',
          'Полоса расширяется, когда нужно место. Новые панели — заготовки, '
          'их выпадающие окна появятся позже.',
        )),
      ],
    );
  }

  Widget _waybarRow(String key) {
    const implemented = {'sound', 'bluetooth', 'wifi', 'brightness'};
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
              _waybarLabel(key),
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
          if (!implemented.contains(key))
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Caption(Loc.t('placeholder', 'заготовка'), size: 9.5),
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

  static String _waybarLabel(String key) {
    final meta = waybarMetaRu[key];
    if (meta != null) return Loc.t(meta.$2, meta.$3);
    return waybarMeta[key]?.$1 ?? key;
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
              'Open the latest release page and see what changed.',
              'Открыть страницу последнего релиза и посмотреть изменения.',
            ),
            button: Loc.t('Check', 'Проверить'),
            onTap: () {
              final open = widget.onOpenUpdates;
              if (open != null) {
                unawaited(open(
                    'https://github.com/krutkrutaya/EXpaDesktop/releases/latest'));
              }
            },
          ),
          const SizedBox(height: 10),
          _updateCard(
            key: const ValueKey('updates-windows'),
            title: Loc.t('Windows Update', 'Обновление Windows'),
            caption: Loc.t(
              'The system update page, exactly where Windows keeps it.',
              'Системная страница обновлений, там, где её держит Windows.',
            ),
            button: Loc.t('Open', 'Открыть'),
            onTap: () {
              final open = widget.onOpenUpdates;
              if (open != null) unawaited(open('ms-settings:windowsupdate'));
            },
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

  // ---- generic Windows pane -------------------------------------------------

  Widget _windowsPane(SettingsItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 16),
        Caption(Loc.t(
          'This setting lives in Windows Settings. The shell opens the right '
          'page; the system does the rest.',
          'Эта настройка живёт в Windows. Оболочка открывает нужную страницу, '
          'остальное делает система.',
        )),
        const SizedBox(height: 16),
        if (item.uri != null)
          Align(
            alignment: Alignment.centerLeft,
            child: PillButton(
              key: const ValueKey('settings-open-windows'),
              label: Loc.t('Open in Windows', 'Открыть в Windows'),
              icon: Icons.open_in_new_rounded,
              onTap: () => unawaited(openSettingsPage(item.uri!)),
            ),
          ),
        const Spacer(),
      ],
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