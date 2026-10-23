// Configs has two tabs:
//   Presets — built-in Lua looks, imported .zip packs, and presets saved from
//             the editor. Applying one changes EXWM/EXPA through DeConfig.
//   Edit    — a real Lua editor plus the live sliders for the same fields.
//
// The imports of a pack happen through the in-app Files window: Configs asks
// the shell for a .zip path, Files shows a picker banner, nothing leaves the
// desktop.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../expa/builtin_presets.dart';
import '../../expa/de_config.dart';
import '../../expa/lua_preset.dart';
import '../../expa/preset_store.dart';
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

  /// Opens the in-app Files picker and returns the chosen .zip path.
  final Future<String?> Function()? pickZip;

  /// Injectable for tests; the default stores under %APPDATA%.
  final PresetStore? presetStore;

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
    this.pickZip,
    this.presetStore,
  });

  @override
  State<ConfigsApp> createState() => _ConfigsAppState();
}

class _ConfigsAppState extends State<ConfigsApp> {
  late DeConfig _draft;
  late final PresetStore _store =
      widget.presetStore ?? PresetStore();
  late final List<LuaPreset> _builtIns = builtInPresets();
  late List<LuaPreset> _custom = _store.loadCustom();
  late final TextEditingController _lua = TextEditingController(
    text: presetToLua(widget.config),
  );
  int _tab = 0;
  bool _importing = false;
  String _status = '';
  String _luaError = '';

  List<LuaPreset> get _presets => [..._builtIns, ..._custom];

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

  @override
  void dispose() {
    _lua.dispose();
    super.dispose();
  }

  void _preview(DeConfig next) => setState(() => _draft = next);

  void _commit(DeConfig next) {
    setState(() => _draft = next);
    widget.onConfig?.call(next);
  }

  void _applyPreset(LuaPreset preset) {
    _commit(preset.config);
    setState(() => _status = 'Applied ${preset.name}');
  }

  Future<void> _addPreset() async {
    final picker = widget.pickZip;
    if (picker == null) {
      setState(() => _status = 'The file picker is not wired in this build.');
      return;
    }
    final path = await picker();
    if (path == null || path.isEmpty || !mounted) return;
    setState(() {
      _importing = true;
      _status = 'Reading ${path.split(RegExp(r'[\\/]')).last}…';
    });
    final result = await _store.importZip(path);
    if (!mounted) return;
    if (result.presets.isNotEmpty) {
      _custom = [...result.presets, ..._custom];
      _store.saveCustom(_custom);
    }
    setState(() {
      _importing = false;
      _status = result.presets.isEmpty
          ? (result.errors.isEmpty
              ? 'No preset was found in the archive.'
              : result.errors.first)
          : 'Imported ${result.presets.length} preset'
              '${result.presets.length == 1 ? '' : 's'}'
              '${result.errors.isEmpty ? '' : ' · ${result.errors.first}'}';
    });
  }

  void _deletePreset(LuaPreset preset) {
    setState(() {
      _custom = [
        for (final item in _custom)
          if (!identical(item, preset)) item,
      ];
      _status = 'Removed ${preset.name}';
    });
    _store.saveCustom(_custom);
  }

  void _applyEditor() {
    try {
      final preset = LuaPreset.parse(
        _lua.text,
        fallbackName: 'Edited preset',
      );
      _commit(preset.config);
      setState(() {
        _luaError = '';
        _status = 'Applied ${preset.name}';
      });
    } on LuaPresetException catch (error) {
      setState(() => _luaError = '$error');
    }
  }

  void _saveEditor() {
    try {
      final preset = LuaPreset.parse(_lua.text, fallbackName: 'My preset');
      final next = <LuaPreset>[
        for (final item in _custom)
          if (item.name != preset.name) item,
        preset,
      ];
      _store.saveCustom(next);
      setState(() {
        _custom = next;
        _luaError = '';
        _status = 'Saved ${preset.name}';
      });
      _commit(preset.config);
    } on LuaPresetException catch (error) {
      setState(() => _luaError = '$error');
    }
  }

  void _resetEditor() {
    _lua.text = presetToLua(_draft);
    setState(() => _luaError = '');
  }

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

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
                label: 'Copy path',
                icon: Icons.copy_rounded,
                onTap: widget.prefsPath.isEmpty
                    ? null
                    : () => Clipboard.setData(
                        ClipboardData(text: widget.prefsPath)),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _tabBar(),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
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
              child: _tab == 0
                  ? KeyedSubtree(
                      key: const ValueKey('configs-presets-tab'),
                      child: _presetsTab(),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('configs-edit-tab'),
                      child: _editTab(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    Widget tab(int index, String label, String key) {
      final active = _tab == index;
      return GestureDetector(
        key: ValueKey(key),
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white54,
              fontSize: 11.5,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(0, 'Presets', 'configs-tab-presets'),
        const SizedBox(width: 4),
        tab(1, 'Edit', 'configs-tab-edit'),
        const Spacer(),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _status.isEmpty
                ? const SizedBox.shrink()
                : Text(
                    _status,
                    key: ValueKey(_status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 10.5),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _presetsTab() {
    return ListView(
      children: [
        Row(
          children: [
            const Expanded(
              child: Caption(
                'Lua looks for the window manager and desktop. “Add preset” '
                'opens Files and reads a .zip of .lua configs.',
              ),
            ),
            const SizedBox(width: 8),
            if (_importing)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white54),
                ),
              ),
            PillButton(
              key: const ValueKey('configs-add-preset'),
              label: 'Add preset',
              icon: Icons.add_rounded,
              onTap: _importing ? null : _addPreset,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final preset in _presets) ...[
          _PresetCard(
            key: ValueKey('configs-preset-${_slug(preset.name)}'),
            preset: preset,
            onApply: () => _applyPreset(preset),
            onDelete: preset.builtIn ? null : () => _deletePreset(preset),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Caption('prefs.cfg: ${widget.prefsPath}'),
        if (widget.repoPath != null) Caption('repository: ${widget.repoPath}'),
      ],
    );
  }

  Widget _editTab() {
    return ListView(
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.code_rounded,
                      size: 16, color: Colors.white70),
                  const SizedBox(width: 7),
                  const Text(
                    'Lua preset',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_luaError.isNotEmpty)
                    const Caption('Invalid', size: 10),
                ],
              ),
              const SizedBox(height: 7),
              TextField(
                key: const ValueKey('configs-lua'),
                controller: _lua,
                minLines: 12,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  height: 1.35,
                  fontFamily: 'Consolas',
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.32),
                  contentPadding: const EdgeInsets.all(10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_luaError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _luaError,
                    key: const ValueKey('configs-lua-error'),
                    style: const TextStyle(
                        color: Color(0xFFFF9A9A), fontSize: 10.5),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  PillButton(
                    key: const ValueKey('configs-lua-apply'),
                    label: 'Apply',
                    icon: Icons.play_arrow_rounded,
                    onTap: _applyEditor,
                  ),
                  const SizedBox(width: 6),
                  PillButton(
                    key: const ValueKey('configs-lua-save'),
                    label: 'Save preset',
                    icon: Icons.bookmark_add_outlined,
                    onTap: _saveEditor,
                  ),
                  const SizedBox(width: 6),
                  PillButton(
                    key: const ValueKey('configs-lua-reset'),
                    label: 'Reset',
                    icon: Icons.restart_alt_rounded,
                    onTap: _resetEditor,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Caption(
                'A preset returns a table: name, description, accent, radius, '
                'dim, dock, animation_speed, animations, snap, gap, '
                'notifications, clock_seconds, font_scale, auto_lock.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _liveControls(),
      ],
    );
  }

  Widget _liveControls() {
    final radius = ((_draft.windowRadius - 8) / 18).clamp(0.0, 1.0);
    final dock = ((_draft.dockIconScale - 0.8) / 0.6).clamp(0.0, 1.0);
    final dim = (_draft.wallpaperDim / 0.65).clamp(0.0, 1.0);
    final speed = ((_draft.animationSpeed - 0.5) / 1.1).clamp(0.0, 1.0);
    final gap = (_draft.snapGap / 20).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card('Appearance', [
          _accentRow(),
          const SizedBox(height: 7),
          _slider(
            key: 'configs-radius',
            label: 'Window radius',
            value: radius,
            text: '${_draft.windowRadius.round()} px',
            onChanged: (value) =>
                _preview(_draft.copyWith(windowRadius: 8 + value * 18)),
            onEnd: () => _commit(_draft),
          ),
          _slider(
            key: 'configs-dock',
            label: 'Dock icon size',
            value: dock,
            text: '${(_draft.dockIconScale * 100).round()}%',
            onChanged: (value) =>
                _preview(_draft.copyWith(dockIconScale: 0.8 + value * 0.6)),
            onEnd: () => _commit(_draft),
          ),
          _slider(
            key: 'configs-dim',
            label: 'Wallpaper dim',
            value: dim,
            text: '${(_draft.wallpaperDim * 100).round()}%',
            onChanged: (value) =>
                _preview(_draft.copyWith(wallpaperDim: value * 0.65)),
            onEnd: () => _commit(_draft),
          ),
          _slider(
            key: 'configs-speed',
            label: 'Animation speed',
            value: speed,
            text: '${(_draft.animationSpeed * 100).round()}%',
            onChanged: (value) => _preview(
                _draft.copyWith(animationSpeed: 0.5 + value * 1.1)),
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
            onChanged: (on) => _commit(_draft.copyWith(clockSeconds: on)),
          ),
        ]),
        const SizedBox(height: 10),
        _card('Windows & behaviour', [
          _toggle(
            key: 'configs-snap',
            label: 'Snap windows to edges',
            value: _draft.snapEnabled,
            onChanged: (on) => _commit(_draft.copyWith(snapEnabled: on)),
          ),
          _slider(
            key: 'configs-gap',
            label: 'Gap between tiles',
            value: gap,
            text: '${_draft.snapGap.round()} px',
            onChanged: (value) =>
                _preview(_draft.copyWith(snapGap: value * 20)),
            onEnd: () => _commit(_draft),
          ),
          _toggle(
            key: 'configs-notifications',
            label: 'Desktop notifications',
            value: _draft.notificationsEnabled,
            onChanged: (on) =>
                _commit(_draft.copyWith(notificationsEnabled: on)),
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
    );
  }

  Widget _card(String title, List<Widget> children) {
    return GlassPanel(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
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
            Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
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
                style:
                    const TextStyle(color: Colors.white70, fontSize: 11.5)),
          ),
          GlassToggle(
              key: ValueKey(key), value: value, onChanged: onChanged),
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
            onSelected: (key) =>
                widget.onWaybarItems?.call([...present, key]),
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

class _PresetCard extends StatefulWidget {
  final LuaPreset preset;
  final VoidCallback onApply;
  final VoidCallback? onDelete;

  const _PresetCard({
    super.key,
    required this.preset,
    required this.onApply,
    this.onDelete,
  });

  @override
  State<_PresetCard> createState() => _PresetCardState();
}

class _PresetCardState extends State<_PresetCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    final accent = Color(DeConfig.accents[preset.config.accentIndex]);
    final badge = preset.builtIn
        ? 'BUILT-IN'
        : preset.imported
            ? 'IMPORTED'
            : 'YOURS';
    final slug = preset.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.008 : 1,
        duration: const Duration(milliseconds: 160),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: _hovered ? 0.36 : 0.26),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: _hovered
                  ? accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 2),
                ),
                child: Icon(Icons.palette_rounded, size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Caption(badge, size: 8.5),
                        ),
                      ],
                    ),
                    if (preset.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        preset.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        Caption('r ${preset.config.windowRadius.round()}',
                            size: 9),
                        Caption(
                            'speed ${preset.config.animationSpeed.toStringAsFixed(2)}',
                            size: 9),
                        Caption(
                            preset.config.animationsEnabled
                                ? 'motion'
                                : 'still',
                            size: 9),
                      ],
                    ),
                    if (preset.warnings.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Caption(preset.warnings.first, size: 9),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  PillButton(
                    key: ValueKey('configs-apply-$slug'),
                    label: 'Apply',
                    icon: Icons.check_rounded,
                    onTap: widget.onApply,
                  ),
                  if (widget.onDelete != null)
                    GestureDetector(
                      key: ValueKey('configs-delete-$slug'),
                      onTap: widget.onDelete,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Icon(Icons.delete_outline_rounded,
                            size: 15, color: Colors.white30),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}