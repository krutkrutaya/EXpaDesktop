// The waybar panel catalog, shared by the Settings Vibe sheet, the Configs
// app and the waybar itself. Every key here opens a real in-shell app (or a
// flyout, for the four base panels).

import 'package:flutter/material.dart';

import '../i18n.dart';

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

String waybarLabel(String key) {
  final meta = waybarMetaRu[key];
  if (meta != null) return Loc.t(meta.$2, meta.$3);
  return waybarMeta[key]?.$1 ?? key;
}