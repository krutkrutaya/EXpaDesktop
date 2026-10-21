// settings_app.dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:ui';

import 'liquid_glass/menu_spring.dart';

class SettingsApp extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final Offset initialPosition;
  final ValueChanged<Offset> onPositionChanged;

  const SettingsApp({
    super.key,
    required this.onClose,
    required this.onMinimize,
    required this.initialPosition,
    required this.onPositionChanged,
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
  int _selectedIndex = -1;
  late Offset _position;
  int _pendingAction = 0; // 0 none, 1 close, 2 minimize

  final List<Map<String, dynamic>> _sections = [
    {
      'title': 'Input & output',
      'items': [
        {'icon': Icons.mouse, 'label': 'Mouse & touchpad'},
        {'icon': Icons.keyboard, 'label': 'Keyboard'},
        {'icon': Icons.speaker, 'label': 'Sound settings'},
        {'icon': Icons.monitor, 'label': 'Display & monitor'},
        {'icon': Icons.accessibility, 'label': 'Accessibility'},
      ],
    },
    {
      'title': 'Connected devices',
      'items': [
        {'icon': Icons.bluetooth, 'label': 'Bluetooth'},
        {'icon': Icons.camera, 'label': 'Drives & cameras'},
      ],
    },
    {
      'title': 'Network & connectivity',
      'items': [
        {'icon': Icons.wifi, 'label': 'Wi-Fi & internet'},
      ],
    },
    {
      'title': 'Appearance',
      'items': [
        {'icon': Icons.wallpaper, 'label': 'Wallpaper'},
        {'icon': Icons.palette, 'label': 'Colors & themes'},
        {'icon': Icons.text_fields, 'label': 'Text & fonts'},
        {'icon': Icons.animation, 'label': 'Animations'},
      ],
    },
    {
      'title': 'Apps & windows',
      'items': [
        {'icon': Icons.apps, 'label': 'Default apps'},
        {'icon': Icons.notifications, 'label': 'Notifications'},
        {'icon': Icons.window, 'label': 'Window manager'},
      ],
    },
    {
      'title': 'Security & privacy',
      'items': [
        {'icon': Icons.login, 'label': 'Login screen'},
        {'icon': Icons.lock, 'label': 'Lock screen'},
        {'icon': Icons.feedback, 'label': 'Feedback'},
      ],
    },
    {
      'title': 'Language & time',
      'items': [
        {'icon': Icons.calendar_today, 'label': 'Date & time'},
        {'icon': Icons.language, 'label': 'Language & region'},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _ticker = createTicker(_onTick);
    _spring.target = 1;
    _ticker.start();
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
                                      return const Icon(Icons.settings, color: Colors.white, size: 20);
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
                                    icon: const Icon(Icons.remove, color: Colors.white, size: 18),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                  ),
                                  const SizedBox(width: 5),
                                  IconButton(
                                    onPressed: _closeWithAnimation,
                                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Center(
                              child: Text(
                                'Select an item',
                                style: TextStyle(color: Colors.white54, fontSize: 15),
                              ),
                            ),
                          ),
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
  /// every item backs the hover/selection states.
  List<Widget> _buildSettingSections() {
    final widgets = <Widget>[];
    var itemIndex = 0;
    for (final section in _sections) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          section['title'] as String,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ));
      for (final item in section['items'] as List) {
        final currentIndex = itemIndex++;
        widgets.add(MouseRegion(
          onEnter: (event) => setState(() => _hoveredIndex = currentIndex),
          onExit: (event) => setState(() => _hoveredIndex = -1),
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedIndex = currentIndex;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: _selectedIndex == currentIndex
                    ? Colors.white.withValues(alpha: 0.2)
                    : _hoveredIndex == currentIndex
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    item['icon'] as IconData,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item['label'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
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
}