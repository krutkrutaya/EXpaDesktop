// The Notifications widget: the in-shell notification center. The shell posts
// events (a new track, a network, an update) and this window shows the history
// with unread state, category labels and clear/mark-read actions.

import 'package:flutter/material.dart';

import '../../expa/notifications.dart';
import '../../i18n.dart';
import '../../ui/glass.dart';

class NotificationsApp extends StatefulWidget {
  final NotificationCenter center;

  const NotificationsApp({super.key, required this.center});

  @override
  State<NotificationsApp> createState() => _NotificationsAppState();
}

class _NotificationsAppState extends State<NotificationsApp> {
  @override
  void initState() {
    super.initState();
    widget.center.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant NotificationsApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.center == widget.center) return;
    oldWidget.center.removeListener(_changed);
    widget.center.addListener(_changed);
  }

  @override
  void dispose() {
    widget.center.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final items = widget.center.items;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_none_rounded,
                  size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                Loc.t('Notifications', 'Уведомления'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              if (widget.center.unread > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8AB4F8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.center.unread}',
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              const Spacer(),
              PillButton(
                key: const ValueKey('notifications-read'),
                label: Loc.t('Read all', 'Прочитать'),
                onTap: widget.center.markAllRead,
              ),
              const SizedBox(width: 6),
              PillButton(
                key: const ValueKey('notifications-clear'),
                label: Loc.t('Clear', 'Очистить'),
                icon: Icons.delete_sweep_outlined,
                onTap: widget.center.clear,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_off_outlined,
                            size: 36,
                            color: Colors.white.withValues(alpha: 0.16)),
                        const SizedBox(height: 8),
                        Caption(Loc.t(
                          'Nothing has happened yet',
                          'Пока ничего не произошло',
                        )),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return GestureDetector(
                        key: ValueKey('notification-${item.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.center.markRead(item),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: item.read
                                ? Colors.black.withValues(alpha: 0.22)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: Colors.white.withValues(
                                  alpha: item.read ? 0.06 : 0.16),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  switch (item.category) {
                                    'music' => Icons.music_note_rounded,
                                    'network' => Icons.wifi_rounded,
                                    'updates' => Icons.system_update_rounded,
                                    _ => Icons.info_outline_rounded,
                                  },
                                  size: 16,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: TextStyle(
                                        color: item.read
                                            ? Colors.white70
                                            : Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: item.read
                                            ? FontWeight.w400
                                            : FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.body,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11.5,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Caption(item.category, size: 9.5),
                                        const SizedBox(width: 8),
                                        Caption(_time(item.time), size: 9.5),
                                        const Spacer(),
                                        GestureDetector(
                                          key: ValueKey(
                                              'notification-remove-${item.id}'),
                                          onTap: () =>
                                              widget.center.remove(item.id),
                                          child: const Icon(Icons.close_rounded,
                                              size: 14,
                                              color: Colors.white30),
                                        ),
                                      ],
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
          ),
        ],
      ),
    );
  }
}