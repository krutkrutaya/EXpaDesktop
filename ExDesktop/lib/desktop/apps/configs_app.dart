// The Configs app: EXPA's live configuration hub. Unlike Settings (the
// friendly panes), this is the power view: every customization knob in one
// place, the Vibe bar's panel list, the open windows and maintenance actions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../expa/de_config.dart';
import '../../expa/version.dart';
import '../../expa/waybar_catalog.dart';
import '../../exwm/window_manager.dart';
import '../../liquid_glass/wave_slider.dart';
import '../../ui/glass.dart';

class ConfigsApp extends StatefulWidget {
  final DeConfig config;
  final ValueChanged<DeConfig>? onConfig;
  final List<String> waybarItems;
  final ValueChanged<List<String>>? onWaybarItems;
  final List<AppWindow> windows;
  final int? activeId;
  final ValueChanged<AppWindow>? onFocusWindow;
  final ValueChanged<AppWindow>? onCloseWindow;
  final VersionInfo version;
  final String prefsPath;
  final String? repoPath;

  const ConfigsApp({
    super.key,
    this.config = DeConfig.defaults,
    this.onConfig,
    this.waybarItems = const ['sound', 'bluetooth', 'wifi', 'brightness'],
    this.onWaybarItems,
    this.windows = const [],
    this.activeId,
    this.onFocusWindow,
    this.onCloseWindow,
    this.version = appVersion,
    this.prefsPath = '',
    this.repoPath,
  });

  @override
  State<ConfigsApp> createState() => _ConfigsAppState();
}

class _ConfigsAppState extends State<ConfigsApp> {
  late DeConfig _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.config;
  }

  @override
  void didUpdateWidget(covariant ConfigsApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) _draft = widget.config;
  }

  void _preview(DeConfig next) => setState(() => _draft = next);

  void _commit(DeConfig next) {
    setState(() => _draft = next);
    widget.onConfig?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              const Text(
                'Configs',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 9),
              Caption('v${widget.version.version}'
                  '${widget.version.commit.isEmpty ? '' : ' · ${widget.version.commit}'}'),
              const Spacer(),
              PillButton(
                key: const ValueKey('configs-copy-prefs'),
                label: 'Copy prefs path',
                icon: Icons.copy_rounded,
                onTap: widget.prefsPath.isEmpty
                    ? null
                    : () => Clipboard.setData(
                        ClipboardData(text: widget.prefsPath)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card('Appearance', [
                    _accentRow(),
                    const SizedBox(height: 8),
                    _slider(
                      key: 'configs-radius',
                      label: 'Window radius',
                      value: ((_draft.windowRadius - 8) / 18).clamp(0.0, 1.0),
                      text: '${_draft.windowRadius.round()} px',
                      onChanged: (value) => _preview(_draft.copyWith(
                          windowRadius: 8 + value * 18)),
                      onEnd: () => _commit(_draft),
                    ),
                    _slider(
                      key: 'configs-dock',
                      label: 'Dock icon size',
                      value: ((_draft.dockIconScale - 0.8) / 0.6)
                          .clamp(0.0, 1.0),
                      text: '${(_draft.dockIconScale * 100).round()}%',
                      onChanged: (value) => _preview(_draft.copyWith(
                          dockIconScale: 0.8 + value * 0.6)),
                      onEnd: () => _commit(_draft),
                    ),
                    _slider(
                      key: 'configs-dim',
                      label: 'Wallpaper dim',
                      value: (_draft.wallpaperDim / 0.65).clamp(0.0, 1.0),
                      text: '${(_draft.wallpaperDim * 100).round()}%',
                      onChanged: (value) => _preview(
                          _draft.copyWith(wallpaperDim: value * 0.65)),
                      onEnd: () => _commit(_draft),
                    ),
                    _slider(
                      key: 'configs-speed',
                      label: 'Animation speed',
                      value: ((_draft.animationSpeed - 0.5) / 1.1)
                          .clamp(0.0, 1.0),
                      text: '${(_draft.animationSpeed * 100).round()}%',
                      onChanged: (value) => _preview(_draft.copyWith(
                          animationSpeed: 0.5 + value * 1.1)),
                      onEnd: () => _commit(_draft),
                    ),
                    _toggle(
                      key: 'configs-animations',
                      label: 'Animations',
                      value: _draft.animationsEnabled,
                      onChanged: (on) =>
                          _commit(_draft.copyWith(animationsEnabled: on)),
                    ),
                    _toggle(
                      key: 'configs-clock-seconds',
                      label: 'Clock seconds',
                      value: _draft.clockSeconds,
                      onChanged: (on) =>
                          _commit(_draft.copyWith(clockSeconds: on)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  _card('Windows & behaviour', [
                    _toggle(
                      key: 'configs-snap',
                      label: 'Snap windows to edges',
                      value: _draft.snapEnabled,
                      onChanged: (on) =>
                          _commit(_draft.copyWith(snapEnabled: on)),
                    ),
                    _slider(
                      key: 'configs-gap',
                      label: 'Gap between tiles',
                      value: (_draft.snapGap / 20).clamp(0.0, 1.0),
                      text: '${_draft.snapGap.round()} px',
                      onChanged: (value) => _preview(
                          _draft.copyWith(snapGap: value * 20)),
                      onEnd: () => _commit(_draft),
                    ),
                    _toggle(
                      key: 'configs-notifications',
                      label: 'Desktop notifications',
                      value: _draft.notificationsEnabled,
                      onChanged: (on) => _commit(
                          _draft.copyWith(notificationsEnabled: on)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  _card('Vibe bar', [_waybarEditor()]),
                  const SizedBox(height: 10),
                  _card('Open windows', [_windowList()]),
                  const SizedBox(height: 10),
                  _card('Maintenance', [
                    Caption('prefs.cfg: ${widget.prefsPath}'),
                    if (widget.repoPath != null)
                      Caption('repository: ${widget.repoPath}'),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PillButton(
                        key: const ValueKey('configs-reset'),
                        label: 'Reset customization',
                        icon: Icons.restart_alt_rounded,
                        onTap: () => _commit(DeConfig.defaults),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return GlassPanel(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _accentRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < DeConfig.accents.length; i++)
          GestureDetector(
            key: ValueKey('configs-accent-$i'),
            onTap: () => _commit(_draft.copyWith(accentIndex: i)),
            child: Container(
              width: 28,
              height: 28,
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
    );
  }

  Widget _slider({
    required String key,
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
                style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
            const Spacer(),
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
        SizedBox(
          height: 28,
          child: KeyedSubtree(
            key: ValueKey(key),
            child: WaveSlider(
              value: value,
              onChanged: onChanged,
              onChangeEnd: (_) => onEnd(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggle({
    required String key,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
          ),
          GlassToggle(key: ValueKey(key), value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _waybarEditor() {
    final present = widget.waybarItems;
    final addable = [
      for (final key in waybarKeys)
        if (!present.contains(key)) key,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final key in waybarKeys)
              if (present.contains(key))
                Container(
                  key: ValueKey('configs-waybar-$key'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(waybarMeta[key]?.$2 ?? Icons.extension_rounded,
                          size: 13, color: Colors.white70),
                      const SizedBox(width: 5),
                      Text(waybarLabel(key),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10.5)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        key: ValueKey('configs-waybar-remove-$key'),
                        onTap: () {
                          final next = [...present]..remove(key);
                          widget.onWaybarItems?.call(next);
                        },
                        child: const Icon(Icons.close_rounded,
                            size: 12, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
          ],
        ),
        if (addable.isNotEmpty) ...[
          const SizedBox(height: 8),
          PopupMenuButton<String>(
            key: const ValueKey('configs-waybar-add'),
            tooltip: '',
            color: const Color(0xF01A1A1A),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (key) => widget.onWaybarItems
                ?.call([...present, key]),
            itemBuilder: (context) => [
              for (final key in addable)
                PopupMenuItem<String>(
                  value: key,
                  child: Text(waybarLabel(key),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12.5)),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 13, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Add panel',
                      style: TextStyle(color: Colors.white, fontSize: 10.5)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _windowList() {
    if (widget.windows.isEmpty) {
      return const Caption('No windows on this desktop');
    }
    return Column(
      children: [
        for (final window in widget.windows)
          Padding(
            key: ValueKey('configs-window-${window.id}'),
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  window.minimized
                      ? Icons.minimize_rounded
                      : window.id == widget.activeId
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                  size: 14,
                  color: window.id == widget.activeId
                      ? Colors.white
                      : Colors.white38,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${window.title}  #${window.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11.5),
                  ),
                ),
                GestureDetector(
                  key: ValueKey('configs-window-focus-${window.id}'),
                  onTap: () => widget.onFocusWindow?.call(window),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(Icons.center_focus_strong_rounded,
                        size: 15, color: Colors.white54),
                  ),
                ),
                GestureDetector(
                  key: ValueKey('configs-window-close-${window.id}'),
                  onTap: () => widget.onCloseWindow?.call(window),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(Icons.close_rounded,
                        size: 15, color: Colors.white38),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}