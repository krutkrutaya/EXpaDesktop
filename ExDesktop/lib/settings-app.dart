// settings-app.dart
import 'package:flutter/material.dart';
import 'dart:ui';

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
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  late final Animation<double> _slideAnimation;
  int _hoveredIndex = -1;
  int _selectedIndex = -1;
  late Offset _position;

  final List<Map<String, dynamic>> _sections = [
    {
      'title': 'Ввод и вывод',
      'items': [
        {'icon': Icons.mouse, 'label': 'Мышь и сенсорная панель'},
        {'icon': Icons.keyboard, 'label': 'Клавиатура'},
        {'icon': Icons.speaker, 'label': 'Настройка звука'},
        {'icon': Icons.monitor, 'label': 'Экран и монитор'},
        {'icon': Icons.accessibility, 'label': 'Специальные возможности'},
      ],
    },
    {
      'title': 'Подключенные устройства',
      'items': [
        {'icon': Icons.bluetooth, 'label': 'Bluetooth'},
        {'icon': Icons.camera, 'label': 'Диски и фотокамеры'},
      ],
    },
    {
      'title': 'Сеть и связь',
      'items': [
        {'icon': Icons.wifi, 'label': 'Wi-Fi и интернет'},
      ],
    },
    {
      'title': 'Внешний вид',
      'items': [
        {'icon': Icons.wallpaper, 'label': 'Обои'},
        {'icon': Icons.palette, 'label': 'Цвета и оформления'},
        {'icon': Icons.text_fields, 'label': 'Текст и шрифты'},
        {'icon': Icons.animation, 'label': 'Анимации'},
      ],
    },
    {
      'title': 'Приложения и окна',
      'items': [
        {'icon': Icons.apps, 'label': 'Приложения по умолчанию'},
        {'icon': Icons.notifications, 'label': 'Уведомления'},
        {'icon': Icons.window, 'label': 'Диспетчер окон'},
      ],
    },
    {
      'title': 'Безопасность и конфиденциальность',
      'items': [
        {'icon': Icons.login, 'label': 'Экран входа в систему'},
        {'icon': Icons.lock, 'label': 'Блокировка экрана'},
        {'icon': Icons.feedback, 'label': 'Обратная связь'},
      ],
    },
    {
      'title': 'Язык и время',
      'items': [
        {'icon': Icons.calendar_today, 'label': 'Дата и время'},
        {'icon': Icons.language, 'label': 'Язык и регион'},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInBack,
      ),
    );
    _opacityAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      reverseCurve: const Interval(0.2, 1.0, curve: Curves.easeIn),
    );
    _slideAnimation = Tween<double>(begin: 600.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeInQuart,
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _closeWithAnimation() {
    _controller.reverse().then((_) {
      widget.onClose();
    });
  }

  void _minimizeWithAnimation() {
    _controller.reverse().then((_) {
      widget.onMinimize();
    });
  }

  @override
  Widget build(BuildContext context) {
    int itemIndex = 0;
    return Transform.translate(
      offset: _position + Offset(0, _slideAnimation.value),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: FadeTransition(
          opacity: _opacityAnimation,
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
                        children: _sections.map((section) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Text(
                                  section['title'] as String,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ...(section['items'] as List).map((item) {
                                final currentIndex = itemIndex;
                                itemIndex++;
                                return MouseRegion(
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
                                );
                              }).toList(),
                            ],
                          );
                        }).toList(),
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
                                    'Настройки',
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
                                'Выберите параметр',
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
}