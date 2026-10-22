// The Settings window's content.
//
// This is the same two-pane settings that used to be its own floating window,
// now living inside a shell window: the window chrome, the entrance and the
// drag belong to [ShellWindow], so this widget is only the left list and the
// right pane. It also gained the Desktop section, which really changes the
// wallpaper of the current in-app desktop.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../liquid_glass/wave_slider.dart';
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

  const SettingsView({
    super.key,
    required this.navigator,
    required this.display,
    this.radio,
    this.sound,
    this.wallpapers = const [],
    this.activeWallpaper = 0,
    this.onWallpaper,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  String? _selectedId;
  int _hoveredIndex = -1;

  final Map<RadioKind, RadioStatus> _radio = {
    RadioKind.wifi: const RadioStatus(kind: RadioKind.wifi, state: RadioState.unknown),
    RadioKind.bluetooth:
        const RadioStatus(kind: RadioKind.bluetooth, state: RadioState.unknown),
  };
  bool _radioBusy = false;

  static const List<_SettingsSection> _sections = [
    _SettingsSection('Input & output', [
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
        native: true,
      ),
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
        id: 'accessibility',
        icon: Icons.accessibility,
        label: 'Accessibility',
        section: 'accessibility',
        uri: 'ms-settings:easeofaccess',
      ),
    ]),
    _SettingsSection('Desktop', [
      SettingsItem(
        id: 'wallpaper',
        icon: Icons.wallpaper,
        label: 'Wallpaper',
        section: 'wallpaper',
        native: true,
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
        label: 'Visual effects',
        section: 'effects',
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
    widget.navigator.addListener(_onNavigator);
    _selectedId = _idForSection(widget.navigator.section);
    _refreshIfRadio();
  }

  @override
  void didUpdateWidget(covariant SettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigator != widget.navigator) {
      oldWidget.navigator.removeListener(_onNavigator);
      widget.navigator.addListener(_onNavigator);
    }
  }

  @override
  void dispose() {
    widget.navigator.removeListener(_onNavigator);
    super.dispose();
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
    setState(() => _selectedId = item.id);
    _refreshIfRadio();
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

  RadioSource get _radioSource => widget.radio ?? RadioControl.instance;
  SoundSource get _soundSource => widget.sound ?? SoundControl.instance;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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
    );
  }

  Widget _nav() {
    final widgets = <Widget>[];
    var itemIndex = 0;
    for (final section in _sections) {
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
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
    if (section == 'bluetooth') return _radio[RadioKind.bluetooth]?.isOn ?? false;
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
              const Caption('Select a section on the left'),
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
          'wallpaper' => _wallpaperPane(item),
          _ => _windowsPane(item),
        },
      ),
    );
  }

  Widget _paneTitle(SettingsItem item) {
    return Row(
      children: [
        Icon(item.icon, color: Colors.white, size: 19),
        const SizedBox(width: 9),
        Text(
          item.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _soundPane(SettingsItem item) {
    final sound = _soundSource;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(sound.muted ? Icons.volume_off : Icons.volume_up,
                size: 17, color: Colors.white70),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                sound.muted ? 'Sound muted' : 'Volume ${sound.percent}%',
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
              ),
            ),
            GlassToggle(
              value: !sound.muted,
              onChanged: (on) => setState(() => sound.muted = !on),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Text('Level',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            Text('${sound.percent}%',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 32,
          child: WaveSlider(
            value: sound.muted ? 0 : sound.volume,
            onChanged: (value) => setState(() => sound.volume = value),
          ),
        ),
        const SizedBox(height: 10),
        const Caption(
          'The slider drives the system volume directly. No Windows window '
          'opens and the shell stays where it is.',
        ),
        const Spacer(),
        _windowsLink('More sound settings', item.uri),
      ],
    );
  }

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
                      style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                  if (status.deviceName != null)
                    Caption(status.deviceName!),
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
              const Icon(Icons.signal_wifi_4_bar, size: 15, color: Colors.white38),
              const SizedBox(width: 8),
              Caption(status.connected ? 'Network connected' : 'Not connected'),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (status.state == RadioState.unavailable)
          const Caption('No such device on this machine.')
        else if (!status.canToggle)
          const Caption(
              'The system will not switch the radio. Turn it on in Windows Settings.')
        else
          const Caption(
              'Switching goes through the Windows radio API: no UAC, no windows.'),
        const Spacer(),
        _windowsLink('Open in Windows Settings', item.uri),
      ],
    );
  }

  Widget _displayPane(SettingsItem item) {
    final display = widget.display;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 18),
        DisplaySlider(
          label: 'Brightness',
          value: display.brightness,
          onChanged: display.onBrightness,
        ),
        const SizedBox(height: 10),
        DisplaySlider(
          label: 'Contrast',
          value: display.contrast,
          onChanged: display.onContrast,
        ),
        const SizedBox(height: 10),
        DisplaySlider(
          label: 'Warmth',
          value: display.warmth,
          onChanged: display.onWarmth,
        ),
        const SizedBox(height: 12),
        const Caption(
          'Brightness and contrast go through DDC/CI, warmth through the '
          'gamma ramp. Warmth 0% is a neutral screen.',
        ),
        const Spacer(),
        _windowsLink('Open in Windows Settings', item.uri),
      ],
    );
  }

  Widget _wallpaperPane(SettingsItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 6),
        const Caption(
          'Each desktop keeps its own wallpaper. Click a picture to set it '
          'for the desktop you are on.',
        ),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < widget.wallpapers.length; i++)
                  _WallpaperTile(
                    key: ValueKey('settings-wallpaper-$i'),
                    asset: widget.wallpapers[i],
                    selected: i == widget.activeWallpaper,
                    onTap: () => widget.onWallpaper?.call(i),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _windowsPane(SettingsItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(item),
        const SizedBox(height: 16),
        const Caption(
          'This setting lives in Windows Settings. The shell opens the right '
          'page; the system does the rest.',
        ),
        const Spacer(),
        _windowsLink('Open in Windows Settings', item.uri),
      ],
    );
  }

  Widget _windowsLink(String label, String? uri) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (uri != null && uri.isNotEmpty) unawaited(openSettingsPage(uri));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_new, color: Colors.white54, size: 14),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _WallpaperTile extends StatefulWidget {
  final String asset;
  final bool selected;
  final VoidCallback onTap;

  const _WallpaperTile({
    super.key,
    required this.asset,
    required this.selected,
    required this.onTap,
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
          width: 108,
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: widget.selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: _hovered ? 0.4 : 0.12),
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
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
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.check_circle,
                          size: 14, color: Colors.white),
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