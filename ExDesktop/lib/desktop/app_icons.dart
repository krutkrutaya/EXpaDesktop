// One icon per app, in the shell's line-icon style.

import 'package:flutter/material.dart';

import 'app_catalog.dart';

IconData iconForApp(ShellApp app) => switch (app) {
      ShellApp.calculator => Icons.calculate_outlined,
      ShellApp.notepad => Icons.notes_outlined,
      ShellApp.files => Icons.folder_outlined,
      ShellApp.paint => Icons.brush_outlined,
      ShellApp.snip => Icons.photo_camera_outlined,
      ShellApp.tasks => Icons.checklist_outlined,
      ShellApp.browser => Icons.public_outlined,
      ShellApp.musics => Icons.music_note_outlined,
      ShellApp.configs => Icons.spa_outlined,// the leaf tile requested next to Musics
      ShellApp.settings => Icons.settings_outlined,
      ShellApp.terminal => Icons.terminal_outlined,
    };

/// The accent a window's icon carries; kept muted so the glass stays grey.
Color accentForApp(ShellApp app) => switch (app) {
      ShellApp.calculator => const Color(0xFF9AD0FF),
      ShellApp.notepad => const Color(0xFFFFE49A),
      ShellApp.files => const Color(0xFFFFC98A),
      ShellApp.paint => const Color(0xFFFF9AD0),
      ShellApp.snip => const Color(0xFF9AFFD0),
      ShellApp.tasks => const Color(0xFFB49AFF),
      ShellApp.browser => const Color(0xFF9AB8FF),
      ShellApp.musics => const Color(0xFFFFA59A),
      ShellApp.configs => const Color(0xFF9AFFE0),
      ShellApp.settings => const Color(0xFFD0D0D0),
      ShellApp.terminal => const Color(0xFF9AFFA5),
    };