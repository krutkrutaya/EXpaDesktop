// settings_app.dart
//
// The shell's own settings. The parameters the shell can drive itself live
// here as real controls: the master volume, the Wi-Fi radio and the
// Bluetooth radio are read from the system and switched from this window.
// Everything else keeps a link to the matching page of Windows Settings -
// that page is the fallback, not the primary place.
//
// Nothing in this file can hide the desktop: the only window callbacks are
// the title bar's close and minimize, and they belong to the title bar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:ui';

import 'liquid_glass/menu_spring.dart';
import 'liquid_glass/wave_slider.dart';
import 'radio_control.dart';
import 'sound_control.dart';
import 'system_actions.dart';

/// One row of the settings list.
class SettingsItem {
  /// Unique id of the row.
  final String id;
  final IconData icon;
  final String label;

  /// The id of the built-in section this row opens.
  final String section;

  /// The Windows page with the same setting - the fallback.
  final String? uri;

  /// Whether the shell drives this parameter itself.
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

class SettingsApp extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final Offset initialPosition;
  final ValueChanged<Offset> onPositionChanged;

  /// The section to show right away, e.g. when the top bar's Wi-Fi button
  /// sends the user here.
  final String? initialSection;

  /// Backends for the live panes. The defaults are the real system ones;
  /// the widget tests pass recorders instead.
  final RadioSource? radio;
  final SoundSource? sound;

  const SettingsApp({
    super.key,
    required this.onClose,
    required this.onMinimize,
    required this.initialPosition,
    required this.onPositionChanged,
    this.initialSection,
    this.radio,
    this.sound,
  });

  @override
  State<SettingsApp> createState() => _SettingsAppState();
}

class _SettingsAppState extends State<SettingsApp> with SingleTickerProviderStateMixin {
  // Liquid-glass spring: opens with a bounce past 1.0 and settles, closes
  // with a smooth exponential shrink, opacity fading out ahead of it.
  late final Ticker _ticker;
  final MenuSpringState _spring = MenuSpringState(0);
  double _lastElapsedS = 0;
  double _scale = 0.001;
  double _opacity = 0;
  int _hoveredIndex = -1;
  String? _selectedId;
  late Offset _position;
  int _pendingAction = 0; // 0 none, 1 close, 2 minimize

  // Live readings of the radios, refreshed when a section opens.
  final Map<RadioKind, RadioStatus> _radio = {
    RadioKind.wifi: const RadioStatus(
      kind: RadioKind.wifi,
      state: RadioState.unknown,
    ),
    RadioKind.bluetooth: const RadioStatus(
      kind: RadioKind.bluetooth,
      state: RadioState.unknown,
    ),
  };
  bool _radioBusy = false;

  static const List<_SettingsSection> _sections = [
    _SettingsSection('Input & output', [
      SettingsItem(
        id: 'mouse',
        icon: Icons.mouse,
        label: 'Mouse & touchpad',
        section: 'input',
        uri: 'ms-settings:mousetouchpad',
      ),
      SettingsItem(
        id: 'keyboard',
        icon: Icons.keyboard,
        label: 'Keyboard',
        section: 'input',
        uri: 'ms-settings:typing',
      ),
      SettingsItem(
        id: 'sound',
        icon: Icons.speaker,
        label: 'Sound settings',
        section: 'sound',
        uri: 'ms-settings:sound',
        native: true,
      ),
      SettingsItem(
        id: 'display',
        icon: Icons.monitor,
        label: 'Display & monitor',
        section: 'display',
        uri: 'ms-settings:display',
      ),
      SettingsItem(
        id: 'accessibility',
        icon: Icons.accessibility,
        label: 'Accessibility',
        section: 'accessibility',
        uri: 'ms-settings:easeofaccess',
      ),
    ]),
    _SettingsSection('Connected devices', [
      SettingsItem(
        id: 'bluetooth',
        icon: Icons.bluetooth,
        label: 'Bluetooth',
        section: 'bluetooth',
        uri: 'ms-settings:bluetooth',
        native: true,
      ),
      SettingsItem(
        id: 'devices',
        icon: Icons.camera,
        label: 'Drives & cameras',
        section: 'devices',
        uri: 'ms-settings:connecteddevices',
      ),
    ]),
    _SettingsSection('Network & connectivity', [
      SettingsItem(
        id: 'wifi',
        icon: Icons.wifi,
        label: 'Wi-Fi & internet',
        section: 'wifi',
        uri: 'ms-settings:network-wifi',
        native: true,
      ),
    ]),
    _SettingsSection('Appearance', [
      SettingsItem(
        id: 'wallpaper',
        icon: Icons.wallpaper,
        label: 'Wallpaper',
        section: 'appearance',
        uri: 'ms-settings:personalization-background',
      ),
      SettingsItem(
        id: 'colors',
        icon: Icons.palette,
        label: 'Colors & themes',
        section: 'appearance',
        uri: 'ms-settings:colors',
      ),
      SettingsItem(
        id: 'fonts',
        icon: Icons.text_fields,
        label: 'Text & fonts',
        section: 'appearance',
        uri: 'ms-settings:fonts',
      ),
      SettingsItem(
        id: 'effects',
        icon: Icons.animation,
        label: 'Visual effects & animations',
        section: 'display',
        uri: 'ms-settings:easeofaccess-display',
      ),
    ]),
    _SettingsSection('Apps & windows', [
      SettingsItem(
        id: 'defaultapps',
        icon: Icons.apps,
        label: 'Default apps',
        section: 'apps',
        uri: 'ms-settings:defaultapps',
      ),
      SettingsItem(
        id: 'notifications',
        icon: Icons.notifications,
        label: 'Notifications',
        section: 'apps',
        uri: 'ms-settings:notifications',
      ),
      SettingsItem(
        id: 'multitasking',
        icon: Icons.window,
        label: 'Multitasking & windows',
        section: 'apps',
        uri: 'ms-settings:multitasking',
      ),
    ]),
    _SettingsSection('Security & privacy', [
      SettingsItem(
        id: 'signin',
        icon: Icons.login,
        label: 'Login screen',
        section: 'security',
        uri: 'ms-settings:signinoptions',
      ),
      SettingsItem(
        id: 'lockscreen',
        icon: Icons.lock,
        label: 'Lock screen',
        section: 'security',
        uri: 'ms-settings:lockscreen',
      ),
      SettingsItem(
        id: 'update',
        icon: Icons.system_update,
        label: 'Windows Update',
        section: 'security',
        uri: 'ms-settings:windowsupdate',
      ),
    ]),
    _SettingsSection('Language & time', [
      SettingsItem(
        id: 'datetime',
        icon: Icons.calendar_today,
        label: 'Date & time',
        section: 'language',
        uri: 'ms-settings:dateandtime',
      ),
      SettingsItem(
        id: 'region',
        icon: Icons.language,
        label: 'Language & region',
        section: 'language',
        uri: 'ms-settings:regionlanguage',
      ),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _selectedId = _idForSection(widget.initialSection);
    _ticker = createTicker(_onTick);
    _spring.target = 1;
    _ticker.start();
    if (_selectedSection == 'wifi' || _selectedSection == 'bluetooth') {
      unawaited(_refreshRadios());
    }
  }

  @override
  void didUpdateWidget(covariant SettingsApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The top bar can send the window to another section while it is open.
    if (widget.initialSection != oldWidget.initialSection) {
      final id = _idForSection(widget.initialSection);
      if (id != null) {
        _select(_itemById(id)!);
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1e6;
    final dt = seconds - _lastElapsedS;
    _lastElapsedS = seconds;
    if (dt <= 0) return;
    final frame = stepMenuSpring(_spring, dt * 1000);
    _scale = frame.scale;
    _opacity = frame.opacity;
    setState(() {});
    if (frame.stopped) {
      _ticker.stop();
      _lastElapsedS = 0;
      if (_pendingAction == 1) {
        widget.onClose();
      } else if (_pendingAction == 2) {
        widget.onMinimize();
      }
      _pendingAction = 0;
    }
  }

  void _closeWithAnimation() {
    _pendingAction = 1;
    _spring.target = 0;
    _resume();
  }

  void _minimizeWithAnimation() {
    _pendingAction = 2;
    _spring.target = 0;
    _resume();
  }

  void _resume() {
    if (_ticker.isActive) return; // already ticking, will pick the new target up
    _lastElapsedS = 0;
    _ticker.start();
  }

  /// Reads both radios from the system.
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

  /// Switches a radio and shows what the system says afterwards.
  Future<void> _toggleRadio(RadioKind kind, bool on) async {
    setState(() {
      _radioBusy = true;
    });
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
    });
    if (item.section == 'wifi' || item.section == 'bluetooth') {
      unawaited(_refreshRadios());
    }
  }

  static SettingsItem? _itemById(String? id) {
    if (id == null) return null;
    for (final group in _sections) {
      for (final item in group.items) {
        if (item.id == id) return item;
      }
    }
    return null;
  }

  /// The first row that belongs to [section], so "открой настройки вайфай"
  /// lands on the Wi-Fi row even though sections and rows have their own ids.
  static String? _idForSection(String? section) {
    if (section == null) return null;
    for (final group in _sections) {
      for (final item in group.items) {
        if (item.section == section || item.id == section) return item.id;
      }
    }
    return null;
  }

  SettingsItem? get _selectedItem => _itemById(_selectedId);

  String? get _selectedSection => _selectedItem?.section;

  /// The real backends unless the tests injected recorders.
  RadioSource get _radioSource => widget.radio ?? RadioControl.instance;

  SoundSource get _soundSource => widget.sound ?? SoundControl.instance;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: _position,
      child: Transform.scale(
        scale: _scale,
        child: Opacity(
          opacity: _opacity / 255,
          child: SizedBox(
            width: 850,
            height: 520,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      width: 250,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.all(10),
                        children: _buildSettingSections(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      width: 595,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                _position += details.delta;
                              });
                              widget.onPositionChanged(_position);
                            },
                            child: Container(
                              height: 45,
                              padding: const EdgeInsets.symmetric(horizontal: 15),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Image.asset(
                                    'assets/icons/settings-app-ico.png',
                                    width: 20,
                                    height: 20,
                                    errorBuilder: (context, error, stack) {
                                      return const Icon(Icons.settings,
                                          color: Colors.white, size: 20);
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Settings',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: _minimizeWithAnimation,
                                    icon: const Icon(Icons.remove,
                                        color: Colors.white, size: 18),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 30, minHeight: 30),
                                  ),
                                  const SizedBox(width: 5),
                                  IconButton(
                                    onPressed: _closeWithAnimation,
                                    icon: const Icon(Icons.close,
                                        color: Colors.white, size: 18),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 30, minHeight: 30),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(child: _buildDetail()),
                        ],
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

  /// The left column of the settings window: each section's title followed
  /// by its items, flattened into one scroll list. A running index across
  /// every item backs the hover state.
  List<Widget> _buildSettingSections() {
    final widgets = <Widget>[];
    var itemIndex = 0;
    for (final section in _sections) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          section.title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ));
      for (final item in section.items) {
        final currentIndex = itemIndex++;
        final selected = _selectedId == item.id;
        widgets.add(MouseRegion(
          onEnter: (event) => setState(() => _hoveredIndex = currentIndex),
          onExit: (event) => setState(() => _hoveredIndex = -1),
          child: GestureDetector(
            onTap: () => _select(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.2)
                    : _hoveredIndex == currentIndex
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    color: selected ? Colors.white : Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (item.native)
                    Icon(
                      _radioIsOn(item.section)
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: _radioIsOn(item.section)
                          ? Colors.white
                          : Colors.white38,
                      size: 14,
                    ),
                ],
              ),
            ),
          ),
        ));
      }
    }
    return widgets;
  }

  bool _radioIsOn(String section) {
    if (section == 'wifi') {
      return _radio[RadioKind.wifi]?.isOn ?? false;
    }
    if (section == 'bluetooth') {
      return _radio[RadioKind.bluetooth]?.isOn ?? false;
    }
    return false;
  }

  /// The right pane: the real controls for what the shell owns, a link to
  /// Windows for everything else.
  Widget _buildDetail() {
    final item = _selectedItem;
    if (item == null) {
      return const Center(
        child: Text(
          'Select an item',
          style: TextStyle(color: Colors.white54, fontSize: 15),
        ),
      );
    }
    switch (item.section) {
      case 'sound':
        return _buildSoundPane(item);
      case 'wifi':
        return _buildRadioPane(item, RadioKind.wifi);
      case 'bluetooth':
        return _buildRadioPane(item, RadioKind.bluetooth);
      default:
        return _buildWindowsPane(item);
    }
  }

  /// The master volume: the shell's own sound control, in the shell.
  Widget _buildSoundPane(SettingsItem item) {
    final sound = _soundSource;
    return _DetailScaffold(
      item: item,
      children: [
        _DetailRow(
          icon: sound.muted ? Icons.volume_off : Icons.volume_up,
          title: sound.muted ? 'Звук заглушён' : 'Громкость ${sound.percent}%',
          trailing: GlassToggle(
            value: !sound.muted,
            onChanged: (on) {
              setState(() {
                sound.muted = !on;
              });
            },
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Text(
              'Уровень',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const Spacer(),
            Text(
              '${sound.percent}%',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: WaveSlider(
            value: sound.muted ? 0.0 : sound.volume,
            onChanged: (value) {
              setState(() {
                sound.volume = value;
              });
            },
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Ползунок управляет системной громкостью: окна при этом не '
          'открываются, а оболочка остаётся на месте.',
          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
        ),
        const Spacer(),
        _WindowsLink(
          label: 'Другие настройки звука',
          uri: item.uri,
        ),
      ],
    );
  }

  /// Wi-Fi and Bluetooth: the radio is read from the system and switched
  /// through the same API the taskbar uses.
  Widget _buildRadioPane(SettingsItem item, RadioKind kind) {
    final status =
        _radio[kind] ?? RadioStatus(kind: kind, state: RadioState.unknown);
    return _DetailScaffold(
      item: item,
      children: [
        _DetailRow(
          icon: kind == RadioKind.wifi ? Icons.wifi : Icons.bluetooth,
          title: status.label,
          subtitle: status.deviceName,
          trailing: GlassToggle(
            value: status.isOn,
            onChanged: (on) {
              unawaited(_toggleRadio(kind, on));
            },
          ),
        ),
        const SizedBox(height: 14),
        if (kind == RadioKind.wifi)
          _DetailRow(
            icon: Icons.signal_wifi_4_bar,
            title: status.connected ? 'Сеть подключена' : 'Сеть не подключена',
          ),
        const SizedBox(height: 8),
        if (status.state == RadioState.unavailable)
          const Text(
            'Устройство не найдено на этой машине.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          )
        else if (!status.canToggle)
          const Text(
            'Система не даёт переключить радио — включите его в Параметрах '
            'Windows.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          )
        else
          const Text(
            'Переключение идёт через API радио Windows — без UAC и без '
            'открытых окон.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
        const Spacer(),
        _WindowsLink(
          label: 'Открыть в Параметрах Windows',
          uri: item.uri,
        ),
      ],
    );
  }

  /// Everything the shell does not own: a link to the Windows page.
  Widget _buildWindowsPane(SettingsItem item) {
    return _DetailScaffold(
      item: item,
      children: [
        const Text(
          'Этот параметр живёт в Параметрах Windows. Оболочка открывает нужную '
          'страницу, остальное система делает сама.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        const Spacer(),
        _WindowsLink(
          label: 'Открыть в Параметрах Windows',
          uri: item.uri,
        ),
      ],
    );
  }
}

/// The frame of every detail pane: the title of the item and its children.
class _DetailScaffold extends StatelessWidget {
  final SettingsItem item;
  final List<Widget> children;

  const _DetailScaffold({required this.item, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                item.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

/// One line of a detail pane: an icon, a title, an optional subtitle and
/// an optional control on the right.
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _DetailRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// A glass switch: a knob that slides inside a capsule.
///
/// Public so the widget tests can tap it by type.
class GlassToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const GlassToggle({super.key, required this.value, required this.onChanged});

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
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
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

/// The fallback: opens the matching page of Windows Settings.
class _WindowsLink extends StatelessWidget {
  final String label;
  final String? uri;

  const _WindowsLink({required this.label, required this.uri});

  @override
  Widget build(BuildContext context) {
    final target = uri;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (target != null && target.isNotEmpty) {
            unawaited(openSettingsPage(target));
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_new, color: Colors.white70, size: 15),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}