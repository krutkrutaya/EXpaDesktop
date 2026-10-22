// The Configs app: intentionally empty.
//
// Its former switches moved into the Settings window (language, wallpaper
// timer, Vibe bar, display). The shelf stays in the launcher so the window
// keeps opening, but there is nothing inside by request.

import 'package:flutter/material.dart';

class ConfigsApp extends StatelessWidget {
  const ConfigsApp({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}